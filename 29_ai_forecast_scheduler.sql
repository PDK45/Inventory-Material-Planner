-- ============================================================
-- MPPMS :: 29_ai_forecast_scheduler.sql
-- Phase A: Automation Scheduler using DBMS_SCHEDULER
-- Run As : MPPMS user on FREEPDB1
-- ============================================================
-- LEARNING: Why do we use DBMS_SCHEDULER?
-- In professional enterprise apps, you do not expect users to manually
-- click "Run Forecast" every day. The model must automatically train
-- and update itself in the background when the database load is low
-- (usually at night).
--
-- This script creates a scheduled job that runs at 2:00 AM every night:
--   1. Evaluates past forecast accuracy (using actual data that came in)
--   2. Re-runs grid-search training for all active products
--   3. Syncs fresh point forecasts to the DEMAND_FORECAST table for MRP
-- ============================================================

SET DEFINE OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED

PROMPT === Creating Nightly AI Forecast Scheduler Job ===

DECLARE
    v_job_exists NUMBER := 0;
BEGIN
    -- Check if the job already exists, drop it if it does (to make script re-runnable)
    SELECT COUNT(*)
    INTO v_job_exists
    FROM USER_SCHEDULER_JOBS
    WHERE JOB_NAME = 'JOB_NIGHTLY_AI_FORECAST';

    IF v_job_exists > 0 THEN
        DBMS_SCHEDULER.DROP_JOB(job_name => 'JOB_NIGHTLY_AI_FORECAST', force => TRUE);
        DBMS_OUTPUT.PUT_LINE('Dropped existing job JOB_NIGHTLY_AI_FORECAST.');
    END IF;

    -- Create the new scheduler job
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'JOB_NIGHTLY_AI_FORECAST',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN ' ||
                           '  -- 1. Evaluate accuracy of previous month forecasts ' ||
                           '  PKG_AI_FORECAST.EVALUATE_ACCURACY; ' ||
                           '  -- 2. Retrain and generate new forecasts ' ||
                           '  PKG_AI_FORECAST.RUN_ALL_PRODUCTS(p_months_ahead => 12); ' ||
                           '  -- 3. Synchronize with MRP DEMAND_FORECAST table ' ||
                           '  PKG_AI_FORECAST.SYNC_TO_DEMAND_FORECAST; ' ||
                           'END;',
        start_date      => TRUNC(SYSDATE) + 2/24 + 1, -- Start at 2:00 AM tomorrow
        repeat_interval => 'FREQ=DAILY; BYHOUR=2; BYMINUTE=0; BYSECOND=0', -- Run daily at 2:00 AM
        enabled         => TRUE,
        comments        => 'Nightly AI Demand Forecasting execution pipeline (Zamil IT Global)'
    );

    DBMS_OUTPUT.PUT_LINE('Created and enabled job JOB_NIGHTLY_AI_FORECAST successfully.');
END;
/

PROMPT
PROMPT ============================================================
PROMPT  Active Scheduler Jobs Verification
PROMPT ============================================================
COL JOB_NAME FORMAT A25
COL REPEAT_INTERVAL FORMAT A40
COL STATE FORMAT A10
COL LAST_START_DATE FORMAT A30

SELECT JOB_NAME,
       STATE,
       REPEAT_INTERVAL,
       LAST_START_DATE,
       NEXT_RUN_DATE
FROM USER_SCHEDULER_JOBS
WHERE JOB_NAME = 'JOB_NIGHTLY_AI_FORECAST';
