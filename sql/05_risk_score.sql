-- 05_risk_score.sql
-- Combines all 7 red flags into one risk score per agency-supplier pair.
-- Pair-level flags (concentration, clustering, outliers) = 2 points; repeat winner = 1;
-- agency-level flags (year-end, round amounts, Benford) = 1 each. Maximum = 10.

USE gebiz;

-- 1: one row per pair that has an unusually large award (from the Python results)
DROP TABLE IF EXISTS flag_outlier;

CREATE TABLE flag_outlier AS
SELECT agency, clean_supplier,
       COUNT(*) AS num_outlier_awards,
       1        AS flag_outlier
FROM outlier_awards
GROUP BY agency, clean_supplier;


-- 2: put every flag for every pair side by side in one table
-- LEFT JOIN keeps all 10,602 pairs, even when a pair has no match in a flag table;
DROP TABLE IF EXISTS pair_risk;

CREATE TABLE pair_risk AS
SELECT
    r.agency,
    r.clean_supplier,
    r.num_awards,
    r.num_years,
    c.pair_total,
    c.share_of_agency_spend,
    c.flag_concentration,                          -- flag 1 (pair)
    r.flag_repeat,                                 -- flag 2 (pair)
    IFNULL(cl.flag_cluster, 0)       AS flag_cluster,      -- flag 3 (pair)
    IFNULL(o.flag_outlier, 0)        AS flag_outlier,      -- flag 5 (pair)
    ye.flag_yearend,                               -- flag 4 (agency)
    rd.flag_round,                                 -- flag 7 (agency)
    IFNULL(b.flag_benford, 0)        AS flag_benford       -- flag 6 (agency)
FROM flag_repeat r
JOIN      flag_concentration c ON c.agency = r.agency AND c.clean_supplier = r.clean_supplier
LEFT JOIN flag_cluster      cl ON cl.agency = r.agency AND cl.clean_supplier = r.clean_supplier
LEFT JOIN flag_outlier       o ON o.agency = r.agency AND o.clean_supplier = r.clean_supplier
JOIN      flag_yearend      ye ON ye.agency = r.agency
JOIN      flag_round        rd ON rd.agency = r.agency
LEFT JOIN benford_agency     b ON b.agency = r.agency;


-- 3: add up the points
ALTER TABLE pair_risk ADD COLUMN risk_score INT;

SET SQL_SAFE_UPDATES = 0;

UPDATE pair_risk
SET risk_score = 2 * flag_concentration
               + 2 * flag_cluster
               + 2 * flag_outlier
               + 1 * flag_repeat
               + 1 * flag_yearend
               + 1 * flag_round
               + 1 * flag_benford;

SET SQL_SAFE_UPDATES = 1;


-- 4: the review list, highest score first (if ties then biggest money first)
SELECT agency, clean_supplier, num_awards,
       ROUND(pair_total / 1e6, 1) AS total_sgd_m,
       risk_score,
       flag_concentration, flag_cluster, flag_outlier, flag_repeat,
       flag_yearend, flag_round, flag_benford
FROM pair_risk
ORDER BY risk_score DESC, pair_total DESC
LIMIT 20;


-- CHECKS
SELECT COUNT(*) FROM pair_risk;                                     -- 10,602 pairs
SELECT risk_score, COUNT(*) FROM pair_risk
GROUP BY risk_score ORDER BY risk_score;                            -- 0: 7,362 · 1: 2,842 · 2: 246 · 3: 128 · 4: 22 · 5: 2
SELECT COUNT(*) FROM pair_risk WHERE risk_score >= 4;               -- 24 pairs for priority review



-- Top 20 pairs for review (highest score first; ties: biggest money first)
SELECT agency, clean_supplier, num_awards,
       ROUND(pair_total / 1e6, 1) AS total_sgd_m, risk_score,
       flag_concentration, flag_cluster, flag_outlier, flag_repeat,
       flag_yearend, flag_round, flag_benford
FROM pair_risk
ORDER BY risk_score DESC, pair_total DESC
LIMIT 20;


-- What did the top pairs actually buy?
SELECT a.agency, a.clean_supplier, a.award_dt,
       ROUND(a.awarded_amt / 1e6, 2) AS amount_sgd_m,
       LEFT(a.tender_description, 90) AS description
FROM awards AS a
JOIN pair_risk AS p
  ON p.agency = a.agency AND p.clean_supplier = a.clean_supplier
WHERE p.risk_score >= 4 AND a.is_panel_contract = 0
ORDER BY p.risk_score DESC, p.pair_total DESC, a.award_dt;



-- FINDINGS (risk score)
-- 10,602 agency-supplier pairs scored; 7,362 (69%) have no flags.
-- 24 pairs score 4 or more and form the priority review list.
-- Top: A*STAR -> Hewlett-Packard (clustered awards, an outlier award, Benford deviation)
--      and Council for Estate Agencies -> NTUC LearningHub (84% of agency spend, round amounts, outlier).
-- Many top pairs are at A*STAR because its agency-level Benford flag lifts all its suppliers;
-- its pair-level flags are mostly repeat/clustered purchases of lab and IT equipment (plausible for a research agency).

