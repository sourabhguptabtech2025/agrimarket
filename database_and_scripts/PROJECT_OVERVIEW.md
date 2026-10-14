# AgriMarket: End-to-End Smart Mandi Intelligence Platform
**Project Workspace:** `C:\Users\HP\Documents\sql_mandi\database_and_scripts`  
**Database Name:** `AgriMarket` | **Host:** `localhost:3306` | **Database User:** `root`  
**Web Dashboard URL:** [http://localhost:8501](http://localhost:8501)

---

## 1. System Summary & Project Portfolio

AgriMarket transforms uncurated agricultural market data from Agmarknet into an enterprise decision-support and trading platform. It unifies high-performance MySQL schema design, ETL data cleaning, procedural business logic, real-time trigger automation, and an interactive Streamlit web dashboard.

```
📁 C:\Users\HP\Documents\sql_mandi\database_and_scripts
│
├── 🚀 run_app.bat                      <- 1-Click Windows Launcher to start web portal
├── 🌐 app.py                           <- Full-Stack Streamlit Web Application (Port 8501)
│
├── 📦 ingest_agrimarket.py             <- Step 1: Automated ETL & Batch Ingestion Pipeline
├── 📜 schema_and_seed.sql              <- Core 11-Table Relational Schema & Seed DDL/DML
├── 📄 ingestion_summary.txt            <- Ingestion Audit: 40,307 cleaned rows imported
│
├── ⚙️ advanced_sql_features.sql        <- Step 10: Logistics, Views, Functions, Procedures & Triggers
├── 📊 real_world_queries.sql           <- 10 Production Analytical SQL Queries
├── 📋 sql_features_guide.md            <- Complete Technical & Viva Reference Guide
├── 🔬 run_verification.py              <- Automated Database Test Runner
├── 📝 sql_execution_verification.txt   <- Audit Transcript: 100% test pass record
│
├── 🔄 upgrade_auth_inventory_email.sql <- Step 11 Migration: Email Auth, Crop Vault & Email Queue
└── 🏛️ setup_user_database.sql         <- Step 12 Architecture: Separate Dedicated AgriUsers_DB
```

---

## 2. Relational Database Architecture (`AgriMarket`)

### The 13 Relational Tables:
| # | Table Name | Type | Key Responsibility |
| :-: | :--- | :--- | :--- |
| **1** | `State` | Lookup | State entity (`StateID`, `StateName` UNIQUE). |
| **2** | `District` | Lookup | District mapped to State with cascading deletion. |
| **3** | `Market` | Lookup | APMC Mandi market centers mapped to District. |
| **4** | `Category` | Lookup | Commodity Groups (`Fruits`, `Vegetables`). |
| **5** | `Commodity` | Lookup | Agricultural crops (`Onion`, `Tomato`, `Apple`, etc.). |
| **6** | `Variety` | Lookup | Specific crop varieties (`Red`, `Unhali`, `Totapuri`, etc.). |
| **7** | `Daily_Prices` | Fact Table | 40,307+ daily mandi auction records with indexed dates. |
| **8** | `System_User` | Auth / Base | Base user table (`UserID`, `Name`, `PhoneNo`, `Email`, `PasswordHash`, `UserType`). |
| **9** | `Farmer` | EER Subclass | Farmer profile extension (`FarmSize_Acres`, `PrimaryCrop`). |
| **10** | `Trader` | EER Subclass | Trader profile extension (`LicenseNumber`, `CompanyName`). |
| **11** | `Price_Alerts` | Business Feature | Real-time user price target monitors (`ABOVE` / `BELOW`). |
| **12** | `District_Logistics` | Logistics Engine | 26 highway routes with distances (km) and freight rates to Pune & Mumbai hubs. |
| **13** | `Buyer_Procurement_Orders` | Automation | Auto-generated 25-Tonne purchase requisitions created by triggers. |
| **14** | `Farmer_Inventory` | Vault Feature | Stored crop batches tracking quintals, cultivation cost, and status. |
| **15** | `Email_Notifications_Log` | Notification Engine | Automated email queue with formatted HTML alert payloads. |

---

## 3. Database Programmability Suite

### A. The 3 Master Analytical Views:
1. **`vw_mandi_complete_feed`**: Unified 7-table master feed with intraday price spreads.
2. **`vw_district_crop_summary`**: Regional aggregations of arrivals, average modal prices, and price ranges.
3. **`vw_buyer_mandi_risk_index`**: Standard deviation and volatility % classifying mandis into risk ratings (`STABLE PRICING`, `MODERATE RISK`, `HIGH VOLATILITY`).

### B. The 4 Stored Functions:
1. `fn_price_spread_pct(min_p, max_p)`: Auction price dispersion percentage.
2. `fn_inflow_status(tonnes)`: Supply volume tier (`Heavy Glut`, `Moderate Supply`, `Low Supply`).
3. `fn_calculate_landed_cost(modal_price, dist_km, freight_rate, cess_pct)`: True terminal landed cost in ₹/Qtl.
4. `fn_quality_discount_ratio(variety_modal, benchmark_modal)`: Variety premium or discount % vs. crop benchmark.

### C. The 5 Stored Procedures:
1. `sp_find_best_mandis(crop, start_date, end_date, limit)`: Ranks top-paying mandis for farmers.
2. `sp_buyer_bulk_procurement_plan(crop, tonnes, hub)`: Ranks mandis by lowest landed cost (including logistics + 1.05% APMC cess).
3. `sp_buyer_arbitrage_radar(crop, date, min_margin)`: Discovers buy-low / sell-high spatial arbitrage across districts.
4. `sp_check_user_alerts(user_id)`: Audits active user alerts against live prices (`TARGET BREACHED` vs `MONITORING`).
5. `sp_farmer_inventory_valuation(farmer_id)`: Evaluates farmer stored crop inventory, net profit/loss, ROI %, and sales recommendations.

### D. The 2 Real-Time Triggers:
1. `trg_after_price_insert_alert` (`AFTER INSERT ON Daily_Prices`):
   - Updates `Price_Alerts.TriggeredMessage` when thresholds are hit.
   - Automatically queues an HTML email notification into `Email_Notifications_Log`.
2. `trg_buyer_auto_procurement_order` (`AFTER INSERT ON Daily_Prices`):
   - Automatically generates a 25-Tonne purchase order in `Buyer_Procurement_Orders` when price dips below a trader's `BELOW` alert target.

---

## 4. Web Application Modules (`app.py`)

1. **Authentication & EER Registration:**
   - 1-click **Quick Demo Login** for Ramesh Patil (Farmer), Suresh Shinde (Farmer), Vikram Joshi (Trader), Anil Deshmukh (Trader), and Admin/Examiner.
   - Registration handles polymorphic inserts into `System_User` + `Farmer`/`Trader`.
2. **Module 1: Farmer Storage Vault & Profit Calculator:**
   - Real-time valuation of stored batches, P&L in INR, ROI %, and sales recommendations.
   - Form to add new harvest batches or change storage status.
   - "Where Should I Sell Today?" procedure runner with Plotly charts.
3. **Module 2: Buyer & Trader Procurement Desk:**
   - Landed Cost Calculator routing delivery to Mumbai (Vashi) or Pune (Market Yard).
   - Live Arbitrage Radar identifying profit margins.
   - Mandi Risk & Volatility matrix with bubble scatter charts.
4. **Module 3: Price Alerts & Automated Email Center:**
   - Configurable price monitors.
   - Real SMTP email dispatcher (Gmail) + fallback Local HTML Outbox viewer.
   - Live Trigger Simulator form demonstrating real-time trigger firing upon price entry.
5. **Module 4: Master Mandi Explorer & Live SQL Terminal:**
   - Cascading search across all 40,307 records with CSV export.
   - Interactive SQL Terminal pre-loaded with the 10 production analytical queries.
   - **"Show Executed SQL Query"** toggle on every module for viva transparency.

---

## 5. Demonstration Credentials

All pre-seeded demo accounts share the password: **`pass123`**

| Role | Name | Email | Phone | District |
| :--- | :--- | :--- | :--- | :--- |
| **Farmer** | Ramesh Patil | `ramesh.patil@agrimarket.in` | `+919822011223` | Pune |
| **Farmer** | Suresh Shinde | `suresh.shinde@agrimarket.in` | `+919822022334` | Nashik |
| **Trader** | Vikram Joshi | `vikram.joshi@agrimarket.in` | `+919822033445` | Pune |
| **Trader** | Anil Deshmukh | `anil.deshmukh@agrimarket.in` | `+919822044556` | Ahilyanagar |
| **Admin** | Chief Examiner | `admin@agrimarket.gov.in` | `+910000000000` | Maharashtra |

---

## 6. How to Run Anytime

Double-click [`run_app.bat`](file:///C:/Users/HP/Documents/sql_mandi/database_and_scripts/run_app.bat) or execute in terminal:
```powershell
python -m streamlit run "C:\Users\HP\Documents\sql_mandi\database_and_scripts\app.py"
```
Access the application at: **`http://localhost:8501`**
