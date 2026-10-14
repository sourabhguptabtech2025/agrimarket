"""
AgriMarket Data Ingestion and Seeding Pipeline
----------------------------------------------
Automated discovery, cleaning, schema provisioning, and batch ingestion of Agmarknet CSV data into MySQL.
"""

import os
import sys
import glob
import getpass
import hashlib
import argparse
from datetime import datetime
import pandas as pd
import mysql.connector
from mysql.connector import Error

# Configuration Constants
BASE_DIR = r"C:\Users\HP\Documents\sql_mandi"
OUTPUT_DIR = os.path.join(BASE_DIR, "database_and_scripts")
DB_NAME = "AgriMarket"
BATCH_SIZE = 3000

EXPECTED_COLUMNS = [
    'State/UT', 'District', 'Market', 'Commodity Group', 'Commodity',
    'Variety', 'Grade', 'Min Price', 'Max Price', 'Modal Price',
    'Price Unit', 'Arrival Quantity', 'Arrival Unit', 'Arrival Date'
]

STRING_COLUMNS = [
    'State/UT', 'District', 'Market', 'Commodity Group', 'Commodity', 'Variety', 'Grade'
]

NUMERIC_COLUMNS = [
    'Min Price', 'Max Price', 'Modal Price', 'Arrival Quantity'
]


def parse_args():
    parser = argparse.ArgumentParser(description="AgriMarket MySQL Ingestion Script")
    parser.add_argument("--host", default="localhost", help="MySQL Host (default: localhost)")
    parser.add_argument("--user", default="root", help="MySQL User (default: root)")
    parser.add_argument("--password", "-p", default=None, help="MySQL Password (optional, will prompt if omitted)")
    parser.add_argument("--port", type=int, default=3306, help="MySQL Port (default: 3306)")
    return parser.parse_args()


def get_password(cli_password):
    if cli_password is not None:
        return cli_password
    env_pwd = os.environ.get("MYSQL_PWD") or os.environ.get("MYSQL_PASSWORD")
    if env_pwd:
        return env_pwd
    return getpass.getpass("Enter MySQL root password: ")


# ==============================================================================
# 1. FILE DISCOVERY
# ==============================================================================
def discover_csv_files(base_dir, output_dir):
    print("=" * 70)
    print("STEP 1: FILE DISCOVERY")
    print("=" * 70)
    discovered = []
    # Search recursively for all .csv files
    for root, dirs, files in os.walk(base_dir):
        # Ignore output directory
        if os.path.abspath(root).startswith(os.path.abspath(output_dir)):
            continue
        for file in files:
            if file.lower().endswith(".csv"):
                file_path = os.path.join(root, file)
                try:
                    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                        raw_line_count = sum(1 for _ in f)
                except Exception as e:
                    raw_line_count = -1
                discovered.append((file_path, raw_line_count))
                rel_path = os.path.relpath(file_path, base_dir)
                print(f"  [Found] {rel_path} | Raw Lines: {raw_line_count:,}")

    print(f"\nTotal CSV files discovered: {len(discovered)}\n")
    return discovered


# ==============================================================================
# 2. CSV CLEANING & STANDARDIZATION
# ==============================================================================
def clean_and_prepare_data(file_info_list):
    print("=" * 70)
    print("STEP 2: CSV CLEANING & STANDARDIZATION")
    print("=" * 70)
    cleaned_frames = []
    skipped_files = []
    processed_files = []

    for file_path, raw_count in file_info_list:
        file_name = os.path.basename(file_path)
        try:
            # Rule 1: Skip row 0 (title banner)
            df = pd.read_csv(file_path, skiprows=1)
        except Exception as e:
            print(f"  [Error Reading] {file_name}: {e}")
            skipped_files.append((file_name, f"Read error: {e}"))
            continue

        # Rule 2: Standardize on the 14 expected columns
        if list(df.columns) != EXPECTED_COLUMNS:
            missing = [c for c in EXPECTED_COLUMNS if c not in df.columns]
            extra = [c for c in df.columns if c not in EXPECTED_COLUMNS]
            reason = f"Non-standard schema (Missing: {missing}, Extra: {extra})"
            print(f"  [Skipped] {file_name}: {reason}")
            skipped_files.append((file_name, reason))
            continue

        initial_len = len(df)

        # Rule 3: Strip string columns
        for col in STRING_COLUMNS:
            df[col] = df[col].astype(str).str.strip()

        # Rule 4: Strip commas and convert numeric columns to float
        for col in NUMERIC_COLUMNS:
            df[col] = df[col].astype(str).str.replace(",", "", regex=False).str.strip()
            df[col] = pd.to_numeric(df[col], errors="coerce")

        # Rule 5: Convert Arrival Date from 'DD-MM-YYYY' to 'YYYY-MM-DD'
        df['Arrival Date'] = pd.to_datetime(df['Arrival Date'], format='%d-%m-%Y', errors='coerce').dt.strftime('%Y-%m-%d')

        # Drop any row where essential foreign key components or dates failed conversion
        clean_df = df.dropna(subset=['State/UT', 'District', 'Market', 'Commodity Group', 'Commodity', 'Variety', 'Arrival Date'])
        cleaned_frames.append(clean_df)
        processed_files.append((file_name, initial_len, len(clean_df)))
        print(f"  [Cleaned] {file_name} | Rows: {len(clean_df):,}")

    if not cleaned_frames:
        raise ValueError("No valid CSV files matched the expected 14-column format.")

    combined_df = pd.concat(cleaned_frames, ignore_index=True)
    print(f"\nTotal combined cleaned records: {len(combined_df):,}\n")
    return combined_df, processed_files, skipped_files


# ==============================================================================
# 3. DATABASE SCHEMA CREATION (11 TABLES)
# ==============================================================================
def create_schema(cursor):
    print("=" * 70)
    print("STEP 3: PROVISIONING 11-TABLE SCHEMA")
    print("=" * 70)

    # Disable foreign key checks during setup to ensure clean idempotent run
    cursor.execute("SET FOREIGN_KEY_CHECKS = 0;")

    # Drop tables if they exist with outdated schemas
    tables_to_drop = [
        "Daily_Prices", "Price_Alerts", "Farmer", "Trader",
        "System_User", "Variety", "Commodity", "Category",
        "Market", "District", "State"
    ]
    for tbl in tables_to_drop:
        cursor.execute(f"DROP TABLE IF EXISTS `{tbl}`;")

    tables_ddl = [
        # 1. State
        """
        CREATE TABLE IF NOT EXISTS State (
            StateID INT AUTO_INCREMENT PRIMARY KEY,
            StateName VARCHAR(100) NOT NULL UNIQUE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """,
        # 2. District
        """
        CREATE TABLE IF NOT EXISTS District (
            DistrictID INT AUTO_INCREMENT PRIMARY KEY,
            StateID INT NOT NULL,
            DistrictName VARCHAR(100) NOT NULL,
            UNIQUE KEY uq_state_district (StateID, DistrictName),
            FOREIGN KEY (StateID) REFERENCES State(StateID) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """,
        # 3. Market
        """
        CREATE TABLE IF NOT EXISTS Market (
            MarketID INT AUTO_INCREMENT PRIMARY KEY,
            DistrictID INT NOT NULL,
            MarketName VARCHAR(150) NOT NULL,
            UNIQUE KEY uq_district_market (DistrictID, MarketName),
            FOREIGN KEY (DistrictID) REFERENCES District(DistrictID) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """,
        # 4. Category
        """
        CREATE TABLE IF NOT EXISTS Category (
            CategoryID INT AUTO_INCREMENT PRIMARY KEY,
            CategoryName VARCHAR(100) NOT NULL UNIQUE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """,
        # 5. Commodity
        """
        CREATE TABLE IF NOT EXISTS Commodity (
            CommodityID INT AUTO_INCREMENT PRIMARY KEY,
            CategoryID INT NOT NULL,
            CommodityName VARCHAR(100) NOT NULL,
            UNIQUE KEY uq_category_commodity (CategoryID, CommodityName),
            FOREIGN KEY (CategoryID) REFERENCES Category(CategoryID) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """,
        # 6. Variety
        """
        CREATE TABLE IF NOT EXISTS Variety (
            VarietyID INT AUTO_INCREMENT PRIMARY KEY,
            CommodityID INT NOT NULL,
            VarietyName VARCHAR(100) NOT NULL,
            UNIQUE KEY uq_commodity_variety (CommodityID, VarietyName),
            FOREIGN KEY (CommodityID) REFERENCES Commodity(CommodityID) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """,
        # 7. Daily_Prices
        """
        CREATE TABLE IF NOT EXISTS Daily_Prices (
            PriceID INT AUTO_INCREMENT PRIMARY KEY,
            MarketID INT NOT NULL,
            VarietyID INT NOT NULL,
            Grade VARCHAR(50),
            RecordDate DATE,
            MinPrice DECIMAL(10,2),
            MaxPrice DECIMAL(10,2),
            ModalPrice DECIMAL(10,2),
            ArrivalTonnes DECIMAL(12,2),
            INDEX idx_date (RecordDate),
            INDEX idx_market_var (MarketID, VarietyID),
            FOREIGN KEY (MarketID) REFERENCES Market(MarketID) ON DELETE CASCADE,
            FOREIGN KEY (VarietyID) REFERENCES Variety(VarietyID) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """,
        # 8. System_User
        """
        CREATE TABLE IF NOT EXISTS System_User (
            UserID INT AUTO_INCREMENT PRIMARY KEY,
            Name VARCHAR(100) NOT NULL,
            PhoneNo VARCHAR(15) UNIQUE NOT NULL,
            PasswordHash VARCHAR(255) NOT NULL,
            DistrictID INT,
            UserType ENUM('Farmer', 'Trader') NOT NULL,
            FOREIGN KEY (DistrictID) REFERENCES District(DistrictID) ON DELETE SET NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """,
        # 9. Farmer
        """
        CREATE TABLE IF NOT EXISTS Farmer (
            UserID INT PRIMARY KEY,
            FarmSize_Acres DECIMAL(6,2),
            PrimaryCrop VARCHAR(100),
            FOREIGN KEY (UserID) REFERENCES System_User(UserID) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """,
        # 10. Trader
        """
        CREATE TABLE IF NOT EXISTS Trader (
            UserID INT PRIMARY KEY,
            LicenseNumber VARCHAR(50) UNIQUE,
            CompanyName VARCHAR(150),
            FOREIGN KEY (UserID) REFERENCES System_User(UserID) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """,
        # 11. Price_Alerts
        """
        CREATE TABLE IF NOT EXISTS Price_Alerts (
            AlertID INT AUTO_INCREMENT PRIMARY KEY,
            UserID INT NOT NULL,
            CommodityID INT NOT NULL,
            TargetPrice DECIMAL(10,2) NOT NULL,
            AlertCondition ENUM('ABOVE', 'BELOW') DEFAULT 'ABOVE',
            IsActive BOOLEAN DEFAULT TRUE,
            TriggeredMessage VARCHAR(255) DEFAULT NULL,
            FOREIGN KEY (UserID) REFERENCES System_User(UserID) ON DELETE CASCADE,
            FOREIGN KEY (CommodityID) REFERENCES Commodity(CommodityID) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """
    ]

    for ddl in tables_ddl:
        cursor.execute(ddl)

    cursor.execute("SET FOREIGN_KEY_CHECKS = 1;")
    print("  Successfully created / verified all 11 tables with relational constraints.\n")


# ==============================================================================
# 4. LOOKUP TABLES POPULATION & IN-MEMORY CACHE
# ==============================================================================
def populate_lookups(cursor, conn, df):
    print("=" * 70)
    print("STEP 4.1: POPULATING LOOKUP TABLES & BUILDING IN-MEMORY MAPPINGS")
    print("=" * 70)

    # 1. State
    unique_states = [(s,) for s in df['State/UT'].drop_duplicates()]
    cursor.executemany("INSERT IGNORE INTO State (StateName) VALUES (%s);", unique_states)
    conn.commit()
    cursor.execute("SELECT StateName, StateID FROM State;")
    state_map = {row[0]: row[1] for row in cursor.fetchall()}
    print(f"  [State] Loaded {len(state_map)} state(s)")

    # 2. District
    unique_districts = df[['State/UT', 'District']].drop_duplicates()
    district_tuples = [(state_map[s], d) for s, d in zip(unique_districts['State/UT'], unique_districts['District'])]
    cursor.executemany("INSERT IGNORE INTO District (StateID, DistrictName) VALUES (%s, %s);", district_tuples)
    conn.commit()
    cursor.execute("SELECT StateID, DistrictName, DistrictID FROM District;")
    district_map = {(row[0], row[1]): row[2] for row in cursor.fetchall()}
    print(f"  [District] Loaded {len(district_map)} district(s)")

    # 3. Market
    unique_markets = df[['State/UT', 'District', 'Market']].drop_duplicates()
    market_tuples = []
    for s, d, m in zip(unique_markets['State/UT'], unique_markets['District'], unique_markets['Market']):
        dist_id = district_map.get((state_map[s], d))
        market_tuples.append((dist_id, m))
    cursor.executemany("INSERT IGNORE INTO Market (DistrictID, MarketName) VALUES (%s, %s);", market_tuples)
    conn.commit()
    cursor.execute("SELECT DistrictID, MarketName, MarketID FROM Market;")
    market_map = {(row[0], row[1]): row[2] for row in cursor.fetchall()}
    print(f"  [Market] Loaded {len(market_map)} market(s)")

    # 4. Category
    unique_categories = [(c,) for c in df['Commodity Group'].drop_duplicates()]
    cursor.executemany("INSERT IGNORE INTO Category (CategoryName) VALUES (%s);", unique_categories)
    conn.commit()
    cursor.execute("SELECT CategoryName, CategoryID FROM Category;")
    category_map = {row[0]: row[1] for row in cursor.fetchall()}
    print(f"  [Category] Loaded {len(category_map)} category(s)")

    # 5. Commodity
    unique_commodities = df[['Commodity Group', 'Commodity']].drop_duplicates()
    commodity_tuples = [(category_map[cat], c) for cat, c in zip(unique_commodities['Commodity Group'], unique_commodities['Commodity'])]
    cursor.executemany("INSERT IGNORE INTO Commodity (CategoryID, CommodityName) VALUES (%s, %s);", commodity_tuples)
    conn.commit()
    cursor.execute("SELECT CategoryID, CommodityName, CommodityID FROM Commodity;")
    commodity_map = {(row[0], row[1]): row[2] for row in cursor.fetchall()}
    print(f"  [Commodity] Loaded {len(commodity_map)} commodity(s)")

    # 6. Variety
    unique_varieties = df[['Commodity Group', 'Commodity', 'Variety']].drop_duplicates()
    variety_tuples = []
    for cat, comm, v in zip(unique_varieties['Commodity Group'], unique_varieties['Commodity'], unique_varieties['Variety']):
        comm_id = commodity_map.get((category_map[cat], comm))
        variety_tuples.append((comm_id, v))
    cursor.executemany("INSERT IGNORE INTO Variety (CommodityID, VarietyName) VALUES (%s, %s);", variety_tuples)
    conn.commit()
    cursor.execute("SELECT CommodityID, VarietyName, VarietyID FROM Variety;")
    variety_map = {(row[0], row[1]): row[2] for row in cursor.fetchall()}
    print(f"  [Variety] Loaded {len(variety_map)} variety(s)\n")

    return state_map, district_map, market_map, category_map, commodity_map, variety_map


# ==============================================================================
# 5. DAILY_PRICES BATCH INGESTION (3,000 PER BATCH)
# ==============================================================================
def ingest_daily_prices(cursor, conn, df, state_map, district_map, market_map, category_map, commodity_map, variety_map):
    print("=" * 70)
    print(f"STEP 4.2: INGESTING DAILY_PRICES (BATCH SIZE = {BATCH_SIZE:,})")
    print("=" * 70)

    # Clean existing price records to allow clean reproducible ingestion
    cursor.execute("SELECT COUNT(*) FROM Daily_Prices;")
    existing_count = cursor.fetchone()[0]
    if existing_count > 0:
        print(f"  Clearing {existing_count:,} existing Daily_Prices records for fresh reload...")
        cursor.execute("TRUNCATE TABLE Daily_Prices;")
        conn.commit()

    insert_sql = """
    INSERT INTO Daily_Prices (
        MarketID, VarietyID, Grade, RecordDate, MinPrice, MaxPrice, ModalPrice, ArrivalTonnes
    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s);
    """

    records_to_insert = []
    for _, row in df.iterrows():
        s_name = row['State/UT']
        d_name = row['District']
        m_name = row['Market']
        cat_name = row['Commodity Group']
        comm_name = row['Commodity']
        v_name = row['Variety']

        s_id = state_map.get(s_name)
        d_id = district_map.get((s_id, d_name)) if s_id else None
        m_id = market_map.get((d_id, m_name)) if d_id else None

        c_id = category_map.get(cat_name)
        comm_id = commodity_map.get((c_id, comm_name)) if c_id else None
        v_id = variety_map.get((comm_id, v_name)) if comm_id else None

        if m_id is None or v_id is None:
            continue

        min_p = float(row['Min Price']) if pd.notna(row['Min Price']) else None
        max_p = float(row['Max Price']) if pd.notna(row['Max Price']) else None
        mod_p = float(row['Modal Price']) if pd.notna(row['Modal Price']) else None
        arr_t = float(row['Arrival Quantity']) if pd.notna(row['Arrival Quantity']) else None

        records_to_insert.append((
            m_id,
            v_id,
            row['Grade'],
            row['Arrival Date'],
            min_p,
            max_p,
            mod_p,
            arr_t
        ))

    total_records = len(records_to_insert)
    print(f"  Prepared {total_records:,} valid records for insertion.")

    # Execute in batches of 3,000
    inserted_so_far = 0
    for i in range(0, total_records, BATCH_SIZE):
        batch = records_to_insert[i:i + BATCH_SIZE]
        cursor.executemany(insert_sql, batch)
        conn.commit()
        inserted_so_far += len(batch)
        print(f"  Inserted batch {i // BATCH_SIZE + 1} ({inserted_so_far:,} / {total_records:,} rows committed)")

    print(f"\nSuccessfully ingested {total_records:,} Daily_Prices records.\n")


# ==============================================================================
# 6. SEEDING TEST USERS, PROFILES & PRICE ALERTS
# ==============================================================================
def seed_profiles_and_alerts(cursor, conn):
    print("=" * 70)
    print("STEP 4.3: SEEDING SYSTEM USERS, FARMERS, TRADERS & PRICE ALERTS")
    print("=" * 70)

    # Fetch available DistrictIDs and CommodityIDs
    cursor.execute("SELECT DistrictID, DistrictName FROM District LIMIT 10;")
    districts = {name: d_id for d_id, name in cursor.fetchall()}
    pune_id = districts.get("Pune") or list(districts.values())[0]
    nashik_id = districts.get("Nashik") or list(districts.values())[min(1, len(districts)-1)]
    ahilya_id = districts.get("Ahilyanagar") or list(districts.values())[min(2, len(districts)-1)]

    cursor.execute("SELECT CommodityID, CommodityName FROM Commodity;")
    commodities = {name: c_id for c_id, name in cursor.fetchall()}
    onion_id = commodities.get("Onion") or list(commodities.values())[0]
    tomato_id = commodities.get("Tomato") or list(commodities.values())[min(1, len(commodities)-1)]
    apple_id = commodities.get("Apple") or list(commodities.values())[min(2, len(commodities)-1)]

    # Clean existing test seed users if already present
    test_phones = ['+919822011223', '+919822022334', '+919822033445', '+919822044556']
    format_strings = ','.join(['%s'] * len(test_phones))
    cursor.execute(f"DELETE FROM System_User WHERE PhoneNo IN ({format_strings});", test_phones)
    conn.commit()

    # Passwords hashed with SHA-256
    def hash_pw(pwd):
        return hashlib.sha256(pwd.encode('utf-8')).hexdigest()

    # 4 Test System_Users (2 Farmers, 2 Traders)
    users = [
        # (Name, PhoneNo, PasswordHash, DistrictID, UserType)
        ("Ramesh Patil", "+919822011223", hash_pw("KisanPatil@2026"), pune_id, "Farmer"),
        ("Suresh Shinde", "+919822022334", hash_pw("KisanShinde@2026"), nashik_id, "Farmer"),
        ("Vikram Joshi", "+919822033445", hash_pw("TraderJoshi@2026"), pune_id, "Trader"),
        ("Anil Deshmukh", "+919822044556", hash_pw("TraderDeshmukh@2026"), ahilya_id, "Trader")
    ]

    user_ids = []
    for u in users:
        cursor.execute("""
            INSERT INTO System_User (Name, PhoneNo, PasswordHash, DistrictID, UserType)
            VALUES (%s, %s, %s, %s, %s);
        """, u)
        user_ids.append(cursor.lastrowid)
    conn.commit()
    print(f"  Inserted 4 System_User profiles: User IDs {user_ids}")

    # Seed Farmers
    farmer_data = [
        (user_ids[0], 12.50, "Onion"),
        (user_ids[1], 8.00, "Tomato")
    ]
    cursor.executemany("""
        INSERT INTO Farmer (UserID, FarmSize_Acres, PrimaryCrop)
        VALUES (%s, %s, %s);
    """, farmer_data)
    conn.commit()
    print(f"  Inserted 2 Farmer profiles linked to User IDs {[user_ids[0], user_ids[1]]}")

    # Seed Traders
    trader_data = [
        (user_ids[2], "TRD-MH-PUN-001", "Maha Agro Wholesale Traders"),
        (user_ids[3], "TRD-MH-AHI-002", "Deshmukh Mandi Supply Co")
    ]
    cursor.executemany("""
        INSERT INTO Trader (UserID, LicenseNumber, CompanyName)
        VALUES (%s, %s, %s);
    """, trader_data)
    conn.commit()
    print(f"  Inserted 2 Trader profiles linked to User IDs {[user_ids[2], user_ids[3]]}")

    # Seed 3 Active Price Alerts
    alerts = [
        (user_ids[0], onion_id, 2500.00, "ABOVE", True, "Target price reached: Onion crossed Rs. 2,500/Quintal"),
        (user_ids[1], tomato_id, 1800.00, "ABOVE", True, "Target price reached: Tomato crossed Rs. 1,800/Quintal"),
        (user_ids[2], apple_id, 8000.00, "BELOW", True, "Buy alert: Apple modal price dropped below Rs. 8,000/Quintal")
    ]
    cursor.executemany("""
        INSERT INTO Price_Alerts (UserID, CommodityID, TargetPrice, AlertCondition, IsActive, TriggeredMessage)
        VALUES (%s, %s, %s, %s, %s, %s);
    """, alerts)
    conn.commit()
    print("  Inserted 3 active Price_Alerts linked to real District and Commodity IDs.\n")


# ==============================================================================
# 7. GENERATE SQL SCHEMA & SEED EXPORT (schema_and_seed.sql)
# ==============================================================================
def export_sql_dump(cursor, output_dir):
    print("=" * 70)
    print("STEP 4.4: GENERATING schema_and_seed.sql EXPORT")
    print("=" * 70)
    dump_path = os.path.join(output_dir, "schema_and_seed.sql")

    with open(dump_path, "w", encoding="utf-8") as f:
        f.write("-- =============================================================================\n")
        f.write("-- AgriMarket Complete Relational Schema & Seed Data Dump\n")
        f.write(f"-- Exported: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write("-- Database: AgriMarket\n")
        f.write("-- =============================================================================\n\n")
        f.write("CREATE DATABASE IF NOT EXISTS AgriMarket;\n")
        f.write("USE AgriMarket;\n\n")
        f.write("SET FOREIGN_KEY_CHECKS = 0;\n\n")

        # Table creation statements
        tables = [
            "State", "District", "Market", "Category", "Commodity",
            "Variety", "Daily_Prices", "System_User", "Farmer", "Trader", "Price_Alerts"
        ]

        for table in tables:
            f.write(f"-- -----------------------------------------------------------------------------\n")
            f.write(f"-- Table structure for `{table}`\n")
            f.write(f"-- -----------------------------------------------------------------------------\n")
            f.write(f"DROP TABLE IF EXISTS `{table}`;\n")
            cursor.execute(f"SHOW CREATE TABLE `{table}`;")
            create_stmt = cursor.fetchone()[1]
            f.write(f"{create_stmt};\n\n")

        f.write("SET FOREIGN_KEY_CHECKS = 1;\n\n")

        # Seed data for lookups and users
        seed_tables = ["State", "District", "Market", "Category", "Commodity", "Variety", "System_User", "Farmer", "Trader", "Price_Alerts"]
        for table in seed_tables:
            cursor.execute(f"SELECT * FROM `{table}`;")
            rows = cursor.fetchall()
            if not rows:
                continue
            cursor.execute(f"DESCRIBE `{table}`;")
            cols = [col[0] for col in cursor.fetchall()]
            cols_str = ", ".join([f"`{c}`" for c in cols])

            f.write(f"-- -----------------------------------------------------------------------------\n")
            f.write(f"-- Seed data for `{table}` ({len(rows)} records)\n")
            f.write(f"-- -----------------------------------------------------------------------------\n")
            
            # Write in batches
            batch_vals = []
            for r in rows:
                val_strs = []
                for val in r:
                    if val is None:
                        val_strs.append("NULL")
                    elif isinstance(val, (int, float)):
                        val_strs.append(str(val))
                    elif isinstance(val, (bool,)):
                        val_strs.append("1" if val else "0")
                    else:
                        escaped = str(val).replace("\\", "\\\\").replace("'", "''")
                        val_strs.append(f"'{escaped}'")
                batch_vals.append(f"({', '.join(val_strs)})")

            # Write inserts in chunks of 500
            chunk_size = 500
            for i in range(0, len(batch_vals), chunk_size):
                chunk = batch_vals[i:i + chunk_size]
                f.write(f"INSERT INTO `{table}` ({cols_str}) VALUES\n" + ",\n".join(chunk) + ";\n")
            f.write("\n")

        # Sample rows for Daily_Prices
        cursor.execute("SELECT * FROM Daily_Prices LIMIT 100;")
        price_rows = cursor.fetchall()
        if price_rows:
            cursor.execute("DESCRIBE Daily_Prices;")
            cols = [col[0] for col in cursor.fetchall()]
            cols_str = ", ".join([f"`{c}`" for c in cols])
            cursor.execute("SELECT COUNT(*) FROM Daily_Prices;")
            cnt_prices = cursor.fetchone()[0]
            f.write(f"-- -----------------------------------------------------------------------------\n")
            f.write(f"-- Sample seed data for `Daily_Prices` (First 100 of {cnt_prices:,} records)\n")
            f.write(f"-- -----------------------------------------------------------------------------\n")
            batch_vals = []
            for r in price_rows:
                val_strs = []
                for val in r:
                    if val is None:
                        val_strs.append("NULL")
                    elif isinstance(val, (int, float)):
                        val_strs.append(str(val))
                    else:
                        escaped = str(val).replace("\\", "\\\\").replace("'", "''")
                        val_strs.append(f"'{escaped}'")
                batch_vals.append(f"({', '.join(val_strs)})")
            f.write(f"INSERT INTO `Daily_Prices` ({cols_str}) VALUES\n" + ",\n".join(batch_vals) + ";\n\n")

    print(f"  SQL dump successfully generated: {dump_path}\n")
    return dump_path


# ==============================================================================
# 8. GENERATE RUN SUMMARY (ingestion_summary.txt)
# ==============================================================================
def generate_summary(cursor, output_dir, discovered_files, processed_files, skipped_files):
    print("=" * 70)
    print("STEP 4.5: GENERATING ingestion_summary.txt")
    print("=" * 70)
    summary_path = os.path.join(output_dir, "ingestion_summary.txt")

    tables = [
        "State", "District", "Market", "Category", "Commodity",
        "Variety", "Daily_Prices", "System_User", "Farmer", "Trader", "Price_Alerts"
    ]

    table_counts = {}
    for t in tables:
        cursor.execute(f"SELECT COUNT(*) FROM `{t}`;")
        table_counts[t] = cursor.fetchone()[0]

    with open(summary_path, "w", encoding="utf-8") as f:
        f.write("=" * 75 + "\n")
        f.write("AGRIMARKET DATABASE INGESTION & NORMALIZATION SUMMARY REPORT\n")
        f.write("=" * 75 + "\n")
        f.write(f"Execution Timestamp : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Target Database     : {DB_NAME}\n")
        f.write(f"Batch Execution Size: {BATCH_SIZE:,} rows per transaction\n")
        f.write(f"Base Directory      : {BASE_DIR}\n")
        f.write(f"Output Directory    : {output_dir}\n")
        f.write("-" * 75 + "\n\n")

        f.write("1. DISCOVERED CSV FILES & RAW ROW COUNTS\n")
        f.write("-" * 75 + "\n")
        for fpath, rcount in discovered_files:
            rel = os.path.relpath(fpath, BASE_DIR)
            f.write(f"  - {rel:<60} : {rcount:>8,} raw lines\n")
        f.write(f"  Total CSV files discovered: {len(discovered_files)}\n\n")

        f.write("2. CSV VALIDATION & CLEANING METRICS\n")
        f.write("-" * 75 + "\n")
        f.write("  Successfully Processed Files (Standard 14-Column Format):\n")
        for fname, in_len, out_len in processed_files:
            f.write(f"    * {fname:<35} | Input Rows: {in_len:>6,} | Cleaned Rows: {out_len:>6,}\n")
        
        if skipped_files:
            f.write("\n  Skipped Files (Non-Standard Schemas):\n")
            for fname, reason in skipped_files:
                f.write(f"    * {fname:<35} | Reason: {reason}\n")
        f.write("\n")

        f.write("3. FINAL ROW COUNTS ACROSS ALL 11 MYSQL TABLES\n")
        f.write("-" * 75 + "\n")
        for t in tables:
            f.write(f"  Table: {t:<20} | Total Rows: {table_counts[t]:>10,}\n")
        f.write("-" * 75 + "\n")
        total_rows_all = sum(table_counts.values())
        f.write(f"  GRAND TOTAL ENTITIES ACROSS ALL TABLES: {total_rows_all:>10,}\n\n")

        f.write("4. SAMPLE TEST SEED VERIFICATION\n")
        f.write("-" * 75 + "\n")
        cursor.execute("SELECT u.UserID, u.Name, u.PhoneNo, u.UserType, d.DistrictName FROM System_User u LEFT JOIN District d ON u.DistrictID = d.DistrictID;")
        users = cursor.fetchall()
        f.write("  System Users:\n")
        for u in users:
            f.write(f"    - ID {u[0]}: {u[1]} ({u[3]}), Phone: {u[2]}, District: {u[4]}\n")

        f.write("\n  Active Price Alerts:\n")
        cursor.execute("""
            SELECT a.AlertID, u.Name, c.CommodityName, a.TargetPrice, a.AlertCondition, a.IsActive, a.TriggeredMessage
            FROM Price_Alerts a
            JOIN System_User u ON a.UserID = u.UserID
            JOIN Commodity c ON a.CommodityID = c.CommodityID;
        """)
        alerts = cursor.fetchall()
        for a in alerts:
            f.write(f"    - Alert #{a[0]}: {a[1]} | {a[2]} | Condition: {a[4]} {a[3]} | Msg: {a[6]}\n")
        f.write("\n" + "=" * 75 + "\n")
        f.write("Pipeline execution completed successfully with 100% relational integrity.\n")
        f.write("=" * 75 + "\n")

    print(f"  Summary report written to: {summary_path}\n")
    return summary_path, table_counts


# ==============================================================================
# MAIN ENTRYPOINT
# ==============================================================================
def main():
    args = parse_args()
    print("=" * 70)
    print("AGRIMARKET ETL & DATABASE SEEDING PIPELINE")
    print("=" * 70)

    # Step 0: Ensure project output directory exists
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"Target Project Output Directory: {OUTPUT_DIR}\n")

    # Step 1: File Discovery
    discovered_files = discover_csv_files(BASE_DIR, OUTPUT_DIR)

    # Step 2: Data Cleaning & Standardization
    combined_df, processed_files, skipped_files = clean_and_prepare_data(discovered_files)

    # Step 3: MySQL Connection & Schema Provisioning
    pwd = get_password(args.password)
    try:
        # Connect to MySQL server (without specifying database initially)
        server_conn = mysql.connector.connect(
            host=args.host,
            user=args.user,
            password=pwd,
            port=args.port
        )
        with server_conn.cursor() as cur:
            cur.execute(f"CREATE DATABASE IF NOT EXISTS {DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;")
        server_conn.close()

        # Connect to AgriMarket database
        conn = mysql.connector.connect(
            host=args.host,
            user=args.user,
            password=pwd,
            port=args.port,
            database=DB_NAME,
            autocommit=False
        )
        cursor = conn.cursor()
        print(f"Connected to MySQL database '{DB_NAME}' on {args.host}:{args.port}.\n")

        # Provision all 11 tables
        create_schema(cursor)

        # Step 4: Populate Lookup tables
        state_map, district_map, market_map, category_map, commodity_map, variety_map = populate_lookups(cursor, conn, combined_df)

        # Step 5: Ingest Daily_Prices in batches of 3,000
        ingest_daily_prices(cursor, conn, combined_df, state_map, district_map, market_map, category_map, commodity_map, variety_map)

        # Step 6: Seed Test Profiles and Active Price Alerts
        seed_profiles_and_alerts(cursor, conn)

        # Step 7: Export SQL schema and seed file
        export_sql_dump(cursor, OUTPUT_DIR)

        # Step 8: Generate detailed run summary
        summary_path, table_counts = generate_summary(cursor, OUTPUT_DIR, discovered_files, processed_files, skipped_files)

        conn.close()

        print("=" * 70)
        print("ALL OPERATIONS COMPLETED SUCCESSFULLY!")
        print("=" * 70)
        print("Final Table Row Counts:")
        for tbl, count in table_counts.items():
            print(f"  {tbl:<18}: {count:>8,} rows")
        print("=" * 70)

    except Error as err:
        print(f"\n[MySQL Error] {err}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
