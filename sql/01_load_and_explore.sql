-- 01_load_and_explore.sql
-- Creates the database, loads the raw GeBIZ data, checks it and explores it

CREATE DATABASE IF NOT EXISTS gebiz;
USE gebiz;

-- Raw table: an exact copy of the CSV, nothing changed yet
CREATE TABLE IF NOT EXISTS raw_awards (
  tender_no            VARCHAR(30),
  tender_description   TEXT,
  agency               VARCHAR(150),
  award_date           VARCHAR(12),     -- kept as text for now, e.g. '6/9/2021' (day/month/year)
  tender_detail_status VARCHAR(40),
  supplier_name        VARCHAR(255),
  awarded_amt          DECIMAL(15,2)
);


TRUNCATE TABLE raw_awards;             -- empty it first, so a re-run never doubles the rows

-- Note: Workbench's Import Wizard silently dropped 55 rows (quote marks in descriptions).
-- LOAD DATA loads all 18,464 rows correctly.


-- NOTE: replace the path below with the file path of gebiz_awards.csv on your computer
LOAD DATA LOCAL INFILE '/Users/aryan/Aryan (C)/GRIND/KPMG WSP/gebiz-procurement-red-flags/data/gebiz_awards.csv'
INTO TABLE raw_awards
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;


-- CHECKS
SELECT COUNT(*) FROM raw_awards;
SELECT COUNT(DISTINCT tender_no) FROM raw_awards;
SELECT tender_detail_status, COUNT(*) FROM raw_awards GROUP BY tender_detail_status;
SELECT COUNT(*) FROM raw_awards WHERE awarded_amt = 0;
SELECT ROUND(SUM(awarded_amt)/1e9, 1) FROM raw_awards;
SELECT MAX(awarded_amt) FROM raw_awards;



-- EXPLORATION
-- Purpose: to understand what "normal" looks like before testing for red flags.

-- Q1. Top 10 agencies by total amount awarded (S$ billions)
-- Why: shows where public money is concentrated; these agencies matter most in the red-flag tests.
SELECT agency,
       ROUND(SUM(awarded_amt) / 1e9, 2) AS total_sgd_bn,
       COUNT(*)                         AS num_awards
FROM raw_awards
GROUP BY agency
ORDER BY total_sgd_bn DESC
LIMIT 10;
-- Finding: LTA (~S$34.8B) and HDB (~S$33.4B) alone account for about 55% of all awarded value;
--          the top 10 agencies account for about 85%.

-- Q2. Top 10 suppliers by total amount won (S$ billions)
-- Why: shows which companies receive the most public money; 'Unknown' = tenders awarded to no one, so excluded.
SELECT supplier_name,
       ROUND(SUM(awarded_amt) / 1e9, 2) AS total_sgd_bn,
       COUNT(*)                         AS num_awards
FROM raw_awards
WHERE supplier_name <> 'Unknown'
GROUP BY supplier_name
ORDER BY total_sgd_bn DESC
LIMIT 10;
-- Finding: all top 10 suppliers by value are construction and engineering firms,
--          led by Rich Construction (~S$3.54B).

-- Q3. Number of awards and value per year
-- Why: checks whether activity is stable over time, a baseline for the year-end spike test later.
-- RIGHT(award_date, 4) takes the last 4 characters of the text date, i.e. the year.
SELECT RIGHT(award_date, 4)             AS award_year,
       COUNT(*)                         AS num_awards,
       ROUND(SUM(awarded_amt) / 1e9, 2) AS total_sgd_bn
FROM raw_awards
GROUP BY award_year
ORDER BY award_year;
-- Finding: about 3,000-3,900 awards a year; 2021 and 2026 are partial years
--          (data runs Apr 2021 to Mar 2026).

-- Q4. The 5 largest single awards
-- Why: shows the scale of the biggest contracts, so the outlier test later has context.
SELECT agency,
       supplier_name,
       ROUND(awarded_amt / 1e9, 2) AS amount_sgd_bn,
       LEFT(tender_description, 100) AS description
FROM raw_awards
ORDER BY awarded_amt DESC
LIMIT 5;
-- Finding: the 5 largest awards are all construction projects over S$1B each:
--          two hospitals (MOH), two rail projects (LTA) and an integrated development (Sport Singapore).
