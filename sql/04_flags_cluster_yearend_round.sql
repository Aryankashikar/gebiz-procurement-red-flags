-- 04_flags_cluster_yearend_round.sql
-- Red flags 3 (clustered awards), 4 (year-end spike), 7 (round amounts).
-- Uses real awards only (panel/rate contracts under $100 excluded).

USE gebiz;

-- ----------------------------------------------------------------
-- RED FLAG 3: CLUSTERED AWARDS (possible split purchases)
-- Question: does an agency give the same supplier separate awards within 30 days?
-- Splitting one purchase into several smaller ones can avoid stricter approval.

-- Method: LAG() looks at the previous award for the same agency-supplier pair.
-- ----------------------------------------------------------------
DROP TABLE IF EXISTS flag_cluster_awards;

CREATE TABLE flag_cluster_awards AS
SELECT *
FROM (
    SELECT
        award_id, agency, clean_supplier, tender_no, award_dt, awarded_amt,
        LAG(award_dt)  OVER (PARTITION BY agency, clean_supplier ORDER BY award_dt, award_id) AS prev_award_dt,
        LAG(tender_no) OVER (PARTITION BY agency, clean_supplier ORDER BY award_dt, award_id) AS prev_tender_no
    FROM awards
    WHERE is_panel_contract = 0
) AS x
WHERE DATEDIFF(award_dt, prev_award_dt) <= 30   -- within 30 days of the previous award
  AND tender_no <> prev_tender_no;              -- and a different tender (not parts of the same one)

-- One row per pair: how many clustered awards each pair has
DROP TABLE IF EXISTS flag_cluster;

CREATE TABLE flag_cluster AS
SELECT agency, clean_supplier,
       COUNT(*) AS num_clustered_awards,
       1        AS flag_cluster
FROM flag_cluster_awards
GROUP BY agency, clean_supplier;

-- ----------------------------------------------------------------
-- RED FLAG 4: YEAR-END SPENDING SPIKE
-- Question: does an agency award unusually many contracts in March,
-- the last month of the financial year ("use it or lose it" budget spending)?
-- Rule: March share of awards >= 2x the normal 1-in-12 (8.3%), agencies with >= 20 awards.
-- ----------------------------------------------------------------
DROP TABLE IF EXISTS flag_yearend;

CREATE TABLE flag_yearend AS
SELECT
    agency,
    COUNT(*)                       AS num_awards,
    SUM(award_month = 3)           AS march_awards,
    ROUND(AVG(award_month = 3), 3) AS march_share,
    (COUNT(*) >= 20 AND AVG(award_month = 3) >= 2 / 12) AS flag_yearend
FROM awards
WHERE is_panel_contract = 0
GROUP BY agency;

-- ----------------------------------------------------------------
-- RED FLAG 7: ROUND AMOUNTS
-- Question: does an agency award unusually many exact-thousand amounts?
-- Round numbers can mean estimates rather than real quoted prices.
-- Rule: round share >= 2x the overall rate, agencies with >= 20 awards.
-- ----------------------------------------------------------------
DROP TABLE IF EXISTS flag_round;

CREATE TABLE flag_round AS
SELECT
    agency,
    COUNT(*)                          AS num_awards,
    ROUND(AVG(is_round_amount), 3)    AS round_share,
    (COUNT(*) >= 20
     AND AVG(is_round_amount) >= 2 * (SELECT AVG(is_round_amount) FROM awards WHERE is_panel_contract = 0)
    ) AS flag_round
FROM awards
WHERE is_panel_contract = 0
GROUP BY agency;


-- CHECKS
SELECT COUNT(*) FROM flag_cluster_awards;                    -- 472 clustered awards
SELECT COUNT(*) FROM flag_cluster;                           -- 347 pairs
SELECT ROUND(AVG(award_month = 3), 3) FROM awards
WHERE is_panel_contract = 0;                                 -- 0.095 (overall March share; 1/12 = 0.083)
SELECT SUM(flag_yearend) FROM flag_yearend;                  -- 12 agencies
SELECT ROUND(AVG(is_round_amount), 3) FROM awards
WHERE is_panel_contract = 0;                                 -- 0.197 (overall round share)
SELECT SUM(flag_round) FROM flag_round;                      -- 2 agencies

-- RESULTS
SELECT * FROM flag_cluster ORDER BY num_clustered_awards DESC LIMIT 10;
-- Top: Health Sciences Authority -> Agilent Technologies (9 clustered awards)

SELECT agency, num_awards, march_share FROM flag_yearend
WHERE flag_yearend = 1 ORDER BY march_share DESC;
-- Top: Intellectual Property Office of Singapore (53% of its awards in March)

SELECT agency, num_awards, round_share FROM flag_round
WHERE flag_round = 1 ORDER BY round_share DESC;
-- Council for Estate Agencies (79% round) and National Council of Social Service (40%)


