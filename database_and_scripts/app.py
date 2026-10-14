"""
AgriMarket & AgriUsers: Smart Mandi Platform (English Farmer-Centric Edition)
----------------------------------------------------------------------------
Clean Two-Database Architecture:
- AgriUsers_DB: User Authentication, Farmer Crop Vault, Alerts, and Email Outbox
- AgriMarket: Mandi Master Data, 40,307+ Daily Prices, Logistics, and Views

Built with:
- Language: Python 3.14
- Web Framework: Streamlit
- Database: MySQL Server (via mysql-connector-python)
- Visualizations: Plotly & HTML5/CSS3
- Hosting: Localhost (Web Server on port 8501)
"""

import os
import sys
import hashlib
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, date

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st
import mysql.connector

# ==============================================================================
# 1. PAGE SETUP & THEME STYLING
# ==============================================================================
st.set_page_config(
    page_title="AgriMarket: Smart Mandi & Crop Vault Platform",
    page_icon="🌾",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom High-Contrast CSS for Agricultural Accessibility
st.markdown("""
<style>
    .farmer-title {
        font-size: 2.3rem;
        font-weight: 800;
        color: #1b5e20;
        margin-bottom: 0.1rem;
    }
    .farmer-subtitle {
        font-size: 1.15rem;
        color: #4a5568;
        margin-bottom: 1.2rem;
    }
    .crop-card {
        background: #ffffff;
        border: 2px solid #e2e8f0;
        border-radius: 12px;
        padding: 16px;
        margin-bottom: 12px;
        box-shadow: 0 2px 6px rgba(0,0,0,0.04);
        transition: transform 0.2s;
    }
    .crop-card:hover {
        border-color: #2e7d32;
        transform: translateY(-2px);
    }
    .price-pill-veg {
        background-color: #e8f5e9;
        color: #2e7d32;
        padding: 6px 14px;
        border-radius: 20px;
        font-weight: 700;
        font-size: 1.1rem;
        display: inline-block;
    }
    .price-pill-fruit {
        background-color: #fff3e0;
        color: #e65100;
        padding: 6px 14px;
        border-radius: 20px;
        font-weight: 700;
        font-size: 1.1rem;
        display: inline-block;
    }
    .db-badge-users {
        background-color: #dbeafe;
        color: #1e40af;
        padding: 3px 8px;
        border-radius: 6px;
        font-size: 0.75rem;
        font-weight: 600;
    }
    .db-badge-market {
        background-color: #dcfce7;
        color: #166534;
        padding: 3px 8px;
        border-radius: 6px;
        font-size: 0.75rem;
        font-weight: 600;
    }
</style>
""", unsafe_allow_html=True)


# ==============================================================================
# 2. TWO-DATABASE ARCHITECTURE UTILITIES
# ==============================================================================
# Database 1: Dedicated User & Crop Vault DB
CONFIG_USERS = {
    "host": "localhost",
    "user": "root",
    "password": "sourabh",
    "database": "AgriUsers_DB",
    "port": 3306,
    "autocommit": True
}

# Database 2: APMC Mandi Market Prices DB
CONFIG_MARKET = {
    "host": "localhost",
    "user": "root",
    "password": "sourabh",
    "database": "AgriMarket",
    "port": 3306,
    "autocommit": True
}

def get_user_db():
    return mysql.connector.connect(**CONFIG_USERS)

def get_market_db():
    return mysql.connector.connect(**CONFIG_MARKET)

def fetch_df(query, params=None, db="market"):
    """Fetch dataframe from either AgriMarket or AgriUsers_DB"""
    try:
        conn = get_market_db() if db == "market" else get_user_db()
        df = pd.read_sql_query(query, conn, params=params)
        conn.close()
        return df
    except Exception as e:
        st.error(f"SQL Fetch Error ({db}): {e}")
        return pd.DataFrame()

def execute_user_dml(query, params=None):
    """Execute INSERT/UPDATE/DELETE in AgriUsers_DB"""
    try:
        conn = get_user_db()
        cur = conn.cursor()
        cur.execute(query, params or ())
        last_id = cur.lastrowid
        row_cnt = cur.rowcount
        conn.close()
        return True, last_id, row_cnt, None
    except Exception as e:
        return False, None, None, str(e)

def call_user_proc(proc_name, params):
    """Call stored procedure in AgriUsers_DB"""
    try:
        conn = get_user_db()
        cur = conn.cursor()
        cur.callproc(proc_name, params)
        results = []
        for res in cur.stored_results():
            cols = [desc[0] for desc in res.description]
            rows = res.fetchall()
            results.append(pd.DataFrame(rows, columns=cols))
        conn.close()
        return results, None
    except Exception as e:
        return None, str(e)

def call_market_proc(proc_name, params):
    """Call stored procedure in AgriMarket"""
    try:
        conn = get_market_db()
        cur = conn.cursor()
        cur.callproc(proc_name, params)
        results = []
        for res in cur.stored_results():
            cols = [desc[0] for desc in res.description]
            rows = res.fetchall()
            results.append(pd.DataFrame(rows, columns=cols))
        conn.close()
        return results, None
    except Exception as e:
        return None, str(e)

def hash_password(pwd: str) -> str:
    return hashlib.sha256(pwd.strip().encode("utf-8")).hexdigest()

def show_sql_panel(sql_code: str, title="🔍 Show Executed SQL Query"):
    with st.expander(title):
        st.code(sql_code, language="sql")


# ==============================================================================
# 3. AUTHENTICATION & SESSION STATE MANAGEMENT
# ==============================================================================
if "logged_in" not in st.session_state:
    st.session_state.logged_in = False
    st.session_state.user_id = None
    st.session_state.user_name = None
    st.session_state.user_type = None
    st.session_state.user_email = None
    st.session_state.user_phone = None
    st.session_state.district_id = None

def login_user(user_row):
    st.session_state.logged_in = True
    st.session_state.user_id = int(user_row["UserID"])
    st.session_state.user_name = user_row["Name"]
    st.session_state.user_type = user_row["UserType"]
    st.session_state.user_email = user_row["Email"]
    st.session_state.user_phone = user_row["PhoneNo"]
    st.session_state.district_id = user_row["DistrictID"]
    st.rerun()

def logout_user():
    st.session_state.logged_in = False
    st.session_state.user_id = None
    st.session_state.user_name = None
    st.session_state.user_type = None
    st.session_state.user_email = None
    st.session_state.user_phone = None
    st.session_state.district_id = None
    st.rerun()


# ==============================================================================
# 4. SIDEBAR: 1-CLICK DEMO ACCESS, SYSTEM ARCHITECTURE & LOGOUT
# ==============================================================================
with st.sidebar:
    st.image("https://img.icons8.com/color/96/wheat.png", width=64)
    st.markdown("## **AgriMarket & Vault**")
    st.caption("Two-Database Architecture (MySQL 8.x)")
    st.markdown('<span class="db-badge-users">Users DB: AgriUsers_DB</span> <span class="db-badge-market">Mandi DB: AgriMarket</span>', unsafe_allow_html=True)
    st.markdown("---")

    if st.session_state.logged_in:
        # User Logged In Profile Card
        st.markdown(f"""
            <div style="background:#f8fafc; border:1px solid #cbd5e1; padding:12px; border-radius:10px;">
                <p style="margin:0; font-size:1.15rem; font-weight:800; color:#1e293b;">{st.session_state.user_name}</p>
                <p style="margin:2px 0 0 0; color:#15803d; font-weight:700;">{'👨‍🌾 Farmer' if st.session_state.user_type == 'Farmer' else '💼 Trader' if st.session_state.user_type == 'Trader' else '🛡️ Administrator'}</p>
                <p style="margin:4px 0 0 0; font-size:0.8rem; color:#64748b;">📧 {st.session_state.user_email}</p>
                <p style="margin:2px 0 0 0; font-size:0.8rem; color:#64748b;">📱 {st.session_state.user_phone}</p>
            </div>
        """, unsafe_allow_html=True)

        if st.button("🚪 Log Out", use_container_width=True):
            logout_user()

        st.markdown("---")
        st.markdown("### ⚡ Quick Switch Account")

    else:
        st.markdown("### ⚡ 1-Click Fast Login")
        st.caption("Click any demo persona to sign in instantly:")

    # Quick 1-Click Login Personas (Always available for testing and viva)
    if st.button("👨‍🌾 Sourabh Gupta [Farmer]", use_container_width=True):
        u = fetch_df("SELECT * FROM System_User WHERE Email = 'sourabhgupta16062007@gmail.com';", db="users")
        if not u.empty: login_user(u.iloc[0])

    if st.button("👨‍🌾 Ramesh Patil [Farmer]", use_container_width=True):
        u = fetch_df("SELECT * FROM System_User WHERE UserID = 1;", db="users")
        if not u.empty: login_user(u.iloc[0])

    if st.button("💼 Vikram Joshi [Trader]", use_container_width=True):
        u = fetch_df("SELECT * FROM System_User WHERE UserID = 3;", db="users")
        if not u.empty: login_user(u.iloc[0])

    if st.button("🛡️ Admin / Professor Mode", use_container_width=True):
        st.session_state.logged_in = True
        st.session_state.user_id = 999
        st.session_state.user_name = "Chief Examiner / Admin"
        st.session_state.user_type = "Admin"
        st.session_state.user_email = "admin@agrimarket.gov.in"
        st.session_state.user_phone = "+910000000000"
        st.session_state.district_id = 1
        st.rerun()

    st.markdown("---")
    st.markdown("### 📊 Live Database Metrics")
    c1, c2 = st.columns(2)
    mandi_cnt = fetch_df("SELECT COUNT(*) AS c FROM Daily_Prices;", db="market")
    user_cnt = fetch_df("SELECT COUNT(*) AS c FROM System_User;", db="users")
    vault_cnt = fetch_df("SELECT COUNT(*) AS c FROM Farmer_Inventory;", db="users")
    alert_cnt = fetch_df("SELECT COUNT(*) AS c FROM Price_Alerts;", db="users")

    c1.metric("Mandi Prices", f"{mandi_cnt.iloc[0]['c']:,}")
    c2.metric("Users", user_cnt.iloc[0]["c"])
    c1.metric("Vault Batches", vault_cnt.iloc[0]["c"])
    c2.metric("Live Alerts", alert_cnt.iloc[0]["c"])


# ==============================================================================
# 5. HEADER & TOP BANNER
# ==============================================================================
st.markdown('<div class="farmer-title">🌾 AgriMarket: Smart Mandi & Crop Vault Platform</div>', unsafe_allow_html=True)
st.markdown('<div class="farmer-subtitle">Live APMC Market Rates, Real Landed Cost Analytics, and Farmer Harvest Storage Vault</div>', unsafe_allow_html=True)


# ==============================================================================
# 6. AUTHENTICATION HUB (SHOWN IF NOT LOGGED IN)
# ==============================================================================
if not st.session_state.logged_in:
    auth_col1, auth_col2 = st.columns([1.1, 1.4])

    with auth_col1:
        st.markdown("### 🔑 User Sign In (Farmers & Traders)")
        with st.form("form_farmer_login"):
            login_id = st.text_input("Email Address or Phone Number", placeholder="e.g. sourabhgupta16062007@gmail.com")
            login_pwd = st.text_input("Password", type="password", placeholder="Enter your password")
            submit_login = st.form_submit_button("Sign In to Portal", type="primary", use_container_width=True)

            if submit_login:
                if login_id.strip() and login_pwd.strip():
                    pwd_hash = hash_password(login_pwd)
                    sql = "SELECT * FROM System_User WHERE (Email = %s OR PhoneNo = %s);"
                    users = fetch_df(sql, (login_id.strip(), login_id.strip()), db="users")
                    if not users.empty and users.iloc[0]["PasswordHash"] == pwd_hash:
                        st.success(f"Welcome back, {users.iloc[0]['Name']}! Logging you in...")
                        login_user(users.iloc[0])
                    else:
                        st.error("❌ Invalid credentials. Please verify your Email/Phone and Password.")
                else:
                    st.warning("⚠️ Please provide both your Email/Phone and Password.")

        st.info("💡 **Instant 1-Click Login:** Click **Sourabh Gupta [Farmer]** or **Ramesh Patil [Farmer]** in the left sidebar.")

    with auth_col2:
        st.markdown("### 📝 Register New Account")
        st.caption("Fill in your details below. All fields marked with (*) are required.")

        with st.form("form_farmer_reg"):
            r_c1, r_c2 = st.columns(2)
            with r_c1:
                r_name = st.text_input("Full Name *", placeholder="e.g. Sourabh Gupta")
                r_email = st.text_input("Email Address *", placeholder="e.g. sourabh@gmail.com")
                r_phone = st.text_input("Phone Number *", placeholder="e.g. +919876543210")
                r_pwd = st.text_input("Password *", type="password")

            with r_c2:
                # Districts from AgriMarket
                d_df = fetch_df("SELECT DistrictID, DistrictName FROM District ORDER BY DistrictName;", db="market")
                d_opts = {row["DistrictName"]: row["DistrictID"] for _, row in d_df.iterrows()} if not d_df.empty else {}
                r_dist = st.selectbox("Operating District *", options=list(d_opts.keys()))

                r_role = st.selectbox("Account Role *", ["Farmer", "Trader"])
                clean_role = "Farmer" if "Farmer" in r_role else "Trader"

                if clean_role == "Farmer":
                    r_farm_size = st.number_input("Farm Size (Acres) *", min_value=0.5, max_value=500.0, value=5.0, step=0.5)
                    r_crop = st.text_input("Primary Crop *", value="Onion")
                    r_lic = ""
                    r_comp = ""
                else:
                    r_farm_size = 0.0
                    r_crop = ""
                    r_lic = st.text_input("APMC Mandi License Number *", placeholder="e.g. TRD-MH-001")
                    r_comp = st.text_input("Company / Trade Name *", placeholder="e.g. Gupta Mandi Traders Ltd")

            submit_reg = st.form_submit_button("Create Account & Sign In", type="primary", use_container_width=True)
            if submit_reg:
                missing = []
                if not r_name.strip(): missing.append("Full Name")
                if not r_email.strip(): missing.append("Email Address")
                if not r_phone.strip(): missing.append("Phone Number")
                if not r_pwd.strip(): missing.append("Password")
                if clean_role == "Trader":
                    if not r_lic.strip(): missing.append("License Number")
                    if not r_comp.strip(): missing.append("Company Name")

                if missing:
                    st.error(f"⚠️ Please fill in all required fields: **{', '.join(missing)}**")
                else:
                    pwd_hash = hash_password(r_pwd)
                    d_id = d_opts.get(r_dist)

                    ins_u_sql = """
                        INSERT INTO System_User (Name, PhoneNo, Email, PasswordHash, DistrictID, UserType)
                        VALUES (%s, %s, %s, %s, %s, %s);
                    """
                    ok, new_uid, _, err = execute_user_dml(ins_u_sql, (r_name.strip(), r_phone.strip(), r_email.strip(), pwd_hash, d_id, clean_role))
                    if ok:
                        if clean_role == "Farmer":
                            execute_user_dml("INSERT INTO Farmer (UserID, FarmSize_Acres, PrimaryCrop) VALUES (%s, %s, %s);", (new_uid, r_farm_size, r_crop.strip()))
                        else:
                            execute_user_dml("INSERT INTO Trader (UserID, LicenseNumber, CompanyName) VALUES (%s, %s, %s);", (new_uid, r_lic.strip(), r_comp.strip()))

                        st.success(f"🎉 Account created successfully for **{r_name}**! Logging you in now...")
                        new_row = pd.Series({"UserID": new_uid, "Name": r_name, "PhoneNo": r_phone, "Email": r_email, "UserType": clean_role, "DistrictID": d_id})
                        login_user(new_row)
                    else:
                        st.error(f"❌ Registration Failed: {err}")

    st.markdown("---")


# ==============================================================================
# 7. MAIN APPLICATION NAVIGATION (5 SIMPLE TABS)
# ==============================================================================
main_tabs = st.tabs([
    "🥦 Vegetables (Daily Market Rates)",
    "🍎 Fruits (Daily Market Rates)",
    "📦 My Crop Storage Vault & Profit Calculator",
    "🚚 Best Mandis & Trader Logistics Desk",
    "💻 Live SQL Inspector & Architecture (Viva Mode)"
])


# ==============================================================================
# TAB 1: 🥦 VEGETABLES (DAILY MARKET RATES)
# ==============================================================================
with main_tabs[0]:
    st.markdown("## 🥦 Fresh Vegetables Daily Market Rates")
    st.caption("Live wholesale auction prices for Onion, Tomato, Potato, Garlic, and Carrot across APMC mandis")

    # Fetch crop metrics for Vegetables
    veg_summary = fetch_df("""
        SELECT c.CommodityName, 
               ROUND(AVG(p.ModalPrice), 2) AS AvgModalPrice,
               ROUND(AVG(p.ModalPrice) / 100.0, 2) AS PricePerKg,
               MIN(p.MinPrice) AS MinPrice, 
               MAX(p.MaxPrice) AS MaxPrice,
               ROUND(SUM(p.ArrivalTonnes), 2) AS TotalArrivalTonnes,
               COUNT(p.PriceID) AS TotalTrades
        FROM Category cat
        JOIN Commodity c ON cat.CategoryID = c.CategoryID
        JOIN Variety v ON c.CommodityID = v.CommodityID
        JOIN Daily_Prices p ON v.VarietyID = p.VarietyID
        WHERE cat.CategoryName = 'Vegetables'
        GROUP BY c.CommodityName
        ORDER BY TotalArrivalTonnes DESC;
    """, db="market")

    # Render Visual Crop Cards for Vegetables
    VEG_ICONS = {
        "Onion": "🧅 Onion",
        "Tomato": "🍅 Tomato",
        "Potato": "🥔 Potato",
        "Garlic": "🧄 Garlic",
        "Carrot": "🥕 Carrot"
    }

    v_cols = st.columns(len(veg_summary)) if not veg_summary.empty else []
    for idx, row in veg_summary.iterrows():
        c_name = row["CommodityName"]
        display_label = VEG_ICONS.get(c_name, f"🥦 {c_name}")
        with v_cols[idx]:
            st.markdown(f"""
                <div class="crop-card">
                    <h3 style="margin:0 0 8px 0; color:#166534;">{display_label}</h3>
                    <p style="margin:0 0 6px 0;"><span class="price-pill-veg">₹ {row['AvgModalPrice']:,.0f} / Quintal</span></p>
                    <p style="margin:0 0 4px 0; font-size:1.05rem; font-weight:700; color:#1e293b;">Average Retail Benchmark: <b>₹ {row['PricePerKg']:.1f} / kg</b></p>
                    <p style="margin:0; font-size:0.85rem; color:#64748b;">Min: ₹{row['MinPrice']:,.0f} | Max: ₹{row['MaxPrice']:,.0f}</p>
                    <p style="margin:2px 0 0 0; font-size:0.85rem; color:#15803d; font-weight:600;">Arrivals: {row['TotalArrivalTonnes']:,.1f} Tonnes</p>
                </div>
            """, unsafe_allow_html=True)

    st.markdown("---")
    st.markdown("### 🔍 Search Vegetable Mandi Prices")
    col_vs1, col_vs2, col_vs3 = st.columns(3)
    sel_veg = col_vs1.selectbox("Select Vegetable", ["All"] + veg_summary["CommodityName"].tolist(), key="sel_veg_filter")
    
    dist_list = ["All"] + fetch_df("SELECT DISTINCT DistrictName FROM District ORDER BY DistrictName;", db="market")["DistrictName"].tolist()
    sel_dist_v = col_vs2.selectbox("Select District", dist_list, key="sel_dist_veg")
    veg_limit = col_vs3.slider("Number of Records (Limit)", 10, 200, 30, key="veg_lim")

    veg_q_where = ["cat.CategoryName = 'Vegetables'"]
    veg_params = []
    if sel_veg != "All":
        veg_q_where.append("c.CommodityName = %s")
        veg_params.append(sel_veg)
    if sel_dist_v != "All":
        veg_q_where.append("d.DistrictName = %s")
        veg_params.append(sel_dist_v)

    veg_table_query = f"""
        SELECT p.RecordDate AS 'Date',
               d.DistrictName AS 'District',
               m.MarketName AS 'APMC Mandi',
               c.CommodityName AS 'Crop',
               v.VarietyName AS 'Variety',
               p.ModalPrice AS 'Modal Price (₹/Qtl)',
               ROUND(p.ModalPrice / 100.0, 2) AS '₹ / kg',
               p.MinPrice AS 'Min Price (₹)',
               p.MaxPrice AS 'Max Price (₹)',
               p.ArrivalTonnes AS 'Arrival (Tonnes)'
        FROM Daily_Prices p
        JOIN Market m ON p.MarketID = m.MarketID
        JOIN District d ON m.DistrictID = d.DistrictID
        JOIN Variety v ON p.VarietyID = v.VarietyID
        JOIN Commodity c ON v.CommodityID = c.CommodityID
        JOIN Category cat ON c.CategoryID = cat.CategoryID
        WHERE {' AND '.join(veg_q_where)}
        ORDER BY p.RecordDate DESC, p.ModalPrice DESC
        LIMIT {veg_limit};
    """
    veg_df = fetch_df(veg_table_query, tuple(veg_params) if veg_params else None, db="market")
    st.dataframe(veg_df, use_container_width=True, hide_index=True)
    show_sql_panel(veg_table_query, "🔍 Show Executed SQL: Vegetables Filter Query")


# ==============================================================================
# TAB 2: 🍎 FRUITS (DAILY MARKET RATES)
# ==============================================================================
with main_tabs[1]:
    st.markdown("## 🍎 Fresh Fruits Daily Market Rates")
    st.caption("Live wholesale auction prices and arrivals for Apple, Banana, and Mango")

    fruit_summary = fetch_df("""
        SELECT c.CommodityName, 
               ROUND(AVG(p.ModalPrice), 2) AS AvgModalPrice,
               ROUND(AVG(p.ModalPrice) / 100.0, 2) AS PricePerKg,
               MIN(p.MinPrice) AS MinPrice, 
               MAX(p.MaxPrice) AS MaxPrice,
               ROUND(SUM(p.ArrivalTonnes), 2) AS TotalArrivalTonnes,
               COUNT(p.PriceID) AS TotalTrades
        FROM Category cat
        JOIN Commodity c ON cat.CategoryID = c.CategoryID
        JOIN Variety v ON c.CommodityID = v.CommodityID
        JOIN Daily_Prices p ON v.VarietyID = p.VarietyID
        WHERE cat.CategoryName = 'Fruits'
        GROUP BY c.CommodityName
        ORDER BY TotalArrivalTonnes DESC;
    """, db="market")

    FRUIT_ICONS = {
        "Apple": "🍎 Apple",
        "Banana": "🍌 Banana",
        "Mango": "🥭 Mango"
    }

    f_cols = st.columns(len(fruit_summary)) if not fruit_summary.empty else []
    for idx, row in fruit_summary.iterrows():
        c_name = row["CommodityName"]
        display_label = FRUIT_ICONS.get(c_name, f"🍎 {c_name}")
        with f_cols[idx]:
            st.markdown(f"""
                <div class="crop-card" style="border-color:#fed7aa;">
                    <h3 style="margin:0 0 8px 0; color:#c2410c;">{display_label}</h3>
                    <p style="margin:0 0 6px 0;"><span class="price-pill-fruit">₹ {row['AvgModalPrice']:,.0f} / Quintal</span></p>
                    <p style="margin:0 0 4px 0; font-size:1.05rem; font-weight:700; color:#1e293b;">Average Retail Benchmark: <b>₹ {row['PricePerKg']:.1f} / kg</b></p>
                    <p style="margin:0; font-size:0.85rem; color:#64748b;">Min: ₹{row['MinPrice']:,.0f} | Max: ₹{row['MaxPrice']:,.0f}</p>
                    <p style="margin:2px 0 0 0; font-size:0.85rem; color:#ea580c; font-weight:600;">Arrivals: {row['TotalArrivalTonnes']:,.1f} Tonnes</p>
                </div>
            """, unsafe_allow_html=True)

    st.markdown("---")
    st.markdown("### 🔍 Search Fruit Mandi Prices")
    col_fs1, col_fs2, col_fs3 = st.columns(3)
    sel_fruit = col_fs1.selectbox("Select Fruit", ["All"] + fruit_summary["CommodityName"].tolist(), key="sel_fruit_filter")
    sel_dist_f = col_fs2.selectbox("Select District", dist_list, key="sel_dist_fruit")
    fruit_limit = col_fs3.slider("Number of Records (Limit)", 10, 200, 30, key="fruit_lim")

    fruit_q_where = ["cat.CategoryName = 'Fruits'"]
    fruit_params = []
    if sel_fruit != "All":
        fruit_q_where.append("c.CommodityName = %s")
        fruit_params.append(sel_fruit)
    if sel_dist_f != "All":
        fruit_q_where.append("d.DistrictName = %s")
        fruit_params.append(sel_dist_f)

    fruit_table_query = f"""
        SELECT p.RecordDate AS 'Date',
               d.DistrictName AS 'District',
               m.MarketName AS 'APMC Mandi',
               c.CommodityName AS 'Crop',
               v.VarietyName AS 'Variety',
               p.ModalPrice AS 'Modal Price (₹/Qtl)',
               ROUND(p.ModalPrice / 100.0, 2) AS '₹ / kg',
               p.MinPrice AS 'Min Price (₹)',
               p.MaxPrice AS 'Max Price (₹)',
               p.ArrivalTonnes AS 'Arrival (Tonnes)'
        FROM Daily_Prices p
        JOIN Market m ON p.MarketID = m.MarketID
        JOIN District d ON m.DistrictID = d.DistrictID
        JOIN Variety v ON p.VarietyID = v.VarietyID
        JOIN Commodity c ON v.CommodityID = c.CommodityID
        JOIN Category cat ON c.CategoryID = cat.CategoryID
        WHERE {' AND '.join(fruit_q_where)}
        ORDER BY p.RecordDate DESC, p.ModalPrice DESC
        LIMIT {fruit_limit};
    """
    fruit_df = fetch_df(fruit_table_query, tuple(fruit_params) if fruit_params else None, db="market")
    st.dataframe(fruit_df, use_container_width=True, hide_index=True)
    show_sql_panel(fruit_table_query, "🔍 Show Executed SQL: Fruits Filter Query")


# ==============================================================================
# TAB 3: 📦 CROP STORAGE VAULT & PROFIT CALCULATOR
# ==============================================================================
with main_tabs[2]:
    st.markdown("## 📦 My Crop Storage Vault & Profit Calculator")
    st.caption("Database: `AgriUsers_DB.Farmer_Inventory` joined with live `AgriMarket` daily wholesale prices")

    # Current user ID to evaluate
    current_uid = st.session_state.user_id if st.session_state.logged_in else 5 # default to Sourabh Gupta

    # Procedure call in AgriUsers_DB
    val_res, val_err = call_user_proc("sp_farmer_inventory_valuation", [current_uid])
    val_data = val_res[0] if val_res else pd.DataFrame()

    show_sql_panel(f"CALL AgriUsers_DB.sp_farmer_inventory_valuation({current_uid});", "🔍 Show Executed SQL: sp_farmer_inventory_valuation")

    if not val_data.empty:
        tot_qtl = float(val_data["QuantityQuintals"].sum() or 0.0)
        tot_cost = float(val_data["TotalInvestmentCost"].sum() or 0.0)
        tot_market_val = float(val_data["CurrentMarketValuation"].sum() or 0.0)
        tot_net_pl = float(val_data["EstimatedNetProfitLossINR"].sum() or 0.0)
        tot_roi = ((tot_market_val - tot_cost) / tot_cost * 100.0) if tot_cost > 0 else 0.0

        kp1, kp2, kp3, kp4 = st.columns(4)
        kp1.metric("📦 Total Stored Harvest", f"{tot_qtl:,.1f} Quintals", f"{tot_qtl/10.0:.1f} Tonnes")
        kp2.metric("💰 Total Cultivation Cost", f"₹ {tot_cost:,.2f}")
        kp3.metric("📈 Live Market Valuation", f"₹ {tot_market_val:,.2f}")
        kp4.metric("💵 Estimated Net Profit / Loss", f"₹ {tot_net_pl:,.2f}", delta=f"{tot_net_pl:,.2f} INR ({tot_roi:.1f}%)")

        st.markdown("### 📋 Stored Harvest Batches in Vault")
        st.dataframe(
            val_data[[
                "InventoryID", "CommodityName", "VarietyName", "QuantityQuintals",
                "CultivationCostPerQtl", "CurrentMandiPricePerQtl", "EstimatedNetProfitLossINR",
                "ROIPercent", "HarvestDate", "StorageStatus", "SalesRecommendation", "BenchmarkMandi"
            ]],
            use_container_width=True,
            hide_index=True
        )
    else:
        st.info("💡 No stored crop batches currently recorded. Use the form below to store your harvest.")

    st.markdown("---")
    col_add_inv, col_upd_inv = st.columns([1.2, 1])

    with col_add_inv:
        st.markdown("#### ➕ Store New Harvest Batch in Vault")
        with st.form("form_add_farmer_batch"):
            # Variety list from AgriMarket
            vars_df = fetch_df("""
                SELECT v.VarietyID, CONCAT(c.CommodityName, ' - ', v.VarietyName) AS CropName
                FROM Variety v
                JOIN Commodity c ON v.CommodityID = c.CommodityID
                ORDER BY c.CommodityName, v.VarietyName;
            """, db="market")
            var_dict = {r["CropName"]: r["VarietyID"] for _, r in vars_df.iterrows()} if not vars_df.empty else {}
            sel_crop_var = st.selectbox("Crop & Variety", list(var_dict.keys()))

            cq1, cq2 = st.columns(2)
            in_qtl = cq1.number_input("Quantity (Quintals)", min_value=1.0, max_value=5000.0, value=100.0, step=10.0)
            in_cost = cq2.number_input("Cultivation Cost (₹ / Qtl)", min_value=100.0, max_value=40000.0, value=1200.0, step=50.0)

            ch1, ch2 = st.columns(2)
            in_hdate = ch1.date_input("Harvest Date", value=date.today())
            in_loc = ch2.text_input("Storage Location", value="Mandi Cold Storage Hub")

            submit_inv = st.form_submit_button("Save Harvest to Vault", type="primary")
            if submit_inv:
                vid = var_dict.get(sel_crop_var)
                ins_inv_sql = """
                    INSERT INTO AgriUsers_DB.Farmer_Inventory (FarmerUserID, VarietyID, QuantityQuintals, CultivationCostPerQtl, HarvestDate, StorageStatus, StorageLocation)
                    VALUES (%s, %s, %s, %s, %s, 'IN_STORAGE', %s);
                """
                ok, iid, _, err = execute_user_dml(ins_inv_sql, (current_uid, vid, in_qtl, in_cost, in_hdate, in_loc))
                if ok:
                    st.success(f"🎉 Harvest batch #{iid} stored successfully!")
                    st.rerun()
                else:
                    st.error(f"Error: {err}")

    with col_upd_inv:
        st.markdown("#### 🔄 Update Batch Status or Sell")
        if not val_data.empty:
            with st.form("form_upd_status"):
                b_opts = {f"Batch #{r['InventoryID']}: {r['CommodityName']} ({r['QuantityQuintals']} Qtl)": r["InventoryID"] for _, r in val_data.iterrows()}
                sel_b = st.selectbox("Select Batch", list(b_opts.keys()))
                new_st = st.selectbox("New Status", ["IN_STORAGE", "READY_TO_SELL", "SOLD"])

                cu1, cu2 = st.columns(2)
                btn_upd = cu1.form_submit_button("Update Status")
                btn_del = cu2.form_submit_button("Delete Batch")

                if btn_upd:
                    bid = b_opts.get(sel_b)
                    execute_user_dml("UPDATE AgriUsers_DB.Farmer_Inventory SET StorageStatus = %s WHERE InventoryID = %s;", (new_st, bid))
                    st.success("Status updated successfully!")
                    st.rerun()

                if btn_del:
                    bid = b_opts.get(sel_b)
                    execute_user_dml("DELETE FROM AgriUsers_DB.Farmer_Inventory WHERE InventoryID = %s;", (bid,))
                    st.warning("Batch deleted.")
                    st.rerun()


# ==============================================================================
# TAB 4: 🚚 BEST MANDIS & TRADER LOGISTICS DESK
# ==============================================================================
with main_tabs[3]:
    st.markdown("## 🚚 Where Should I Sell Today? & Trader Logistics Desk")
    st.caption("Best-paying APMC mandis for farmers & true landed cost calculator with highway freight for traders")

    col_bm1, col_bm2 = st.columns([1.1, 1.3])

    with col_bm1:
        st.markdown("### 🏆 Highest-Paying Mandis (`sp_find_best_mandis`)")
        comm_all = fetch_df("SELECT DISTINCT CommodityName FROM Commodity ORDER BY CommodityName;", db="market")["CommodityName"].tolist()
        b_crop = st.selectbox("Select Crop", comm_all, index=comm_all.index("Onion") if "Onion" in comm_all else 0)
        b_limit = st.slider("Top Mandis Count", 3, 10, 5)

        best_m_res, _ = call_market_proc("sp_find_best_mandis", [b_crop, date(2026, 1, 1), date(2026, 10, 10), b_limit])
        show_sql_panel(f"CALL AgriMarket.sp_find_best_mandis('{b_crop}', '2026-01-01', '2026-10-10', {b_limit});", "🔍 Show Executed SQL: sp_find_best_mandis")

        if best_m_res and not best_m_res[0].empty:
            st.dataframe(best_m_res[0][["MarketName", "DistrictName", "AvgModalPrice", "PeakMaxPrice", "TotalArrivalTonnes"]], use_container_width=True, hide_index=True)
        else:
            st.info("No records found.")

    with col_bm2:
        st.markdown("### 🚛 True Landed Cost Calculator (`sp_buyer_bulk_procurement_plan`)")
        st.caption("Mandi Auction Price + Highway Freight (from District_Logistics) + 1.05% APMC Cess = True Landed Cost")

        c_lc1, c_lc2 = st.columns(2)
        lc_crop = c_lc1.selectbox("Crop", comm_all, index=comm_all.index("Tomato") if "Tomato" in comm_all else 0, key="lc_crop_box")
        lc_hub = c_lc2.selectbox("Delivery Destination Hub", ["Mumbai (Vashi Hub)", "Pune (Market Yard Hub)"])

        plan_res, _ = call_market_proc("sp_buyer_bulk_procurement_plan", [lc_crop, 50.00, lc_hub])
        show_sql_panel(f"CALL AgriMarket.sp_buyer_bulk_procurement_plan('{lc_crop}', 50.00, '{lc_hub}');", "🔍 Show Executed SQL: sp_buyer_bulk_procurement_plan")

        if plan_res and not plan_res[0].empty:
            st.dataframe(plan_res[0][["MarketName", "DistrictName", "MandiModalPricePerQtl", "TransportDistanceKm", "LandedCostPerQuintal", "SupplyFeasibility"]].head(6), use_container_width=True, hide_index=True)
        else:
            st.info("Cost not available.")

    # Arbitrage Radar
    st.markdown("---")
    st.markdown("### ⚡ Inter-District Arbitrage Radar (`sp_buyer_arbitrage_radar`)")
    st.caption("Buy low in one district and sell high in another district on the exact same trading date")

    ca1, ca2 = st.columns(2)
    arb_crop = ca1.selectbox("Arbitrage Crop", comm_all, index=comm_all.index("Onion") if "Onion" in comm_all else 0)
    arb_date = ca2.date_input("Trading Date", value=date(2026, 5, 15))

    arb_res, _ = call_market_proc("sp_buyer_arbitrage_radar", [arb_crop, arb_date, 400.00])
    show_sql_panel(f"CALL AgriMarket.sp_buyer_arbitrage_radar('{arb_crop}', '{arb_date}', 400.00);", "🔍 Show Executed SQL: sp_buyer_arbitrage_radar")

    if arb_res and not arb_res[0].empty:
        st.dataframe(arb_res[0].head(5), use_container_width=True, hide_index=True)
    else:
        st.info("No arbitrage spread >= ₹400 found on this date.")


# ==============================================================================
# TAB 5: 💻 LIVE SQL INSPECTOR (PROFESSOR VIVA MODE)
# ==============================================================================
with main_tabs[4]:
    st.markdown("## 💻 Live SQL Terminal & System Architecture Inspector")
    st.caption("Two-Database System Architecture: `AgriUsers_DB` (Users & Vault) + `AgriMarket` (Mandi Prices)")

    col_arch1, col_arch2 = st.columns(2)
    with col_arch1:
        st.markdown("""
        #### 📦 Database 1: `AgriUsers_DB`
        * `System_User`: User IDs, Name, Phone, Email, Password Hash
        * `Farmer`: Farmer details (Farm size, primary crop)
        * `Trader`: Trader details (APMC license, company name)
        * `Farmer_Inventory`: Stored harvest batches, cultivation costs, net P&L
        * `Price_Alerts`: Real-time SMS & Email price target alerts
        * `Email_Notifications_Log`: Automated email notification queue & outbox logs
        * `Buyer_Procurement_Orders`: Auto-generated 25 MT purchase orders
        """)
    with col_arch2:
        st.markdown("""
        #### 🌾 Database 2: `AgriMarket`
        * `Daily_Prices`: 40,307+ daily APMC auction records
        * `Market`: 90 APMC wholesale mandis
        * `District`: 13 Maharashtra districts
        * `Commodity` & `Variety`: Commodities & Varieties across Vegetables and Fruits
        * `District_Logistics`: 26 Highway route distances and freight rates to Pune & Mumbai
        * Views: `vw_mandi_complete_feed`, `vw_buyer_mandi_risk_index`
        """)

    st.markdown("---")
    st.markdown("### ▶️ Execute Custom SQL Query")
    chosen_db = st.radio("Target Database:", ["AgriMarket (Mandi Data)", "AgriUsers_DB (Users & Inventory)"], horizontal=True)
    db_key = "market" if "AgriMarket" in chosen_db else "users"

    default_sql = "SELECT * FROM vw_district_crop_summary LIMIT 10;" if db_key == "market" else "SELECT * FROM System_User;"
    user_sql = st.text_area("SQL Statement:", value=default_sql, height=120)

    if st.button("Run SQL Query", type="primary"):
        res_df = fetch_df(user_sql, db=db_key)
        if not res_df.empty:
            st.success(f"Returned {len(res_df):,} records:")
            st.dataframe(res_df, use_container_width=True)
        else:
            st.info("Query returned 0 rows or executed successfully.")
