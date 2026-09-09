-- ============================================================
-- MPPMS :: 44_pkg_costing.sql (FIXED SCHEMA)
-- Purpose : Material Standard Costing & Price Variance
-- Run As  : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

CREATE OR REPLACE PACKAGE PKG_COSTING AS
    PROCEDURE SET_STANDARD_COST(
        p_material_id   IN NUMBER,
        p_cost          IN NUMBER,
        p_currency_code IN VARCHAR2 DEFAULT 'INR',
        p_cost_type     IN VARCHAR2 DEFAULT 'STANDARD',
        p_notes         IN VARCHAR2 DEFAULT NULL
    );
    PROCEDURE CALCULATE_PPV(
        p_po_id             IN NUMBER,
        p_po_line_id        IN NUMBER,
        p_material_id       IN NUMBER,
        p_qty_received      IN NUMBER,
        p_po_unit_price     IN NUMBER,
        p_po_currency       IN VARCHAR2 DEFAULT 'SAR',
        p_gr_transaction_id IN NUMBER DEFAULT NULL
    );
    FUNCTION GET_STANDARD_COST(
        p_material_id   IN NUMBER,
        p_currency_code IN VARCHAR2 DEFAULT 'INR'
    ) RETURN NUMBER;
    FUNCTION GET_INVENTORY_VALUATION(
        p_warehouse_id  IN NUMBER DEFAULT NULL,
        p_currency_code IN VARCHAR2 DEFAULT 'SAR'
    ) RETURN SYS_REFCURSOR;
    FUNCTION GET_PPV_REPORT(
        p_from_date     IN DATE DEFAULT ADD_MONTHS(TRUNC(SYSDATE,'MM'),-3),
        p_to_date       IN DATE DEFAULT SYSDATE,
        p_currency_code IN VARCHAR2 DEFAULT 'SAR'
    ) RETURN SYS_REFCURSOR;
    FUNCTION GET_COST_TREND(
        p_material_id   IN NUMBER,
        p_currency_code IN VARCHAR2 DEFAULT 'SAR'
    ) RETURN SYS_REFCURSOR;
    FUNCTION GET_COSTING_DASHBOARD(p_currency_code IN VARCHAR2 DEFAULT 'SAR') RETURN SYS_REFCURSOR;
END PKG_COSTING;
/

CREATE OR REPLACE PACKAGE BODY PKG_COSTING AS

    FUNCTION GET_CURRENT_PERIOD_ID RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        SELECT PERIOD_ID INTO v_id FROM COST_PERIOD
        WHERE STATUS = 'OPEN'
        ORDER BY START_DATE DESC
        FETCH FIRST 1 ROW ONLY;
        RETURN v_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL;
    END;

    PROCEDURE SET_STANDARD_COST(
        p_material_id   IN NUMBER,
        p_cost          IN NUMBER,
        p_currency_code IN VARCHAR2 DEFAULT 'INR',
        p_cost_type     IN VARCHAR2 DEFAULT 'STANDARD',
        p_notes         IN VARCHAR2 DEFAULT NULL
    ) IS
        v_period_id NUMBER := GET_CURRENT_PERIOD_ID;
    BEGIN
        IF v_period_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20600, 'No OPEN cost period found.');
        END IF;

        MERGE INTO MATERIAL_COST mc
        USING (SELECT p_material_id m_id, v_period_id p_id, p_cost_type ct FROM DUAL) src
        ON (mc.MATERIAL_ID = src.m_id AND mc.PERIOD_ID = src.p_id AND mc.COST_TYPE = src.ct)
        WHEN MATCHED THEN UPDATE SET
            STANDARD_COST  = p_cost,
            CURRENCY_CODE  = p_currency_code,
            EFFECTIVE_FROM = TRUNC(SYSDATE),
            SET_BY         = USER,
            SET_DATE       = SYSDATE,
            NOTES          = p_notes
        WHEN NOT MATCHED THEN INSERT (
            MATERIAL_ID, PERIOD_ID, STANDARD_COST, CURRENCY_CODE,
            COST_TYPE, EFFECTIVE_FROM, SET_BY, NOTES
        ) VALUES (
            p_material_id, v_period_id, p_cost, p_currency_code,
            p_cost_type, TRUNC(SYSDATE), USER, p_notes
        );
        COMMIT;
    END SET_STANDARD_COST;

    FUNCTION GET_STANDARD_COST(
        p_material_id   IN NUMBER,
        p_currency_code IN VARCHAR2 DEFAULT 'INR'
    ) RETURN NUMBER IS
        v_std_cost      NUMBER;
        v_from_currency VARCHAR2(3);
    BEGIN
        SELECT mc.STANDARD_COST, mc.CURRENCY_CODE
        INTO v_std_cost, v_from_currency
        FROM MATERIAL_COST mc
        JOIN COST_PERIOD cp ON cp.PERIOD_ID = mc.PERIOD_ID
        WHERE mc.MATERIAL_ID = p_material_id
          AND mc.COST_TYPE   = 'STANDARD'
          AND cp.STATUS      = 'OPEN'
        ORDER BY cp.START_DATE DESC
        FETCH FIRST 1 ROW ONLY;

        IF v_from_currency != p_currency_code THEN
            v_std_cost := PKG_VENDOR_SCORECARD.CONVERT_CURRENCY(
                              v_std_cost, v_from_currency, p_currency_code);
        END IF;
        RETURN v_std_cost;
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN 0;
    END GET_STANDARD_COST;

    PROCEDURE CALCULATE_PPV(
        p_po_id             IN NUMBER,
        p_po_line_id        IN NUMBER,
        p_material_id       IN NUMBER,
        p_qty_received      IN NUMBER,
        p_po_unit_price     IN NUMBER,
        p_po_currency       IN VARCHAR2 DEFAULT 'SAR',
        p_gr_transaction_id IN NUMBER DEFAULT NULL
    ) IS
        v_std_cost_inr  NUMBER;
        v_po_price_inr  NUMBER;
        v_variance_unit NUMBER;
        v_total_var     NUMBER;
        v_var_type      VARCHAR2(15);
        v_period_id     NUMBER := GET_CURRENT_PERIOD_ID;
    BEGIN
        v_std_cost_inr := GET_STANDARD_COST(p_material_id, 'INR');
        v_po_price_inr := PKG_VENDOR_SCORECARD.CONVERT_CURRENCY(
                              p_po_unit_price, p_po_currency, 'INR');

        v_variance_unit := v_po_price_inr - v_std_cost_inr;
        v_total_var     := ROUND(v_variance_unit * p_qty_received, 2);
        v_var_type      := CASE WHEN v_variance_unit < 0 THEN 'FAVOURABLE' ELSE 'ADVERSE' END;

        IF v_std_cost_inr > 0 AND ABS(v_variance_unit) > 0 THEN
            INSERT INTO PRICE_VARIANCE_LOG (
                PO_ID, PO_LINE_ID, MATERIAL_ID, GR_TRANSACTION_ID, PERIOD_ID,
                STANDARD_COST, PO_UNIT_PRICE, PO_CURRENCY, PO_PRICE_IN_INR,
                QTY_RECEIVED, PRICE_VARIANCE_UNIT, TOTAL_VARIANCE_AMOUNT,
                VARIANCE_TYPE, VARIANCE_PCT
            ) VALUES (
                p_po_id, p_po_line_id, p_material_id, p_gr_transaction_id, v_period_id,
                v_std_cost_inr, p_po_unit_price, p_po_currency, v_po_price_inr,
                p_qty_received, v_variance_unit, v_total_var,
                v_var_type,
                CASE WHEN v_std_cost_inr > 0
                     THEN ROUND(ABS(v_variance_unit/v_std_cost_inr)*100, 3) ELSE NULL END
            );
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('PPV calculation warning: ' || SQLERRM);
    END CALCULATE_PPV;

    FUNCTION GET_INVENTORY_VALUATION(
        p_warehouse_id  IN NUMBER DEFAULT NULL,
        p_currency_code IN VARCHAR2 DEFAULT 'SAR'
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT m.MATERIAL_ID, m.MATERIAL_CODE, m.MATERIAL_NAME,
                   m.CATEGORY AS MATERIAL_CATEGORY, m.UNIT_OF_MEASURE,
                   w.WAREHOUSE_NAME,
                   ib.QTY_ON_HAND, (ib.QTY_ON_HAND - NVL(ib.QTY_RESERVED,0) - NVL(ib.QTY_BLOCKED,0) - NVL(ib.QTY_IN_QUALITY,0)) AS QTY_AVAILABLE, ib.QTY_RESERVED,
                   mc.STANDARD_COST,
                   mc.CURRENCY_CODE AS COST_CURRENCY,
                   ROUND(ib.QTY_ON_HAND * mc.STANDARD_COST, 2) AS STOCK_VALUE,
                   p_currency_code AS DISPLAY_CURRENCY
            FROM INVENTORY_BALANCE ib
            JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = ib.MATERIAL_ID
            JOIN WAREHOUSE_MASTER w ON w.WAREHOUSE_ID = ib.WAREHOUSE_ID
            LEFT JOIN (
                SELECT mc2.MATERIAL_ID, mc2.STANDARD_COST, mc2.CURRENCY_CODE
                FROM MATERIAL_COST mc2
                JOIN COST_PERIOD cp ON cp.PERIOD_ID = mc2.PERIOD_ID
                WHERE cp.STATUS = 'OPEN' AND mc2.COST_TYPE = 'STANDARD'
            ) mc ON mc.MATERIAL_ID = ib.MATERIAL_ID
            WHERE (p_warehouse_id IS NULL OR ib.WAREHOUSE_ID = p_warehouse_id)
              AND ib.QTY_ON_HAND > 0
            ORDER BY STOCK_VALUE DESC NULLS LAST;
        RETURN v_cur;
    END GET_INVENTORY_VALUATION;

    FUNCTION GET_PPV_REPORT(
        p_from_date     IN DATE DEFAULT ADD_MONTHS(TRUNC(SYSDATE,'MM'),-3),
        p_to_date       IN DATE DEFAULT SYSDATE,
        p_currency_code IN VARCHAR2 DEFAULT 'SAR'
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT m.MATERIAL_CODE, m.MATERIAL_NAME,
                   s.SUPPLIER_NAME,
                   pvl.PO_CURRENCY, pvl.PO_UNIT_PRICE, pvl.STANDARD_COST,
                   pvl.PRICE_VARIANCE_UNIT, pvl.QTY_RECEIVED,
                   pvl.TOTAL_VARIANCE_AMOUNT, pvl.VARIANCE_TYPE,
                   pvl.VARIANCE_PCT, pvl.POSTED_DATE
            FROM PRICE_VARIANCE_LOG pvl
            JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = pvl.MATERIAL_ID
            JOIN PURCHASE_ORDER  po ON po.PO_ID = pvl.PO_ID
            JOIN SUPPLIER_MASTER s  ON s.SUPPLIER_ID = po.SUPPLIER_ID
            WHERE pvl.POSTED_DATE BETWEEN p_from_date AND p_to_date
            ORDER BY ABS(pvl.TOTAL_VARIANCE_AMOUNT) DESC;
        RETURN v_cur;
    END GET_PPV_REPORT;

    FUNCTION GET_COST_TREND(
        p_material_id   IN NUMBER,
        p_currency_code IN VARCHAR2 DEFAULT 'SAR'
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT cp.PERIOD_NAME, cp.FISCAL_YEAR, cp.PERIOD_NUMBER,
                   mc.STANDARD_COST, mc.CURRENCY_CODE,
                   mc.SET_DATE
            FROM MATERIAL_COST mc
            JOIN COST_PERIOD cp ON cp.PERIOD_ID = mc.PERIOD_ID
            WHERE mc.MATERIAL_ID = p_material_id
              AND mc.COST_TYPE   = 'STANDARD'
            ORDER BY cp.FISCAL_YEAR, cp.PERIOD_NUMBER;
        RETURN v_cur;
    END GET_COST_TREND;

    FUNCTION GET_COSTING_DASHBOARD(p_currency_code IN VARCHAR2 DEFAULT 'SAR') RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT
                (SELECT COUNT(DISTINCT MATERIAL_ID) FROM MATERIAL_COST mc
                 JOIN COST_PERIOD cp ON cp.PERIOD_ID=mc.PERIOD_ID WHERE cp.STATUS='OPEN')
                    AS MATERIALS_WITH_COST,
                (SELECT NVL(SUM(ib.QTY_ON_HAND * mc.STANDARD_COST),0)
                 FROM INVENTORY_BALANCE ib
                 JOIN MATERIAL_COST mc ON mc.MATERIAL_ID = ib.MATERIAL_ID
                 JOIN COST_PERIOD cp   ON cp.PERIOD_ID = mc.PERIOD_ID
                 WHERE cp.STATUS='OPEN' AND mc.COST_TYPE='STANDARD')
                    AS TOTAL_INVENTORY_VALUE_INR,
                (SELECT NVL(SUM(TOTAL_VARIANCE_AMOUNT),0) FROM PRICE_VARIANCE_LOG
                 WHERE VARIANCE_TYPE='ADVERSE'
                   AND POSTED_DATE >= TRUNC(SYSDATE,'MM'))
                    AS ADVERSE_PPV_MTD_INR,
                (SELECT NVL(SUM(TOTAL_VARIANCE_AMOUNT),0) FROM PRICE_VARIANCE_LOG
                 WHERE VARIANCE_TYPE='FAVOURABLE'
                   AND POSTED_DATE >= TRUNC(SYSDATE,'MM'))
                    AS FAVOURABLE_PPV_MTD_INR
            FROM DUAL;
        RETURN v_cur;
    END GET_COSTING_DASHBOARD;

END PKG_COSTING;
/
SHOW ERRORS PACKAGE BODY PKG_COSTING;
