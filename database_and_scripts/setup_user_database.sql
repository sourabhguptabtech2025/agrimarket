-- =============================================================================
-- AgriUsers_DB: Dedicated User Management & Farmer Inventory Database
-- Database: AgriUsers_DB (Separated from AgriMarket)
-- Target Host: localhost:3306 (MySQL 8.x / 26.x)
-- =============================================================================

CREATE DATABASE IF NOT EXISTS AgriUsers_DB 
CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE AgriUsers_DB;

SET FOREIGN_KEY_CHECKS = 0;

-- =============================================================================
-- 1. BASE TABLE: System_User (Auth & Personal Identity)
-- =============================================================================
CREATE TABLE IF NOT EXISTS `System_User` (
    `UserID` INT AUTO_INCREMENT PRIMARY KEY,
    `Name` VARCHAR(100) NOT NULL,
    `PhoneNo` VARCHAR(15) UNIQUE NOT NULL,
    `Email` VARCHAR(150) UNIQUE NOT NULL,
    `PasswordHash` VARCHAR(255) NOT NULL,
    `DistrictID` INT DEFAULT NULL,
    `UserType` ENUM('Farmer', 'Trader', 'Admin') NOT NULL DEFAULT 'Farmer',
    `PreferredLanguage` VARCHAR(20) DEFAULT 'English',
    `CreatedAt` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 2. SUBCLASS TABLE: Farmer (EER Specialization)
-- =============================================================================
CREATE TABLE IF NOT EXISTS `Farmer` (
    `UserID` INT PRIMARY KEY,
    `FarmSize_Acres` DECIMAL(6,2) DEFAULT 5.00,
    `PrimaryCrop` VARCHAR(100) DEFAULT 'Onion',
    `VillageTaluka` VARCHAR(150) DEFAULT NULL,
    CONSTRAINT `fk_farmer_user` FOREIGN KEY (`UserID`) 
        REFERENCES `System_User` (`UserID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 3. SUBCLASS TABLE: Trader (EER Specialization)
-- =============================================================================
CREATE TABLE IF NOT EXISTS `Trader` (
    `UserID` INT PRIMARY KEY,
    `LicenseNumber` VARCHAR(50) UNIQUE,
    `CompanyName` VARCHAR(150) DEFAULT NULL,
    `GstNumber` VARCHAR(30) DEFAULT NULL,
    CONSTRAINT `fk_trader_user` FOREIGN KEY (`UserID`) 
        REFERENCES `System_User` (`UserID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 4. FARMER STORAGE VAULT: Farmer_Inventory (Batch Tracking & P&L)
-- =============================================================================
CREATE TABLE IF NOT EXISTS `Farmer_Inventory` (
    `InventoryID` INT AUTO_INCREMENT PRIMARY KEY,
    `FarmerUserID` INT NOT NULL,
    `VarietyID` INT NOT NULL,
    `QuantityQuintals` DECIMAL(10,2) NOT NULL,
    `CultivationCostPerQtl` DECIMAL(10,2) NOT NULL,
    `HarvestDate` DATE NOT NULL,
    `StorageStatus` ENUM('IN_STORAGE', 'READY_TO_SELL', 'SOLD') DEFAULT 'IN_STORAGE',
    `StorageLocation` VARCHAR(150) DEFAULT 'On-Farm Cold Room',
    `CreatedAt` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_inventory_farmer` FOREIGN KEY (`FarmerUserID`) 
        REFERENCES `System_User` (`UserID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 5. REAL-TIME MONITORS: Price_Alerts (SMS & Email Triggers)
-- =============================================================================
CREATE TABLE IF NOT EXISTS `Price_Alerts` (
    `AlertID` INT AUTO_INCREMENT PRIMARY KEY,
    `UserID` INT NOT NULL,
    `CommodityID` INT NOT NULL,
    `TargetPrice` DECIMAL(10,2) NOT NULL,
    `AlertCondition` ENUM('ABOVE', 'BELOW') DEFAULT 'ABOVE',
    `IsActive` BOOLEAN DEFAULT TRUE,
    `TriggeredMessage` VARCHAR(255) DEFAULT NULL,
    `CreatedAt` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_alert_user` FOREIGN KEY (`UserID`) 
        REFERENCES `System_User` (`UserID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 6. NOTIFICATION QUEUE: Email_Notifications_Log
-- =============================================================================
CREATE TABLE IF NOT EXISTS `Email_Notifications_Log` (
    `NotificationID` INT AUTO_INCREMENT PRIMARY KEY,
    `UserID` INT NOT NULL,
    `RecipientEmail` VARCHAR(150) NOT NULL,
    `Subject` VARCHAR(255) NOT NULL,
    `EmailBody` TEXT NOT NULL,
    `DeliveryStatus` ENUM('SENT_SMTP', 'LOGGED_LOCAL_OUTBOX') DEFAULT 'LOGGED_LOCAL_OUTBOX',
    `CreatedAt` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_email_user` FOREIGN KEY (`UserID`) 
        REFERENCES `System_User` (`UserID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 7. BUYER AUTOMATION: Buyer_Procurement_Orders
-- =============================================================================
CREATE TABLE IF NOT EXISTS `Buyer_Procurement_Orders` (
    `OrderID` INT AUTO_INCREMENT PRIMARY KEY,
    `BuyerUserID` INT NOT NULL,
    `MarketID` INT NOT NULL,
    `VarietyID` INT NOT NULL,
    `OrderDate` DATE NOT NULL,
    `SuggestedQtyTonnes` DECIMAL(10,2) NOT NULL,
    `TriggeredPrice` DECIMAL(10,2) NOT NULL,
    `OrderStatus` VARCHAR(50) DEFAULT 'AUTO_GENERATED',
    `CreatedAt` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_bpo_user` FOREIGN KEY (`BuyerUserID`) 
        REFERENCES `System_User` (`UserID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;


-- =============================================================================
-- 8. MIGRATE EXISTING USERS & INVENTORY FROM AgriMarket INTO AgriUsers_DB
-- =============================================================================
INSERT IGNORE INTO AgriUsers_DB.System_User (UserID, Name, PhoneNo, Email, PasswordHash, DistrictID, UserType)
SELECT UserID, Name, PhoneNo, COALESCE(Email, CONCAT('user', UserID, '@agrimarket.in')), PasswordHash, DistrictID, UserType 
FROM AgriMarket.System_User;

INSERT IGNORE INTO AgriUsers_DB.Farmer (UserID, FarmSize_Acres, PrimaryCrop)
SELECT UserID, FarmSize_Acres, PrimaryCrop 
FROM AgriMarket.Farmer;

INSERT IGNORE INTO AgriUsers_DB.Trader (UserID, LicenseNumber, CompanyName)
SELECT UserID, LicenseNumber, CompanyName 
FROM AgriMarket.Trader;

INSERT IGNORE INTO AgriUsers_DB.Farmer_Inventory (InventoryID, FarmerUserID, VarietyID, QuantityQuintals, CultivationCostPerQtl, HarvestDate, StorageStatus, StorageLocation)
SELECT InventoryID, FarmerUserID, VarietyID, QuantityQuintals, CultivationCostPerQtl, HarvestDate, StorageStatus, StorageLocation 
FROM AgriMarket.Farmer_Inventory;

INSERT IGNORE INTO AgriUsers_DB.Price_Alerts (AlertID, UserID, CommodityID, TargetPrice, AlertCondition, IsActive, TriggeredMessage)
SELECT AlertID, UserID, CommodityID, TargetPrice, AlertCondition, IsActive, TriggeredMessage 
FROM AgriMarket.Price_Alerts;

INSERT IGNORE INTO AgriUsers_DB.Email_Notifications_Log (NotificationID, UserID, RecipientEmail, Subject, EmailBody, DeliveryStatus, CreatedAt)
SELECT NotificationID, UserID, RecipientEmail, Subject, EmailBody, DeliveryStatus, CreatedAt 
FROM AgriMarket.Email_Notifications_Log;


-- =============================================================================
-- 9. CROSS-DATABASE STORED PROCEDURE: sp_farmer_inventory_valuation
-- Evaluates stored inventory against live AgriMarket.Daily_Prices
-- =============================================================================
DROP PROCEDURE IF EXISTS `sp_farmer_inventory_valuation`;
DELIMITER //
CREATE PROCEDURE `sp_farmer_inventory_valuation`(
    IN in_farmer_id INT
)
BEGIN
    WITH LatestVarietyPrices AS (
        SELECT 
            p.VarietyID,
            p.ModalPrice,
            p.RecordDate,
            m.MarketName,
            d.DistrictName,
            ROW_NUMBER() OVER(PARTITION BY p.VarietyID ORDER BY p.RecordDate DESC, p.PriceID DESC) as rn
        FROM AgriMarket.Daily_Prices p
        JOIN AgriMarket.Market m ON p.MarketID = m.MarketID
        JOIN AgriMarket.District d ON m.DistrictID = d.DistrictID
    ),
    LatestCommodityPrices AS (
        SELECT 
            v.CommodityID,
            p.ModalPrice,
            p.RecordDate,
            m.MarketName,
            d.DistrictName,
            ROW_NUMBER() OVER(PARTITION BY v.CommodityID ORDER BY p.RecordDate DESC, p.PriceID DESC) as rn
        FROM AgriMarket.Daily_Prices p
        JOIN AgriMarket.Variety v ON p.VarietyID = v.VarietyID
        JOIN AgriMarket.Market m ON p.MarketID = m.MarketID
        JOIN AgriMarket.District d ON m.DistrictID = d.DistrictID
    )
    SELECT 
        fi.InventoryID,
        fi.FarmerUserID,
        u.Name AS FarmerName,
        c.CommodityName,
        v.VarietyName,
        fi.QuantityQuintals,
        fi.CultivationCostPerQtl,
        ROUND(fi.QuantityQuintals * fi.CultivationCostPerQtl, 2) AS TotalInvestmentCost,
        COALESCE(lv.ModalPrice, lc.ModalPrice, fi.CultivationCostPerQtl) AS CurrentMandiPricePerQtl,
        COALESCE(lv.RecordDate, lc.RecordDate) AS PriceDate,
        COALESCE(lv.MarketName, lc.MarketName) AS BenchmarkMandi,
        ROUND(fi.QuantityQuintals * COALESCE(lv.ModalPrice, lc.ModalPrice, fi.CultivationCostPerQtl), 2) AS CurrentMarketValuation,
        ROUND((fi.QuantityQuintals * COALESCE(lv.ModalPrice, lc.ModalPrice, fi.CultivationCostPerQtl)) - 
              (fi.QuantityQuintals * fi.CultivationCostPerQtl), 2) AS EstimatedNetProfitLossINR,
        ROUND(((COALESCE(lv.ModalPrice, lc.ModalPrice, fi.CultivationCostPerQtl) - fi.CultivationCostPerQtl) / 
              NULLIF(fi.CultivationCostPerQtl, 0)) * 100.0, 2) AS ROIPercent,
        fi.HarvestDate,
        fi.StorageStatus,
        fi.StorageLocation,
        CASE 
            WHEN COALESCE(lv.ModalPrice, lc.ModalPrice, fi.CultivationCostPerQtl) >= (fi.CultivationCostPerQtl * 1.20) 
                THEN 'SELL NOW (PROFITABLE)'
            WHEN COALESCE(lv.ModalPrice, lc.ModalPrice, fi.CultivationCostPerQtl) >= fi.CultivationCostPerQtl 
                THEN 'MARGINAL PROFIT (HOLD OR SELL)'
            ELSE 'HOLD IN STORAGE (UNDER COST)'
        END AS SalesRecommendation
    FROM AgriUsers_DB.Farmer_Inventory fi
    JOIN AgriUsers_DB.System_User u ON fi.FarmerUserID = u.UserID
    JOIN AgriMarket.Variety v ON fi.VarietyID = v.VarietyID
    JOIN AgriMarket.Commodity c ON v.CommodityID = c.CommodityID
    LEFT JOIN LatestVarietyPrices lv ON v.VarietyID = lv.VarietyID AND lv.rn = 1
    LEFT JOIN LatestCommodityPrices lc ON c.CommodityID = lc.CommodityID AND lc.rn = 1
    WHERE fi.FarmerUserID = in_farmer_id
    ORDER BY fi.HarvestDate DESC;
END //
DELIMITER ;


-- =============================================================================
-- 10. CROSS-DATABASE STORED PROCEDURE: sp_check_user_alerts
-- Checks active user alerts against latest AgriMarket mandi prices
-- =============================================================================
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
        FROM AgriMarket.Daily_Prices p
        JOIN AgriMarket.Market m ON p.MarketID = m.MarketID
        JOIN AgriMarket.Variety v ON p.VarietyID = v.VarietyID
        JOIN AgriMarket.Commodity c ON v.CommodityID = c.CommodityID
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
    FROM AgriUsers_DB.Price_Alerts pa
    JOIN AgriUsers_DB.System_User u ON pa.UserID = u.UserID
    JOIN AgriMarket.Commodity c ON pa.CommodityID = c.CommodityID
    LEFT JOIN LatestCommodityPrices lp ON pa.CommodityID = lp.CommodityID AND lp.rn = 1
    WHERE pa.UserID = in_user_id;
END //
DELIMITER ;


-- =============================================================================
-- 11. UPGRADE AgriMarket TRIGGERS TO UPDATE AgriUsers_DB
-- =============================================================================
USE AgriMarket;

DROP TRIGGER IF EXISTS `trg_after_price_insert_alert`;
DELIMITER //
CREATE TRIGGER `trg_after_price_insert_alert`
AFTER INSERT ON `Daily_Prices`
FOR EACH ROW
BEGIN
    -- 1. Update Price_Alerts in AgriUsers_DB
    UPDATE AgriUsers_DB.Price_Alerts pa
    JOIN Variety v ON v.VarietyID = NEW.VarietyID
    SET pa.TriggeredMessage = CONCAT('ALERT HIT on ', NEW.RecordDate, ': Modal Price reached Rs.', NEW.ModalPrice)
    WHERE pa.CommodityID = v.CommodityID
      AND pa.IsActive = TRUE
      AND (
          (pa.AlertCondition = 'ABOVE' AND NEW.ModalPrice >= pa.TargetPrice)
          OR
          (pa.AlertCondition = 'BELOW' AND NEW.ModalPrice <= pa.TargetPrice)
      );

    -- 2. Log email notification into AgriUsers_DB.Email_Notifications_Log
    INSERT INTO AgriUsers_DB.Email_Notifications_Log (
        UserID,
        RecipientEmail,
        Subject,
        EmailBody,
        DeliveryStatus
    )
    SELECT 
        pa.UserID,
        COALESCE(u.Email, CONCAT('user', pa.UserID, '@agrimarket.in')),
        CONCAT('AgriMarket Alert: ', c.CommodityName, ' Target Met at Rs. ', NEW.ModalPrice, '/Qtl!'),
        CONCAT(
            '<div style="font-family: Arial, sans-serif; padding: 15px; border: 1px solid #4CAF50; border-radius: 8px;">',
            '<h2 style="color: #2E7D32;">AgriMarket Real-Time Price Target Breached!</h2>',
            '<p>Hello <b>', u.Name, '</b>,</p>',
            '<p>A trade in the APMC network has hit your target:</p>',
            '<ul>',
            '<li><b>Crop:</b> ', c.CommodityName, ' (', v.VarietyName, ')</li>',
            '<li><b>Mandi:</b> ', m.MarketName, ' (', d.DistrictName, ')</li>',
            '<li><b>Modal Price:</b> Rs. ', NEW.ModalPrice, ' / Quintal</li>',
            '<li><b>Target Price:</b> Rs. ', pa.TargetPrice, ' / Quintal (', pa.AlertCondition, ')</li>',
            '<li><b>Arrival:</b> ', COALESCE(NEW.ArrivalTonnes, 0.00), ' Tonnes</li>',
            '</ul>',
            '</div>'
        ),
        'LOGGED_LOCAL_OUTBOX'
    FROM AgriUsers_DB.Price_Alerts pa
    JOIN AgriUsers_DB.System_User u ON pa.UserID = u.UserID
    JOIN Variety v ON v.VarietyID = NEW.VarietyID
    JOIN Commodity c ON v.CommodityID = c.CommodityID
    JOIN Market m ON m.MarketID = NEW.MarketID
    JOIN District d ON m.DistrictID = d.DistrictID
    WHERE pa.CommodityID = v.CommodityID
      AND pa.IsActive = TRUE
      AND (
          (pa.AlertCondition = 'ABOVE' AND NEW.ModalPrice >= pa.TargetPrice)
          OR
          (pa.AlertCondition = 'BELOW' AND NEW.ModalPrice <= pa.TargetPrice)
      );
END //
DELIMITER ;


DROP TRIGGER IF EXISTS `trg_buyer_auto_procurement_order`;
DELIMITER //
CREATE TRIGGER `trg_buyer_auto_procurement_order`
AFTER INSERT ON `Daily_Prices`
FOR EACH ROW
BEGIN
    INSERT INTO AgriUsers_DB.Buyer_Procurement_Orders (
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
    FROM AgriUsers_DB.Price_Alerts pa
    JOIN AgriUsers_DB.System_User u ON pa.UserID = u.UserID
    JOIN Variety v ON v.VarietyID = NEW.VarietyID
    WHERE pa.CommodityID = v.CommodityID
      AND u.UserType = 'Trader'
      AND pa.AlertCondition = 'BELOW'
      AND pa.IsActive = TRUE
      AND NEW.ModalPrice <= pa.TargetPrice;
END //
DELIMITER ;
