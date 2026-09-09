-- ============================================================
-- MPPMS :: 28_ai_forecast_views.sql
-- Phase A: Database Views for APEX Dashboard Reports
-- Run As : MPPMS user on FREEPDB1
-- ============================================================
-- LEARNING: Why do we use views for APEX?
-- APEX components (charts, interactive grids, card list) should
-- query clean, simple views rather than complex JOIN queries. This
-- encapsulates the SQL logic in the database schema, keeping the
-- APEX page definition lightweight and highly performant.
-- ============================================================

SET DEFINE OFF
SET FEEDBACK ON

PROMPT === Creating views for APEX Dashboard ===

-- ============================================================
-- VIEW 1: VW_AI_FORECAST_VS_ACTUAL
-- Purpose : Main source for the APEX forecast chart.
--           Combines actual demand history (past) and AI point
--           forecast with confidence bands (future) in a single
--           continuous timeline.
-- ============================================================
CREATE OR REPLACE FORCE VIEW VW_AI_FORECAST_VS_ACTUAL AS
SELECT
    p.PRODUCT_ID,
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    dh.DEMAND_MONTH AS CALENDAR_DATE,
    dh.ACTUAL_QTY AS ACTUAL_QTY,
    dh.CLEANED_QTY AS CLEANED_QTY,
    NULL AS PREDICTED_QTY,
    NULL AS LOWER_BOUND,
    NULL AS UPPER_BOUND,
    'ACTUAL' AS RECORD_TYPE
FROM DEMAND_HISTORY dh
JOIN PRODUCT_MASTER p ON p.PRODUCT_ID = dh.PRODUCT_ID
UNION ALL
SELECT
    p.PRODUCT_ID,
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    af.FORECAST_MONTH AS CALENDAR_DATE,
    NULL AS ACTUAL_QTY,
    NULL AS CLEANED_QTY,
    af.PREDICTED_QTY AS PREDICTED_QTY,
    af.LOWER_BOUND AS LOWER_BOUND,
    af.UPPER_BOUND AS UPPER_BOUND,
    'FORECAST' AS RECORD_TYPE
FROM AI_DEMAND_FORECAST af
JOIN PRODUCT_MASTER p ON p.PRODUCT_ID = af.PRODUCT_ID
WHERE af.FORECAST_STATUS = 'ACTIVE';

COMMENT ON TABLE VW_AI_FORECAST_VS_ACTUAL IS 'Combined historical actuals and future AI forecasts (with 95% confidence bands) for timeline charts';

PROMPT [OK] View VW_AI_FORECAST_VS_ACTUAL created.

-- ============================================================
-- VIEW 2: VW_FORECAST_ACCURACY_KPI
-- Purpose : Source for KPI cards and dashboard summary lists.
--           Exposes accuracy scores of the currently active model
--           for each product.
-- ============================================================
CREATE OR REPLACE FORCE VIEW VW_FORECAST_ACCURACY_KPI AS
SELECT
    p.PRODUCT_ID,
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    mp.PARAM_ID,
    mp.ALPHA AS LEVEL_ALPHA,
    mp.BETA AS TREND_BETA,
    mp.GAMMA AS SEASON_GAMMA,
    mp.TRAIN_MAE,
    mp.TRAIN_MAPE,
    mp.TRAIN_RMSE,
    mp.VAL_MAE,
    mp.CONFIDENCE_LEVEL,
    mp.TRAINING_MONTHS,
    mp.TRAINED_DATE,
    -- Custom display formatting for APEX cards
    CASE mp.CONFIDENCE_LEVEL
        WHEN 'EXCELLENT' THEN 'u-color-1' -- APEX CSS classes for green
        WHEN 'GOOD'      THEN 'u-color-2' -- Blue
        WHEN 'FAIR'      THEN 'u-color-3' -- Orange
        ELSE                  'u-color-4' -- Red
    END AS METRIC_CSS_CLASS,
    ROUND(mp.TRAIN_MAPE, 1) || '%' AS MAPE_DISPLAY,
    'MAE: ' || ROUND(mp.TRAIN_MAE, 1) || ' / RMSE: ' || ROUND(mp.TRAIN_RMSE, 1) AS ERROR_DETAILS
FROM FORECAST_MODEL_PARAMS mp
JOIN PRODUCT_MASTER p ON p.PRODUCT_ID = mp.PRODUCT_ID
WHERE mp.MODEL_STATUS = 'ACTIVE';

COMMENT ON TABLE VW_FORECAST_ACCURACY_KPI IS 'Trained model KPI metrics for APEX summary pages and list view cards';

PROMPT [OK] View VW_FORECAST_ACCURACY_KPI created.

-- ============================================================
-- VIEW 3: VW_MODEL_HEALTH
-- Purpose : Detailed audits of model parameters, run times,
--           drift indicators, and error histories.
-- ============================================================
CREATE OR REPLACE FORCE VIEW VW_MODEL_HEALTH AS
SELECT
    al.LOG_ID,
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    al.RUN_DATE,
    al.BEST_ALPHA,
    al.BEST_BETA,
    al.BEST_GAMMA,
    al.TRAINING_MAE,
    al.TRAINING_MAPE,
    al.TRAINING_RMSE,
    al.VALIDATION_MAE,
    al.COMBINATIONS_TESTED AS GRID_ITERATIONS,
    al.OPTIMIZATION_SEC AS EXECUTION_SECONDS,
    al.ACCURACY_GRADE AS MODEL_GRADE,
    al.RUN_STATUS,
    al.ERROR_MESSAGE
FROM FORECAST_ACCURACY_LOG al
JOIN PRODUCT_MASTER p ON p.PRODUCT_ID = al.PRODUCT_ID
ORDER BY al.RUN_DATE DESC;

COMMENT ON TABLE VW_MODEL_HEALTH IS 'MLOps audit log for training execution history, execution times, and parameters tuning status';

PROMPT [OK] View VW_MODEL_HEALTH created.

-- ============================================================
-- VIEW 4: VW_FORECAST_ACCURACY_DRIFT
-- Purpose : Tracking the accuracy of past forecasts as new months
--           happen. Checks if the forecast error is widening.
-- ============================================================
CREATE OR REPLACE FORCE VIEW VW_FORECAST_ACCURACY_DRIFT AS
SELECT
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    af.FORECAST_MONTH,
    af.PREDICTED_QTY,
    af.ACTUAL_QTY,
    af.ABSOLUTE_ERROR,
    af.PCT_ERROR AS ERROR_PCT,
    af.HORIZON_MONTHS
FROM AI_DEMAND_FORECAST af
JOIN PRODUCT_MASTER p ON p.PRODUCT_ID = af.PRODUCT_ID
WHERE af.FORECAST_STATUS = 'EVALUATED'
ORDER BY af.FORECAST_MONTH DESC, p.PRODUCT_CODE;

COMMENT ON TABLE VW_FORECAST_ACCURACY_DRIFT IS 'Evaluation details of historical forecast errors for drift analysis';

PROMPT [OK] View VW_FORECAST_ACCURACY_DRIFT created.

-- ============================================================
-- VERIFICATION
-- ============================================================
PROMPT
PROMPT ============================================================
PROMPT  Views successfully compiled!
PROMPT ============================================================
SELECT VIEW_NAME FROM USER_VIEWS
WHERE VIEW_NAME IN (
    'VW_AI_FORECAST_VS_ACTUAL',
    'VW_FORECAST_ACCURACY_KPI',
    'VW_MODEL_HEALTH',
    'VW_FORECAST_ACCURACY_DRIFT'
)
ORDER BY VIEW_NAME;
