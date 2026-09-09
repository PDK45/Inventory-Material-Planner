-- ============================================================
-- MPPMS :: 46_pkg_lot_serial.sql (FIXED SCHEMA)
-- Purpose : Lot & Serial Number Tracking Engine
-- Run As  : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

CREATE OR REPLACE PACKAGE PKG_LOT_SERIAL AS
    FUNCTION CREATE_LOT(
        p_material_id       IN NUMBER,
        p_po_id             IN NUMBER,
        p_gr_txn_id         IN NUMBER,
        p_qty_received      IN NUMBER,
        p_warehouse_id      IN NUMBER,
        p_bin_id            IN NUMBER DEFAULT NULL,
        p_supplier_id       IN NUMBER DEFAULT NULL,
        p_heat_number       IN VARCHAR2 DEFAULT NULL,
        p_mill_cert_number  IN VARCHAR2 DEFAULT NULL,
        p_country_of_origin IN VARCHAR2 DEFAULT NULL,
        p_mill_name         IN VARCHAR2 DEFAULT NULL,
        p_manufacture_date  IN DATE DEFAULT NULL,
        p_expiry_date       IN DATE DEFAULT NULL,
        p_qc_inspection_id  IN NUMBER DEFAULT NULL
    ) RETURN VARCHAR2;

    PROCEDURE ISSUE_FROM_LOT(
        p_material_id       IN NUMBER,
        p_warehouse_id      IN NUMBER,
        p_qty_to_issue      IN NUMBER,
        p_reference_doc_type IN VARCHAR2,
        p_reference_doc_id  IN NUMBER,
        p_performed_by      IN VARCHAR2 DEFAULT USER,
        p_lot_id            IN NUMBER DEFAULT NULL
    );

    PROCEDURE TRANSFER_LOT(
        p_lot_id            IN NUMBER,
        p_qty               IN NUMBER,
        p_from_warehouse_id IN NUMBER,
        p_to_warehouse_id   IN NUMBER,
        p_to_bin_id         IN NUMBER DEFAULT NULL,
        p_performed_by      IN VARCHAR2 DEFAULT USER
    );

    PROCEDURE ASSIGN_SERIAL(
        p_serial_number     IN VARCHAR2,
        p_material_id       IN NUMBER,
        p_lot_id            IN NUMBER DEFAULT NULL,
        p_warehouse_id      IN NUMBER,
        p_bin_id            IN NUMBER DEFAULT NULL,
        p_po_id             IN NUMBER DEFAULT NULL,
        p_warrant_expiry    IN DATE DEFAULT NULL
    );

    PROCEDURE ISSUE_SERIAL(
        p_serial_id         IN NUMBER,
        p_reference_doc_type IN VARCHAR2,
        p_reference_doc_id  IN NUMBER,
        p_performed_by      IN VARCHAR2 DEFAULT USER
    );

    FUNCTION GET_LOT_TRACEABILITY(p_lot_id IN NUMBER) RETURN CLOB;

    FUNCTION GET_EXPIRING_LOTS(p_days_ahead IN NUMBER DEFAULT 90) RETURN SYS_REFCURSOR;

    FUNCTION GET_LOT_STATUS(p_lot_number IN VARCHAR2) RETURN SYS_REFCURSOR;

    FUNCTION GET_MATERIAL_LOTS(p_material_id IN NUMBER) RETURN SYS_REFCURSOR;

    FUNCTION GET_SERIAL_HISTORY(p_serial_number IN VARCHAR2) RETURN SYS_REFCURSOR;

    FUNCTION GET_LOT_REGISTER RETURN SYS_REFCURSOR;
END PKG_LOT_SERIAL;
/

CREATE OR REPLACE PACKAGE BODY PKG_LOT_SERIAL AS

    FUNCTION CREATE_LOT(
        p_material_id       IN NUMBER,
        p_po_id             IN NUMBER,
        p_gr_txn_id         IN NUMBER,
        p_qty_received      IN NUMBER,
        p_warehouse_id      IN NUMBER,
        p_bin_id            IN NUMBER DEFAULT NULL,
        p_supplier_id       IN NUMBER DEFAULT NULL,
        p_heat_number       IN VARCHAR2 DEFAULT NULL,
        p_mill_cert_number  IN VARCHAR2 DEFAULT NULL,
        p_country_of_origin IN VARCHAR2 DEFAULT NULL,
        p_mill_name         IN VARCHAR2 DEFAULT NULL,
        p_manufacture_date  IN DATE DEFAULT NULL,
        p_expiry_date       IN DATE DEFAULT NULL,
        p_qc_inspection_id  IN NUMBER DEFAULT NULL
    ) RETURN VARCHAR2 IS
        v_lot_number    VARCHAR2(30);
        v_seq           NUMBER;
        v_lot_id        NUMBER;
    BEGIN
        SELECT SEQ_LOT_NUMBER.NEXTVAL INTO v_seq FROM DUAL;
        v_lot_number := 'LOT-' || TO_CHAR(SYSDATE,'YYYY') || '-' || LPAD(v_seq,6,'0');

        INSERT INTO LOT_MASTER (
            LOT_NUMBER, MATERIAL_ID, SUPPLIER_ID, PO_ID, GR_TRANSACTION_ID,
            QC_INSPECTION_ID, HEAT_NUMBER, MILL_CERT_NUMBER,
            COUNTRY_OF_ORIGIN, MILL_NAME,
            MANUFACTURE_DATE, EXPIRY_DATE,
            QTY_RECEIVED, QTY_AVAILABLE,
            WAREHOUSE_ID, BIN_ID, STATUS
        ) VALUES (
            v_lot_number, p_material_id, p_supplier_id, p_po_id, p_gr_txn_id,
            p_qc_inspection_id, p_heat_number, p_mill_cert_number,
            p_country_of_origin, p_mill_name,
            p_manufacture_date, p_expiry_date,
            p_qty_received, p_qty_received,
            p_warehouse_id, p_bin_id, 'AVAILABLE'
        ) RETURNING LOT_ID INTO v_lot_id;

        INSERT INTO LOT_TRANSACTION (
            LOT_ID, TRANSACTION_TYPE, QTY_CHANGE, QTY_AFTER,
            WAREHOUSE_ID, BIN_ID, REFERENCE_DOC_TYPE, REFERENCE_DOC_ID,
            PERFORMED_BY
        ) VALUES (
            v_lot_id, 'RECEIPT', p_qty_received, p_qty_received,
            p_warehouse_id, p_bin_id, 'PO', p_po_id, USER
        );

        COMMIT;
        RETURN v_lot_number;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK;
            RAISE_APPLICATION_ERROR(-20700, 'Create lot failed: ' || SQLERRM);
    END CREATE_LOT;

    PROCEDURE ISSUE_FROM_LOT(
        p_material_id        IN NUMBER,
        p_warehouse_id       IN NUMBER,
        p_qty_to_issue       IN NUMBER,
        p_reference_doc_type IN VARCHAR2,
        p_reference_doc_id   IN NUMBER,
        p_performed_by       IN VARCHAR2 DEFAULT USER,
        p_lot_id             IN NUMBER DEFAULT NULL
    ) IS
        v_remaining_qty NUMBER := p_qty_to_issue;
        v_issue_qty     NUMBER;
    BEGIN
        FOR lot IN (
            SELECT LOT_ID, LOT_NUMBER, QTY_AVAILABLE
            FROM LOT_MASTER
            WHERE MATERIAL_ID  = p_material_id
              AND WAREHOUSE_ID = p_warehouse_id
              AND STATUS       NOT IN ('CONSUMED','REJECTED','EXPIRED')
              AND QTY_AVAILABLE > 0
              AND (p_lot_id IS NULL OR LOT_ID = p_lot_id)
            ORDER BY RECEIPT_DATE ASC, LOT_ID ASC
        ) LOOP
            EXIT WHEN v_remaining_qty <= 0;

            v_issue_qty := LEAST(v_remaining_qty, lot.QTY_AVAILABLE);

            UPDATE LOT_MASTER
            SET QTY_AVAILABLE = QTY_AVAILABLE - v_issue_qty,
                QTY_CONSUMED  = QTY_CONSUMED  + v_issue_qty,
                STATUS = CASE
                    WHEN QTY_AVAILABLE - v_issue_qty <= 0 THEN 'CONSUMED'
                    ELSE 'PARTIALLY_USED' END
            WHERE LOT_ID = lot.LOT_ID;

            INSERT INTO LOT_TRANSACTION (
                LOT_ID, TRANSACTION_TYPE, QTY_CHANGE, QTY_AFTER,
                WAREHOUSE_ID, REFERENCE_DOC_TYPE, REFERENCE_DOC_ID,
                PERFORMED_BY
            ) VALUES (
                lot.LOT_ID, 'ISSUE', -v_issue_qty,
                lot.QTY_AVAILABLE - v_issue_qty,
                p_warehouse_id, p_reference_doc_type, p_reference_doc_id,
                p_performed_by
            );

            v_remaining_qty := v_remaining_qty - v_issue_qty;
        END LOOP;

        IF v_remaining_qty > 0 THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20701, 'Insufficient lot qty. Shortfall: ' || v_remaining_qty);
        END IF;
        COMMIT;
    END ISSUE_FROM_LOT;

    PROCEDURE TRANSFER_LOT(
        p_lot_id            IN NUMBER,
        p_qty               IN NUMBER,
        p_from_warehouse_id IN NUMBER,
        p_to_warehouse_id   IN NUMBER,
        p_to_bin_id         IN NUMBER DEFAULT NULL,
        p_performed_by      IN VARCHAR2 DEFAULT USER
    ) IS
        v_avail NUMBER;
    BEGIN
        SELECT QTY_AVAILABLE INTO v_avail FROM LOT_MASTER WHERE LOT_ID = p_lot_id;
        IF v_avail < p_qty THEN
            RAISE_APPLICATION_ERROR(-20702, 'Transfer qty exceeds available: ' || v_avail);
        END IF;

        UPDATE LOT_MASTER
        SET QTY_AVAILABLE = QTY_AVAILABLE - p_qty,
            WAREHOUSE_ID  = p_to_warehouse_id,
            BIN_ID        = p_to_bin_id
        WHERE LOT_ID = p_lot_id;

        INSERT INTO LOT_TRANSACTION (LOT_ID, TRANSACTION_TYPE, QTY_CHANGE, QTY_AFTER,
            WAREHOUSE_ID, BIN_ID, REFERENCE_DOC_TYPE, PERFORMED_BY)
        VALUES (p_lot_id, 'TRANSFER', 0, p_qty,
            p_to_warehouse_id, p_to_bin_id, 'TRANSFER', p_performed_by);

        COMMIT;
    END TRANSFER_LOT;

    PROCEDURE ASSIGN_SERIAL(
        p_serial_number  IN VARCHAR2, p_material_id IN NUMBER,
        p_lot_id         IN NUMBER DEFAULT NULL,
        p_warehouse_id   IN NUMBER, p_bin_id IN NUMBER DEFAULT NULL,
        p_po_id          IN NUMBER DEFAULT NULL,
        p_warrant_expiry IN DATE DEFAULT NULL
    ) IS
    BEGIN
        INSERT INTO SERIAL_MASTER (
            SERIAL_NUMBER, MATERIAL_ID, LOT_ID, SUPPLIER_ID,
            PO_ID, WAREHOUSE_ID, BIN_ID, STATUS,
            RECEIVED_DATE, WARRANT_EXPIRY
        )
        SELECT p_serial_number, p_material_id, p_lot_id, po.SUPPLIER_ID,
               p_po_id, p_warehouse_id, p_bin_id, 'IN_STOCK',
               TRUNC(SYSDATE), p_warrant_expiry
        FROM PURCHASE_ORDER po WHERE po.PO_ID = p_po_id
        UNION ALL
        SELECT p_serial_number, p_material_id, p_lot_id, NULL,
               p_po_id, p_warehouse_id, p_bin_id, 'IN_STOCK',
               TRUNC(SYSDATE), p_warrant_expiry
        FROM DUAL WHERE p_po_id IS NULL;

        COMMIT;
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20703,'Serial number already exists: '||p_serial_number);
    END ASSIGN_SERIAL;

    PROCEDURE ISSUE_SERIAL(
        p_serial_id          IN NUMBER,
        p_reference_doc_type IN VARCHAR2,
        p_reference_doc_id   IN NUMBER,
        p_performed_by       IN VARCHAR2 DEFAULT USER
    ) IS
        v_wh_id NUMBER;
        v_bn_id NUMBER;
    BEGIN
        SELECT WAREHOUSE_ID, BIN_ID INTO v_wh_id, v_bn_id
        FROM SERIAL_MASTER WHERE SERIAL_ID = p_serial_id AND STATUS = 'IN_STOCK';

        UPDATE SERIAL_MASTER
        SET STATUS = 'ISSUED', ISSUED_DATE = SYSDATE,
            WAREHOUSE_ID = NULL, BIN_ID = NULL
        WHERE SERIAL_ID = p_serial_id;

        INSERT INTO SERIAL_TRANSACTION (SERIAL_ID, TRANSACTION_TYPE,
            FROM_WAREHOUSE_ID, FROM_BIN_ID, REFERENCE_DOC_TYPE,
            REFERENCE_DOC_ID, PERFORMED_BY)
        VALUES (p_serial_id, 'ISSUE', v_wh_id, v_bn_id,
            p_reference_doc_type, p_reference_doc_id, p_performed_by);

        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20704, 'Serial not found or not IN_STOCK.');
    END ISSUE_SERIAL;

    FUNCTION GET_LOT_TRACEABILITY(p_lot_id IN NUMBER) RETURN CLOB IS
        v_json CLOB;
    BEGIN
        SELECT JSON_OBJECT(
            'lot_id'        VALUE l.LOT_ID,
            'lot_number'    VALUE l.LOT_NUMBER,
            'material_code' VALUE m.MATERIAL_CODE,
            'material_name' VALUE m.MATERIAL_NAME,
            'supplier_name' VALUE s.SUPPLIER_NAME,
            'heat_number'   VALUE l.HEAT_NUMBER,
            'mill_cert'     VALUE l.MILL_CERT_NUMBER,
            'country'       VALUE l.COUNTRY_OF_ORIGIN,
            'mill_name'     VALUE l.MILL_NAME,
            'qty_received'  VALUE l.QTY_RECEIVED,
            'qty_available' VALUE l.QTY_AVAILABLE,
            'qty_consumed'  VALUE l.QTY_CONSUMED,
            'qty_rejected'  VALUE l.QTY_REJECTED,
            'receipt_date'  VALUE TO_CHAR(l.RECEIPT_DATE,'DD-MON-YYYY'),
            'expiry_date'   VALUE TO_CHAR(l.EXPIRY_DATE,'DD-MON-YYYY'),
            'status'        VALUE l.STATUS,
            'transactions'  VALUE (
                SELECT JSON_ARRAYAGG(
                    JSON_OBJECT(
                        'type'     VALUE lt.TRANSACTION_TYPE,
                        'qty'      VALUE lt.QTY_CHANGE,
                        'date'     VALUE TO_CHAR(lt.TRANSACTION_DATE,'DD-MON-YYYY HH24:MI'),
                        'ref_type' VALUE lt.REFERENCE_DOC_TYPE,
                        'ref_id'   VALUE lt.REFERENCE_DOC_ID,
                        'by'       VALUE lt.PERFORMED_BY
                    ) ORDER BY lt.TRANSACTION_DATE
                )
                FROM LOT_TRANSACTION lt WHERE lt.LOT_ID = l.LOT_ID
            )
        )
        INTO v_json
        FROM LOT_MASTER l
        JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = l.MATERIAL_ID
        LEFT JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = l.SUPPLIER_ID
        WHERE l.LOT_ID = p_lot_id;

        RETURN NVL(v_json, '{}');
    EXCEPTION WHEN OTHERS THEN RETURN '{"error":"' || SQLERRM || '"}';
    END GET_LOT_TRACEABILITY;

    FUNCTION GET_EXPIRING_LOTS(p_days_ahead IN NUMBER DEFAULT 90) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT l.LOT_ID, l.LOT_NUMBER, m.MATERIAL_CODE, m.MATERIAL_NAME,
                   s.SUPPLIER_NAME, w.WAREHOUSE_NAME,
                   l.QTY_AVAILABLE, l.EXPIRY_DATE,
                   TRUNC(l.EXPIRY_DATE) - TRUNC(SYSDATE) AS DAYS_TO_EXPIRY,
                   l.STATUS
            FROM LOT_MASTER l
            JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = l.MATERIAL_ID
            LEFT JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = l.SUPPLIER_ID
            LEFT JOIN WAREHOUSE_MASTER w ON w.WAREHOUSE_ID = l.WAREHOUSE_ID
            WHERE l.EXPIRY_DATE IS NOT NULL
              AND l.EXPIRY_DATE BETWEEN TRUNC(SYSDATE) AND TRUNC(SYSDATE)+p_days_ahead
              AND l.STATUS NOT IN ('CONSUMED','REJECTED','EXPIRED')
              AND l.QTY_AVAILABLE > 0
            ORDER BY l.EXPIRY_DATE ASC;
        RETURN v_cur;
    END GET_EXPIRING_LOTS;

    FUNCTION GET_LOT_STATUS(p_lot_number IN VARCHAR2) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT l.LOT_ID, l.LOT_NUMBER, m.MATERIAL_CODE, m.MATERIAL_NAME,
                   s.SUPPLIER_NAME, l.HEAT_NUMBER, l.MILL_CERT_NUMBER,
                   l.COUNTRY_OF_ORIGIN, l.MILL_NAME,
                   l.QTY_RECEIVED, l.QTY_AVAILABLE, l.QTY_CONSUMED,
                   l.QTY_REJECTED, l.STATUS,
                   l.RECEIPT_DATE, l.EXPIRY_DATE,
                   w.WAREHOUSE_NAME, l.BIN_ID
            FROM LOT_MASTER l
            JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = l.MATERIAL_ID
            LEFT JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = l.SUPPLIER_ID
            LEFT JOIN WAREHOUSE_MASTER w ON w.WAREHOUSE_ID = l.WAREHOUSE_ID
            WHERE l.LOT_NUMBER = p_lot_number;
        RETURN v_cur;
    END GET_LOT_STATUS;

    FUNCTION GET_MATERIAL_LOTS(p_material_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT l.LOT_ID, l.LOT_NUMBER, s.SUPPLIER_NAME,
                   l.HEAT_NUMBER, l.QTY_RECEIVED, l.QTY_AVAILABLE,
                   l.QTY_CONSUMED, l.STATUS, l.RECEIPT_DATE, l.EXPIRY_DATE,
                   w.WAREHOUSE_NAME
            FROM LOT_MASTER l
            LEFT JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = l.SUPPLIER_ID
            LEFT JOIN WAREHOUSE_MASTER w ON w.WAREHOUSE_ID = l.WAREHOUSE_ID
            WHERE l.MATERIAL_ID = p_material_id
            ORDER BY l.RECEIPT_DATE DESC;
        RETURN v_cur;
    END GET_MATERIAL_LOTS;

    FUNCTION GET_SERIAL_HISTORY(p_serial_number IN VARCHAR2) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT sm.SERIAL_NUMBER, m.MATERIAL_CODE, m.MATERIAL_NAME,
                   sm.STATUS, sm.RECEIVED_DATE, sm.ISSUED_DATE,
                   sm.WARRANT_EXPIRY,
                   st.TRANSACTION_TYPE,
                   st.FROM_WAREHOUSE_ID, st.TO_WAREHOUSE_ID,
                   st.REFERENCE_DOC_TYPE, st.REFERENCE_DOC_ID,
                   st.TRANSACTION_DATE, st.PERFORMED_BY
            FROM SERIAL_MASTER sm
            JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = sm.MATERIAL_ID
            LEFT JOIN SERIAL_TRANSACTION st ON st.SERIAL_ID = sm.SERIAL_ID
            WHERE sm.SERIAL_NUMBER = p_serial_number
            ORDER BY st.TRANSACTION_DATE;
        RETURN v_cur;
    END GET_SERIAL_HISTORY;

    FUNCTION GET_LOT_REGISTER RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT l.LOT_ID, l.LOT_NUMBER,
                   m.MATERIAL_CODE, m.MATERIAL_NAME,
                   s.SUPPLIER_NAME, s.ADDRESS AS LOCATION,
                   l.HEAT_NUMBER, l.MILL_CERT_NUMBER,
                   l.QTY_RECEIVED, l.QTY_AVAILABLE, l.QTY_CONSUMED,
                   l.STATUS, l.RECEIPT_DATE, l.EXPIRY_DATE,
                   w.WAREHOUSE_NAME,
                   CASE WHEN l.EXPIRY_DATE < TRUNC(SYSDATE) THEN 'EXPIRED'
                        WHEN l.EXPIRY_DATE < TRUNC(SYSDATE)+30 THEN 'EXPIRING_30'
                        WHEN l.EXPIRY_DATE < TRUNC(SYSDATE)+90 THEN 'EXPIRING_90'
                        ELSE 'OK' END AS EXPIRY_STATUS
            FROM LOT_MASTER l
            JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = l.MATERIAL_ID
            LEFT JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = l.SUPPLIER_ID
            LEFT JOIN WAREHOUSE_MASTER w ON w.WAREHOUSE_ID = l.WAREHOUSE_ID
            ORDER BY l.STATUS, l.RECEIPT_DATE DESC;
        RETURN v_cur;
    END GET_LOT_REGISTER;

END PKG_LOT_SERIAL;
/
SHOW ERRORS PACKAGE BODY PKG_LOT_SERIAL;
