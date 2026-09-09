-- ============================================================
-- MPPMS :: 27a_pkg_ai_forecast_spec.sql
-- Phase A: PKG_AI_FORECAST Package Specification
-- Run As : MPPMS user on FREEPDB1
-- ============================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

CREATE OR REPLACE PACKAGE PKG_AI_FORECAST AS

    -- --------------------------------------------------------
    -- CONSTANTS
    -- LEARNING: Naming constants avoids magic numbers in code.
    -- If you need to change season length, change ONE place.
    -- --------------------------------------------------------
    C_SEASON_LEN    CONSTANT NUMBER := 12;   -- Monthly seasonality
    C_MIN_HISTORY   CONSTANT NUMBER := 13;   -- Min rows to train (>1 season)
    C_TRAIN_SPLIT   CONSTANT NUMBER := 20;   -- Use first 20 months to train
    C_VAL_SPLIT     CONSTANT NUMBER := 4;    -- Hold last 4 months for validation
    C_HORIZON       CONSTANT NUMBER := 12;   -- Forecast 12 months ahead
    C_CI_Z          CONSTANT NUMBER := 1.96; -- 95% confidence Z-score

    -- --------------------------------------------------------
    -- PUBLIC API
    -- --------------------------------------------------------

    -- Main: Train model + generate forecasts for one product
    PROCEDURE RUN_FORECAST (
        p_product_id    IN  NUMBER,
        p_months_ahead  IN  NUMBER DEFAULT 12,
        p_status        OUT VARCHAR2,
        p_message       OUT VARCHAR2
    );

    -- Batch: Run all active products (called by scheduler)
    PROCEDURE RUN_ALL_PRODUCTS (
        p_months_ahead IN NUMBER DEFAULT 12
    );

    -- After a forecast month passes, record actual vs predicted
    PROCEDURE EVALUATE_ACCURACY (
        p_product_id IN NUMBER DEFAULT NULL
    );

    -- Copy AI forecasts into existing DEMAND_FORECAST table
    -- so MRP engine picks them up automatically
    PROCEDURE SYNC_TO_DEMAND_FORECAST (
        p_product_id IN NUMBER DEFAULT NULL
    );

    -- Lookup a single predicted quantity
    FUNCTION GET_PREDICTED_QTY (
        p_product_id IN NUMBER,
        p_month      IN DATE
    ) RETURN NUMBER;

    -- Returns: EXCELLENT / GOOD / FAIR / POOR / INSUFFICIENT_DATA
    FUNCTION GET_MODEL_STATUS (
        p_product_id IN NUMBER
    ) RETURN VARCHAR2;

END PKG_AI_FORECAST;
/
SHOW ERRORS PACKAGE PKG_AI_FORECAST;
PROMPT [OK] PKG_AI_FORECAST spec compiled.
