-- =============================================================================
-- AgriMarket Step 10: 10 Real-World Production SQL Queries
-- Database: AgriMarket
-- =============================================================================

USE AgriMarket;

-- =============================================================================
-- QUERY 1: Multi-Table Operational Join (Master Mandi Feed & Intraday Spreads)
-- Demonstrates: 7-table relational JOIN with calculated intraday price spread.
-- Real-World Use: Daily mandi price dashboard for market regulators & buyers.
-- =============================================================================
SELECT 
    p.PriceID,
    p.RecordDate,
    s.StateName,
    d.DistrictName,
    m.MarketName,
    c.CommodityName,
    v.VarietyName,
    p.Grade,
    p.MinPrice,
    p.MaxPrice,
    p.ModalPrice,
    p.ArrivalTonnes,
    fn_price_spread_pct(p.MinPrice, p.MaxPrice) AS IntradaySpreadPct,
    fn_inflow_status(p.ArrivalTonnes) AS SupplyClassification
FROM Daily_Prices p
JOIN Market m ON p.MarketID = m.MarketID
JOIN District d ON m.DistrictID = d.DistrictID
JOIN State s ON d.StateID = s.StateID
JOIN Variety v ON p.VarietyID = v.VarietyID
JOIN Commodity c ON v.CommodityID = c.CommodityID
JOIN Category cat ON c.CategoryID = cat.CategoryID
WHERE c.CommodityName = 'Onion'
ORDER BY p.RecordDate DESC, p.ArrivalTonnes DESC
LIMIT 10;


-- =============================================================================
-- QUERY 2: Mandi Performance & Liquidity Ranking with GROUP BY & HAVING
-- Demonstrates: Multi-table aggregation, filtering groups with HAVING.
-- Real-World Use: Identifies high-volume, liquid markets for wholesale buyers.
-- =============================================================================
SELECT 
    d.DistrictName,
    m.MarketName,
    c.CommodityName,
    COUNT(p.PriceID) AS TotalTradingDays,
    ROUND(SUM(p.ArrivalTonnes), 2) AS CumulativeArrivalTonnes,
    ROUND(AVG(p.ModalPrice), 2) AS AvgModalPrice,
    MAX(p.MaxPrice) AS PeakMaxPrice,
    MIN(p.MinPrice) AS LowestMinPrice,
    ROUND(AVG(fn_price_spread_pct(p.MinPrice, p.MaxPrice)), 2) AS AvgPriceSpreadPct
FROM Daily_Prices p
JOIN Market m ON p.MarketID = m.MarketID
JOIN District d ON m.DistrictID = d.DistrictID
JOIN Variety v ON p.VarietyID = v.VarietyID
JOIN Commodity c ON v.CommodityID = c.CommodityID
WHERE c.CommodityName IN ('Onion', 'Tomato', 'Potato')
GROUP BY d.DistrictName, m.MarketName, c.CommodityName
HAVING COUNT(p.PriceID) >= 50 AND SUM(p.ArrivalTonnes) >= 1000.00
ORDER BY CumulativeArrivalTonnes DESC, AvgModalPrice DESC
LIMIT 10;


-- =============================================================================
-- QUERY 3: Nested Subquery — Critical Supply Crunch & Price Spike Detection
-- Demonstrates: Correlated nested subquery comparing daily arrivals vs district average.
-- Real-World Use: Early-warning food security monitor & speculative spike alert.
-- =============================================================================
SELECT 
    p.PriceID,
    p.RecordDate,
    d.DistrictName,
    m.MarketName,
    c.CommodityName,
    p.ArrivalTonnes AS ActualArrival,
    ROUND(dist_stats.AvgDistrictArrival, 2) AS DistrictBaselineArrival,
    p.ModalPrice AS ActualPrice,
    ROUND(dist_stats.AvgDistrictPrice, 2) AS DistrictBaselinePrice,
    ROUND(((p.ArrivalTonnes - dist_stats.AvgDistrictArrival) / dist_stats.AvgDistrictArrival) * 100, 2) AS SupplyDeficitPct,
    ROUND(((p.ModalPrice - dist_stats.AvgDistrictPrice) / dist_stats.AvgDistrictPrice) * 100, 2) AS PriceInflationPct
FROM Daily_Prices p
JOIN Market m ON p.MarketID = m.MarketID
JOIN District d ON m.DistrictID = d.DistrictID
JOIN Variety v ON p.VarietyID = v.VarietyID
JOIN Commodity c ON v.CommodityID = c.CommodityID
JOIN (
    -- Subquery: District-level baseline averages per commodity
    SELECT 
        m_inner.DistrictID,
        v_inner.CommodityID,
        AVG(p_inner.ArrivalTonnes) AS AvgDistrictArrival,
        AVG(p_inner.ModalPrice) AS AvgDistrictPrice
    FROM Daily_Prices p_inner
    JOIN Market m_inner ON p_inner.MarketID = m_inner.MarketID
    JOIN Variety v_inner ON p_inner.VarietyID = v_inner.VarietyID
    GROUP BY m_inner.DistrictID, v_inner.CommodityID
) dist_stats ON d.DistrictID = dist_stats.DistrictID AND c.CommodityID = dist_stats.CommodityID
WHERE p.ArrivalTonnes < (dist_stats.AvgDistrictArrival * 0.40)  -- Arrival is 60%+ below normal
  AND p.ModalPrice > (dist_stats.AvgDistrictPrice * 1.30)        -- Price is 30%+ above normal
ORDER BY PriceInflationPct DESC
LIMIT 10;


-- =============================================================================
-- QUERY 4: Seasonality & Monthly Price Cycle Analysis (MONTHNAME / Year-Month)
-- Demonstrates: Temporal extraction, aggregation across calendar months.
-- Real-World Use: Helps farmers plan sowing & storage; buyers plan cold storage stocking.
-- =============================================================================
SELECT 
    c.CommodityName,
    YEAR(p.RecordDate) AS HarvestYear,
    MONTH(p.RecordDate) AS MonthNum,
    MONTHNAME(p.RecordDate) AS TradingMonth,
    COUNT(p.PriceID) AS ActiveMandiSessions,
    ROUND(SUM(p.ArrivalTonnes), 2) AS MonthlyArrivalTonnes,
    ROUND(AVG(p.ModalPrice), 2) AS MonthlyAvgModalPrice,
    MIN(p.MinPrice) AS MonthlyMinPrice,
    MAX(p.MaxPrice) AS MonthlyMaxPrice,
    ROUND(STDDEV_POP(p.ModalPrice), 2) AS MonthlyPriceVolatility
FROM Daily_Prices p
JOIN Variety v ON p.VarietyID = v.VarietyID
JOIN Commodity c ON v.CommodityID = c.CommodityID
WHERE c.CommodityName IN ('Onion', 'Mango', 'Tomato')
GROUP BY c.CommodityName, YEAR(p.RecordDate), MONTH(p.RecordDate), MONTHNAME(p.RecordDate)
ORDER BY c.CommodityName, HarvestYear ASC, MonthNum ASC;


-- =============================================================================
-- QUERY 5: EER Subclass Polymorphic Query (System_User + Farmer + Trader)
-- Demonstrates: Outer joins on subclass tables with role-specific attributes.
-- Real-World Use: Unified CRM directory for platform administrators & APMC secretariats.
-- =============================================================================
SELECT 
    u.UserID,
    u.Name AS FullName,
    u.PhoneNo,
    d.DistrictName AS OperatingDistrict,
    u.UserType,
    CASE 
        WHEN u.UserType = 'Farmer' THEN CONCAT(f.FarmSize_Acres, ' Acres (Primary: ', f.PrimaryCrop, ')')
        WHEN u.UserType = 'Trader' THEN CONCAT(t.CompanyName, ' (Lic: ', t.LicenseNumber, ')')
        ELSE 'General Account'
    END AS RoleSpecificProfile,
    COUNT(pa.AlertID) AS ConfiguredAlertsCount
FROM System_User u
LEFT JOIN District d ON u.DistrictID = d.DistrictID
LEFT JOIN Farmer f ON u.UserID = f.UserID
LEFT JOIN Trader t ON u.UserID = t.UserID
LEFT JOIN Price_Alerts pa ON u.UserID = pa.UserID
GROUP BY u.UserID, u.Name, u.PhoneNo, d.DistrictName, u.UserType, f.FarmSize_Acres, f.PrimaryCrop, t.CompanyName, t.LicenseNumber
ORDER BY u.UserID ASC;


-- =============================================================================
-- QUERY 6: Production View Exploration (vw_buyer_mandi_risk_index)
-- Demonstrates: Querying analytical views with risk-based filtering.
-- Real-World Use: Corporate procurement contract risk assessment.
-- =============================================================================
SELECT 
    DistrictName,
    MarketName,
    CommodityName,
    TotalTradingDays,
    AvgModalPrice,
    PriceStdDev,
    VolatilityPct,
    AvgIntradaySpreadPct,
    ProcurementRiskRating
FROM vw_buyer_mandi_risk_index
WHERE ProcurementRiskRating IN ('STABLE PRICING (SAFE CONTRACTS)', 'HIGH VOLATILITY (RISKY)')
ORDER BY ProcurementRiskRating DESC, VolatilityPct DESC
LIMIT 10;


-- =============================================================================
-- QUERY 7: Stored Functions Suite Demonstration
-- Demonstrates: Simultaneous invocation of all 4 custom scalar functions.
-- Real-World Use: Real-time decision-support metrics in transaction processing.
-- =============================================================================
SELECT 
    p.PriceID,
    c.CommodityName,
    v.VarietyName,
    p.ModalPrice AS VarietyModalPrice,
    bench.BenchmarkPrice,
    fn_quality_discount_ratio(p.ModalPrice, bench.BenchmarkPrice) AS QualityPremiumPct,
    p.ArrivalTonnes,
    fn_inflow_status(p.ArrivalTonnes) AS InflowClassification,
    fn_price_spread_pct(p.MinPrice, p.MaxPrice) AS IntradaySpreadPct,
    fn_calculate_landed_cost(p.ModalPrice, 150.00, 2.50, 1.05) AS LandedCostToPuneHub
FROM Daily_Prices p
JOIN Variety v ON p.VarietyID = v.VarietyID
JOIN Commodity c ON v.CommodityID = c.CommodityID
JOIN (
    -- Commodity-level benchmark average
    SELECT v2.CommodityID, ROUND(AVG(p2.ModalPrice), 2) AS BenchmarkPrice
    FROM Daily_Prices p2
    JOIN Variety v2 ON p2.VarietyID = v2.VarietyID
    GROUP BY v2.CommodityID
) bench ON c.CommodityID = bench.CommodityID
WHERE c.CommodityName = 'Apple'
ORDER BY p.RecordDate DESC
LIMIT 10;


-- =============================================================================
-- QUERY 8: Stored Procedures 1 & 2 Execution (Best Mandis & Bulk Procurement)
-- Demonstrates: Invocation of farmer mandi ranking and buyer bulk procurement procedures.
-- Real-World Use: Farmer dispatch decisions and wholesale delivery planning.
-- =============================================================================

-- Call Procedure 1: Top 5 Mandis for Onion farmers between Jan and Oct 2026
CALL sp_find_best_mandis('Onion', '2026-01-01', '2026-10-10', 5);

-- Call Procedure 2: Bulk Procurement Plan for 100 Tonnes of Tomato to Mumbai Vashi Hub
CALL sp_buyer_bulk_procurement_plan('Tomato', 100.00, 'Mumbai (Vashi Hub)');


-- =============================================================================
-- QUERY 9: Stored Procedures 3 & 4 Execution (Arbitrage Radar & User Alerts)
-- Demonstrates: Inter-district price difference finder and live alert monitor.
-- Real-World Use: Commission agents profiting from mandi price spreads.
-- =============================================================================

-- Call Procedure 3: Arbitrage Radar for Onion on May 15, 2026 with min spread >= Rs. 400/Qtl
CALL sp_buyer_arbitrage_radar('Onion', '2026-05-15', 400.00);

-- Call Procedure 4: Check active price alert status for User 1 (Farmer Ramesh Patil)
CALL sp_check_user_alerts(1);

-- Call Procedure 4: Check active price alert status for User 3 (Trader Vikram Joshi)
CALL sp_check_user_alerts(3);


-- =============================================================================
-- QUERY 10: Trigger Verification & Automated Order Lifecycle
-- Demonstrates: Real-time trigger firing upon price record insertion and rollback/cleanup.
-- Real-World Use: Automated trade execution when market hits algorithmic limit order.
-- =============================================================================

-- Step 1: Inspect baseline alert status for Trader Vikram Joshi (AlertID 3, Apple <= 8000.00)
SELECT AlertID, UserID, CommodityID, TargetPrice, AlertCondition, TriggeredMessage 
FROM Price_Alerts 
WHERE AlertID = 3;

-- Step 2: Insert a price record that triggers the alert (Modal Price = Rs. 7,400 < Rs. 8,000)
INSERT INTO Daily_Prices (MarketID, VarietyID, Grade, RecordDate, MinPrice, MaxPrice, ModalPrice, ArrivalTonnes)
VALUES (
    (SELECT MarketID FROM Market WHERE MarketName LIKE '%Pune%' LIMIT 1),
    (SELECT VarietyID FROM Variety WHERE CommodityID = 1 LIMIT 1), -- Apple Variety
    'Grade-A',
    '2026-10-11',
    6800.00,
    7800.00,
    7400.00,
    35.00
);

-- Capture the inserted ID
SET @test_price_id = LAST_INSERT_ID();

-- Step 3: Verify Trigger 1 updated Price_Alerts message
SELECT AlertID, TargetPrice, AlertCondition, TriggeredMessage 
FROM Price_Alerts 
WHERE AlertID = 3;

-- Step 4: Verify Trigger 2 auto-generated an order in Buyer_Procurement_Orders
SELECT OrderID, BuyerUserID, MarketID, VarietyID, OrderDate, SuggestedQtyTonnes, TriggeredPrice, OrderStatus 
FROM Buyer_Procurement_Orders 
ORDER BY OrderID DESC 
LIMIT 1;

-- Step 5: Clean up the test row
DELETE FROM Daily_Prices WHERE PriceID = @test_price_id;
DELETE FROM Buyer_Procurement_Orders WHERE TriggeredPrice = 7400.00 AND OrderDate = '2026-10-11';
