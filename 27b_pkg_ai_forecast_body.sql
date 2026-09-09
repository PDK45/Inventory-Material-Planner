-- MPPMS :: 27b_pkg_ai_forecast_body.sql  (v2 - corrected)
-- Phase A: PKG_AI_FORECAST Package Body
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

CREATE OR REPLACE PACKAGE BODY PKG_AI_FORECAST AS

    TYPE t_arr IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

    -- --------------------------------------------------------
    -- Load demand history into array. Returns row count.
    -- --------------------------------------------------------
    FUNCTION LOAD_HISTORY(p_product_id IN NUMBER, p_y OUT t_arr) RETURN NUMBER IS
        v_idx PLS_INTEGER := 0;
    BEGIN
        p_y.DELETE;
        FOR r IN (SELECT CLEANED_QTY FROM DEMAND_HISTORY
                   WHERE PRODUCT_ID = p_product_id
                   ORDER BY DEMAND_MONTH ASC) LOOP
            v_idx := v_idx + 1;
            p_y(v_idx) := r.CLEANED_QTY;
        END LOOP;
        RETURN v_idx;
    END LOAD_HISTORY;

    -- --------------------------------------------------------
    -- Core Holt-Winters engine. Returns training MAE.
    -- L=level, Tr=trend, Ss=seasonal arrays (renamed to avoid
    -- clash with outer scope variable names)
    -- --------------------------------------------------------
    FUNCTION RUN_HW (
        p_y    IN  t_arr,
        p_n    IN  NUMBER,
        p_m    IN  NUMBER,
        p_a    IN  NUMBER,
        p_b    IN  NUMBER,
        p_g    IN  NUMBER,
        p_Lv   OUT t_arr,   -- level
        p_Tr   OUT t_arr,   -- trend
        p_Ss   OUT t_arr,   -- seasonal
        p_fit  OUT t_arr    -- fitted values
    ) RETURN NUMBER IS
        v_sum1   NUMBER := 0;
        v_avg1   NUMBER;
        v_tr_sum NUMBER := 0;
        v_sp     NUMBER;
        v_fitted NUMBER;
        v_mae    NUMBER := 0;
        v_cnt    PLS_INTEGER := 0;
    BEGIN
        p_Lv.DELETE; p_Tr.DELETE; p_Ss.DELETE; p_fit.DELETE;

        -- Init seasonal from first season
        FOR i IN 1..p_m LOOP v_sum1 := v_sum1 + p_y(i); END LOOP;
        v_avg1 := v_sum1 / p_m;
        FOR i IN 1..p_m LOOP
            p_Ss(i) := CASE WHEN v_avg1 > 0 THEN p_y(i)/v_avg1 ELSE 1 END;
        END LOOP;

        -- Init level and trend
        p_Lv(p_m) := v_avg1;
        -- Avoid accessing indices beyond p_n if p_n < 2*p_m. Fallback to simple overall slope if needed.
        IF p_n >= 2*p_m THEN
            FOR i IN 1..p_m LOOP
                v_tr_sum := v_tr_sum + (p_y(p_m+i) - p_y(i)) / p_m;
            END LOOP;
            p_Tr(p_m) := v_tr_sum / p_m;
        ELSE
            p_Tr(p_m) := (p_y(p_n) - p_y(1)) / (p_n - 1);
        END IF;

        -- Smoothing loop
        FOR t IN p_m+1..p_n LOOP
            v_sp     := CASE WHEN NVL(p_Ss(t-p_m),0)=0 THEN 1 ELSE p_Ss(t-p_m) END;
            v_fitted := (p_Lv(t-1) + p_Tr(t-1)) * v_sp;
            p_fit(t) := v_fitted;
            p_Lv(t)  := p_a*(p_y(t)/v_sp) + (1-p_a)*(p_Lv(t-1)+p_Tr(t-1));
            p_Tr(t)  := p_b*(p_Lv(t)-p_Lv(t-1)) + (1-p_b)*p_Tr(t-1);
            p_Ss(t)  := CASE WHEN p_Lv(t)=0 THEN p_Ss(t-p_m)
                             ELSE p_g*(p_y(t)/p_Lv(t)) + (1-p_g)*p_Ss(t-p_m) END;
            v_mae    := v_mae + ABS(p_y(t) - v_fitted);
            v_cnt    := v_cnt + 1;
        END LOOP;

        RETURN CASE WHEN v_cnt>0 THEN v_mae/v_cnt ELSE 999999 END;
    END RUN_HW;

    -- --------------------------------------------------------
    -- Grid search: 225 combos, train on first 20, validate on last 4
    -- --------------------------------------------------------
    PROCEDURE OPTIMIZE_PARAMS (
        p_y        IN  t_arr,
        p_n        IN  NUMBER,
        p_m        IN  NUMBER,
        p_best_a   OUT NUMBER,
        p_best_b   OUT NUMBER,
        p_best_g   OUT NUMBER,
        p_best_mae OUT NUMBER,
        p_combos   OUT NUMBER
    ) IS
        v_Lv t_arr; v_Tr t_arr; v_Ss t_arr; v_fit t_arr;
        v_a  NUMBER; v_b  NUMBER; v_g  NUMBER;
        v_dummy   NUMBER;
        v_val_mae NUMBER;
        v_s_ref   NUMBER;
        v_pred    NUMBER;
        v_n_tr    NUMBER := GREATEST(p_m, LEAST(p_n-4, C_TRAIN_SPLIT));
        v_y_tr    t_arr;
    BEGIN
        p_best_a := 0.3; p_best_b := 0.1; p_best_g := 0.2;
        p_best_mae := 999999; p_combos := 0;

        FOR i IN 1..v_n_tr LOOP v_y_tr(i) := p_y(i); END LOOP;

        FOR ia IN 1..9 LOOP
            FOR ib IN 1..5 LOOP
                FOR ig IN 1..5 LOOP
                    v_a := ia/10; v_b := ib*0.1; v_g := ig/10;
                    p_combos := p_combos + 1;
                    v_dummy := RUN_HW(v_y_tr, v_n_tr, p_m, v_a, v_b, v_g,
                                      v_Lv, v_Tr, v_Ss, v_fit);
                    v_val_mae := 0;
                    DECLARE
                        v_val_points NUMBER := p_n - v_n_tr;
                    BEGIN
                        IF v_val_points > 0 THEN
                            FOR h IN 1..v_val_points LOOP
                                v_s_ref := v_n_tr - p_m + MOD(h-1,p_m) + 1;
                                IF v_s_ref < 1      THEN v_s_ref := 1;      END IF;
                                IF v_s_ref > v_n_tr THEN v_s_ref := v_n_tr; END IF;
                                v_pred := GREATEST(0,
                                            (v_Lv(v_n_tr) + h*v_Tr(v_n_tr)) *
                                             NVL(v_Ss(v_s_ref),1));
                                v_val_mae := v_val_mae + ABS(p_y(v_n_tr+h) - v_pred) / v_val_points;
                            END LOOP;
                        ELSE
                            v_val_mae := v_dummy;
                        END IF;
                    END;
                    IF v_val_mae < p_best_mae THEN
                        p_best_mae := v_val_mae;
                        p_best_a   := v_a;
                        p_best_b   := v_b;
                        p_best_g   := v_g;
                    END IF;
                END LOOP;
            END LOOP;
        END LOOP;
    END OPTIMIZE_PARAMS;

    -- --------------------------------------------------------
    -- Calculate MAE, MAPE, RMSE, and error std-dev
    -- --------------------------------------------------------
    PROCEDURE CALC_METRICS (
        p_y    IN  t_arr, p_fit IN t_arr,
        p_n    IN  NUMBER, p_m  IN NUMBER,
        p_mae  OUT NUMBER, p_mape OUT NUMBER,
        p_rmse OUT NUMBER, p_std  OUT NUMBER
    ) IS
        TYPE t_err_arr IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
        v_errs    t_err_arr;
        v_mae     NUMBER := 0; v_mape NUMBER := 0;
        v_sse     NUMBER := 0; v_cnt  PLS_INTEGER := 0;
        v_err     NUMBER; v_mean NUMBER := 0; v_var NUMBER := 0;
    BEGIN
        FOR t IN p_m+1..p_n LOOP
            IF p_fit.EXISTS(t) AND NVL(p_y(t),0)>0 THEN
                v_err := p_y(t) - p_fit(t);
                v_cnt := v_cnt + 1;
                v_errs(v_cnt) := v_err;
                v_mae  := v_mae  + ABS(v_err);
                v_mape := v_mape + ABS(v_err)/p_y(t)*100;
                v_sse  := v_sse  + POWER(v_err,2);
                v_mean := v_mean + v_err;
            END IF;
        END LOOP;
        IF v_cnt > 0 THEN
            p_mae  := ROUND(v_mae/v_cnt,4);
            p_mape := ROUND(v_mape/v_cnt,4);
            p_rmse := ROUND(SQRT(v_sse/v_cnt),4);
            v_mean := v_mean/v_cnt;
            FOR i IN 1..v_cnt LOOP
                v_var := v_var + POWER(v_errs(i)-v_mean,2);
            END LOOP;
            p_std := ROUND(SQRT(v_var/v_cnt),4);
        ELSE
            p_mae:=0; p_mape:=0; p_rmse:=0; p_std:=0;
        END IF;
    END CALC_METRICS;

    FUNCTION GRADE_MAPE(p_mape IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF    p_mape < 10 THEN RETURN 'EXCELLENT';
        ELSIF p_mape < 20 THEN RETURN 'GOOD';
        ELSIF p_mape < 50 THEN RETURN 'FAIR';
        ELSE                   RETURN 'POOR';
        END IF;
    END GRADE_MAPE;

    -- ========================================================
    -- PUBLIC: RUN_FORECAST — full ML pipeline for one product
    -- ========================================================
    PROCEDURE RUN_FORECAST (
        p_product_id   IN  NUMBER,
        p_months_ahead IN  NUMBER DEFAULT 12,
        p_status       OUT VARCHAR2,
        p_message      OUT VARCHAR2
    ) IS
        v_y    t_arr; v_Lv t_arr; v_Tr t_arr; v_Ss t_arr; v_fit t_arr;
        v_n    NUMBER; v_m  NUMBER := C_SEASON_LEN;
        v_ba   NUMBER; v_bb NUMBER; v_bg NUMBER;
        v_bval NUMBER; v_combo NUMBER;
        v_mae  NUMBER; v_mape NUMBER; v_rmse NUMBER; v_std NUMBER;
        v_pid  NUMBER; v_conf VARCHAR2(10);
        v_t0   NUMBER; v_secs NUMBER;
        v_sref NUMBER; v_pred NUMBER; v_low NUMBER; v_high NUMBER;
        v_Lf   NUMBER; v_Bf  NUMBER;
        v_from DATE;   v_to   DATE;
    BEGIN
        p_status := 'SUCCESS';
        v_t0 := DBMS_UTILITY.GET_TIME;

        v_n := LOAD_HISTORY(p_product_id, v_y);
        IF v_n < C_MIN_HISTORY THEN
            p_status  := 'INSUFFICIENT_DATA';
            p_message := 'Need >='||C_MIN_HISTORY||' months, found '||v_n;
            RETURN;
        END IF;

        -- Optimize params
        OPTIMIZE_PARAMS(v_y,v_n,v_m, v_ba,v_bb,v_bg, v_bval,v_combo);

        -- Final full-data run
        v_mae := RUN_HW(v_y,v_n,v_m, v_ba,v_bb,v_bg, v_Lv,v_Tr,v_Ss,v_fit);

        -- Metrics
        CALC_METRICS(v_y,v_fit,v_n,v_m, v_mae,v_mape,v_rmse,v_std);

        v_conf := GRADE_MAPE(v_mape);
        v_secs := (DBMS_UTILITY.GET_TIME - v_t0)/100;
        v_Lf   := v_Lv(v_n);
        v_Bf   := v_Tr(v_n);

        -- Save params: mark old STALE, insert new
        UPDATE FORECAST_MODEL_PARAMS
           SET MODEL_STATUS = 'STALE'
         WHERE PRODUCT_ID = p_product_id AND MODEL_STATUS = 'ACTIVE';

        SELECT SEQ_PARAM_ID.NEXTVAL INTO v_pid FROM DUAL;

        SELECT MIN(DEMAND_MONTH), MAX(DEMAND_MONTH)
          INTO v_from, v_to
          FROM DEMAND_HISTORY WHERE PRODUCT_ID = p_product_id;

        INSERT INTO FORECAST_MODEL_PARAMS (
            PARAM_ID, PRODUCT_ID, ALPHA, BETA, GAMMA, SEASON_LENGTH,
            FINAL_LEVEL, FINAL_TREND,
            TRAIN_MAE, TRAIN_MAPE, TRAIN_RMSE, VAL_MAE, VAL_MAPE,
            TRAINING_MONTHS, TRAINING_FROM, TRAINING_TO,
            MODEL_STATUS, CONFIDENCE_LEVEL, TRAINED_DATE
        ) VALUES (
            v_pid, p_product_id, v_ba, v_bb, v_bg, v_m,
            v_Lf, v_Bf,
            v_mae, v_mape, v_rmse, v_bval, NULL,
            v_n, v_from, v_to,
            'ACTIVE', v_conf, SYSDATE
        );

        -- Save learned seasonal indices (12 values)
        FOR mo IN 1..v_m LOOP
            DECLARE v_si NUMBER; BEGIN
                v_si := v_n - v_m + mo;
                IF v_Ss.EXISTS(v_si) THEN
                    INSERT INTO SEASONAL_INDEX_STORE
                        (PRODUCT_ID, PARAM_ID, MONTH_NUM, SEASONAL_INDEX)
                    VALUES (p_product_id, v_pid, mo, ROUND(v_Ss(v_si),5));
                END IF;
            END;
        END LOOP;

        -- Delete existing future forecasts for the product to prevent unique constraint (UQ_AIF_PROD_MONTH) violations
        DELETE FROM AI_DEMAND_FORECAST
         WHERE PRODUCT_ID = p_product_id
           AND FORECAST_MONTH >= TRUNC(SYSDATE, 'MM');

        FOR h IN 1..p_months_ahead LOOP
            v_sref := v_n - v_m + MOD(h-1,v_m) + 1;
            IF v_sref < 1 THEN v_sref := v_sref + v_m; END IF;
            v_pred := GREATEST(0, (v_Lf + h*v_Bf) * NVL(v_Ss(v_sref),1));
            -- CI: 95% band, widens with sqrt(h)
            v_low  := GREATEST(0, v_pred - C_CI_Z * v_std * SQRT(h));
            v_high := v_pred + C_CI_Z * v_std * SQRT(h);
            INSERT INTO AI_DEMAND_FORECAST (
                PRODUCT_ID, PARAM_ID, FORECAST_MONTH,
                PREDICTED_QTY, LOWER_BOUND, UPPER_BOUND,
                HORIZON_MONTHS, PREDICTION_STD, FORECAST_STATUS
            ) VALUES (
                p_product_id, v_pid,
                ADD_MONTHS(TRUNC(SYSDATE,'MM'), h),
                ROUND(v_pred,0), ROUND(v_low,0), ROUND(v_high,0),
                h, ROUND(v_std*SQRT(h),4), 'ACTIVE'
            );
        END LOOP;

        -- Accuracy log
        INSERT INTO FORECAST_ACCURACY_LOG (
            PRODUCT_ID, PARAM_ID, RUN_DATE,
            TRAINING_MAE, TRAINING_MAPE, TRAINING_RMSE,
            VALIDATION_MAE,
            BEST_ALPHA, BEST_BETA, BEST_GAMMA,
            COMBINATIONS_TESTED, OPTIMIZATION_SEC,
            MONTHS_OF_HISTORY, FORECASTS_GENERATED,
            ACCURACY_GRADE, RUN_STATUS
        ) VALUES (
            p_product_id, v_pid, SYSDATE,
            v_mae, v_mape, v_rmse, v_bval,
            v_ba, v_bb, v_bg,
            v_combo, v_secs,
            v_n, p_months_ahead,
            v_conf, 'SUCCESS'
        );

        COMMIT;

        p_message := 'a='||v_ba||' b='||v_bb||' g='||v_bg||
                     ' MAPE='||ROUND(v_mape,2)||'% RMSE='||ROUND(v_rmse,1)||
                     ' Grade='||v_conf||' Forecasts='||p_months_ahead;
        DBMS_OUTPUT.PUT_LINE('[AI PRD-'||p_product_id||'] '||p_message);

    EXCEPTION WHEN OTHERS THEN
        ROLLBACK;
        p_status  := 'ERROR';
        p_message := SQLERRM;
        BEGIN
            INSERT INTO FORECAST_ACCURACY_LOG
                (PRODUCT_ID,RUN_DATE,RUN_STATUS,ERROR_MESSAGE)
            VALUES (p_product_id,SYSDATE,'FAILED',SUBSTR(p_message,1,500));
            COMMIT;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END RUN_FORECAST;

    -- ========================================================
    -- PUBLIC: RUN_ALL_PRODUCTS
    -- ========================================================
    PROCEDURE RUN_ALL_PRODUCTS (p_months_ahead IN NUMBER DEFAULT 12) IS
        v_status  VARCHAR2(30);
        v_msg     VARCHAR2(500);
        v_ok      NUMBER := 0;
        v_fail    NUMBER := 0;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('=== AI Forecast batch start ===');
        FOR r IN (SELECT PRODUCT_ID, PRODUCT_CODE FROM PRODUCT_MASTER
                   WHERE STATUS='ACTIVE' ORDER BY PRODUCT_CODE) LOOP
            RUN_FORECAST(r.PRODUCT_ID, p_months_ahead, v_status, v_msg);
            IF v_status = 'SUCCESS' THEN v_ok   := v_ok   + 1;
            ELSE                         v_fail := v_fail + 1;
                DBMS_OUTPUT.PUT_LINE('[SKIP] '||r.PRODUCT_CODE||': '||v_msg);
            END IF;
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('Batch done. OK='||v_ok||' Skipped='||v_fail);
    END RUN_ALL_PRODUCTS;

    -- ========================================================
    -- PUBLIC: SYNC_TO_DEMAND_FORECAST
    -- Pushes AI forecasts into existing table so MRP uses them
    -- ========================================================
    PROCEDURE SYNC_TO_DEMAND_FORECAST (p_product_id IN NUMBER DEFAULT NULL) IS
        v_cnt NUMBER;
    BEGIN
        DELETE FROM DEMAND_FORECAST
         WHERE FORECAST_TYPE = 'AI'
           AND (p_product_id IS NULL OR PRODUCT_ID = p_product_id);

        INSERT INTO DEMAND_FORECAST
            (PRODUCT_ID, FORECAST_PERIOD, FORECAST_QTY,
             FORECAST_TYPE, CREATED_BY, CREATED_DATE)
        SELECT af.PRODUCT_ID, af.FORECAST_MONTH, af.PREDICTED_QTY,
               'AI', 'PKG_AI_FORECAST', SYSDATE
          FROM AI_DEMAND_FORECAST af
         WHERE af.FORECAST_STATUS = 'ACTIVE'
           AND (p_product_id IS NULL OR af.PRODUCT_ID = p_product_id);

        v_cnt := SQL%ROWCOUNT;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('SYNC: '||v_cnt||' AI forecasts -> DEMAND_FORECAST');
    EXCEPTION WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('SYNC error: '||SQLERRM);
    END SYNC_TO_DEMAND_FORECAST;

    -- ========================================================
    -- PUBLIC: EVALUATE_ACCURACY
    -- After a month passes, compare prediction vs actual
    -- ========================================================
    PROCEDURE EVALUATE_ACCURACY (p_product_id IN NUMBER DEFAULT NULL) IS
        v_actual  NUMBER;
        v_abs_err NUMBER;
        v_pct_err NUMBER;
        v_cnt     NUMBER := 0;
    BEGIN
        FOR r IN (
            SELECT af.AI_FORECAST_ID, af.PRODUCT_ID,
                   af.FORECAST_MONTH,  af.PREDICTED_QTY
              FROM AI_DEMAND_FORECAST af
             WHERE af.FORECAST_MONTH  < TRUNC(SYSDATE,'MM')
               AND af.FORECAST_STATUS = 'ACTIVE'
               AND (p_product_id IS NULL OR af.PRODUCT_ID = p_product_id)
               AND EXISTS (SELECT 1 FROM DEMAND_HISTORY dh
                            WHERE dh.PRODUCT_ID   = af.PRODUCT_ID
                              AND dh.DEMAND_MONTH = af.FORECAST_MONTH)
        ) LOOP
            SELECT ACTUAL_QTY INTO v_actual FROM DEMAND_HISTORY
             WHERE PRODUCT_ID = r.PRODUCT_ID
               AND DEMAND_MONTH = r.FORECAST_MONTH;

            v_abs_err := ABS(r.PREDICTED_QTY - v_actual);
            v_pct_err := CASE WHEN v_actual > 0
                              THEN ROUND(v_abs_err / v_actual * 100, 2)
                              ELSE NULL END;

            UPDATE AI_DEMAND_FORECAST
               SET ACTUAL_QTY      = v_actual,
                   ABSOLUTE_ERROR  = v_abs_err,
                   PCT_ERROR       = v_pct_err,
                   FORECAST_STATUS = 'EVALUATED'
             WHERE AI_FORECAST_ID  = r.AI_FORECAST_ID;
            v_cnt := v_cnt + 1;
        END LOOP;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('EVALUATE: '||v_cnt||' forecasts evaluated.');
    END EVALUATE_ACCURACY;

    -- ========================================================
    -- PUBLIC: GET_PREDICTED_QTY
    -- ========================================================
    FUNCTION GET_PREDICTED_QTY(p_product_id IN NUMBER, p_month IN DATE)
    RETURN NUMBER IS
        v_qty NUMBER := 0;
    BEGIN
        SELECT NVL(PREDICTED_QTY,0) INTO v_qty
          FROM AI_DEMAND_FORECAST
         WHERE PRODUCT_ID     = p_product_id
           AND FORECAST_MONTH = TRUNC(p_month,'MM')
           AND FORECAST_STATUS IN ('ACTIVE','EVALUATED')
           AND ROWNUM = 1;
        RETURN v_qty;
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END GET_PREDICTED_QTY;

    -- ========================================================
    -- PUBLIC: GET_MODEL_STATUS
    -- ========================================================
    FUNCTION GET_MODEL_STATUS(p_product_id IN NUMBER) RETURN VARCHAR2 IS
        v_grade VARCHAR2(20);
        v_cnt   NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_cnt FROM DEMAND_HISTORY
         WHERE PRODUCT_ID = p_product_id;
        IF v_cnt < C_MIN_HISTORY THEN RETURN 'INSUFFICIENT_DATA'; END IF;

        BEGIN
            SELECT CONFIDENCE_LEVEL INTO v_grade
              FROM FORECAST_MODEL_PARAMS
             WHERE PRODUCT_ID = p_product_id
               AND MODEL_STATUS = 'ACTIVE'
               AND ROWNUM = 1;
            RETURN NVL(v_grade,'UNKNOWN');
        EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 'NOT_TRAINED';
        END;
    END GET_MODEL_STATUS;

END PKG_AI_FORECAST;
/
SHOW ERRORS PACKAGE BODY PKG_AI_FORECAST;
PROMPT [SUCCESS] PKG_AI_FORECAST body compiled.
