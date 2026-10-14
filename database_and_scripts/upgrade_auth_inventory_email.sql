-- =============================================================================
-- AgriMarket Schema Upgrade: Email Auth, Farmer Inventory & Email Queue
-- Database: AgriMarket
-- =============================================================================

USE AgriMarket;

SET FOREIGN_KEY_CHECKS = 0;

-- =============================================================================
-- 1. UPGRADE System_User TABLE: ADD Email & RE-SEED DEMO CREDENTIALS
-- =============================================================================

-- Add Email column safely if it doesn't already exist
SET @col_exists = (
    SELECT COUNT(*) 
    FROM information_schema.COLUMNS 
    WHERE TABLE_SCHEMA = 'AgriMarket' 
      AND TABLE_NAME = 'System_User' 
      AND COLUMN_NAME = 'Email'
);

SET @sql_add_email = IF(
    @col_exists = 0,
    'ALTER TABLE System_User ADD COLUMN Email VARCHAR(150) UNIQUE AFTER PhoneNo;',
    'SELECT "Column Email already exists in System_User" AS Info;'
);
PREPARE stmt_email FROM @sql_add_email;
EXECUTE stmt_email;
DEALLOCATE PREPARE stmt_email;

-- Default password hash for 'pass123' (SHA-256)
-- pass123 SHA256 = b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
SET @demo_pwd_hash = SHA2('pass123', 256);

-- Update seed users with official emails and predictable password 'pass123'
UPDATE System_User 
SET Email = 'ramesh.patil@agrimarket.in', PasswordHash = @demo_pwd_hash
WHERE UserID = 1;

UPDATE System_User 
SET Email = 'suresh.shinde@agrimarket.in', PasswordHash = @demo_pwd_hash
WHERE UserID = 2;

UPDATE System_User 
SET Email = 'vikram.joshi@agrimarket.in', PasswordHash = @demo_pwd_hash
WHERE UserID = 3;

UPDATE System_User 
SET Email = 'anil.deshmukh@agrimarket.in', PasswordHash = @demo_pwd_hash
WHERE UserID = 4;


-- =============================================================================
-- 2. CREATE Farmer_Inventory TABLE (Stored Harvests & Batch Tracking)
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
        REFERENCES `System_User` (`UserID`) ON DELETE CASCADE,
    CONSTRAINT `fk_inventory_variety` FOREIGN KEY (`VarietyID`) 
        REFERENCES `Variety` (`VarietyID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed realistic inventory records if table is currently empty
INSERT IGNORE INTO `Farmer_Inventory` 
    (`InventoryID`, `FarmerUserID`, `VarietyID`, `QuantityQuintals`, `CultivationCostPerQtl`, `HarvestDate`, `StorageStatus`, `StorageLocation`)
VALUES
    (1, 1, 10, 350.00, 1250.00, '2026-09-15', 'IN_STORAGE', 'Lasalgaon Farmer Warehouse #3'),
    (2, 1, 11, 200.00, 1100.00, '2026-08-20', 'READY_TO_SELL', 'Pimpalgaon Dry Air Storage'),
    (3, 2, 23, 180.00, 850.00, '2026-10-01', 'IN_STORAGE', 'Nashik Agro Cold Storage Hub B');


-- =============================================================================
-- 3. CREATE Email_Notifications_Log TABLE (Automated Notification Queue)
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
-- 4. UPGRADE TRIGGER: trg_after_price_insert_alert
-- Automatically writes triggered alert message AND queues an email notification!
-- =============================================================================

DROP TRIGGER IF EXISTS `trg_after_price_insert_alert`;
DELIMITER //
CREATE TRIGGER `trg_after_price_insert_alert`
AFTER INSERT ON `Daily_Prices`
FOR EACH ROW
BEGIN
    -- 1. Update Price_Alerts message
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

    -- 2. Automatically log an email alert into Email_Notifications_Log
    INSERT INTO Email_Notifications_Log (
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
            '<div style="font-family: Arial, sans-serif; padding: 20px; border: 1px solid #4CAF50; border-radius: 8px;">',
            '<h2 style="color: #2E7D32;">AgriMarket Real-Time Price Target Breached!</h2>',
            '<p>Dear <b>', u.Name, '</b>,</p>',
            '<p>A recorded trade in the APMC mandi network has met your price criteria:</p>',
            '<table style="width: 100%; border-collapse: collapse;">',
            '<tr><td><b>Crop / Commodity:</b></td><td>', c.CommodityName, '</td></tr>',
            '<tr><td><b>Variety & Grade:</b></td><td>', v.VarietyName, ' (Grade: ', COALESCE(NEW.Grade, 'Local'), ')</td></tr>',
            '<tr><td><b>Mandi Center:</b></td><td>', m.MarketName, ' (District: ', d.DistrictName, ')</td></tr>',
            '<tr><td><b>Date of Trade:</b></td><td>', NEW.RecordDate, '</td></tr>',
            '<tr><td><b>Recorded Modal Price:</b></td><td style="color: #1B5E20; font-size: 16px;"><b>Rs. ', NEW.ModalPrice, ' / Quintal</b></td></tr>',
            '<tr><td><b>Your Alert Target:</b></td><td>Rs. ', pa.TargetPrice, ' / Quintal (Condition: ', pa.AlertCondition, ')</td></tr>',
            '<tr><td><b>Arrival Volume:</b></td><td>', COALESCE(NEW.ArrivalTonnes, 0.00), ' Metric Tonnes</td></tr>',
            '</table>',
            '<br/><p>Log in to your <b>AgriMarket Dashboard</b> immediately to capitalize on this pricing.</p>',
            '<p style="color: #777; font-size: 12px;">This is an automated notification from AgriMarket Engine.</p>',
            '</div>'
        ),
        'LOGGED_LOCAL_OUTBOX'
    FROM Price_Alerts pa
    JOIN System_User u ON pa.UserID = u.UserID
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


-- =============================================================================
-- 5. CREATE STORED PROCEDURE: sp_farmer_inventory_valuation
-- Joins farmer stored batches with latest market prices to calculate P&L & ROI
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
        FROM Daily_Prices p
        JOIN Market m ON p.MarketID = m.MarketID
        JOIN District d ON m.DistrictID = d.DistrictID
    ),
    LatestCommodityPrices AS (
        SELECT 
            v.CommodityID,
            p.ModalPrice,
            p.RecordDate,
            m.MarketName,
            d.DistrictName,
            ROW_NUMBER() OVER(PARTITION BY v.CommodityID ORDER BY p.RecordDate DESC, p.PriceID DESC) as rn
        FROM Daily_Prices p
        JOIN Variety v ON p.VarietyID = v.VarietyID
        JOIN Market m ON p.MarketID = m.MarketID
        JOIN District d ON m.DistrictID = d.DistrictID
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
    FROM Farmer_Inventory fi
    JOIN System_User u ON fi.FarmerUserID = u.UserID
    JOIN Variety v ON fi.VarietyID = v.VarietyID
    JOIN Commodity c ON v.CommodityID = c.CommodityID
    LEFT JOIN LatestVarietyPrices lv ON v.VarietyID = lv.VarietyID AND lv.rn = 1
    LEFT JOIN LatestCommodityPrices lc ON c.CommodityID = lc.CommodityID AND lc.rn = 1
    WHERE fi.FarmerUserID = in_farmer_id
    ORDER BY fi.HarvestDate DESC;
END //
DELIMITER ;

SET FOREIGN_KEY_CHECKS = 1;
