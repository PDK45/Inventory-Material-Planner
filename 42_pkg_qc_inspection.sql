-- ============================================================
-- MPPMS :: 42_pkg_qc_inspection.sql (FIXED SCHEMA)
-- Purpose : QC Inspection Engine for Steel Manufacturing
-- Run As  : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

CREATE OR REPLACE PACKAGE PKG_QC_INSPECTION AS
    FUNCTION INITIATE_INSPECTION(
        p_gr_transaction_id IN NUMBER,
        p_po_id             IN NUMBER,
        p_material_id       IN NUMBER,
        p_supplier_id       IN NUMBER,
        p_lot_number        IN VARCHAR2,
        p_qty_received      IN NUMBER,
        p_warehouse_id      IN NUMBER,
        p_heat_number       IN VARCHAR2 DEFAULT NULL,
        p_mill_cert_number  IN VARCHAR2 DEFAULT NULL
    ) RETURN NUMBER;

    FUNCTION GET_MATERIAL_CATEGORY(p_material_id IN NUMBER) RETURN VARCHAR2;

    PROCEDURE LOAD_PARAMETERS(p_inspection_id IN NUMBER);

    PROCEDURE RECORD_RESULT(
        p_inspection_id     IN NUMBER,
        p_parameter_code    IN VARCHAR2,
        p_numeric_value     IN NUMBER   DEFAULT NULL,
        p_text_value        IN VARCHAR2 DEFAULT NULL,
        p_test_method       IN VARCHAR2 DEFAULT NULL,
        p_notes             IN VARCHAR2 DEFAULT NULL
    );

    PROCEDURE COMPLETE_INSPECTION(
        p_inspection_id IN NUMBER,
        p_inspector     IN VARCHAR2 DEFAULT USER,
        p_qty_accepted  IN NUMBER   DEFAULT NULL,
        p_qty_rejected  IN NUMBER   DEFAULT NULL,
        p_waiver_reason IN VARCHAR2 DEFAULT NULL
    );

    FUNCTION INITIATE_RETURN(
        p_inspection_id       IN NUMBER,
        p_qty_returned        IN NUMBER,
        p_reason              IN VARCHAR2,
        p_credit_expected     IN NUMBER   DEFAULT NULL,
        p_currency_code       IN VARCHAR2 DEFAULT 'SAR'
    ) RETURN NUMBER;

    FUNCTION GET_PENDING_INSPECTIONS RETURN SYS_REFCURSOR;

    FUNCTION GET_REJECTION_ANALYSIS(p_months IN NUMBER DEFAULT 6) RETURN SYS_REFCURSOR;

    FUNCTION GET_INSPECTION_DETAIL(p_inspection_id IN NUMBER) RETURN SYS_REFCURSOR;
END PKG_QC_INSPECTION;
/

CREATE OR REPLACE PACKAGE BODY PKG_QC_INSPECTION AS

    FUNCTION GET_MATERIAL_CATEGORY(p_material_id IN NUMBER) RETURN VARCHAR2 IS
        v_code  VARCHAR2(50);
        v_name  VARCHAR2(240);
        v_cat   VARCHAR2(50);
    BEGIN
        SELECT UPPER(MATERIAL_CODE), UPPER(MATERIAL_NAME), UPPER(NVL(CATEGORY,'GENERAL'))
        INTO v_code, v_name, v_cat
        FROM MATERIAL_MASTER WHERE MATERIAL_ID = p_material_id;

        IF v_code LIKE '%BEAM%' OR v_code LIKE '%CHANNEL%' OR v_code LIKE '%ANGLE%'
           OR v_code LIKE '%PLATE%' OR v_name LIKE '%H-BEAM%' OR v_name LIKE '%STRUCTURAL%' THEN
            RETURN 'STRUCTURAL_STEEL';
        ELSIF v_code LIKE '%COIL%' OR v_code LIKE '%SHEET%' OR v_name LIKE '%COIL%' OR v_name LIKE '%SHEET%' THEN
            RETURN 'STEEL_COIL';
        ELSIF v_code LIKE '%PIPE%' OR v_code LIKE '%TUBE%' OR v_name LIKE '%PIPE%' OR v_name LIKE '%TUBE%' THEN
            RETURN 'STEEL_PIPE';
        ELSIF v_code LIKE '%BLT%' OR v_code LIKE '%BOLT%' OR v_code LIKE '%NUT%' OR v_name LIKE '%BOLT%' THEN
            RETURN 'FASTENERS';
        ELSIF v_code LIKE '%WLD%' OR v_name LIKE '%WELD%' OR v_name LIKE '%ELECTRODE%' THEN
            RETURN 'WELDING_CONSUMABLES';
        ELSIF v_code LIKE '%PNT%' OR v_name LIKE '%PAINT%' OR v_name LIKE '%COAT%' THEN
            RETURN 'PAINT_COATING';
        ELSE
            RETURN 'GENERAL';
        END IF;
    EXCEPTION WHEN OTHERS THEN RETURN 'GENERAL';
    END GET_MATERIAL_CATEGORY;

    PROCEDURE LOAD_PARAMETERS(p_inspection_id IN NUMBER) IS
        v_material_id NUMBER;
        v_category    VARCHAR2(50);
    BEGIN
        SELECT MATERIAL_ID INTO v_material_id
        FROM QC_INSPECTION WHERE INSPECTION_ID = p_inspection_id;

        v_category := GET_MATERIAL_CATEGORY(v_material_id);

        DELETE FROM QC_INSPECTION_LINE
        WHERE INSPECTION_ID = p_inspection_id AND RESULT = 'PENDING';

        INSERT INTO QC_INSPECTION_LINE (
            INSPECTION_ID, PARAM_ID, PARAMETER_CODE, PARAMETER_NAME,
            UNIT, SPEC_MIN, SPEC_MAX, RESULT
        )
        SELECT p_inspection_id, PARAM_ID, PARAMETER_CODE, PARAMETER_NAME,
               UNIT, SPEC_MIN, SPEC_MAX, 'PENDING'
        FROM QC_PARAMETER
        WHERE MATERIAL_CATEGORY = v_category
        ORDER BY SORT_ORDER;

        IF SQL%ROWCOUNT = 0 THEN
            INSERT INTO QC_INSPECTION_LINE (
                INSPECTION_ID, PARAM_ID, PARAMETER_CODE, PARAMETER_NAME,
                UNIT, SPEC_MIN, SPEC_MAX, RESULT
            )
            SELECT p_inspection_id, PARAM_ID, PARAMETER_CODE, PARAMETER_NAME,
                   UNIT, SPEC_MIN, SPEC_MAX, 'PENDING'
            FROM QC_PARAMETER WHERE MATERIAL_CATEGORY = 'GENERAL'
            ORDER BY SORT_ORDER;
        END IF;
        COMMIT;
    END LOAD_PARAMETERS;

    FUNCTION INITIATE_INSPECTION(
        p_gr_transaction_id IN NUMBER,
        p_po_id             IN NUMBER,
        p_material_id       IN NUMBER,
        p_supplier_id       IN NUMBER,
        p_lot_number        IN VARCHAR2,
        p_qty_received      IN NUMBER,
        p_warehouse_id      IN NUMBER,
        p_heat_number       IN VARCHAR2 DEFAULT NULL,
        p_mill_cert_number  IN VARCHAR2 DEFAULT NULL
    ) RETURN NUMBER IS
        v_inspection_id NUMBER;
        v_insp_num      VARCHAR2(30);
        v_seq           NUMBER;
    BEGIN
        SELECT SEQ_QC_INSPECTION_NUM.NEXTVAL INTO v_seq FROM DUAL;
        v_insp_num := 'QC-' || TO_CHAR(SYSDATE,'YYYY') || '-' || LPAD(v_seq,6,'0');

        INSERT INTO QC_INSPECTION (
            INSPECTION_NUMBER, GR_TRANSACTION_ID, PO_ID,
            MATERIAL_ID, SUPPLIER_ID, LOT_NUMBER,
            WAREHOUSE_ID, TOTAL_QTY_RECEIVED, QTY_SAMPLED,
            INSPECTION_STATUS, HEAT_NUMBER, MILL_CERT_NUMBER,
            MILL_CERT_RECEIVED
        ) VALUES (
            v_insp_num, p_gr_transaction_id, p_po_id,
            p_material_id, p_supplier_id, p_lot_number,
            p_warehouse_id, p_qty_received,
            GREATEST(1, ROUND(p_qty_received * 0.10)),
            'PENDING', p_heat_number, p_mill_cert_number,
            CASE WHEN p_mill_cert_number IS NOT NULL THEN 'Y' ELSE 'N' END
        ) RETURNING INSPECTION_ID INTO v_inspection_id;

        COMMIT;

        LOAD_PARAMETERS(v_inspection_id);
        RETURN v_inspection_id;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK;
            RAISE_APPLICATION_ERROR(-20500, 'Initiate inspection failed: ' || SQLERRM);
    END INITIATE_INSPECTION;

    PROCEDURE RECORD_RESULT(
        p_inspection_id     IN NUMBER,
        p_parameter_code    IN VARCHAR2,
        p_numeric_value     IN NUMBER   DEFAULT NULL,
        p_text_value        IN VARCHAR2 DEFAULT NULL,
        p_test_method       IN VARCHAR2 DEFAULT NULL,
        p_notes             IN VARCHAR2 DEFAULT NULL
    ) IS
        v_result      VARCHAR2(10) := 'PENDING';
        v_spec_min    NUMBER;
        v_spec_max    NUMBER;
        v_param_type  VARCHAR2(20);
        v_dev_pct     NUMBER;
    BEGIN
        SELECT qp.PARAMETER_TYPE, ql.SPEC_MIN, ql.SPEC_MAX
        INTO v_param_type, v_spec_min, v_spec_max
        FROM QC_INSPECTION_LINE ql
        JOIN QC_PARAMETER qp ON qp.PARAM_ID = ql.PARAM_ID
        WHERE ql.INSPECTION_ID = p_inspection_id
          AND ql.PARAMETER_CODE = p_parameter_code;

        IF v_param_type = 'NUMERIC' AND p_numeric_value IS NOT NULL THEN
            IF (v_spec_min IS NULL OR p_numeric_value >= v_spec_min)
               AND (v_spec_max IS NULL OR p_numeric_value <= v_spec_max) THEN
                v_result := 'PASS';
            ELSE
                v_result := 'FAIL';
                IF v_spec_min IS NOT NULL AND p_numeric_value < v_spec_min THEN
                    v_dev_pct := ROUND((v_spec_min - p_numeric_value)/v_spec_min*100, 2);
                ELSIF v_spec_max IS NOT NULL AND p_numeric_value > v_spec_max THEN
                    v_dev_pct := ROUND((p_numeric_value - v_spec_max)/v_spec_max*100, 2);
                END IF;
            END IF;
        ELSIF v_param_type = 'PASS_FAIL' AND p_text_value IS NOT NULL THEN
            v_result := UPPER(p_text_value);
        END IF;

        UPDATE QC_INSPECTION_LINE
        SET MEASURED_VALUE_NUM  = p_numeric_value,
            MEASURED_VALUE_TEXT = p_text_value,
            RESULT              = v_result,
            DEVIATION_PCT       = v_dev_pct,
            TEST_METHOD         = p_test_method,
            NOTES               = p_notes
        WHERE INSPECTION_ID  = p_inspection_id
          AND PARAMETER_CODE = p_parameter_code;

        UPDATE QC_INSPECTION SET INSPECTION_STATUS = 'IN_PROGRESS'
        WHERE INSPECTION_ID = p_inspection_id
          AND INSPECTION_STATUS = 'PENDING';

        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20501, 'Parameter ' || p_parameter_code || ' not found for inspection ' || p_inspection_id);
    END RECORD_RESULT;

    PROCEDURE COMPLETE_INSPECTION(
        p_inspection_id IN NUMBER,
        p_inspector     IN VARCHAR2 DEFAULT USER,
        p_qty_accepted  IN NUMBER   DEFAULT NULL,
        p_qty_rejected  IN NUMBER   DEFAULT NULL,
        p_waiver_reason IN VARCHAR2 DEFAULT NULL
    ) IS
        v_fail_count    NUMBER;
        v_total_params  NUMBER;
        v_overall       VARCHAR2(15);
        v_qty_total     NUMBER;
        v_qty_accepted  NUMBER;
        v_qty_rejected  NUMBER;
    BEGIN
        SELECT TOTAL_QTY_RECEIVED INTO v_qty_total
        FROM QC_INSPECTION WHERE INSPECTION_ID = p_inspection_id;

        SELECT COUNT(*), SUM(CASE WHEN RESULT='FAIL' THEN 1 ELSE 0 END)
        INTO v_total_params, v_fail_count
        FROM QC_INSPECTION_LINE WHERE INSPECTION_ID = p_inspection_id;

        IF v_fail_count = 0 THEN
            v_overall := 'PASS';
            v_qty_accepted := NVL(p_qty_accepted, v_qty_total);
            v_qty_rejected := NVL(p_qty_rejected, 0);
        ELSIF p_waiver_reason IS NOT NULL AND v_fail_count <= 1 THEN
            v_overall := 'CONDITIONAL';
            v_qty_accepted := NVL(p_qty_accepted, v_qty_total * 0.9);
            v_qty_rejected := NVL(p_qty_rejected, v_qty_total * 0.1);
        ELSE
            v_overall := 'FAIL';
            v_qty_accepted := NVL(p_qty_accepted, 0);
            v_qty_rejected := NVL(p_qty_rejected, v_qty_total);
        END IF;

        UPDATE QC_INSPECTION SET
            INSPECTION_STATUS = 'COMPLETED',
            OVERALL_RESULT    = v_overall,
            INSPECTOR_NAME    = p_inspector,
            QTY_ACCEPTED      = v_qty_accepted,
            QTY_REJECTED      = v_qty_rejected,
            WAIVER_REASON     = p_waiver_reason,
            COMPLETED_DATE    = SYSDATE
        WHERE INSPECTION_ID = p_inspection_id;

        IF v_qty_accepted > 0 THEN
            UPDATE INVENTORY_BALANCE
            SET QTY_ON_HAND    = NVL(QTY_ON_HAND,0) + v_qty_accepted,
                QTY_IN_QUALITY = GREATEST(0, NVL(QTY_IN_QUALITY,0) - v_qty_accepted),
                LAST_UPDATED_DATE = SYSDATE
            WHERE MATERIAL_ID  = (SELECT MATERIAL_ID FROM QC_INSPECTION WHERE INSPECTION_ID = p_inspection_id)
              AND WAREHOUSE_ID = (SELECT WAREHOUSE_ID FROM QC_INSPECTION WHERE INSPECTION_ID = p_inspection_id)
              AND ROWNUM = 1;
        END IF;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK;
            RAISE_APPLICATION_ERROR(-20502, 'Complete inspection failed: ' || SQLERRM);
    END COMPLETE_INSPECTION;

    FUNCTION INITIATE_RETURN(
        p_inspection_id       IN NUMBER,
        p_qty_returned        IN NUMBER,
        p_reason              IN VARCHAR2,
        p_credit_expected     IN NUMBER   DEFAULT NULL,
        p_currency_code       IN VARCHAR2 DEFAULT 'SAR'
    ) RETURN NUMBER IS
        v_return_id     NUMBER;
        v_return_num    VARCHAR2(30);
        v_seq           NUMBER;
        v_supplier_id   NUMBER;
        v_material_id   NUMBER;
        v_failed_params VARCHAR2(500);
    BEGIN
        SELECT SEQ_QC_RETURN_NUM.NEXTVAL INTO v_seq FROM DUAL;
        v_return_num := 'QCR-' || TO_CHAR(SYSDATE,'YYYY') || '-' || LPAD(v_seq,6,'0');

        SELECT SUPPLIER_ID, MATERIAL_ID INTO v_supplier_id, v_material_id
        FROM QC_INSPECTION WHERE INSPECTION_ID = p_inspection_id;

        SELECT LISTAGG(PARAMETER_NAME, ', ') WITHIN GROUP (ORDER BY PARAMETER_NAME)
        INTO v_failed_params
        FROM QC_INSPECTION_LINE
        WHERE INSPECTION_ID = p_inspection_id AND RESULT = 'FAIL';

        INSERT INTO QC_RETURN (
            RETURN_NUMBER, INSPECTION_ID, SUPPLIER_ID, MATERIAL_ID,
            QTY_RETURNED, RETURN_REASON, FAILED_PARAMETERS,
            SUPPLIER_CREDIT_EXPECTED, CURRENCY_CODE, RETURN_STATUS
        ) VALUES (
            v_return_num, p_inspection_id, v_supplier_id, v_material_id,
            p_qty_returned, p_reason, v_failed_params,
            p_credit_expected, p_currency_code, 'INITIATED'
        ) RETURNING RETURN_ID INTO v_return_id;

        PKG_VENDOR_SCORECARD.CALCULATE_SCORE(
            v_supplier_id,
            TO_NUMBER(TO_CHAR(SYSDATE,'MM')),
            TO_NUMBER(TO_CHAR(SYSDATE,'YYYY'))
        );

        COMMIT;
        RETURN v_return_id;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK;
            RAISE_APPLICATION_ERROR(-20503, 'Initiate return failed: ' || SQLERRM);
    END INITIATE_RETURN;

    FUNCTION GET_PENDING_INSPECTIONS RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT qi.INSPECTION_ID, qi.INSPECTION_NUMBER,
                   m.MATERIAL_CODE, m.MATERIAL_NAME,
                   s.SUPPLIER_NAME, s.SUPPLIER_CODE,
                   qi.TOTAL_QTY_RECEIVED, qi.QTY_SAMPLED,
                   qi.INSPECTION_DATE, qi.INSPECTION_STATUS,
                   qi.HEAT_NUMBER, qi.MILL_CERT_RECEIVED,
                   TRUNC(SYSDATE) - TRUNC(qi.INSPECTION_DATE) AS DAYS_OPEN,
                   (SELECT COUNT(*) FROM QC_INSPECTION_LINE ql
                    WHERE ql.INSPECTION_ID = qi.INSPECTION_ID AND ql.RESULT='PENDING') AS PENDING_PARAMS,
                   (SELECT COUNT(*) FROM QC_INSPECTION_LINE ql
                    WHERE ql.INSPECTION_ID = qi.INSPECTION_ID) AS TOTAL_PARAMS
            FROM QC_INSPECTION qi
            JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = qi.MATERIAL_ID
            JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = qi.SUPPLIER_ID
            WHERE qi.INSPECTION_STATUS IN ('PENDING','IN_PROGRESS')
            ORDER BY qi.INSPECTION_DATE ASC;
        RETURN v_cur;
    END GET_PENDING_INSPECTIONS;

    FUNCTION GET_REJECTION_ANALYSIS(p_months IN NUMBER DEFAULT 6) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT s.SUPPLIER_NAME, s.SUPPLIER_CODE,
                   m.MATERIAL_CODE, m.MATERIAL_NAME,
                   COUNT(qi.INSPECTION_ID)                       AS TOTAL_INSPECTIONS,
                   SUM(CASE WHEN qi.OVERALL_RESULT='PASS' THEN 1 ELSE 0 END) AS PASSED,
                   SUM(CASE WHEN qi.OVERALL_RESULT='FAIL' THEN 1 ELSE 0 END) AS FAILED,
                   ROUND(SUM(CASE WHEN qi.OVERALL_RESULT='FAIL' THEN 1 ELSE 0 END)
                       / NULLIF(COUNT(*),0) * 100, 2) AS REJECTION_RATE_PCT,
                   SUM(qi.QTY_REJECTED) AS TOTAL_QTY_REJECTED
            FROM QC_INSPECTION qi
            JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = qi.SUPPLIER_ID
            JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = qi.MATERIAL_ID
            WHERE qi.INSPECTION_STATUS = 'COMPLETED'
              AND qi.COMPLETED_DATE >= ADD_MONTHS(SYSDATE, -p_months)
            GROUP BY s.SUPPLIER_NAME, s.SUPPLIER_CODE, m.MATERIAL_CODE, m.MATERIAL_NAME
            ORDER BY REJECTION_RATE_PCT DESC;
        RETURN v_cur;
    END GET_REJECTION_ANALYSIS;

    FUNCTION GET_INSPECTION_DETAIL(p_inspection_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT ql.LINE_ID, ql.PARAMETER_CODE, ql.PARAMETER_NAME,
                   ql.UNIT, ql.SPEC_MIN, ql.SPEC_MAX,
                   ql.MEASURED_VALUE_NUM, ql.MEASURED_VALUE_TEXT,
                   ql.RESULT, ql.DEVIATION_PCT, ql.TEST_METHOD, ql.NOTES,
                   qp.STANDARD_REF, qp.PARAMETER_TYPE, qp.IS_MANDATORY
            FROM QC_INSPECTION_LINE ql
            LEFT JOIN QC_PARAMETER qp ON qp.PARAM_ID = ql.PARAM_ID
            WHERE ql.INSPECTION_ID = p_inspection_id
            ORDER BY qp.SORT_ORDER NULLS LAST;
        RETURN v_cur;
    END GET_INSPECTION_DETAIL;

END PKG_QC_INSPECTION;
/
SHOW ERRORS PACKAGE BODY PKG_QC_INSPECTION;
