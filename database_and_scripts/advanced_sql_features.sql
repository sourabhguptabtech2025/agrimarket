-- =============================================================================
-- AgriMarket Step 10 Advanced SQL Suite: Database Features
-- Database: AgriMarket
-- Target Schema: MySQL 8.x / 26.x
-- =============================================================================

USE AgriMarket;

-- Ensure function creation is permitted
SET GLOBAL log_bin_trust_function_creators = 1;
SET FOREIGN_KEY_CHECKS = 0;

-- =============================================================================
-- SECTION A: SUPPORTING TABLES FOR BUYER LOGISTICS & AUTOMATED ORDERS
-- =============================================================================

-- 1. District_Logistics Table
DROP TABLE IF EXISTS `District_Logistics`;
CREATE TABLE `District_Logistics` (
    `LogisticsID` INT AUTO_INCREMENT PRIMARY KEY,
    `OriginDistrictID` INT NOT NULL,
    `DestHubName` VARCHAR(100) NOT NULL,
    `DistanceKm` DECIMAL(6,2) NOT NULL,
    `FreightPerKmQuintal` DECIMAL(5,2) DEFAULT 2.50,
    UNIQUE KEY `uq_origin_desthub` (`OriginDistrictID`, `DestHubName`),
    CONSTRAINT `fk_logistics_district` FOREIGN KEY (`OriginDistrictID`) 
        REFERENCES `District` (`DistrictID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed Data: Highway Distances from All 13 Districts to Pune and Mumbai Hubs
INSERT INTO `District_Logistics` (`OriginDistrictID`, `DestHubName`, `DistanceKm`, `FreightPerKmQuintal`) VALUES
-- 1. Ahilyanagar
(1, 'Pune (Market Yard Hub)', 125.00, 2.40),
(1, 'Mumbai (Vashi Hub)', 245.00, 2.60),
-- 2. Amarawati
(2, 'Pune (Market Yard Hub)', 565.00, 2.20),
(2, 'Mumbai (Vashi Hub)', 650.00, 2.30),
-- 3. Chattrapati Sambhajinagar
(3, 'Pune (Market Yard Hub)', 235.00, 2.45),
(3, 'Mumbai (Vashi Hub)', 330.00, 2.55),
-- 4. Kolhapur
(4, 'Pune (Market Yard Hub)', 235.00, 2.35),
(4, 'Mumbai (Vashi Hub)', 375.00, 2.50),
-- 5. Mumbai
(5, 'Pune (Market Yard Hub)', 150.00, 2.70),
(5, 'Mumbai (Vashi Hub)', 25.00, 3.20),
-- 6. Nagpur
(6, 'Pune (Market Yard Hub)', 710.00, 2.15),
(6, 'Mumbai (Vashi Hub)', 790.00, 2.25),
-- 7. Nashik
(7, 'Pune (Market Yard Hub)', 210.00, 2.40),
(7, 'Mumbai (Vashi Hub)', 165.00, 2.50),
-- 8. Pune
(8, 'Pune (Market Yard Hub)', 15.00, 3.00),
(8, 'Mumbai (Vashi Hub)', 145.00, 2.65),
-- 9. Solapur
(9, 'Pune (Market Yard Hub)', 250.00, 2.35),
(9, 'Mumbai (Vashi Hub)', 395.00, 2.50),
-- 10. Thane
(10, 'Pune (Market Yard Hub)', 160.00, 2.65),
(10, 'Mumbai (Vashi Hub)', 30.00, 3.10),
-- 11. Dharashiv
(11, 'Pune (Market Yard Hub)', 270.00, 2.40),
(11, 'Mumbai (Vashi Hub)', 415.00, 2.55),
-- 12. Ratnagiri
(12, 'Pune (Market Yard Hub)', 305.00, 2.60),
(12, 'Mumbai (Vashi Hub)', 335.00, 2.70),
-- 13. Dhule
(13, 'Pune (Market Yard Hub)', 340.00, 2.45),
(13, 'Mumbai (Vashi Hub)', 325.00, 2.50);

-- 2. Buyer_Procurement_Orders Table
DROP TABLE IF EXISTS `Buyer_Procurement_Orders`;
CREATE TABLE `Buyer_Procurement_Orders` (
    `OrderID` INT AUTO_INCREMENT PRIMARY KEY,
    `BuyerUserID` INT NOT NULL,
    `MarketID` INT NOT NULL,
    `VarietyID` INT NOT NULL,
    `OrderDate` DATE NOT NULL,
    `SuggestedQtyTonnes` DECIMAL(10,2) NOT NULL,
    `TriggeredPrice` DECIMAL(10,2) NOT NULL,
    `OrderStatus` VARCHAR(50) DEFAULT 'AUTO_GENERATED',
    CONSTRAINT `fk_bpo_user` FOREIGN KEY (`BuyerUserID`) 
        REFERENCES `System_User` (`UserID`) ON DELETE CASCADE,
    CONSTRAINT `fk_bpo_market` FOREIGN KEY (`MarketID`) 
        REFERENCES `Market` (`MarketID`) ON DELETE CASCADE,
    CONSTRAINT `fk_bpo_variety` FOREIGN KEY (`VarietyID`) 
        REFERENCES `Variety` (`VarietyID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;


-- =============================================================================
-- SECTION B: REAL-WORLD SQL VIEWS
-- =============================================================================

-- View 1: Complete Mandi Feed (Master Denormalized Feed)
DROP VIEW IF EXISTS `vw_mandi_complete_feed`;
CREATE VIEW `vw_mandi_complete_feed` AS
SELECT 
    p.PriceID,
    p.RecordDate,
    s.StateName,
    d.DistrictName,
    m.MarketName,
    cat.CategoryName,
    c.CommodityName,
    v.VarietyName,
    p.Grade,
    p.MinPrice,
    p.MaxPrice,
    p.ModalPrice,
    p.ArrivalTonnes,
    ROUND(((p.MaxPrice - p.MinPrice) / NULLIF(p.MinPrice, 0)) * 100, 2) AS IntradaySpreadPct
FROM Daily_Prices p
JOIN Market m ON p.MarketID = m.MarketID
JOIN District d ON m.DistrictID = d.DistrictID
JOIN State s ON d.StateID = s.StateID
JOIN Variety v ON p.VarietyID = v.VarietyID
JOIN Commodity c ON v.CommodityID = c.CommodityID
JOIN Category cat ON c.CategoryID = cat.CategoryID;


-- View 2: District Crop Summary (Regional Agri-Commodity Performance)
DROP VIEW IF EXISTS `vw_district_crop_summary`;
CREATE VIEW `vw_district_crop_summary` AS
SELECT 
    d.DistrictName,
    cat.CategoryName,
    c.CommodityName,
    COUNT(p.PriceID) AS TotalTradingRecords,
    ROUND(SUM(p.ArrivalTonnes), 2) AS TotalArrivalTonnes,
    ROUND(AVG(p.ModalPrice), 2) AS AvgModalPrice,
    MAX(p.MaxPrice) AS HighestMaxPrice,
    MIN(p.MinPrice) AS LowestMinPrice,
    ROUND(AVG(((p.MaxPrice - p.MinPrice) / NULLIF(p.MinPrice, 0)) * 100), 2) AS AvgIntradaySpreadPct
FROM Daily_Prices p
JOIN Market m ON p.MarketID = m.MarketID
JOIN District d ON m.DistrictID = d.DistrictID
JOIN Variety v ON p.VarietyID = v.VarietyID
JOIN Commodity c ON v.CommodityID = c.CommodityID
JOIN Category cat ON c.CategoryID = cat.CategoryID
GROUP BY d.DistrictName, cat.CategoryName, c.CommodityName;


-- View 3: Buyer Mandi Risk Index (Stability & Volatility Scoring for >= 10 Records)
DROP VIEW IF EXISTS `vw_buyer_mandi_risk_index`;
CREATE VIEW `vw_buyer_mandi_risk_index` AS
SELECT 
    d.DistrictName,
    m.MarketName,
    c.CommodityName,
    COUNT(p.PriceID) AS TotalTradingDays,
    ROUND(AVG(p.ModalPrice), 2) AS AvgModalPrice,
    ROUND(STDDEV_POP(p.ModalPrice), 2) AS PriceStdDev,
    ROUND((STDDEV_POP(p.ModalPrice) / AVG(p.ModalPrice)) * 100, 2) AS VolatilityPct,
    ROUND(AVG(((p.MaxPrice - p.MinPrice) / NULLIF(p.MinPrice, 0)) * 100), 2) AS AvgIntradaySpreadPct,
    CASE 
        WHEN (STDDEV_POP(p.ModalPrice) / AVG(p.ModalPrice)) * 100 >= 25.00 THEN 'HIGH VOLATILITY (RISKY)'
        WHEN (STDDEV_POP(p.ModalPrice) / AVG(p.ModalPrice)) * 100 >= 12.00 THEN 'MODERATE RISK'
        ELSE 'STABLE PRICING (SAFE CONTRACTS)'
    END AS ProcurementRiskRating
FROM Daily_Prices p
JOIN Market m ON p.MarketID = m.MarketID
JOIN District d ON m.DistrictID = d.DistrictID
JOIN Variety v ON p.VarietyID = v.VarietyID
JOIN Commodity c ON v.CommodityID = c.CommodityID
GROUP BY d.DistrictName, m.MarketName, c.CommodityName
HAVING COUNT(p.PriceID) >= 10;


-- =============================================================================
-- SECTION C: STORED FUNCTIONS
-- =============================================================================

-- Function 1: Price Spread Percentage
DROP FUNCTION IF EXISTS `fn_price_spread_pct`;
DELIMITER //
CREATE FUNCTION `fn_price_spread_pct`(min_p DECIMAL(10,2), max_p DECIMAL(10,2)) 
RETURNS DECIMAL(6,2)
DETERMINISTIC
NO SQL
BEGIN
    IF min_p IS NULL OR max_p IS NULL OR min_p <= 0 THEN
        RETURN 0.00;
    END IF;
    -- Clamped to 9999.99 to guarantee fitting inside DECIMAL(6,2) for extreme auction outliers
    RETURN LEAST(ROUND(((max_p - min_p) / min_p) * 100.0, 2), 9999.99);
END //
DELIMITER ;


-- Function 2: Market Inflow Status Classification
DROP FUNCTION IF EXISTS `fn_inflow_status`;
DELIMITER //
CREATE FUNCTION `fn_inflow_status`(tonnes DECIMAL(12,2)) 
RETURNS VARCHAR(30)
DETERMINISTIC
NO SQL
BEGIN
    IF tonnes IS NULL THEN
        RETURN 'Unknown Supply';
    ELSEIF tonnes >= 1000.00 THEN
        RETURN 'Heavy Glut (>=1000T)';
    ELSEIF tonnes >= 100.00 THEN
        RETURN 'Moderate Supply (100-999T)';
    ELSE
        RETURN 'Low Supply (<100T)';
    END IF;
END //
DELIMITER ;


-- Function 3: Buyer Landed Cost Calculation
-- Formula: ModalPrice + (DistanceKm * FreightRate) + (ModalPrice * MandiCessPct / 100.0)
DROP FUNCTION IF EXISTS `fn_calculate_landed_cost`;
DELIMITER //
CREATE FUNCTION `fn_calculate_landed_cost`(
    modal_price DECIMAL(10,2), 
    distance_km DECIMAL(6,2), 
    freight_rate DECIMAL(5,2), 
    mandi_cess_pct DECIMAL(4,2)
) 
RETURNS DECIMAL(10,2)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE freight_cost DECIMAL(10,2);
    DECLARE cess_cost DECIMAL(10,2);
    
    SET freight_cost = COALESCE(distance_km * freight_rate, 0.00);
    SET cess_cost = COALESCE((modal_price * mandi_cess_pct) / 100.0, 0.00);
    
    RETURN ROUND(modal_price + freight_cost + cess_cost, 2);
END //
DELIMITER ;


-- Function 4: Variety Quality Discount or Premium Ratio
-- Formula: ((variety_modal - benchmark_modal) / benchmark_modal) * 100.0
DROP FUNCTION IF EXISTS `fn_quality_discount_ratio`;
DELIMITER //
CREATE FUNCTION `fn_quality_discount_ratio`(
    variety_modal DECIMAL(10,2), 
    benchmark_modal DECIMAL(10,2)
) 
RETURNS DECIMAL(6,2)
DETERMINISTIC
NO SQL
BEGIN
    IF benchmark_modal IS NULL OR benchmark_modal <= 0 OR variety_modal IS NULL THEN
        RETURN 0.00;
    END IF;
    -- Clamped to [-9999.99, 9999.99] to prevent DECIMAL(6,2) overflow on outlier variety benchmarks
    RETURN LEAST(GREATEST(ROUND(((variety_modal - benchmark_modal) / benchmark_modal) * 100.0, 2), -9999.99), 9999.99);
END //
DELIMITER ;


-- =============================================================================
-- SECTION D: STORED PROCEDURES
-- =============================================================================

-- Procedure 1: Find Best Mandis for Farmers (Highest Modal Price & Peak Returns)
DROP PROCEDURE IF EXISTS `sp_find_best_mandis`;
DELIMITER //
CREATE PROCEDURE `sp_find_best_mandis`(
    IN in_commodity VARCHAR(100),
    IN in_start_date DATE,
    IN in_end_date DATE,
    IN in_limit INT
)
BEGIN
    DECLARE row_limit INT DEFAULT 10;
    IF in_limit IS NOT NULL AND in_limit > 0 THEN
        SET row_limit = in_limit;
    END IF;

    SELECT 
        m.MarketName,
        d.DistrictName,
        c.CommodityName,
        ROUND(AVG(p.ModalPrice), 2) AS AvgModalPrice,
        MAX(p.MaxPrice) AS PeakMaxPrice,
        MIN(p.MinPrice) AS LowestMinPrice,
        ROUND(SUM(p.ArrivalTonnes), 2) AS TotalArrivalTonnes,
        ROUND(AVG(((p.MaxPrice - p.MinPrice) / NULLIF(p.MinPrice, 0)) * 100), 2) AS AvgPriceSpreadPct,
        COUNT(p.PriceID) AS TotalTradingDays
    FROM Daily_Prices p
    JOIN Market m ON p.MarketID = m.MarketID
    JOIN District d ON m.DistrictID = d.DistrictID
    JOIN Variety v ON p.VarietyID = v.VarietyID
    JOIN Commodity c ON v.CommodityID = c.CommodityID
    WHERE c.CommodityName = in_commodity
      AND p.RecordDate BETWEEN in_start_date AND in_end_date
    GROUP BY m.MarketID, m.MarketName, d.DistrictName, c.CommodityName
    ORDER BY AvgModalPrice DESC, PeakMaxPrice DESC
    LIMIT row_limit;
END //
DELIMITER ;


-- Procedure 2: Buyer Bulk Procurement Optimization Plan
-- Calculates landed cost to delivery hub and estimated total cost (1 Tonne = 10 Quintals)
DROP PROCEDURE IF EXISTS `sp_buyer_bulk_procurement_plan`;
DELIMITER //
CREATE PROCEDURE `sp_buyer_bulk_procurement_plan`(
    IN in_commodity VARCHAR(100),
    IN in_required_tonnes DECIMAL(12,2),
    IN in_hub_name VARCHAR(100)
)
BEGIN
    WITH LatestMandiPrices AS (
        SELECT 
            p.PriceID,
            p.MarketID,
            p.VarietyID,
            p.RecordDate,
            p.ModalPrice,
            p.ArrivalTonnes,
            ROW_NUMBER() OVER(PARTITION BY p.MarketID ORDER BY p.RecordDate DESC, p.PriceID DESC) as rn
        FROM Daily_Prices p
        JOIN Variety v ON p.VarietyID = v.VarietyID
        JOIN Commodity c ON v.CommodityID = c.CommodityID
        WHERE c.CommodityName = in_commodity
    )
    SELECT 
        m.MarketName,
        d.DistrictName,
        c.CommodityName,
        v.VarietyName,
        lp.RecordDate AS PriceAsOfDate,
        lp.ModalPrice AS MandiModalPricePerQtl,
        dl.DestHubName AS DeliveryHub,
        dl.DistanceKm AS TransportDistanceKm,
        dl.FreightPerKmQuintal AS FreightRatePerQtl,
        fn_calculate_landed_cost(lp.ModalPrice, dl.DistanceKm, dl.FreightPerKmQuintal, 1.05) AS LandedCostPerQuintal,
        lp.ArrivalTonnes AS AvailableArrivalTonnes,
        in_required_tonnes AS RequestedTonnes,
        CASE 
            WHEN lp.ArrivalTonnes >= in_required_tonnes THEN 'SUFFICIENT SUPPLY'
            ELSE 'PARTIAL SUPPLY / TIGHT'
        END AS SupplyFeasibility,
        ROUND((fn_calculate_landed_cost(lp.ModalPrice, dl.DistanceKm, dl.FreightPerKmQuintal, 1.05) * 10.0) * in_required_tonnes, 2) AS EstTotalCostINR
    FROM LatestMandiPrices lp
    JOIN Market m ON lp.MarketID = m.MarketID
    JOIN District d ON m.DistrictID = d.DistrictID
    JOIN Variety v ON lp.VarietyID = v.VarietyID
    JOIN Commodity c ON v.CommodityID = c.CommodityID
    JOIN District_Logistics dl ON d.DistrictID = dl.OriginDistrictID AND dl.DestHubName = in_hub_name
    WHERE lp.rn = 1
    ORDER BY LandedCostPerQuintal ASC;
END //
DELIMITER ;


-- Procedure 3: Trader Inter-District Arbitrage Radar
-- Identifies price mismatches across districts on the same day for the same crop
DROP PROCEDURE IF EXISTS `sp_buyer_arbitrage_radar`;
DELIMITER //
CREATE PROCEDURE `sp_buyer_arbitrage_radar`(
    IN in_commodity VARCHAR(100),
    IN in_date DATE,
    IN in_min_margin DECIMAL(10,2)
)
BEGIN
    SELECT 
        c.CommodityName,
        p_buy.RecordDate AS TradingDate,
        m_buy.MarketName AS BuyMandi,
        d_buy.DistrictName AS BuyDistrict,
        p_buy.ModalPrice AS BuyModalPrice,
        p_buy.ArrivalTonnes AS BuyAvailableTonnes,
        m_sell.MarketName AS SellMandi,
        d_sell.DistrictName AS SellDistrict,
        p_sell.ModalPrice AS SellModalPrice,
        p_sell.ArrivalTonnes AS SellDemandTonnes,
        (p_sell.ModalPrice - p_buy.ModalPrice) AS GrossMarginPerQuintal,
        ROUND(((p_sell.ModalPrice - p_buy.ModalPrice) / p_buy.ModalPrice) * 100, 2) AS ArbitrageSpreadPct
    FROM Daily_Prices p_buy
    JOIN Market m_buy ON p_buy.MarketID = m_buy.MarketID
    JOIN District d_buy ON m_buy.DistrictID = d_buy.DistrictID
    JOIN Variety v_buy ON p_buy.VarietyID = v_buy.VarietyID
    JOIN Commodity c ON v_buy.CommodityID = c.CommodityID
    JOIN Daily_Prices p_sell ON p_sell.RecordDate = p_buy.RecordDate
    JOIN Market m_sell ON p_sell.MarketID = m_sell.MarketID
    JOIN District d_sell ON m_sell.DistrictID = d_sell.DistrictID
    JOIN Variety v_sell ON p_sell.VarietyID = v_sell.VarietyID AND v_sell.CommodityID = c.CommodityID
    WHERE c.CommodityName = in_commodity
      AND p_buy.RecordDate = in_date
      AND d_buy.DistrictID <> d_sell.DistrictID
      AND (p_sell.ModalPrice - p_buy.ModalPrice) >= in_min_margin
    ORDER BY GrossMarginPerQuintal DESC;
END //
DELIMITER ;


-- Procedure 4: Check Active Price Alerts for a User
DROP PROCEDURE IF EXISTS `sp_check_user_alerts`;
DELIMITER //
CREATE PROCEDURE `sp_check_user_alerts`(
    IN in_user_id INT
)
BEGIN
    WITH LatestCommodityPrices AS (
        SELECT 
            c.CommodityID,
            p.ModalPrice,
            p.RecordDate,
            m.MarketName,
            ROW_NUMBER() OVER(PARTITION BY c.CommodityID ORDER BY p.RecordDate DESC, p.PriceID DESC) as rn
        FROM Daily_Prices p
        JOIN Market m ON p.MarketID = m.MarketID
        JOIN Variety v ON p.VarietyID = v.VarietyID
        JOIN Commodity c ON v.CommodityID = c.CommodityID
    )
    SELECT 
        pa.AlertID,
        u.UserID,
        u.Name AS UserName,
        u.UserType,
        c.CommodityName,
        pa.TargetPrice,
        pa.AlertCondition,
        lp.ModalPrice AS CurrentMarketPrice,
        lp.MarketName AS BenchMarkMandi,
        lp.RecordDate AS PriceRecordedDate,
        CASE 
            WHEN pa.AlertCondition = 'ABOVE' AND lp.ModalPrice >= pa.TargetPrice THEN 'TARGET BREACHED'
            WHEN pa.AlertCondition = 'BELOW' AND lp.ModalPrice <= pa.TargetPrice THEN 'TARGET BREACHED'
            ELSE 'MONITORING'
        END AS AlertStatus,
        pa.TriggeredMessage,
        pa.IsActive
    FROM Price_Alerts pa
    JOIN System_User u ON pa.UserID = u.UserID
    JOIN Commodity c ON pa.CommodityID = c.CommodityID
    LEFT JOIN LatestCommodityPrices lp ON pa.CommodityID = lp.CommodityID AND lp.rn = 1
    WHERE pa.UserID = in_user_id;
END //
DELIMITER ;


-- =============================================================================
-- SECTION E: AUTOMATED REAL-TIME TRIGGERS
-- =============================================================================

-- Trigger 1: Real-time Price Alert Message Update
DROP TRIGGER IF EXISTS `trg_after_price_insert_alert`;
DELIMITER //
CREATE TRIGGER `trg_after_price_insert_alert`
AFTER INSERT ON `Daily_Prices`
FOR EACH ROW
BEGIN
    -- Update all matching active alerts for the commodity associated with NEW.VarietyID
    UPDATE Price_Alerts pa
    JOIN Variety v ON v.VarietyID = NEW.VarietyID
    SET pa.TriggeredMessage = CONCAT('ALERT HIT on ', NEW.RecordDate, ': Modal Price reached Rs.', NEW.ModalPrice)
    WHERE pa.CommodityID = v.CommodityID
      AND pa.IsActive = TRUE
      AND (
          (pa.AlertCondition = 'ABOVE' AND NEW.ModalPrice >= pa.TargetPrice)
          OR
          (pa.AlertCondition = 'BELOW' AND NEW.ModalPrice <= pa.TargetPrice)
      );
END //
DELIMITER ;


-- Trigger 2: Automated Buyer Procurement Order Generation on Price Dip
DROP TRIGGER IF EXISTS `trg_buyer_auto_procurement_order`;
DELIMITER //
CREATE TRIGGER `trg_buyer_auto_procurement_order`
AFTER INSERT ON `Daily_Prices`
FOR EACH ROW
BEGIN
    -- If daily price drops to or below a Trader's BELOW target price, auto-generate procurement order
    INSERT INTO Buyer_Procurement_Orders (
        BuyerUserID,
        MarketID,
        VarietyID,
        OrderDate,
        SuggestedQtyTonnes,
        TriggeredPrice,
        OrderStatus
    )
    SELECT 
        pa.UserID,
        NEW.MarketID,
        NEW.VarietyID,
        NEW.RecordDate,
        25.00,
        NEW.ModalPrice,
        'AUTO_GENERATED'
    FROM Price_Alerts pa
    JOIN System_User u ON pa.UserID = u.UserID
    JOIN Variety v ON v.VarietyID = NEW.VarietyID
    WHERE pa.CommodityID = v.CommodityID
      AND u.UserType = 'Trader'
      AND pa.AlertCondition = 'BELOW'
      AND pa.IsActive = TRUE
      AND NEW.ModalPrice <= pa.TargetPrice;
END //
DELIMITER ;
