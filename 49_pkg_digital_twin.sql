-- ============================================================
-- MPPMS :: 49_pkg_digital_twin.sql
-- Phase 12: PKG_DIGITAL_TWIN — Monte Carlo Simulation Engine
-- Run As: MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS Phase 12 :: Creating PKG_DIGITAL_TWIN
PROMPT ============================================================

CREATE OR REPLACE PACKAGE PKG_DIGITAL_TWIN AS

    PROCEDURE RUN_SIMULATION (
        p_scenario_name     IN  VARCHAR2,
        p_material_id       IN  NUMBER      DEFAULT NULL,
        p_shipping_delay    IN  NUMBER      DEFAULT 0,
        p_tariff_spike_pct  IN  NUMBER      DEFAULT 0,
        p_demand_surge_pct  IN  NUMBER      DEFAULT 0,
        p_trial_count       IN  NUMBER      DEFAULT 1000,
        p_scenario_id       OUT NUMBER,
        p_status            OUT VARCHAR2,
        p_message           OUT VARCHAR2
    );

    PROCEDURE RUN_FULL_CHAIN_SIMULATION (
        p_scenario_name     IN  VARCHAR2,
        p_shipping_delay    IN  NUMBER      DEFAULT 0,
        p_tariff_spike_pct  IN  NUMBER      DEFAULT 0,
        p_demand_surge_pct  IN  NUMBER      DEFAULT 0,
        p_trial_count       IN  NUMBER      DEFAULT 1000,
        p_scenario_id       OUT NUMBER,
        p_status            OUT VARCHAR2,
        p_message           OUT VARCHAR2
    );

    FUNCTION GET_SCENARIO_SUMMARY (p_scenario_id IN NUMBER) RETURN SYS_REFCURSOR;
    FUNCTION GET_HEATMAP_DATA     (p_scenario_id IN NUMBER) RETURN SYS_REFCURSOR;
    FUNCTION GET_EXPOSURE_HISTOGRAM (
        p_scenario_id  IN NUMBER,
        p_bucket_count IN NUMBER DEFAULT 20
    ) RETURN SYS_REFCURSOR;

    PROCEDURE PURGE_OLD_SCENARIOS (p_days IN NUMBER DEFAULT 30);

END PKG_DIGITAL_TWIN;
/
SHOW ERRORS PACKAGE PKG_DIGITAL_TWIN;

CREATE OR REPLACE PACKAGE BODY PKG_DIGITAL_TWIN AS

    -- Box-Muller Transform: two uniform randoms -> standard normal variate
    FUNCTION BOX_MULLER_NORMAL (p_mean IN NUMBER, p_stddev IN NUMBER) RETURN NUMBER IS
        v_u1 NUMBER;
        v_u2 NUMBER;
        v_z  NUMBER;
    BEGIN
        v_u1 := GREATEST(DBMS_RANDOM.VALUE(0,1), 0.000001);
        v_u2 := DBMS_RANDOM.VALUE(0,1);
        v_z  := SQRT(-2 * LN(v_u1)) * COS(2 * ACOS(-1) * v_u2);
        RETURN p_mean + p_stddev * v_z;
    END BOX_MULLER_NORMAL;

    FUNCTION TO_INR (p_amount IN NUMBER, p_currency IN VARCHAR2) RETURN NUMBER IS
        v_rate NUMBER := 1;
    BEGIN
        BEGIN
            SELECT EXCHANGE_RATE INTO v_rate
              FROM SOURCING_EXCHANGE_RATE
             WHERE FROM_CURRENCY = p_currency AND TO_CURRENCY = 'INR' AND IS_ACTIVE = 'Y' AND ROWNUM = 1;
        EXCEPTION WHEN OTHERS THEN v_rate := 1;
        END;
        RETURN p_amount * v_rate;
    END TO_INR;

    PROCEDURE SIMULATE_MATERIAL (
        p_scenario_id      IN  NUMBER,
        p_material_id      IN  NUMBER,
        p_shipping_delay   IN  NUMBER,
        p_tariff_spike_pct IN  NUMBER,
        p_demand_surge_pct IN  NUMBER,
        p_trial_count      IN  NUMBER,
        p_stockout_count   OUT NUMBER,
        p_avg_buffer_days  OUT NUMBER,
        p_p50_exposure     OUT NUMBER,
        p_p95_exposure     OUT NUMBER
    ) IS
        v_current_stock  NUMBER := 0;
        v_safety_stock   NUMBER := 0;
        v_lead_time      NUMBER := 7;
        v_standard_cost  NUMBER := 0;
        v_monthly_demand NUMBER := 100;
        v_material_code  VARCHAR2(30);
        v_material_name  VARCHAR2(200);
        v_eff_delay      NUMBER;
        v_eff_cost_mult  NUMBER;
        v_eff_demand     NUMBER;
        v_stock_end      NUMBER;
        v_buffer_days    NUMBER;
        v_exposure       NUMBER;
        v_stockout       VARCHAR2(1);
        v_stockout_day   NUMBER;
        v_total_buffer   NUMBER := 0;
        v_stockout_cnt   NUMBER := 0;
        v_exposures      SYS.ODCINUMBERLIST := SYS.ODCINUMBERLIST();
    BEGIN
        BEGIN
            SELECT m.SAFETY_STOCK, m.LEAD_TIME, m.STANDARD_COST, m.MATERIAL_CODE, m.MATERIAL_NAME
              INTO v_safety_stock, v_lead_time, v_standard_cost, v_material_code, v_material_name
              FROM MATERIAL_MASTER m WHERE m.MATERIAL_ID = p_material_id;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        BEGIN
            v_current_stock := PKG_INVENTORY.GET_TOTAL_AVAILABLE_STOCK(p_material_id);
        EXCEPTION WHEN OTHERS THEN v_current_stock := 0;
        END;

        v_monthly_demand := GREATEST(v_safety_stock * 2, 10);

        FOR i IN 1..p_trial_count LOOP
            v_eff_delay     := GREATEST(0, BOX_MULLER_NORMAL(p_shipping_delay, GREATEST(p_shipping_delay * 0.2, 1)));
            v_eff_cost_mult := GREATEST(1.0, BOX_MULLER_NORMAL(1 + (p_tariff_spike_pct/100), 0.05));
            v_eff_demand    := GREATEST(0,   BOX_MULLER_NORMAL(v_monthly_demand * (1 + p_demand_surge_pct/100), v_monthly_demand * 0.15));
            v_stock_end     := v_current_stock - v_eff_demand;

            IF v_stock_end < v_safety_stock THEN
                v_stockout     := 'Y';
                v_stockout_day := GREATEST(1, ROUND((v_current_stock / GREATEST(v_eff_demand/30, 0.01))));
                v_stockout_cnt := v_stockout_cnt + 1;
            ELSE
                v_stockout     := 'N';
                v_stockout_day := NULL;
            END IF;

            v_buffer_days  := GREATEST(0, (v_stock_end - v_safety_stock) / GREATEST(v_eff_demand/30, 0.01));
            v_total_buffer := v_total_buffer + v_buffer_days;
            v_exposure     := (v_eff_demand * v_standard_cost * (v_eff_cost_mult - 1))
                            + CASE WHEN v_stockout = 'Y' THEN v_eff_demand * v_standard_cost * 0.15 ELSE 0 END;

            v_exposures.EXTEND;
            v_exposures(v_exposures.COUNT) := TO_INR(v_exposure, 'INR');

            INSERT INTO SIMULATION_TRIAL (
                TRIAL_ID, SCENARIO_ID, TRIAL_NO, EFFECTIVE_DELAY_DAYS, EFFECTIVE_COST_MULT,
                EFFECTIVE_DEMAND_QTY, PROJECTED_STOCK_END, STOCKOUT_OCCURRED, STOCKOUT_DAY,
                FINANCIAL_EXPOSURE_INR, BUFFER_DAYS_REMAINING
            ) VALUES (
                SEQ_SIMULATION_TRIAL.NEXTVAL, p_scenario_id, i, v_eff_delay, v_eff_cost_mult,
                v_eff_demand, v_stock_end, v_stockout, v_stockout_day,
                TO_INR(v_exposure,'INR'), v_buffer_days
            );
        END LOOP;

        p_stockout_count  := v_stockout_cnt;
        p_avg_buffer_days := v_total_buffer / GREATEST(p_trial_count, 1);

        SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY COLUMN_VALUE),
               PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY COLUMN_VALUE)
          INTO p_p50_exposure, p_p95_exposure
          FROM TABLE(v_exposures);

        DECLARE
            v_risk_pct  NUMBER := (v_stockout_cnt / GREATEST(p_trial_count,1)) * 100;
            v_risk_lvl  VARCHAR2(10);
            v_rec       VARCHAR2(500);
        BEGIN
            IF    v_risk_pct < 20 THEN v_risk_lvl := 'GREEN'; v_rec := 'Stock level adequate. Monitor monthly.';
            ELSIF v_risk_pct < 60 THEN v_risk_lvl := 'AMBER'; v_rec := 'Consider raising safety stock by 25%. Activate Rank-2 supplier.';
            ELSE                       v_risk_lvl := 'RED';   v_rec := 'CRITICAL: Expedite emergency PO immediately. Switch to Rank-1 supplier. Consider air freight.';
            END IF;

            INSERT INTO SIMULATION_RESULT_HEATMAP (
                HEATMAP_ID, SCENARIO_ID, MATERIAL_ID, MATERIAL_CODE, MATERIAL_NAME,
                CURRENT_STOCK_QTY, ADJUSTED_DEMAND_QTY, EFFECTIVE_LEAD_DAYS,
                STOCKOUT_RISK_PCT, FINANCIAL_EXPOSURE_INR, RISK_LEVEL, RECOMMENDATION
            ) VALUES (
                SEQ_SIMULATION_HEATMAP.NEXTVAL, p_scenario_id, p_material_id, v_material_code, v_material_name,
                v_current_stock, v_monthly_demand * (1 + p_demand_surge_pct/100),
                v_lead_time + p_shipping_delay, v_risk_pct, p_p95_exposure, v_risk_lvl, v_rec
            );
        END;
    EXCEPTION WHEN OTHERS THEN NULL;
    END SIMULATE_MATERIAL;

    PROCEDURE RUN_SIMULATION (
        p_scenario_name     IN  VARCHAR2,
        p_material_id       IN  NUMBER      DEFAULT NULL,
        p_shipping_delay    IN  NUMBER      DEFAULT 0,
        p_tariff_spike_pct  IN  NUMBER      DEFAULT 0,
        p_demand_surge_pct  IN  NUMBER      DEFAULT 0,
        p_trial_count       IN  NUMBER      DEFAULT 1000,
        p_scenario_id       OUT NUMBER,
        p_status            OUT VARCHAR2,
        p_message           OUT VARCHAR2
    ) IS
        v_sc_cnt NUMBER := 0;
        v_buf    NUMBER := 0;
        v_p50    NUMBER := 0;
        v_p95    NUMBER := 0;
        v_sc_tot NUMBER := 0;
        v_risk   NUMBER;
    BEGIN
        p_status := 'SUCCESS';

        INSERT INTO SIMULATION_SCENARIO (
            SCENARIO_ID, SCENARIO_NAME, MATERIAL_ID,
            SHIPPING_DELAY_DAYS, TARIFF_SPIKE_PCT, DEMAND_SURGE_PCT,
            TRIAL_COUNT, SIMULATION_STATUS
        ) VALUES (
            SEQ_SIMULATION_SCENARIO.NEXTVAL, p_scenario_name, p_material_id,
            p_shipping_delay, p_tariff_spike_pct, p_demand_surge_pct,
            p_trial_count, 'RUNNING'
        ) RETURNING SCENARIO_ID INTO p_scenario_id;
        COMMIT;

        IF p_material_id IS NOT NULL THEN
            SIMULATE_MATERIAL(p_scenario_id, p_material_id, p_shipping_delay, p_tariff_spike_pct,
                              p_demand_surge_pct, p_trial_count, v_sc_cnt, v_buf, v_p50, v_p95);
            v_sc_tot := v_sc_cnt;
        ELSE
            FOR r IN (SELECT MATERIAL_ID FROM MATERIAL_MASTER WHERE STATUS = 'ACTIVE') LOOP
                SIMULATE_MATERIAL(p_scenario_id, r.MATERIAL_ID, p_shipping_delay, p_tariff_spike_pct,
                                  p_demand_surge_pct, p_trial_count, v_sc_cnt, v_buf, v_p50, v_p95);
                v_sc_tot := v_sc_tot + v_sc_cnt;
            END LOOP;
        END IF;

        v_risk := LEAST(100, (v_sc_tot / GREATEST(p_trial_count, 1)) * 100);

        UPDATE SIMULATION_SCENARIO
           SET SIMULATION_STATUS = 'COMPLETED',
               STOCKOUT_RISK_PCT = v_risk,
               P50_EXPOSURE_INR  = v_p50,
               P95_EXPOSURE_INR  = v_p95,
               AVG_BUFFER_DAYS   = v_buf,
               SAFE_BUFFER_DAYS  = GREATEST(0, v_buf - p_shipping_delay),
               COMPLETED_DATE    = SYSDATE
         WHERE SCENARIO_ID = p_scenario_id;
        COMMIT;

        p_message := 'Monte Carlo complete. Trials: ' || p_trial_count
                  || '. Stockout Risk: ' || ROUND(v_risk, 1) || '%. '
                  || 'P95 Exposure: INR ' || ROUND(v_p95, 0);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            UPDATE SIMULATION_SCENARIO SET SIMULATION_STATUS = 'FAILED' WHERE SCENARIO_ID = p_scenario_id;
            COMMIT;
            p_status  := 'ERROR';
            p_message := 'Simulation failed: ' || SQLERRM;
    END RUN_SIMULATION;

    PROCEDURE RUN_FULL_CHAIN_SIMULATION (
        p_scenario_name     IN  VARCHAR2,
        p_shipping_delay    IN  NUMBER      DEFAULT 0,
        p_tariff_spike_pct  IN  NUMBER      DEFAULT 0,
        p_demand_surge_pct  IN  NUMBER      DEFAULT 0,
        p_trial_count       IN  NUMBER      DEFAULT 1000,
        p_scenario_id       OUT NUMBER,
        p_status            OUT VARCHAR2,
        p_message           OUT VARCHAR2
    ) IS
    BEGIN
        RUN_SIMULATION(p_scenario_name, NULL, p_shipping_delay, p_tariff_spike_pct,
                       p_demand_surge_pct, p_trial_count, p_scenario_id, p_status, p_message);
    END RUN_FULL_CHAIN_SIMULATION;

    FUNCTION GET_SCENARIO_SUMMARY (p_scenario_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_rc SYS_REFCURSOR;
    BEGIN
        OPEN v_rc FOR
            SELECT SCENARIO_ID, SCENARIO_NAME, SHIPPING_DELAY_DAYS, TARIFF_SPIKE_PCT,
                   DEMAND_SURGE_PCT, TRIAL_COUNT, SIMULATION_STATUS,
                   ROUND(STOCKOUT_RISK_PCT,2) AS STOCKOUT_RISK_PCT,
                   ROUND(P50_EXPOSURE_INR,0)  AS P50_EXPOSURE_INR,
                   ROUND(P95_EXPOSURE_INR,0)  AS P95_EXPOSURE_INR,
                   ROUND(AVG_BUFFER_DAYS,1)   AS AVG_BUFFER_DAYS,
                   ROUND(SAFE_BUFFER_DAYS,1)  AS SAFE_BUFFER_DAYS,
                   CREATED_DATE, COMPLETED_DATE
              FROM SIMULATION_SCENARIO WHERE SCENARIO_ID = p_scenario_id;
        RETURN v_rc;
    END GET_SCENARIO_SUMMARY;

    FUNCTION GET_HEATMAP_DATA (p_scenario_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_rc SYS_REFCURSOR;
    BEGIN
        OPEN v_rc FOR
            SELECT MATERIAL_CODE, MATERIAL_NAME,
                   ROUND(CURRENT_STOCK_QTY,2)      AS CURRENT_STOCK,
                   ROUND(ADJUSTED_DEMAND_QTY,2)    AS ADJUSTED_DEMAND,
                   ROUND(EFFECTIVE_LEAD_DAYS,1)    AS EFFECTIVE_LEAD_DAYS,
                   ROUND(STOCKOUT_RISK_PCT,1)      AS STOCKOUT_RISK_PCT,
                   ROUND(FINANCIAL_EXPOSURE_INR,0) AS FINANCIAL_EXPOSURE_INR,
                   RISK_LEVEL, RECOMMENDATION
              FROM SIMULATION_RESULT_HEATMAP
             WHERE SCENARIO_ID = p_scenario_id
             ORDER BY STOCKOUT_RISK_PCT DESC;
        RETURN v_rc;
    END GET_HEATMAP_DATA;

    FUNCTION GET_EXPOSURE_HISTOGRAM (p_scenario_id IN NUMBER, p_bucket_count IN NUMBER DEFAULT 20) RETURN SYS_REFCURSOR IS
        v_rc SYS_REFCURSOR;
    BEGIN
        OPEN v_rc FOR
            SELECT
                NTILE(p_bucket_count) OVER (ORDER BY FINANCIAL_EXPOSURE_INR) AS bucket_num,
                COUNT(*) AS trial_count,
                ROUND(MIN(FINANCIAL_EXPOSURE_INR)/1000,0) AS bucket_min_k,
                ROUND(MAX(FINANCIAL_EXPOSURE_INR)/1000,0) AS bucket_max_k,
                ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct_of_total
              FROM SIMULATION_TRIAL
             WHERE SCENARIO_ID = p_scenario_id
             GROUP BY NTILE(p_bucket_count) OVER (ORDER BY FINANCIAL_EXPOSURE_INR),
                      FINANCIAL_EXPOSURE_INR
             ORDER BY bucket_num;
        RETURN v_rc;
    END GET_EXPOSURE_HISTOGRAM;

    PROCEDURE PURGE_OLD_SCENARIOS (p_days IN NUMBER DEFAULT 30) IS
    BEGIN
        DELETE FROM SIMULATION_SCENARIO
         WHERE CREATED_DATE < SYSDATE - p_days
           AND SIMULATION_STATUS IN ('COMPLETED','FAILED');
        COMMIT;
    END PURGE_OLD_SCENARIOS;

END PKG_DIGITAL_TWIN;
/
SHOW ERRORS PACKAGE BODY PKG_DIGITAL_TWIN;

PROMPT [SUCCESS] PKG_DIGITAL_TWIN ready.
