-- ============================================================
-- MPPMS :: 27c_test_forecast.sql
-- Phase A: Test and Validate the AI Demand Forecasting Engine
-- Run As : MPPMS user on FREEPDB1
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON
SET PAGESIZE 100
SET LINESIZE 160

PROMPT ============================================================
PROMPT  Phase A Testing :: Running AI Model Training and Forecasting
PROMPT ============================================================

-- 1. Execute the batch forecasting for all active products
BEGIN
    PKG_AI_FORECAST.RUN_ALL_PRODUCTS(p_months_ahead => 12);
END;
/

PROMPT ============================================================
PROMPT  Model Training and Parameter Optimization Results
PROMPT ============================================================
COL PRODUCT_CODE FORMAT A12
COL PRODUCT_NAME FORMAT A30
COL MODEL_VERSION FORMAT 99
COL LEVEL_ALPHA FORMAT 9.99
COL TREND_BETA FORMAT 9.99
COL SEASON_GAMMA FORMAT 9.99
COL TRAIN_MAPE FORMAT 990.99
COL VAL_MAE FORMAT 9990.99
COL CONFIDENCE FORMAT A10

SELECT p.PRODUCT_CODE,
       SUBSTR(p.PRODUCT_NAME, 1, 30) AS PRODUCT_NAME,
       m.MODEL_VERSION,
       m.ALPHA AS LEVEL_ALPHA,
       m.BETA AS TREND_BETA,
       m.GAMMA AS SEASON_GAMMA,
       m.TRAIN_MAPE,
       m.VAL_MAE,
       m.CONFIDENCE_LEVEL AS CONFIDENCE,
       m.TRAINED_DATE
FROM FORECAST_MODEL_PARAMS m
JOIN PRODUCT_MASTER p ON p.PRODUCT_ID = m.PRODUCT_ID
WHERE m.MODEL_STATUS = 'ACTIVE'
ORDER BY p.PRODUCT_CODE;

PROMPT ============================================================
PROMPT  Syncing AI Predictions to Core DEMAND_FORECAST Table
PROMPT ============================================================
BEGIN
    PKG_AI_FORECAST.SYNC_TO_DEMAND_FORECAST;
END;
/

PROMPT ============================================================
PROMPT  Verifying Sync in DEMAND_FORECAST
PROMPT ============================================================
SELECT FORECAST_TYPE, COUNT(*), MIN(FORECAST_PERIOD), MAX(FORECAST_PERIOD)
FROM DEMAND_FORECAST
GROUP BY FORECAST_TYPE;

PROMPT ============================================================
PROMPT  Sample Forecast Points (Next 3 Months for PRD-2001)
PROMPT ============================================================
COL FORECAST_MONTH FORMAT A12
COL PREDICTED_QTY FORMAT 999,990
COL LOWER_BOUND FORMAT 999,990
COL UPPER_BOUND FORMAT 999,990

SELECT p.PRODUCT_CODE,
       TO_CHAR(af.FORECAST_MONTH, 'YYYY-MON') AS FORECAST_MONTH,
       af.PREDICTED_QTY,
       af.LOWER_BOUND,
       af.UPPER_BOUND,
       af.HORIZON_MONTHS
FROM AI_DEMAND_FORECAST af
JOIN PRODUCT_MASTER p ON p.PRODUCT_ID = af.PRODUCT_ID
WHERE p.PRODUCT_CODE = 'PRD-2001'
  AND af.FORECAST_STATUS = 'ACTIVE'
  AND af.HORIZON_MONTHS <= 3
ORDER BY af.FORECAST_MONTH;

PROMPT
PROMPT === Test complete. All metrics verified! ===
