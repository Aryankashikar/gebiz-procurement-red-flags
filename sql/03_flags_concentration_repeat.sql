-- 03_flags_concentration_repeat.sql
-- Red flags 1 and 2, measured per agency-supplier pair.
-- Uses real awards only (panel/rate contracts under $100 excluded).

USE gebiz;

-- ----------------------------------------------------------------
-- RED FLAG 1: SUPPLIER CONCENTRATION
-- Question: does one supplier receive a large share of an agency's spending?
-- Rule: share >= 25% of the agency's total spend, agency spend >= S$1M,
--       and at least 2 awards (so one big one-off project doesn't count as a pattern).
-- ----------------------------------------------------------------
DROP TABLE IF EXISTS flag_concentration;

CREATE TABLE flag_concentration AS
SELECT
    p.agency,
    p.clean_supplier,
    p.num_awards,
    p.pair_total,
    t.agency_total,
    ROUND(p.pair_total / t.agency_total, 4) AS share_of_agency_spend,
    (p.pair_total / t.agency_total >= 0.25
     AND t.agency_total >= 1000000
     AND p.num_awards >= 2) AS flag_concentration
FROM (
    -- total won by each supplier from each agency
    SELECT agency, clean_supplier,
           COUNT(*)         AS num_awards,
           SUM(awarded_amt) AS pair_total
    FROM awards
    WHERE is_panel_contract = 0
    GROUP BY agency, clean_supplier
) AS p
JOIN (
    -- total spent by each agency
    SELECT agency, SUM(awarded_amt) AS agency_total
    FROM awards
    WHERE is_panel_contract = 0
    GROUP BY agency
) AS t
ON p.agency = t.agency;

-- ----------------------------------------------------------------
-- RED FLAG 2: REPEAT WINNERS
-- Question: does the same supplier keep winning from the same agency, year after year?
-- Rule: at least 5 awards AND wins in at least 4 of the 5 financial years.
-- ----------------------------------------------------------------
DROP TABLE IF EXISTS flag_repeat;

CREATE TABLE flag_repeat AS
SELECT
    agency,
    clean_supplier,
    COUNT(*)                 AS num_awards,
    COUNT(DISTINCT fin_year) AS num_years,
    MIN(award_dt)            AS first_award,
    MAX(award_dt)            AS last_award,
    (COUNT(*) >= 5 AND COUNT(DISTINCT fin_year) >= 4) AS flag_repeat
FROM awards
WHERE is_panel_contract = 0
GROUP BY agency, clean_supplier;

-- CHECKS
SELECT COUNT(*) FROM flag_concentration;                        -- 10,602 agency-supplier pairs
SELECT SUM(flag_concentration) FROM flag_concentration;         -- 18 flagged pairs
SELECT COUNT(*) FROM flag_repeat;                               -- 10,602 (same pairs)
SELECT SUM(flag_repeat) FROM flag_repeat;                       -- 175 flagged pairs

-- RESULTS
SELECT agency, clean_supplier, num_awards, share_of_agency_spend
FROM flag_concentration WHERE flag_concentration = 1
ORDER BY share_of_agency_spend DESC;
-- Top: Council for Estate Agencies -> NTUC LearningHub (2 awards, ~84% of its spend)

SELECT agency, clean_supplier, num_awards, num_years
FROM flag_repeat WHERE flag_repeat = 1
ORDER BY num_awards DESC LIMIT 10;
-- Top: Monetary Authority of Singapore -> NCS (22 awards across all 5 years)

