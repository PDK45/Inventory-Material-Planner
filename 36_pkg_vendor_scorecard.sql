-- ============================================================
-- MPPMS :: 36_pkg_vendor_scorecard.sql (FIXED SCHEMA)
-- Purpose : Vendor Scorecard Calculation Engine
-- Run As  : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

CREATE OR REPLACE PACKAGE PKG_VENDOR_SCORECARD AS
    PROCEDURE CALCULATE_SCORE(
        p_supplier_id IN NUMBER,
        p_month       IN NUMBER,
        p_year        IN NUMBER
    );
    PROCEDURE CALCULATE_ALL_SCORES(
        p_month IN NUMBER DEFAULT TO_NUMBER(TO_CHAR(SYSDATE,'MM')),
        p_year  IN NUMBER DEFAULT TO_NUMBER(TO_CHAR(SYSDATE,'YYYY'))
    );
    FUNCTION CONVERT_CURRENCY(
        p_amount        IN NUMBER,
        p_from_currency IN VARCHAR2,
        p_to_currency   IN VARCHAR2,
        p_rate_date     IN DATE DEFAULT TRUNC(SYSDATE)
    ) RETURN NUMBER;
    FUNCTION GET_SCORECARD_JSON(p_supplier_id IN NUMBER) RETURN CLOB;
    FUNCTION GET_TOP_SUPPLIERS(p_limit IN NUMBER DEFAULT 10) RETURN SYS_REFCURSOR;
    FUNCTION GET_RISK_SUPPLIERS(p_threshold IN NUMBER DEFAULT 60) RETURN SYS_REFCURSOR;
    FUNCTION GET_ALL_SCORECARDS RETURN SYS_REFCURSOR;
END PKG_VENDOR_SCORECARD;
/

CREATE OR REPLACE PACKAGE BODY PKG_VENDOR_SCORECARD AS

    FUNCTION CONVERT_CURRENCY(
        p_amount        IN NUMBER,
        p_from_currency IN VARCHAR2,
        p_to_currency   IN VARCHAR2,
        p_rate_date     IN DATE DEFAULT TRUNC(SYSDATE)
    ) RETURN NUMBER IS
        v_rate   NUMBER := 1;
    BEGIN
        IF p_from_currency = p_to_currency THEN
            RETURN p_amount;
        END IF;
        BEGIN
            SELECT RATE INTO v_rate
            FROM EXCHANGE_RATE
            WHERE FROM_CURRENCY = p_from_currency
              AND TO_CURRENCY   = p_to_currency
              AND RATE_DATE = (
                  SELECT MAX(RATE_DATE) FROM EXCHANGE_RATE
                  WHERE FROM_CURRENCY = p_from_currency
                    AND TO_CURRENCY   = p_to_currency
                    AND RATE_DATE    <= p_rate_date
              );
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                BEGIN
                    SELECT 1/RATE INTO v_rate
                    FROM EXCHANGE_RATE
                    WHERE FROM_CURRENCY = p_to_currency
                      AND TO_CURRENCY   = p_from_currency
                      AND RATE_DATE = (
                          SELECT MAX(RATE_DATE) FROM EXCHANGE_RATE
                          WHERE FROM_CURRENCY = p_to_currency
                            AND TO_CURRENCY   = p_from_currency
                            AND RATE_DATE    <= p_rate_date
                      );
                EXCEPTION WHEN OTHERS THEN v_rate := 1;
                END;
        END;
        RETURN ROUND(p_amount * v_rate, 2);
    END CONVERT_CURRENCY;

    PROCEDURE CALCULATE_SCORE(
        p_supplier_id IN NUMBER,
        p_month       IN NUMBER,
        p_year        IN NUMBER
    ) IS
        v_period_start   DATE := TO_DATE('01-' || LPAD(p_month,2,'0') || '-' || p_year, 'DD-MM-YYYY');
        v_period_end     DATE := LAST_DAY(v_period_start);

        v_total_lines    NUMBER := 0;
        v_on_time        NUMBER := 0;
        v_late           NUMBER := 0;
        v_avg_days_late  NUMBER := 0;
        v_delivery_score NUMBER := 0;

        v_lots_recv      NUMBER := 0;
        v_lots_accept    NUMBER := 0;
        v_lots_reject    NUMBER := 0;
        v_reject_rate    NUMBER := 0;
        v_quality_score  NUMBER := 0;

        v_po_value       NUMBER := 0;
        v_inv_value      NUMBER := 0;
        v_price_var_pct  NUMBER := 0;
        v_price_score    NUMBER := 0;

        v_overall_score  NUMBER := 0;
        v_rating         VARCHAR2(1);
    BEGIN
        SELECT COUNT(*),
               SUM(CASE WHEN DELIVERY_STATUS = 'ON_TIME' THEN 1 ELSE 0 END),
               SUM(CASE WHEN DELIVERY_STATUS = 'LATE'    THEN 1 ELSE 0 END),
               NVL(AVG(CASE WHEN DAYS_LATE > 0 THEN DAYS_LATE END), 0)
        INTO v_total_lines, v_on_time, v_late, v_avg_days_late
        FROM DELIVERY_EVENT
        WHERE SUPPLIER_ID = p_supplier_id
          AND CREATED_DATE BETWEEN v_period_start AND v_period_end;

        IF v_total_lines > 0 THEN
            v_delivery_score := ROUND((v_on_time / v_total_lines) * 40, 2);
        ELSE
            v_delivery_score := 30;
        END IF;

        SELECT COUNT(*),
               SUM(CASE WHEN OVERALL_RESULT = 'PASS' THEN 1 ELSE 0 END),
               SUM(CASE WHEN OVERALL_RESULT = 'FAIL' THEN 1 ELSE 0 END)
        INTO v_lots_recv, v_lots_accept, v_lots_reject
        FROM QC_INSPECTION
        WHERE SUPPLIER_ID = p_supplier_id
          AND INSPECTION_STATUS = 'COMPLETED'
          AND COMPLETED_DATE BETWEEN v_period_start AND v_period_end;

        IF v_lots_recv > 0 THEN
            v_reject_rate   := ROUND((v_lots_reject / v_lots_recv) * 100, 3);
            v_quality_score := ROUND((1 - (v_lots_reject / v_lots_recv)) * 35, 2);
        ELSE
            v_quality_score := 26;
        END IF;

        SELECT NVL(SUM(TOTAL_AMOUNT_INR), 0)
        INTO v_inv_value
        FROM SUPPLIER_INVOICE
        WHERE SUPPLIER_ID = p_supplier_id
          AND INVOICE_DATE BETWEEN v_period_start AND v_period_end
          AND STATUS NOT IN ('REJECTED','CANCELLED');

        SELECT NVL(SUM(pl.UNIT_PRICE * pl.ORDERED_QTY), 0)
        INTO v_po_value
        FROM PURCHASE_ORDER po
        JOIN PURCHASE_ORDER_ITEMS pl ON po.PO_ID = pl.PO_ID
        WHERE po.SUPPLIER_ID = p_supplier_id
          AND po.ORDER_DATE BETWEEN v_period_start AND v_period_end;

        IF v_po_value > 0 AND v_inv_value > 0 THEN
            v_price_var_pct := ROUND(ABS((v_inv_value - v_po_value) / v_po_value) * 100, 3);
            v_price_score   := GREATEST(0, ROUND(25 - (v_price_var_pct * 5), 2));
        ELSE
            v_price_score := 20;
        END IF;

        v_overall_score := v_delivery_score + v_quality_score + v_price_score;
        v_rating := CASE
            WHEN v_overall_score >= 85 THEN 'A'
            WHEN v_overall_score >= 70 THEN 'B'
            WHEN v_overall_score >= 55 THEN 'C'
            ELSE 'D'
        END;

        MERGE INTO SUPPLIER_SCORECARD sc
        USING (SELECT p_supplier_id sid, p_month mon, p_year yr FROM DUAL) src
        ON (sc.SUPPLIER_ID = src.sid AND sc.PERIOD_MONTH = src.mon AND sc.PERIOD_YEAR = src.yr)
        WHEN MATCHED THEN UPDATE SET
            TOTAL_PO_LINES       = v_total_lines,
            ON_TIME_LINES        = v_on_time,
            LATE_LINES           = v_late,
            AVG_DAYS_LATE        = v_avg_days_late,
            DELIVERY_SCORE       = v_delivery_score,
            TOTAL_LOTS_RECEIVED  = v_lots_recv,
            LOTS_ACCEPTED        = v_lots_accept,
            LOTS_REJECTED        = v_lots_reject,
            REJECTION_RATE_PCT   = v_reject_rate,
            QUALITY_SCORE        = v_quality_score,
            TOTAL_PO_VALUE       = v_po_value,
            TOTAL_INVOICE_VALUE  = v_inv_value,
            PRICE_VARIANCE_PCT   = v_price_var_pct,
            PRICE_SCORE          = v_price_score,
            OVERALL_SCORE        = v_overall_score,
            RATING               = v_rating,
            CALCULATED_DATE      = SYSDATE
        WHEN NOT MATCHED THEN INSERT (
            SUPPLIER_ID, PERIOD_MONTH, PERIOD_YEAR,
            TOTAL_PO_LINES, ON_TIME_LINES, LATE_LINES, AVG_DAYS_LATE, DELIVERY_SCORE,
            TOTAL_LOTS_RECEIVED, LOTS_ACCEPTED, LOTS_REJECTED, REJECTION_RATE_PCT, QUALITY_SCORE,
            TOTAL_PO_VALUE, TOTAL_INVOICE_VALUE, PRICE_VARIANCE_PCT, PRICE_SCORE,
            OVERALL_SCORE, RATING
        ) VALUES (
            p_supplier_id, p_month, p_year,
            v_total_lines, v_on_time, v_late, v_avg_days_late, v_delivery_score,
            v_lots_recv, v_lots_accept, v_lots_reject, v_reject_rate, v_quality_score,
            v_po_value, v_inv_value, v_price_var_pct, v_price_score,
            v_overall_score, v_rating
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('ERROR calculating scorecard for supplier ' || p_supplier_id || ': ' || SQLERRM);
    END CALCULATE_SCORE;

    PROCEDURE CALCULATE_ALL_SCORES(
        p_month IN NUMBER DEFAULT TO_NUMBER(TO_CHAR(SYSDATE,'MM')),
        p_year  IN NUMBER DEFAULT TO_NUMBER(TO_CHAR(SYSDATE,'YYYY'))
    ) IS
    BEGIN
        FOR s IN (SELECT SUPPLIER_ID FROM SUPPLIER_MASTER WHERE STATUS = 'ACTIVE' OR STATUS = 'APPROVED' OR ROWNUM <= 100) LOOP
            CALCULATE_SCORE(s.SUPPLIER_ID, p_month, p_year);
        END LOOP;
    END CALCULATE_ALL_SCORES;

    FUNCTION GET_SCORECARD_JSON(p_supplier_id IN NUMBER) RETURN CLOB IS
        v_json CLOB := '[]';
    BEGIN
        SELECT JSON_ARRAYAGG(
            JSON_OBJECT(
                'period'         VALUE TO_CHAR(PERIOD_YEAR) || '-' || LPAD(PERIOD_MONTH,2,'0'),
                'overall_score'  VALUE OVERALL_SCORE,
                'rating'         VALUE RATING,
                'delivery_score' VALUE DELIVERY_SCORE,
                'quality_score'  VALUE QUALITY_SCORE,
                'price_score'    VALUE PRICE_SCORE,
                'rejection_rate' VALUE REJECTION_RATE_PCT
            ) ORDER BY PERIOD_YEAR, PERIOD_MONTH
        )
        INTO v_json
        FROM SUPPLIER_SCORECARD
        WHERE SUPPLIER_ID = p_supplier_id;
        RETURN NVL(v_json, '[]');
    EXCEPTION WHEN OTHERS THEN RETURN '[]';
    END GET_SCORECARD_JSON;

    FUNCTION GET_TOP_SUPPLIERS(p_limit IN NUMBER DEFAULT 10) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
        v_month NUMBER := TO_NUMBER(TO_CHAR(SYSDATE,'MM'));
        v_year  NUMBER := TO_NUMBER(TO_CHAR(SYSDATE,'YYYY'));
    BEGIN
        OPEN v_cur FOR
            SELECT s.SUPPLIER_ID, s.SUPPLIER_NAME, s.SUPPLIER_CODE,
                   sc.OVERALL_SCORE, sc.RATING,
                   sc.DELIVERY_SCORE, sc.QUALITY_SCORE, sc.PRICE_SCORE,
                   sc.REJECTION_RATE_PCT, sc.ON_TIME_LINES, sc.TOTAL_PO_LINES
            FROM SUPPLIER_SCORECARD sc
            JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = sc.SUPPLIER_ID
            WHERE sc.PERIOD_MONTH = v_month AND sc.PERIOD_YEAR = v_year
            ORDER BY sc.OVERALL_SCORE DESC
            FETCH FIRST p_limit ROWS ONLY;
        RETURN v_cur;
    END GET_TOP_SUPPLIERS;

    FUNCTION GET_RISK_SUPPLIERS(p_threshold IN NUMBER DEFAULT 60) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT s.SUPPLIER_ID, s.SUPPLIER_NAME, s.SUPPLIER_CODE,
                   sc.OVERALL_SCORE, sc.RATING,
                   sc.REJECTION_RATE_PCT, sc.LATE_LINES,
                   sc.PERIOD_MONTH, sc.PERIOD_YEAR
            FROM SUPPLIER_SCORECARD sc
            JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = sc.SUPPLIER_ID
            WHERE sc.OVERALL_SCORE < p_threshold
              AND sc.PERIOD_YEAR = TO_NUMBER(TO_CHAR(SYSDATE,'YYYY'))
            ORDER BY sc.OVERALL_SCORE ASC;
        RETURN v_cur;
    END GET_RISK_SUPPLIERS;

    FUNCTION GET_ALL_SCORECARDS RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT s.SUPPLIER_ID, s.SUPPLIER_NAME, s.SUPPLIER_CODE,
                   s.ADDRESS AS LOCATION, sc.PERIOD_MONTH, sc.PERIOD_YEAR,
                   sc.OVERALL_SCORE, sc.RATING,
                   sc.DELIVERY_SCORE, sc.QUALITY_SCORE, sc.PRICE_SCORE,
                   sc.ON_TIME_LINES, sc.TOTAL_PO_LINES,
                   sc.REJECTION_RATE_PCT, sc.LOTS_REJECTED,
                   sc.PRICE_VARIANCE_PCT, sc.CALCULATED_DATE
            FROM SUPPLIER_SCORECARD sc
            JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = sc.SUPPLIER_ID
            ORDER BY sc.OVERALL_SCORE DESC, s.SUPPLIER_NAME;
        RETURN v_cur;
    END GET_ALL_SCORECARDS;

END PKG_VENDOR_SCORECARD;
/
SHOW ERRORS PACKAGE BODY PKG_VENDOR_SCORECARD;
