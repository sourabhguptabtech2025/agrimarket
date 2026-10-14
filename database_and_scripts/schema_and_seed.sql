-- =============================================================================
-- AgriMarket Complete Relational Schema & Seed Data Dump
-- Exported: 2026-10-10 17:53:28
-- Database: AgriMarket
-- =============================================================================

CREATE DATABASE IF NOT EXISTS AgriMarket;
USE AgriMarket;

SET FOREIGN_KEY_CHECKS = 0;

-- -----------------------------------------------------------------------------
-- Table structure for `State`
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS `State`;
CREATE TABLE `state` (
  `StateID` int NOT NULL AUTO_INCREMENT,
  `StateName` varchar(100) NOT NULL,
  PRIMARY KEY (`StateID`),
  UNIQUE KEY `StateName` (`StateName`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- Table structure for `District`
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS `District`;
CREATE TABLE `district` (
  `DistrictID` int NOT NULL AUTO_INCREMENT,
  `StateID` int NOT NULL,
  `DistrictName` varchar(100) NOT NULL,
  PRIMARY KEY (`DistrictID`),
  UNIQUE KEY `uq_state_district` (`StateID`,`DistrictName`),
  CONSTRAINT `district_ibfk_1` FOREIGN KEY (`StateID`) REFERENCES `state` (`StateID`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=14 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- Table structure for `Market`
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS `Market`;
CREATE TABLE `market` (
  `MarketID` int NOT NULL AUTO_INCREMENT,
  `DistrictID` int NOT NULL,
  `MarketName` varchar(150) NOT NULL,
  PRIMARY KEY (`MarketID`),
  UNIQUE KEY `uq_district_market` (`DistrictID`,`MarketName`),
  CONSTRAINT `market_ibfk_1` FOREIGN KEY (`DistrictID`) REFERENCES `district` (`DistrictID`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=91 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- Table structure for `Category`
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS `Category`;
CREATE TABLE `category` (
  `CategoryID` int NOT NULL AUTO_INCREMENT,
  `CategoryName` varchar(100) NOT NULL,
  PRIMARY KEY (`CategoryID`),
  UNIQUE KEY `CategoryName` (`CategoryName`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- Table structure for `Commodity`
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS `Commodity`;
CREATE TABLE `commodity` (
  `CommodityID` int NOT NULL AUTO_INCREMENT,
  `CategoryID` int NOT NULL,
  `CommodityName` varchar(100) NOT NULL,
  PRIMARY KEY (`CommodityID`),
  UNIQUE KEY `uq_category_commodity` (`CategoryID`,`CommodityName`),
  CONSTRAINT `commodity_ibfk_1` FOREIGN KEY (`CategoryID`) REFERENCES `category` (`CategoryID`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- Table structure for `Variety`
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS `Variety`;
CREATE TABLE `variety` (
  `VarietyID` int NOT NULL AUTO_INCREMENT,
  `CommodityID` int NOT NULL,
  `VarietyName` varchar(100) NOT NULL,
  PRIMARY KEY (`VarietyID`),
  UNIQUE KEY `uq_commodity_variety` (`CommodityID`,`VarietyName`),
  CONSTRAINT `variety_ibfk_1` FOREIGN KEY (`CommodityID`) REFERENCES `commodity` (`CommodityID`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=25 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- Table structure for `Daily_Prices`
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS `Daily_Prices`;
CREATE TABLE `daily_prices` (
  `PriceID` int NOT NULL AUTO_INCREMENT,
  `MarketID` int NOT NULL,
  `VarietyID` int NOT NULL,
  `Grade` varchar(50) DEFAULT NULL,
  `RecordDate` date DEFAULT NULL,
  `MinPrice` decimal(10,2) DEFAULT NULL,
  `MaxPrice` decimal(10,2) DEFAULT NULL,
  `ModalPrice` decimal(10,2) DEFAULT NULL,
  `ArrivalTonnes` decimal(12,2) DEFAULT NULL,
  PRIMARY KEY (`PriceID`),
  KEY `idx_date` (`RecordDate`),
  KEY `idx_market_var` (`MarketID`,`VarietyID`),
  KEY `VarietyID` (`VarietyID`),
  CONSTRAINT `daily_prices_ibfk_1` FOREIGN KEY (`MarketID`) REFERENCES `market` (`MarketID`) ON DELETE CASCADE,
  CONSTRAINT `daily_prices_ibfk_2` FOREIGN KEY (`VarietyID`) REFERENCES `variety` (`VarietyID`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=40308 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- Table structure for `System_User`
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS `System_User`;
CREATE TABLE `system_user` (
  `UserID` int NOT NULL AUTO_INCREMENT,
  `Name` varchar(100) NOT NULL,
  `PhoneNo` varchar(15) NOT NULL,
  `PasswordHash` varchar(255) NOT NULL,
  `DistrictID` int DEFAULT NULL,
  `UserType` enum('Farmer','Trader') NOT NULL,
  PRIMARY KEY (`UserID`),
  UNIQUE KEY `PhoneNo` (`PhoneNo`),
  KEY `DistrictID` (`DistrictID`),
  CONSTRAINT `system_user_ibfk_1` FOREIGN KEY (`DistrictID`) REFERENCES `district` (`DistrictID`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- Table structure for `Farmer`
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS `Farmer`;
CREATE TABLE `farmer` (
  `UserID` int NOT NULL,
  `FarmSize_Acres` decimal(6,2) DEFAULT NULL,
  `PrimaryCrop` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`UserID`),
  CONSTRAINT `farmer_ibfk_1` FOREIGN KEY (`UserID`) REFERENCES `system_user` (`UserID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- Table structure for `Trader`
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS `Trader`;
CREATE TABLE `trader` (
  `UserID` int NOT NULL,
  `LicenseNumber` varchar(50) DEFAULT NULL,
  `CompanyName` varchar(150) DEFAULT NULL,
  PRIMARY KEY (`UserID`),
  UNIQUE KEY `LicenseNumber` (`LicenseNumber`),
  CONSTRAINT `trader_ibfk_1` FOREIGN KEY (`UserID`) REFERENCES `system_user` (`UserID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- Table structure for `Price_Alerts`
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS `Price_Alerts`;
CREATE TABLE `price_alerts` (
  `AlertID` int NOT NULL AUTO_INCREMENT,
  `UserID` int NOT NULL,
  `CommodityID` int NOT NULL,
  `TargetPrice` decimal(10,2) NOT NULL,
  `AlertCondition` enum('ABOVE','BELOW') DEFAULT 'ABOVE',
  `IsActive` tinyint(1) DEFAULT '1',
  `TriggeredMessage` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`AlertID`),
  KEY `UserID` (`UserID`),
  KEY `CommodityID` (`CommodityID`),
  CONSTRAINT `price_alerts_ibfk_1` FOREIGN KEY (`UserID`) REFERENCES `system_user` (`UserID`) ON DELETE CASCADE,
  CONSTRAINT `price_alerts_ibfk_2` FOREIGN KEY (`CommodityID`) REFERENCES `commodity` (`CommodityID`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET FOREIGN_KEY_CHECKS = 1;

-- -----------------------------------------------------------------------------
-- Seed data for `State` (1 records)
-- -----------------------------------------------------------------------------
INSERT INTO `State` (`StateID`, `StateName`) VALUES
(1, 'Maharashtra');

-- -----------------------------------------------------------------------------
-- Seed data for `District` (13 records)
-- -----------------------------------------------------------------------------
INSERT INTO `District` (`DistrictID`, `StateID`, `DistrictName`) VALUES
(1, 1, 'Ahilyanagar'),
(2, 1, 'Amarawati'),
(3, 1, 'Chattrapati Sambhajinagar'),
(11, 1, 'Dharashiv'),
(13, 1, 'Dhule'),
(4, 1, 'Kolhapur'),
(5, 1, 'Mumbai'),
(6, 1, 'Nagpur'),
(7, 1, 'Nashik'),
(8, 1, 'Pune'),
(12, 1, 'Ratnagiri'),
(9, 1, 'Solapur'),
(10, 1, 'Thane');

-- -----------------------------------------------------------------------------
-- Seed data for `Market` (90 records)
-- -----------------------------------------------------------------------------
INSERT INTO `Market` (`MarketID`, `DistrictID`, `MarketName`) VALUES
(1, 1, 'APMC Ahilyanagar'),
(32, 1, 'APMC Akole'),
(33, 1, 'APMC Jamkhed'),
(34, 1, 'APMC Karjat'),
(35, 1, 'APMC Kopargaon'),
(36, 1, 'APMC Newasa'),
(37, 1, 'APMC Parner'),
(38, 1, 'APMC Pathardi'),
(15, 1, 'APMC Rahata'),
(2, 1, 'APMC Rahuri'),
(39, 1, 'APMC Sangamner'),
(40, 1, 'APMC Shevgaon'),
(41, 1, 'APMC Shrigonda'),
(16, 1, 'APMC Shrirampur'),
(42, 1, 'Karjat(Rashin)'),
(43, 1, 'Newasa(Ghodegaon)'),
(44, 1, 'Omchatinya Multi State Agro Purpose Co-Op Society, Dist Ahilyanagar'),
(45, 1, 'Prasanna Krushi Market, Tal Parnet, Dist Ahilyanagar'),
(87, 1, 'Rahuri(Songaon)'),
(46, 1, 'Rahuri(Vambori)'),
(47, 1, 'Shree Sairaj Krushi Market, Dist Ahilyanagar'),
(3, 2, 'Amrawati(Frui & Veg. Market)'),
(14, 2, 'APMC Anajngaon'),
(4, 3, 'APMC Chattrapati Sambhajinagar'),
(48, 3, 'APMC Gangapur'),
(49, 3, 'APMC Lasur Station'),
(50, 3, 'APMC Paithan'),
(51, 3, 'APMC Vaijpur'),
(5, 4, 'APMC Kolhapur'),
(22, 4, 'APMC Vadgaonpeth'),
(23, 5, 'APMC Mumbai'),
(6, 5, 'Mumbai- Fruit Market'),
(58, 5, 'Mumbai-Onion & Potato Market'),
(7, 6, 'APMC Hingna'),
(88, 6, 'APMC Kalmeshwar'),
(18, 6, 'APMC Kamthi'),
(8, 6, 'APMC Nagpur'),
(89, 6, 'APMC Parshiwani'),
(19, 6, 'APMC Ramtek'),
(59, 7, 'APMC Chandwad'),
(60, 7, 'APMC Devala'),
(61, 7, 'APMC Dindori'),
(90, 7, 'APMC Ghoti'),
(62, 7, 'APMC Kalvan'),
(63, 7, 'APMC Lasalgaon'),
(64, 7, 'APMC Manmad'),
(65, 7, 'APMC Nampur'),
(66, 7, 'APMC Nandgaon'),
(9, 7, 'APMC Nasik'),
(67, 7, 'APMC Pimpalgaon Baswant'),
(68, 7, 'APMC Satana'),
(69, 7, 'APMC Sinner'),
(70, 7, 'APMC Umrane'),
(71, 7, 'APMC Yeola'),
(72, 7, 'Dindori(Vani)'),
(73, 7, 'Lasalgaon(Niphad)'),
(74, 7, 'Lasalgaon(Vinchur)'),
(75, 7, 'Malharshree Khajgi Krushi Utpann Bajar, Chandanpuri Tal Malegaon, Nashik'),
(76, 7, 'Pimpalgaon Baswant(Saykheda)'),
(77, 7, 'Shivsiddha Govind Producer Company Ltd Sanchalit Khajgi Krushi Utpann Bajar Samati-Abhona-Kalwan'),
(78, 7, 'Shri Rameshwar Krushi Market, M.Nagar, Tal Deola, Dist Nashik'),
(79, 8, 'APMC Indapur'),
(31, 8, 'APMC Junnar'),
(80, 8, 'APMC Khed'),
(24, 8, 'APMC Manchar'),
(10, 8, 'APMC Pune'),
(81, 8, 'Junnar(Alephata)'),
(25, 8, 'Junnar(Narayangaon)'),
(26, 8, 'Junnar(Otur)'),
(27, 8, 'Khed(Chakan)'),
(28, 8, 'Pune(Khadiki)'),
(20, 8, 'Pune(Manjri)'),
(11, 8, 'Pune(Moshi)'),
(29, 8, 'Pune(Pimpri)'),
(21, 9, 'APMC Akluj'),
(82, 9, 'APMC Barshi'),
(83, 9, 'APMC Mangal Wedha'),
(84, 9, 'APMC Pandharpur'),
(12, 9, 'APMC Solapur'),
(85, 9, 'Kurdwadi(Modnimb)'),
(86, 9, 'Laxmi-Sopan Agriculture Produce Marketing Co Ltd, Barshi, Dist Solapur'),
(13, 10, 'APMC Kalyan'),
(17, 11, 'APMC Dharashiv'),
(52, 11, 'APMC Paranda'),
(30, 12, 'APMC Ratnagiri (Nachane)'),
(53, 13, 'APMC Dhule'),
(54, 13, 'APMC Sakri'),
(55, 13, 'APMC Shirpur'),
(56, 13, 'Janata Agri Market (DLS Agro Infrastructure Pvt Ltd), Dist Dhule'),
(57, 13, 'Pratap Nana Mahale Khajgi Krushi Uttpana Bazar, Samati-Dhule');

-- -----------------------------------------------------------------------------
-- Seed data for `Category` (2 records)
-- -----------------------------------------------------------------------------
INSERT INTO `Category` (`CategoryID`, `CategoryName`) VALUES
(1, 'Fruits'),
(2, 'Vegetables');

-- -----------------------------------------------------------------------------
-- Seed data for `Commodity` (8 records)
-- -----------------------------------------------------------------------------
INSERT INTO `Commodity` (`CommodityID`, `CategoryID`, `CommodityName`) VALUES
(1, 1, 'Apple'),
(2, 1, 'Banana'),
(3, 1, 'Mango'),
(4, 2, 'Carrot'),
(5, 2, 'Garlic'),
(6, 2, 'Onion'),
(7, 2, 'Potato'),
(8, 2, 'Tomato');

-- -----------------------------------------------------------------------------
-- Seed data for `Variety` (24 records)
-- -----------------------------------------------------------------------------
INSERT INTO `Variety` (`VarietyID`, `CommodityID`, `VarietyName`) VALUES
(1, 1, 'Other'),
(2, 1, 'Simla'),
(4, 2, 'Khandesh'),
(3, 2, 'Other'),
(7, 3, 'Hapus(Alphaso)'),
(6, 3, 'Other'),
(5, 3, 'Totapuri'),
(8, 4, 'Other'),
(9, 5, 'Other'),
(14, 6, '1st Sort'),
(15, 6, '2nd Sort'),
(18, 6, 'Chinchwad'),
(19, 6, 'Fursungi'),
(20, 6, 'Halva'),
(13, 6, 'Local'),
(12, 6, 'Other'),
(17, 6, 'Pole'),
(10, 6, 'Red'),
(11, 6, 'Unhali'),
(16, 6, 'White'),
(22, 7, 'Local'),
(21, 7, 'Other'),
(24, 8, 'Local'),
(23, 8, 'Other');

-- -----------------------------------------------------------------------------
-- Seed data for `System_User` (4 records)
-- -----------------------------------------------------------------------------
INSERT INTO `System_User` (`UserID`, `Name`, `PhoneNo`, `PasswordHash`, `DistrictID`, `UserType`) VALUES
(1, 'Ramesh Patil', '+919822011223', 'fd8ec1d4c3412560dddb56a3ceb9d916157d1fb94795c94d72e679bda54d9fc4', 8, 'Farmer'),
(2, 'Suresh Shinde', '+919822022334', 'a494477628e79eb71480a45eb9d35b6445f2c26c275317840dffb87157e7266d', 7, 'Farmer'),
(3, 'Vikram Joshi', '+919822033445', 'eca7111288b6ba2594c367aaf8b99aa92567e3196aadcadbb28f1aefaabf87d6', 8, 'Trader'),
(4, 'Anil Deshmukh', '+919822044556', '477b56ce75442b838a8df50493b8c2aa3f3ab197719a2705c487ecf19d3a5e0e', 1, 'Trader');

-- -----------------------------------------------------------------------------
-- Seed data for `Farmer` (2 records)
-- -----------------------------------------------------------------------------
INSERT INTO `Farmer` (`UserID`, `FarmSize_Acres`, `PrimaryCrop`) VALUES
(1, '12.50', 'Onion'),
(2, '8.00', 'Tomato');

-- -----------------------------------------------------------------------------
-- Seed data for `Trader` (2 records)
-- -----------------------------------------------------------------------------
INSERT INTO `Trader` (`UserID`, `LicenseNumber`, `CompanyName`) VALUES
(3, 'TRD-MH-PUN-001', 'Maha Agro Wholesale Traders'),
(4, 'TRD-MH-AHI-002', 'Deshmukh Mandi Supply Co');

-- -----------------------------------------------------------------------------
-- Seed data for `Price_Alerts` (3 records)
-- -----------------------------------------------------------------------------
INSERT INTO `Price_Alerts` (`AlertID`, `UserID`, `CommodityID`, `TargetPrice`, `AlertCondition`, `IsActive`, `TriggeredMessage`) VALUES
(1, 1, 6, '2500.00', 'ABOVE', 1, 'Target price reached: Onion crossed Rs. 2,500/Quintal'),
(2, 2, 8, '1800.00', 'ABOVE', 1, 'Target price reached: Tomato crossed Rs. 1,800/Quintal'),
(3, 3, 1, '8000.00', 'BELOW', 1, 'Buy alert: Apple modal price dropped below Rs. 8,000/Quintal');

-- -----------------------------------------------------------------------------
-- Sample seed data for `Daily_Prices` (First 100 of 40,307 records)
-- -----------------------------------------------------------------------------
INSERT INTO `Daily_Prices` (`PriceID`, `MarketID`, `VarietyID`, `Grade`, `RecordDate`, `MinPrice`, `MaxPrice`, `ModalPrice`, `ArrivalTonnes`) VALUES
(1, 1, 1, 'Local', '2026-10-08', '7000.00', '10000.00', '8500.00', '2.30'),
(2, 1, 1, 'Local', '2026-10-06', '7000.00', '10000.00', '8500.00', '1.70'),
(3, 1, 1, 'Local', '2026-10-04', '7000.00', '10000.00', '8500.00', '2.30'),
(4, 1, 1, 'Local', '2026-10-03', '7000.00', '9000.00', '8000.00', '1.80'),
(5, 1, 1, 'Local', '2026-10-02', '7000.00', '9000.00', '8000.00', '2.70'),
(6, 1, 1, 'Local', '2026-09-29', '8000.00', '9000.00', '8500.00', '2.20'),
(7, 1, 1, 'Local', '2026-09-26', '9000.00', '11500.00', '10250.00', '2.50'),
(8, 1, 1, 'Local', '2026-09-22', '8000.00', '11000.00', '9500.00', '2.80'),
(9, 1, 1, 'Local', '2026-09-20', '10000.00', '12800.00', '11400.00', '2.20'),
(10, 1, 1, 'Local', '2026-09-18', '2000.00', '12000.00', '7000.00', '2.50'),
(11, 1, 1, 'Local', '2026-09-12', '12000.00', '18000.00', '15000.00', '2.00'),
(12, 1, 1, 'Local', '2026-09-08', '4000.00', '16500.00', '10500.00', '1.90'),
(13, 1, 1, 'Local', '2026-09-07', '4500.00', '16500.00', '10500.00', '1.80'),
(14, 1, 1, 'Local', '2026-09-06', '4000.00', '16000.00', '10000.00', '1.60'),
(15, 1, 1, 'Local', '2026-09-05', '5000.00', '16000.00', '10500.00', '1.40'),
(16, 1, 1, 'Local', '2026-09-04', '5000.00', '16500.00', '10750.00', '1.20'),
(17, 1, 1, 'Local', '2026-09-03', '5000.00', '16000.00', '10500.00', '1.30'),
(18, 1, 1, 'Local', '2026-09-01', '5000.00', '16600.00', '10800.00', '1.30'),
(19, 1, 1, 'Local', '2026-08-30', '7500.00', '16600.00', '12050.00', '1.60'),
(20, 1, 1, 'Local', '2026-08-29', '5000.00', '16600.00', '10800.00', '1.50'),
(21, 1, 1, 'Local', '2026-08-28', '6600.00', '16600.00', '11600.00', '1.40'),
(22, 1, 1, 'Local', '2026-08-25', '8000.00', '12000.00', '10000.00', '1.10'),
(23, 1, 1, 'Local', '2026-08-21', '9000.00', '22000.00', '15500.00', '1.90'),
(24, 1, 1, 'Local', '2026-08-17', '7500.00', '25000.00', '16250.00', '0.90'),
(25, 1, 1, 'Local', '2026-08-16', '5500.00', '15500.00', '10500.00', '1.30'),
(26, 1, 1, 'Local', '2026-08-14', '5000.00', '18000.00', '11500.00', '2.80'),
(27, 1, 1, 'Local', '2026-08-13', '4200.00', '19000.00', '11600.00', '1.80'),
(28, 1, 1, 'Local', '2026-08-10', '9000.00', '18300.00', '13650.00', '0.90'),
(29, 1, 1, 'Local', '2026-08-08', '5000.00', '18000.00', '11500.00', '0.50'),
(30, 1, 1, 'Local', '2026-08-03', '16000.00', '22000.00', '19000.00', '0.20'),
(31, 1, 1, 'Local', '2026-08-02', '16000.00', '22000.00', '19000.00', '0.20'),
(32, 1, 1, 'Local', '2026-08-01', '16000.00', '22000.00', '19000.00', '0.10'),
(33, 1, 1, 'Local', '2026-07-31', '16000.00', '22000.00', '19000.00', '0.20'),
(34, 1, 1, 'Local', '2026-07-28', '15000.00', '23000.00', '19000.00', '0.30'),
(35, 1, 1, 'Local', '2026-07-26', '16000.00', '22000.00', '19000.00', '0.20'),
(36, 1, 1, 'Local', '2026-07-24', '16000.00', '21500.00', '18750.00', '0.20'),
(37, 1, 1, 'Local', '2026-07-23', '16000.00', '22000.00', '19000.00', '0.20'),
(38, 1, 1, 'Local', '2026-07-21', '18000.00', '22000.00', '20000.00', '0.20'),
(39, 1, 1, 'Local', '2026-07-19', '18000.00', '22000.00', '20000.00', '0.10'),
(40, 1, 1, 'Local', '2026-07-17', '18000.00', '22000.00', '20000.00', '0.20'),
(41, 1, 1, 'Local', '2026-07-16', '17000.00', '21000.00', '19000.00', '0.20'),
(42, 1, 1, 'Local', '2026-07-14', '16000.00', '19500.00', '17750.00', '0.20'),
(43, 1, 1, 'Local', '2026-07-09', '17000.00', '21000.00', '19000.00', '0.30'),
(44, 1, 1, 'Local', '2026-07-06', '18000.00', '23000.00', '20500.00', '0.10'),
(45, 1, 1, 'Local', '2026-07-05', '16000.00', '20000.00', '18000.00', '0.20'),
(46, 1, 1, 'Local', '2026-07-04', '13000.00', '18000.00', '15500.00', '0.30'),
(47, 1, 1, 'Local', '2026-06-27', '10000.00', '20000.00', '15000.00', '0.20'),
(48, 1, 1, 'Local', '2026-06-23', '14000.00', '21500.00', '17750.00', '0.30'),
(49, 1, 1, 'Local', '2026-06-21', '1000.00', '20000.00', '15000.00', '0.10'),
(50, 1, 1, 'Local', '2026-06-18', '13000.00', '20000.00', '16500.00', '0.20'),
(51, 1, 1, 'Local', '2026-06-16', '10000.00', '20000.00', '15000.00', '0.20'),
(52, 1, 1, 'Local', '2026-06-09', '14000.00', '19000.00', '16500.00', '0.10'),
(53, 1, 1, 'Local', '2026-05-30', '11000.00', '19000.00', '15000.00', '0.10'),
(54, 1, 1, 'Local', '2026-05-21', '15000.00', '20000.00', '17500.00', '0.40'),
(55, 1, 1, 'Local', '2026-05-19', '14000.00', '19000.00', '16500.00', '0.20'),
(56, 1, 1, 'Local', '2026-05-16', '15000.00', '18000.00', '16500.00', '0.30'),
(57, 1, 1, 'Local', '2026-05-11', '15000.00', '18000.00', '16500.00', '0.10'),
(58, 1, 1, 'Local', '2026-05-10', '16000.00', '18000.00', '17000.00', '0.20'),
(59, 1, 1, 'Local', '2026-04-27', '15000.00', '18000.00', '16500.00', '0.30'),
(60, 1, 1, 'Local', '2026-04-26', '18000.00', '22500.00', '20200.00', '0.70'),
(61, 1, 1, 'Local', '2026-04-18', '14000.00', '20000.00', '17000.00', '0.50'),
(62, 1, 1, 'Local', '2026-04-12', '12000.00', '18000.00', '15000.00', '0.20'),
(63, 1, 1, 'Local', '2026-04-09', '12000.00', '20000.00', '16000.00', '0.20'),
(64, 1, 1, 'Local', '2026-04-07', '12000.00', '23000.00', '17500.00', '0.30'),
(65, 1, 1, 'Local', '2026-04-05', '15000.00', '25000.00', '20000.00', '0.20'),
(66, 1, 1, 'Local', '2026-04-01', '12500.00', '15000.00', '13750.00', '0.30'),
(67, 1, 1, 'Local', '2026-03-20', '10000.00', '18000.00', '14000.00', '0.70'),
(68, 1, 1, 'Local', '2026-03-16', '10000.00', '20000.00', '15000.00', '0.30'),
(69, 1, 1, 'Local', '2026-03-06', '8000.00', '20000.00', '14000.00', '0.90'),
(70, 1, 1, 'Local', '2026-03-05', '10000.00', '15000.00', '12500.00', '0.60'),
(71, 1, 1, 'Local', '2026-02-20', '7000.00', '16000.00', '11500.00', '1.70'),
(72, 1, 1, 'Local', '2026-02-14', '8000.00', '16000.00', '12000.00', '1.10'),
(73, 1, 1, 'Local', '2026-02-12', '7000.00', '16000.00', '11500.00', '1.00'),
(74, 1, 1, 'Local', '2026-02-09', '10000.00', '16000.00', '13000.00', '0.60'),
(75, 1, 1, 'Local', '2026-02-08', '8000.00', '16000.00', '12000.00', '0.60'),
(76, 1, 1, 'Local', '2026-02-07', '8000.00', '16000.00', '12000.00', '0.60'),
(77, 1, 1, 'Local', '2026-01-31', '9000.00', '16000.00', '12500.00', '1.20'),
(78, 1, 1, 'Local', '2026-01-17', '7000.00', '15000.00', '11000.00', '3.70'),
(79, 1, 1, 'Local', '2026-01-13', '9000.00', '15000.00', '12000.00', '1.50'),
(80, 1, 1, 'Local', '2026-01-10', '7000.00', '15000.00', '11000.00', '8.10'),
(81, 1, 1, 'Local', '2026-01-06', '8000.00', '14000.00', '11000.00', '1.00'),
(82, 1, 1, 'Local', '2026-01-01', '7000.00', '14000.00', '10500.00', '6.10'),
(83, 1, 1, 'Local', '2025-12-29', '8000.00', '12000.00', '10000.00', '1.80'),
(84, 1, 1, 'Local', '2025-12-26', '8000.00', '11000.00', '9500.00', '0.70'),
(85, 1, 1, 'Local', '2025-12-19', '8000.00', '14000.00', '11000.00', '1.30'),
(86, 1, 1, 'Local', '2025-12-06', '4000.00', '10500.00', '7250.00', '1.80'),
(87, 1, 1, 'Local', '2025-12-04', '5000.00', '10000.00', '7500.00', '1.70'),
(88, 1, 1, 'Local', '2025-12-01', '4000.00', '10000.00', '7000.00', '1.00'),
(89, 1, 1, 'Local', '2025-11-24', '4500.00', '10000.00', '7250.00', '1.70'),
(90, 1, 1, 'Local', '2025-11-21', '4000.00', '11000.00', '7500.00', '2.00'),
(91, 1, 1, 'Local', '2025-11-18', '4000.00', '12000.00', '8000.00', '1.60'),
(92, 1, 1, 'Local', '2025-11-13', '4000.00', '12500.00', '8250.00', '1.70'),
(93, 1, 1, 'Local', '2025-11-07', '5000.00', '12000.00', '8500.00', '1.20'),
(94, 2, 1, 'Local', '2026-10-03', '3000.00', '6000.00', '4500.00', '0.60'),
(95, 2, 1, 'Local', '2026-09-28', '5500.00', '6000.00', '5750.00', '0.80'),
(96, 2, 1, 'Local', '2026-09-19', '7000.00', '7000.00', '7000.00', '0.40'),
(97, 2, 1, 'Local', '2026-09-08', '9000.00', '9000.00', '9000.00', '0.70'),
(98, 2, 1, 'Local', '2026-08-30', '7000.00', '9200.00', '8100.00', '0.40'),
(99, 2, 1, 'Local', '2026-08-20', '8000.00', '8500.00', '8250.00', '0.30'),
(100, 2, 1, 'Local', '2026-08-16', '10700.00', '10700.00', '10700.00', '0.20');

