-- ============================================================
-- MPPMS :: 38_pkg_asl.sql (FIXED SCHEMA)
-- Purpose : Approved Supplier List Management
-- Run As  : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

CREATE OR REPLACE PACKAGE PKG_ASL AS
    FUNCTION VALIDATE_SUPPLIER(
        p_material_id IN NUMBER,
        p_supplier_id IN NUMBER
    ) RETURN VARCHAR2;

    FUNCTION GET_PREFERRED_SUPPLIER(p_material_id IN NUMBER) RETURN NUMBER;

    FUNCTION GET_ASL_FOR_MATERIAL(p_material_id IN NUMBER) RETURN SYS_REFCURSOR;

    FUNCTION GET_MATERIALS_FOR_SUPPLIER(p_supplier_id IN NUMBER) RETURN SYS_REFCURSOR;

    PROCEDURE ADD_TO_ASL(
        p_material_id     IN NUMBER,
        p_supplier_id     IN NUMBER,
        p_rank            IN NUMBER DEFAULT 2,
        p_price           IN NUMBER DEFAULT NULL,
        p_currency        IN VARCHAR2 DEFAULT 'SAR',
        p_lead_time_days  IN NUMBER DEFAULT 30,
        p_expiry_date     IN DATE DEFAULT NULL,
        p_approved_by     IN VARCHAR2 DEFAULT USER,
        p_notes           IN VARCHAR2 DEFAULT NULL
    );

    PROCEDURE BLOCK_SUPPLIER(
        p_supplier_id IN NUMBER,
        p_reason      IN VARCHAR2
    );

    FUNCTION GET_EXPIRING_ASL(p_days_ahead IN NUMBER DEFAULT 30) RETURN SYS_REFCURSOR;

    FUNCTION GET_ASL_DASHBOARD RETURN SYS_REFCURSOR;
END PKG_ASL;
/

CREATE OR REPLACE PACKAGE BODY PKG_ASL AS

    FUNCTION VALIDATE_SUPPLIER(
        p_material_id IN NUMBER,
        p_supplier_id IN NUMBER
    ) RETURN VARCHAR2 IS
        v_status    VARCHAR2(20);
        v_expiry    DATE;
    BEGIN
        SELECT APPROVAL_STATUS, EXPIRY_DATE
        INTO v_status, v_expiry
        FROM APPROVED_SUPPLIER_LIST
        WHERE MATERIAL_ID = p_material_id
          AND SUPPLIER_ID = p_supplier_id;

        IF v_expiry IS NOT NULL AND v_expiry < TRUNC(SYSDATE) THEN
            RETURN 'EXPIRED';
        END IF;
        RETURN v_status;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 'NOT_LISTED';
        WHEN OTHERS        THEN RETURN 'ERROR';
    END VALIDATE_SUPPLIER;

    FUNCTION GET_PREFERRED_SUPPLIER(p_material_id IN NUMBER) RETURN NUMBER IS
        v_supplier_id NUMBER;
    BEGIN
        SELECT SUPPLIER_ID INTO v_supplier_id
        FROM APPROVED_SUPPLIER_LIST
        WHERE MATERIAL_ID     = p_material_id
          AND APPROVAL_STATUS = 'APPROVED'
          AND (EXPIRY_DATE IS NULL OR EXPIRY_DATE >= TRUNC(SYSDATE))
        ORDER BY PREFERENCE_RANK ASC
        FETCH FIRST 1 ROW ONLY;
        RETURN v_supplier_id;
    EXCEPTION WHEN OTHERS THEN RETURN NULL;
    END GET_PREFERRED_SUPPLIER;

    FUNCTION GET_ASL_FOR_MATERIAL(p_material_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT a.ASL_ID, a.MATERIAL_ID, m.MATERIAL_CODE, m.MATERIAL_NAME,
                   a.SUPPLIER_ID, s.SUPPLIER_NAME, s.SUPPLIER_CODE, s.ADDRESS AS LOCATION,
                   a.APPROVAL_STATUS, a.PREFERENCE_RANK,
                   a.UNIT_PRICE_AGREED, a.CURRENCY_CODE,
                   a.LEAD_TIME_DAYS,
                   a.APPROVED_BY, a.APPROVED_DATE, a.EXPIRY_DATE,
                   CASE WHEN a.EXPIRY_DATE < TRUNC(SYSDATE) THEN 'EXPIRED'
                        WHEN a.EXPIRY_DATE < TRUNC(SYSDATE)+30 THEN 'EXPIRING_SOON'
                        ELSE a.APPROVAL_STATUS END AS EFFECTIVE_STATUS
            FROM APPROVED_SUPPLIER_LIST a
            JOIN MATERIAL_MASTER  m ON m.MATERIAL_ID  = a.MATERIAL_ID
            JOIN SUPPLIER_MASTER  s ON s.SUPPLIER_ID  = a.SUPPLIER_ID
            WHERE a.MATERIAL_ID = p_material_id
            ORDER BY a.PREFERENCE_RANK;
        RETURN v_cur;
    END GET_ASL_FOR_MATERIAL;

    FUNCTION GET_MATERIALS_FOR_SUPPLIER(p_supplier_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT a.ASL_ID, a.MATERIAL_ID, m.MATERIAL_CODE, m.MATERIAL_NAME,
                   m.UNIT_OF_MEASURE, a.APPROVAL_STATUS, a.PREFERENCE_RANK,
                   a.UNIT_PRICE_AGREED, a.CURRENCY_CODE, a.LEAD_TIME_DAYS,
                   a.EXPIRY_DATE,
                   (SELECT COUNT(*) FROM PURCHASE_ORDER po
                    WHERE po.SUPPLIER_ID = p_supplier_id
                      AND po.ORDER_DATE > ADD_MONTHS(SYSDATE,-12)) AS POS_LAST_12M
            FROM APPROVED_SUPPLIER_LIST a
            JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = a.MATERIAL_ID
            WHERE a.SUPPLIER_ID = p_supplier_id
            ORDER BY a.APPROVAL_STATUS, m.MATERIAL_CODE;
        RETURN v_cur;
    END GET_MATERIALS_FOR_SUPPLIER;

    PROCEDURE ADD_TO_ASL(
        p_material_id     IN NUMBER,
        p_supplier_id     IN NUMBER,
        p_rank            IN NUMBER DEFAULT 2,
        p_price           IN NUMBER DEFAULT NULL,
        p_currency        IN VARCHAR2 DEFAULT 'SAR',
        p_lead_time_days  IN NUMBER DEFAULT 30,
        p_expiry_date     IN DATE DEFAULT NULL,
        p_approved_by     IN VARCHAR2 DEFAULT USER,
        p_notes           IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        MERGE INTO APPROVED_SUPPLIER_LIST asl
        USING (SELECT p_material_id m_id, p_supplier_id s_id FROM DUAL) src
        ON (asl.MATERIAL_ID = src.m_id AND asl.SUPPLIER_ID = src.s_id)
        WHEN MATCHED THEN UPDATE SET
            APPROVAL_STATUS   = 'APPROVED',
            PREFERENCE_RANK   = p_rank,
            UNIT_PRICE_AGREED = p_price,
            CURRENCY_CODE     = p_currency,
            LEAD_TIME_DAYS    = p_lead_time_days,
            EXPIRY_DATE       = NVL(p_expiry_date, TRUNC(SYSDATE) + 365),
            APPROVED_BY       = p_approved_by,
            APPROVED_DATE     = TRUNC(SYSDATE),
            NOTES             = p_notes,
            UPDATED_DATE      = SYSDATE
        WHEN NOT MATCHED THEN INSERT (
            MATERIAL_ID, SUPPLIER_ID, APPROVAL_STATUS, PREFERENCE_RANK,
            UNIT_PRICE_AGREED, CURRENCY_CODE, LEAD_TIME_DAYS,
            EXPIRY_DATE, APPROVED_BY, APPROVED_DATE, NOTES
        ) VALUES (
            p_material_id, p_supplier_id, 'APPROVED', p_rank,
            p_price, p_currency, p_lead_time_days,
            NVL(p_expiry_date, TRUNC(SYSDATE) + 365),
            p_approved_by, TRUNC(SYSDATE), p_notes
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK;
            RAISE_APPLICATION_ERROR(-20300, 'ASL update failed: ' || SQLERRM);
    END ADD_TO_ASL;

    PROCEDURE BLOCK_SUPPLIER(
        p_supplier_id IN NUMBER,
        p_reason      IN VARCHAR2
    ) IS
    BEGIN
        UPDATE APPROVED_SUPPLIER_LIST
        SET APPROVAL_STATUS = 'BLOCKED',
            NOTES           = 'BLOCKED: ' || p_reason || ' [' || TO_CHAR(SYSDATE,'DD-MON-YYYY') || ']',
            UPDATED_DATE    = SYSDATE
        WHERE SUPPLIER_ID = p_supplier_id;
        COMMIT;
    END BLOCK_SUPPLIER;

    FUNCTION GET_EXPIRING_ASL(p_days_ahead IN NUMBER DEFAULT 30) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT a.ASL_ID, m.MATERIAL_CODE, m.MATERIAL_NAME,
                   s.SUPPLIER_NAME, s.SUPPLIER_CODE,
                   a.APPROVAL_STATUS, a.EXPIRY_DATE,
                   TRUNC(a.EXPIRY_DATE) - TRUNC(SYSDATE) AS DAYS_TO_EXPIRY
            FROM APPROVED_SUPPLIER_LIST a
            JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = a.MATERIAL_ID
            JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = a.SUPPLIER_ID
            WHERE a.EXPIRY_DATE BETWEEN TRUNC(SYSDATE)
                                    AND TRUNC(SYSDATE) + p_days_ahead
              AND a.APPROVAL_STATUS != 'BLOCKED'
            ORDER BY a.EXPIRY_DATE ASC;
        RETURN v_cur;
    END GET_EXPIRING_ASL;

    FUNCTION GET_ASL_DASHBOARD RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT m.MATERIAL_ID, m.MATERIAL_CODE, m.MATERIAL_NAME,
                   COUNT(a.ASL_ID)                                    AS APPROVED_SUPPLIER_COUNT,
                   MIN(a.PREFERENCE_RANK)                             AS BEST_RANK,
                   SUM(CASE WHEN a.APPROVAL_STATUS='APPROVED'   THEN 1 ELSE 0 END) AS APPROVED_CNT,
                   SUM(CASE WHEN a.APPROVAL_STATUS='BLOCKED'    THEN 1 ELSE 0 END) AS BLOCKED_CNT,
                   MIN(a.UNIT_PRICE_AGREED)                           AS MIN_PRICE,
                   MAX(a.UNIT_PRICE_AGREED)                           AS MAX_PRICE,
                   MIN(a.CURRENCY_CODE) KEEP (DENSE_RANK FIRST ORDER BY a.PREFERENCE_RANK) AS PREFERRED_CURR,
                   MIN(a.LEAD_TIME_DAYS)                              AS MIN_LEAD_DAYS
            FROM APPROVED_SUPPLIER_LIST a
            JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = a.MATERIAL_ID
            GROUP BY m.MATERIAL_ID, m.MATERIAL_CODE, m.MATERIAL_NAME
            ORDER BY m.MATERIAL_CODE;
        RETURN v_cur;
    END GET_ASL_DASHBOARD;

END PKG_ASL;
/
SHOW ERRORS PACKAGE BODY PKG_ASL;
