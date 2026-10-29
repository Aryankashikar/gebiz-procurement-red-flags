-- 02_clean.sql
-- Builds the clean analysis table `awards` from `raw_awards`

USE gebiz;

DROP TABLE IF EXISTS awards;            -- so the script can be re-run

CREATE TABLE awards AS
SELECT
    tender_no,
    tender_description,
    agency,

    -- 1. Proper date: text '6/9/2021' (day/month/year) -> DATE 2021-09-06
    STR_TO_DATE(award_date, '%e/%c/%Y') AS award_dt,

    tender_detail_status,
    supplier_name,

    -- 2. Clean supplier name: uppercase, no dots or commas, single spaces
    --    so 'ABC PTE. LTD.' and 'ABC PTE LTD' count as one company
    TRIM(REGEXP_REPLACE(UPPER(REPLACE(REPLACE(supplier_name, '.', ''), ',', '')), ' +', ' ')) AS clean_supplier,

    awarded_amt,

    -- 3. $1-type awards = panel / rate contracts (real value is paid later at agreed rates)
    (awarded_amt < 100) AS is_panel_contract,

    -- 4. Exact thousands (e.g. 250,000), used for the round-amount test
    (awarded_amt >= 1000 AND MOD(awarded_amt, 1000) = 0) AS is_round_amount,

    -- 5. Spend category from keywords in the description (first match wins)
    CASE
        WHEN UPPER(tender_description) REGEXP 'CONSTRUCT|BUILDING WORKS|ERECTION|CIVIL|ADDITIONS? AND ALTERATION|A&A|REDEVELOP|UPGRAD|RENOVAT|REINSTAT|ROAD|DRAIN|TUNNEL|VIADUCT|BRIDGE|STATION|DEPOT|PILING|DEMOLI|REPAIR|REPLACEMENT OF|INSTALLATION|\\bWORKS\\b'
            THEN 'Construction & Works'
        WHEN UPPER(tender_description) REGEXP 'SOFTWARE|\\bSYSTEMS?\\b|\\bIT\\b|\\bICT\\b|APPLICATION|DIGITAL|CLOUD|NETWORK|\\bDATA\\b|LICEN[CS]E|COMPUTER|CYBER|PLATFORM|PORTAL|WEBSITE|\\bAPP\\b'
            THEN 'IT & Digital'
        WHEN UPPER(tender_description) REGEXP 'CONSULT|ADVISORY|AUDIT|STUDY|RESEARCH|LEGAL|SURVEY|TRAINING|ASSESSMENT|EVALUATION|DESIGN SERVICES|PROJECT MANAGEMENT|ARCHITECT|ENGINEERING SERVICES|COACHING|PROGRAMME|ENRICHMENT|COURSE|WORKSHOP'
            THEN 'Professional Services'
        WHEN UPPER(tender_description) REGEXP 'CLEAN|MAINTEN|SECURITY|PEST|LANDSCAP|HORTICULT|FACILIT|MANAGING AGENT|CONSERVANCY|WASTE|TERM CONTRACT'
            THEN 'Facilities & Maintenance'
        WHEN UPPER(tender_description) REGEXP 'EVENT|ORGANIS|PUBLICITY|PUBLIC RELATIONS|MEDIA|MARKETING|COMMUNICATION|CAMPAIGN|EXHIBITION|VIDEO|PRODUCTION|CREATIVE'
            THEN 'Events & Communications'
        WHEN UPPER(tender_description) REGEXP 'SUPPLY|PURCHASE|EQUIPMENT|VEHICLE|FURNITURE|DELIVERY|PROCUREMENT OF|REAGENT|CONSUMABLE|UNIFORM'
            THEN 'Goods & Equipment'
        ELSE 'Other'
    END AS spend_category

FROM raw_awards
-- 6. Remove tenders awarded to no one (supplier 'Unknown', $0): not real awards
WHERE tender_detail_status <> 'Awarded to No Suppliers';

-- 7. Add a unique ID per award (needed to join results back later)
ALTER TABLE awards ADD COLUMN award_id INT AUTO_INCREMENT PRIMARY KEY FIRST;

-- 8. Time columns used by the year-end and clustering tests
ALTER TABLE awards
    ADD COLUMN award_month TINYINT,
    ADD COLUMN fin_year SMALLINT;

SET SQL_SAFE_UPDATES = 0;               -- allows an UPDATE on the whole table

UPDATE awards
SET award_month = MONTH(award_dt),
    -- Singapore's government financial year runs April to March:
    -- Apr 2021 - Mar 2022 = FY2021
    fin_year = CASE WHEN MONTH(award_dt) >= 4 THEN YEAR(award_dt) ELSE YEAR(award_dt) - 1 END;

SET SQL_SAFE_UPDATES = 1;


-- CHECKS
SELECT COUNT(*) FROM awards;                                                    -- 17,825
SELECT COUNT(*) FROM awards WHERE award_dt IS NULL;                             -- 0
SELECT MIN(award_dt), MAX(award_dt) FROM awards;                                -- 2021-04-01 and 2026-03-31
SELECT fin_year, COUNT(*) FROM awards GROUP BY fin_year ORDER BY fin_year;      -- FY2021: 3,810 | FY2022: 3,333 | FY2023: 3,573 | FY2024: 3,422 | FY2025: 3,687
SELECT SUM(is_panel_contract) FROM awards;                                      -- 2,087
SELECT COUNT(*), ROUND(SUM(awarded_amt)/1e9, 1) FROM awards
WHERE is_panel_contract = 0;                                                    -- 15,738 and 123.8
SELECT SUM(is_round_amount) FROM awards;                                        -- 3,104
SELECT COUNT(DISTINCT supplier_name), COUNT(DISTINCT clean_supplier) FROM awards; -- about 6,150 and 6,146
SELECT spend_category, COUNT(*) FROM awards GROUP BY spend_category ORDER BY 2 DESC;



