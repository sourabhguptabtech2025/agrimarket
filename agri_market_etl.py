import os
import sys
import glob
import logging
from datetime import datetime
import pandas as pd
import mysql.connector
from mysql.connector import Error
from playwright.sync_api import sync_playwright, Page, TimeoutError as PlaywrightTimeoutError

# ==============================================================================
# CONFIGURATION & CONSTANTS
# ==============================================================================
DB_CONFIG = {
    "host": "localhost",
    "user": "root",          # Replace with your MySQL username
    "password": "your_password",  # Replace with your MySQL password
    "database": "AgriMarket",
    "port": 3306,
    "autocommit": False
}

DOWNLOAD_DIR = os.path.abspath("./agmarknet_downloads")
os.makedirs(DOWNLOAD_DIR, exist_ok=True)

TARGET_CRITERIA = {
    "commodity_group": "Vegetables",
    "commodities": ["Onion", "Tomato"],
    "state": "Maharashtra",
    "districts": [
        "Pune", "Mumbai", "Nashik", "Nagpur",
        "Chhatrapati Sambhajinagar",  # Handled with 'Aurangabad' alias fallback
        "Solapur", "Kolhapur", "Jalgaon", "Ahmednagar", "Satara"
    ],
    "date_from": "01-Jan-2025",
    "date_to": "31-Dec-2025"
}

AGMARKNET_URL = "https://agmarknet.gov.in/PriceTrends/SA_Pri_Month.aspx"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S"
)
logger = logging.getLogger("AgriETL")


# ==============================================================================
# 1. DATABASE SETUP & CONNECTION
# ==============================================================================
def get_db_connection():
    """Initializes and returns a MySQL database connection, creating schema if needed."""
    try:
        # Initial connection without DB to create AgriMarket if missing
        temp_conn = mysql.connector.connect(
            host=DB_CONFIG["host"],
            user=DB_CONFIG["user"],
            password=DB_CONFIG["password"],
            port=DB_CONFIG["port"]
        )
        with temp_conn.cursor() as cur:
            cur.execute(f"CREATE DATABASE IF NOT EXISTS {DB_CONFIG['database']};")
        temp_conn.close()

        # Connect to AgriMarket
        conn = mysql.connector.connect(**DB_CONFIG)
        logger.info(f"Connected to MySQL database '{DB_CONFIG['database']}'.")
        _create_tables_if_not_exist(conn)
        return conn
    except Error as err:
        logger.error(f"MySQL Connection Error: {err}")
        sys.exit(1)


def _create_tables_if_not_exist(conn):
    """Creates the normalized tables with relational integrity constraints."""
    market_table_sql = """
    CREATE TABLE IF NOT EXISTS Market (
        market_id INT AUTO_INCREMENT PRIMARY KEY,
        market_name VARCHAR(150) NOT NULL,
        district_name VARCHAR(100) NOT NULL,
        state_name VARCHAR(100) NOT NULL,
        UNIQUE KEY uq_market (market_name, district_name)
    );
    """

    daily_prices_sql = """
    CREATE TABLE IF NOT EXISTS Daily_Prices (
        price_id INT AUTO_INCREMENT PRIMARY KEY,
        market_id INT NOT NULL,
        commodity_name VARCHAR(100) NOT NULL,
        reported_date DATE NOT NULL,
        min_price DECIMAL(10, 2) DEFAULT NULL,
        max_price DECIMAL(10, 2) DEFAULT NULL,
        modal_price DECIMAL(10, 2) DEFAULT NULL,
        arrival_quantity DECIMAL(10, 2) DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (market_id) REFERENCES Market(market_id) ON DELETE CASCADE,
        UNIQUE KEY uq_daily_record (market_id, commodity_name, reported_date)
    );
    """

    with conn.cursor() as cursor:
        cursor.execute(market_table_sql)
        cursor.execute(daily_prices_sql)
        conn.commit()
    logger.info("Database schema verified/created successfully.")


# ==============================================================================
# 2. AUTOMATION & BROWSER INTERACTION (PLAYWRIGHT)
# ==============================================================================
def select_dropdown_by_text(page: Page, selector: str, text: str, wait_postback: bool = True):
    """Safely select an option by visible label and wait for ASP.NET postback."""
    logger.info(f"Selecting '{text}' from {selector}...")
    page.wait_for_selector(selector, state="visible", timeout=15000)
    
    # Try exact match or case-insensitive match
    options = page.eval_on_selector(
        selector,
        """(select, query) => {
            const opts = Array.from(select.options);
            const found = opts.find(o => o.text.trim().toLowerCase() === query.trim().toLowerCase());
            return found ? found.value : null;
        }""",
        text
    )

    if options is not None:
        page.select_option(selector, value=options)
    else:
        # Fallback to direct label selection
        page.select_option(selector, label=text)

    if wait_postback:
        page.wait_for_load_state("networkidle", timeout=15000)


def automate_agmarknet_form(page: Page):
    """Fills the form with Commodity Group, Commodities, State, Districts, and Dates."""
    logger.info("Navigating to Agmarknet Daily Price and Arrival portal...")
    page.goto(AGMARKNET_URL, wait_until="domcontentloaded", timeout=60000)
    page.wait_for_load_state("networkidle")

    # 1. Commodity Group
    group_selector = "select[id*='ddlCommodityGroup'], select[id*='cboCommodityGroup'], select#ddlCommodityGroup"
    select_dropdown_by_text(page, group_selector, TARGET_CRITERIA["commodity_group"])

    # 2. State
    state_selector = "select[id*='ddlState'], select[id*='cboState'], select#ddlState"
    select_dropdown_by_text(page, state_selector, TARGET_CRITERIA["state"])

    # 3. Commodities (multi-select / single select listbox)
    comm_selector = "select[id*='ddlCommodity'], select[id*='lstCommodity'], select[id*='cboCommodity']"
    page.wait_for_selector(comm_selector, state="visible")
    try:
        # Attempt multi-selection if supported
        page.select_option(comm_selector, label=TARGET_CRITERIA["commodities"])
    except Exception:
        # Select first matching commodity
        select_dropdown_by_text(page, comm_selector, TARGET_CRITERIA["commodities"][0], wait_postback=False)

    # 4. Districts (Select target 10 districts)
    dist_selector = "select[id*='ddlDistrict'], select[id*='lstDistrict'], select[id*='cboDistrict']"
    page.wait_for_selector(dist_selector, state="visible")

    # Handle Sambhajinagar / Aurangabad name changes in government portals
    selected_districts = []
    for d in TARGET_CRITERIA["districts"]:
        if d == "Chhatrapati Sambhajinagar":
            selected_districts.extend(["Chhatrapati Sambhajinagar", "Aurangabad"])
        else:
            selected_districts.append(d)

    try:
        page.select_option(dist_selector, label=selected_districts)
    except Exception:
        logger.warning("Could not multi-select all districts at once; selecting all available matched.")
        page.eval_on_selector(
            dist_selector,
            """(select, list) => {
                const lowerList = list.map(item => item.toLowerCase());
                Array.from(select.options).forEach(opt => {
                    if (lowerList.includes(opt.text.trim().toLowerCase())) {
                        opt.selected = true;
                    }
                });
                select.dispatchEvent(new Event('change', { bubbles: true }));
            }""",
            selected_districts
        )

    # 5. Date Range
    date_from_sel = "input[id*='txtDateFrom'], input[id*='txtFromDate'], input[id*='DateFrom']"
    date_to_sel = "input[id*='txtDateTo'], input[id*='txtToDate'], input[id*='DateTo']"

    if page.query_selector(date_from_sel):
        page.fill(date_from_sel, TARGET_CRITERIA["date_from"])
    if page.query_selector(date_to_sel):
        page.fill(date_to_sel, TARGET_CRITERIA["date_to"])

    logger.info("Form fields successfully populated.")


def trigger_download_export(page: Page, dataset_type: str) -> str:
    """Clicks export/download button and intercepts the downloaded CSV/Excel file."""
    logger.info(f"Preparing to download '{dataset_type}' dataset...")
    
    # Common export button selectors in Agmarknet (Excel / CSV export)
    export_buttons = [
        f"input[value*='Export'][value*='{dataset_type}']",
        f"input[id*='btnExport{dataset_type}']",
        "input[value*='Export to Excel']",
        "input[value*='Export to CSV']",
        "input[id*='btnExport']",
        "input[id*='btnSubmit']"
    ]
    
    btn_handle = None
    for sel in export_buttons:
        if page.query_selector(sel):
            btn_handle = sel
            break

    target_file_path = os.path.join(DOWNLOAD_DIR, f"{dataset_type.lower()}_data.csv")

    if btn_handle:
        try:
            with page.expect_download(timeout=45000) as download_info:
                page.click(btn_handle)
            download = download_info.value
            download.save_as(target_file_path)
            logger.info(f"Downloaded {dataset_type} file to: {target_file_path}")
            return target_file_path
        except PlaywrightTimeoutError:
            logger.warning(f"Download trigger timed out for {dataset_type}. Checking if file exported to directory.")
    
    # If portal displays tabular data instead of direct file download, extract table directly
    table_selector = "table[id*='grid'], table[id*='Grid'], table.table-striped, table[id*='cphBody']"
    if page.query_selector(table_selector):
        logger.info(f"Export button not detected. Scraping displayed HTML table for {dataset_type}...")
        html = page.inner_html(table_selector)
        dfs = pd.read_html(f"<table>{html}</table>")
        if dfs:
            dfs[0].to_csv(target_file_path, index=False)
            logger.info(f"Extracted table saved to: {target_file_path}")
            return target_file_path

    raise RuntimeError(f"Could not download or extract dataset for {dataset_type}")


# ==============================================================================
# 3. DATA MERGING & ETL (PANDAS)
# ==============================================================================
def clean_and_merge_datasets(price_file_path: str, arrival_file_path: str) -> pd.DataFrame:
    """Loads price & arrival datasets, normalizes columns, and merges them."""
    logger.info("Reading downloaded datasets into pandas DataFrames...")

    # Load Price data (handles CSV or Excel)
    df_price = pd.read_excel(price_file_path) if price_file_path.endswith((".xls", ".xlsx")) else pd.read_csv(price_file_path)
    # Load Arrival data
    df_arrival = pd.read_excel(arrival_file_path) if arrival_file_path.endswith((".xls", ".xlsx")) else pd.read_csv(arrival_file_path)

    # Normalize column names: strip spaces and lowercase for reliable matching
    df_price.columns = df_price.columns.str.strip()
    df_arrival.columns = df_arrival.columns.str.strip()

    # Column name mappings standard across Agmarknet variations
    col_map = {
        "Market": "Market Name",
        "Market Center": "Market Name",
        "Mkt Name": "Market Name",
        "Price Date": "Reported Date",
        "Arrival Date": "Reported Date",
        "Date": "Reported Date",
        "Commodity": "Commodity Name",
        "District": "District Name",
        "State": "State Name",
        "Min Price (Rs./Quintal)": "Min Price",
        "Max Price (Rs./Quintal)": "Max Price",
        "Modal Price (Rs./Quintal)": "Modal Price",
        "Arrival (Tonnes)": "Arrivals (Tonnes)",
        "Arrivals in Tonnes": "Arrivals (Tonnes)"
    }
    df_price.rename(columns=col_map, inplace=True)
    df_arrival.rename(columns=col_map, inplace=True)

    # Ensure keys exist
    for df, name in [(df_price, "Price"), (df_arrival, "Arrival")]:
        if "Market Name" not in df.columns or "Reported Date" not in df.columns:
            raise KeyError(f"Missing required keys ('Market Name', 'Reported Date') in {name} file. Found columns: {list(df.columns)}")

    # Standardize dates to datetime
    df_price["Reported Date"] = pd.to_datetime(df_price["Reported Date"], errors="coerce").dt.date
    df_arrival["Reported Date"] = pd.to_datetime(df_arrival["Reported Date"], errors="coerce").dt.date

    # Drop invalid date rows
    df_price.dropna(subset=["Reported Date", "Market Name"], inplace=True)
    df_arrival.dropna(subset=["Reported Date", "Market Name"], inplace=True)

    # Standardize string fields
    df_price["Market Name"] = df_price["Market Name"].astype(str).str.strip().str.title()
    df_arrival["Market Name"] = df_arrival["Market Name"].astype(str).str.strip().str.title()

    logger.info("Merging datasets on ['Market Name', 'Reported Date']...")
    merged_df = pd.merge(
        df_price,
        df_arrival,
        on=["Market Name", "Reported Date"],
        how="inner",
        suffixes=("_price", "_arrival")
    )

    # Deduplicate / resolve commodity, district, state columns
    for base_col in ["Commodity Name", "District Name", "State Name"]:
        if f"{base_col}_price" in merged_df.columns:
            merged_df[base_col] = merged_df[f"{base_col}_price"]
        elif f"{base_col}_arrival" in merged_df.columns:
            merged_df[base_col] = merged_df[f"{base_col}_arrival"]
        elif base_col not in merged_df.columns:
            # Default fallbacks if omitted in source report
            merged_df[base_col] = "Vegetables" if "Commodity" in base_col else ("Maharashtra" if "State" in base_col else "Maharashtra District")

    # Clean numeric fields
    numeric_cols = ["Min Price", "Max Price", "Modal Price", "Arrivals (Tonnes)"]
    for col in numeric_cols:
        if col in merged_df.columns:
            merged_df[col] = pd.to_numeric(merged_df[col].astype(str).str.replace(",", ""), errors="coerce")
        else:
            merged_df[col] = None

    logger.info(f"Data merging complete. Total combined records: {len(merged_df)}")
    return merged_df


# ==============================================================================
# 4. DATABASE INGESTION & RELATIONAL INTEGRITY
# ==============================================================================
def ingest_into_database(conn, df: pd.DataFrame):
    """Inserts unique Markets into Market table first, then inserts records into Daily_Prices."""
    if df.empty:
        logger.warning("DataFrame is empty. Skipping database insertion.")
        return

    cursor = conn.cursor()
    try:
        # Step A: Insert Unique Markets (Parent Table)
        unique_markets = df[["Market Name", "District Name", "State Name"]].drop_duplicates()
        logger.info(f"Synchronizing {len(unique_markets)} unique markets in 'Market' table...")

        insert_market_sql = """
        INSERT INTO Market (market_name, district_name, state_name)
        VALUES (%s, %s, %s)
        ON DUPLICATE KEY UPDATE market_name=VALUES(market_name);
        """
        market_tuples = [
            (row["Market Name"], row["District Name"], row["State Name"])
            for _, row in unique_markets.iterrows()
        ]
        cursor.executemany(insert_market_sql, market_tuples)
        conn.commit()

        # Step B: Cache Market IDs for Foreign Key mapping
        cursor.execute("SELECT market_name, district_name, market_id FROM Market;")
        market_lookup = {
            (row[0].strip().title(), row[1].strip().title()): row[2]
            for row in cursor.fetchall()
        }

        # Step C: Prepare and Insert Records into Daily_Prices (Child Table)
        logger.info("Inserting daily price and arrival records into 'Daily_Prices' table...")
        insert_price_sql = """
        INSERT INTO Daily_Prices (
            market_id, commodity_name, reported_date, min_price, max_price, modal_price, arrival_quantity
        ) VALUES (%s, %s, %s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            min_price = VALUES(min_price),
            max_price = VALUES(max_price),
            modal_price = VALUES(modal_price),
            arrival_quantity = VALUES(arrival_quantity);
        """

        records_to_insert = []
        for _, row in df.iterrows():
            m_key = (row["Market Name"].strip().title(), str(row["District Name"]).strip().title())
            market_id = market_lookup.get(m_key)

            # Fallback if district name variance occurred
            if not market_id:
                for (m_name, _), m_id in market_lookup.items():
                    if m_name == row["Market Name"].strip().title():
                        market_id = m_id
                        break

            if not market_id:
                logger.warning(f"Could not resolve market_id for: {row['Market Name']}. Skipping record.")
                continue

            records_to_insert.append((
                market_id,
                str(row["Commodity Name"]),
                row["Reported Date"],
                row["Min Price"] if pd.notna(row["Min Price"]) else None,
                row["Max Price"] if pd.notna(row["Max Price"]) else None,
                row["Modal Price"] if pd.notna(row["Modal Price"]) else None,
                row["Arrivals (Tonnes)"] if pd.notna(row["Arrivals (Tonnes)"]) else None,
            ))

        # Batch execution
        batch_size = 500
        for i in range(0, len(records_to_insert), batch_size):
            batch = records_to_insert[i : i + batch_size]
            cursor.executemany(insert_price_sql, batch)
            conn.commit()

        logger.info(f"Successfully inserted/updated {len(records_to_insert)} records in 'Daily_Prices'.")

    except Error as err:
        conn.rollback()
        logger.error(f"Database insertion failed: {err}")
        raise
    finally:
        cursor.close()


# ==============================================================================
# MAIN WORKFLOW
# ==============================================================================
def main():
    conn = get_db_connection()

    with sync_playwright() as p:
        # Launch visible browser (headless=False)
        logger.info("Launching visible Chromium browser...")
        browser = p.chromium.launch(
            headless=False,
            channel="chrome",  # Uses your installed Chrome browser
            slow_mo=200
        )
        context = browser.new_context(accept_downloads=True)
        page = context.new_page()

        try:
            # Step 1 & 2: Navigation and Form Selection
            automate_agmarknet_form(page)

            # Step 3: CAPTCHA Handling (CRITICAL - Pause Execution)
            print("\n" + "=" * 80)
            print(" [ACTION REQUIRED] CAPTCHA DETECTION")
            print(" Please switch to the visible browser window, solve the CAPTCHA,")
            print(" and click 'Submit' / generate the report if required.")
            print("=" * 80)
            input("Press [Enter] here once you have solved the CAPTCHA to continue execution...")

            # Step 4: Download Price and Arrival Datasets
            # If the portal exports both Price and Arrival separately, trigger each export:
            price_file = trigger_download_export(page, "Price")
            arrival_file = trigger_download_export(page, "Arrival")

            # Step 5: Pandas Merge & Cleaning
            merged_data = clean_and_merge_datasets(price_file, arrival_file)

            # Step 6: Database Ingestion
            ingest_into_database(conn, merged_data)

            print("\n" + "=" * 80)
            print(" ETL PIPELINE COMPLETED SUCCESSFULLY!")
            print(f" Total records synchronized: {len(merged_data)}")
            print("=" * 80)

        except Exception as e:
            logger.error(f"Pipeline encountered an error: {e}", exc_info=True)
        finally:
            browser.close()
            if conn and conn.is_connected():
                conn.close()
                logger.info("Database connection closed.")


if __name__ == "__main__":
    main()