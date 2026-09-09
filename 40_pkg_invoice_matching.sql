-- ============================================================
-- MPPMS :: 40_pkg_invoice_matching.sql (FIXED SCHEMA)
-- Purpose : 3-Way AP Invoice Matching Engine
-- Run As  : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

CREATE OR REPLACE PACKAGE PKG_INVOICE_MATCHING AS
    c_PRICE_TOLERANCE_PCT  CONSTANT NUMBER := 2.0;
    c_QTY_TOLERANCE_PCT    CONSTANT NUMBER := 0.0;

    FUNCTION CREATE_INVOICE(
        p_supplier_id    IN NUMBER,
        p_invoice_number IN VARCHAR2,
        p_invoice_date   IN DATE,
        p_currency_code  IN VARCHAR2 DEFAULT 'SAR',
        p_term_code      IN VARCHAR2 DEFAULT 'NET30',
        p_notes          IN VARCHAR2 DEFAULT NULL
    ) RETURN NUMBER;

    PROCEDURE ADD_INVOICE_LINE(
        p_invoice_id    IN NUMBER,
        p_po_id         IN NUMBER,
        p_po_line_id    IN NUMBER,
        p_invoiced_qty  IN NUMBER,
        p_unit_price    IN NUMBER,
        p_tax_pct       IN NUMBER DEFAULT 15
    );

    PROCEDURE PERFORM_3WAY_MATCH(
        p_invoice_id IN NUMBER,
        p_matched_by IN VARCHAR2 DEFAULT USER
    );

    PROCEDURE APPROVE_INVOICE(
        p_invoice_id  IN NUMBER,
        p_approved_by IN VARCHAR2 DEFAULT USER
    );

    PROCEDURE REJECT_INVOICE(
        p_invoice_id IN NUMBER,
        p_reason     IN VARCHAR2,
        p_rejected_by IN VARCHAR2 DEFAULT USER
    );

    PROCEDURE MARK_PAID(
        p_invoice_id        IN NUMBER,
        p_payment_reference IN VARCHAR2,
        p_paid_date         IN DATE DEFAULT TRUNC(SYSDATE)
    );

    FUNCTION GET_MATCHING_DASHBOARD RETURN SYS_REFCURSOR;

    FUNCTION GET_AP_AGEING RETURN SYS_REFCURSOR;

    FUNCTION GET_SUPPLIER_INVOICES(p_supplier_id IN NUMBER DEFAULT NULL) RETURN SYS_REFCURSOR;
END PKG_INVOICE_MATCHING;
/

CREATE OR REPLACE PACKAGE BODY PKG_INVOICE_MATCHING AS

    FUNCTION CREATE_INVOICE(
        p_supplier_id    IN NUMBER,
        p_invoice_number IN VARCHAR2,
        p_invoice_date   IN DATE,
        p_currency_code  IN VARCHAR2 DEFAULT 'SAR',
        p_term_code      IN VARCHAR2 DEFAULT 'NET30',
        p_notes          IN VARCHAR2 DEFAULT NULL
    ) RETURN NUMBER IS
        v_invoice_id  NUMBER;
        v_term_id     NUMBER;
        v_net_days    NUMBER := 30;
        v_exch_rate   NUMBER := 1;
    BEGIN
        BEGIN
            SELECT TERM_ID, NET_DAYS INTO v_term_id, v_net_days
            FROM PAYMENT_TERM WHERE TERM_CODE = p_term_code;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            SELECT TERM_ID, NET_DAYS INTO v_term_id, v_net_days
            FROM PAYMENT_TERM WHERE TERM_CODE = 'NET30';
        END;

        BEGIN
            SELECT RATE INTO v_exch_rate
            FROM EXCHANGE_RATE
            WHERE FROM_CURRENCY = p_currency_code
              AND TO_CURRENCY   = 'INR'
              AND RATE_DATE = (SELECT MAX(RATE_DATE) FROM EXCHANGE_RATE
                               WHERE FROM_CURRENCY = p_currency_code
                                 AND TO_CURRENCY = 'INR');
        EXCEPTION WHEN OTHERS THEN v_exch_rate := 1;
        END;

        INSERT INTO SUPPLIER_INVOICE (
            INVOICE_NUMBER, SUPPLIER_ID, INVOICE_DATE, DUE_DATE,
            CURRENCY_CODE, EXCHANGE_RATE, PAYMENT_TERM_ID,
            STATUS, MATCH_STATUS, NOTES
        ) VALUES (
            p_invoice_number, p_supplier_id, TRUNC(p_invoice_date),
            TRUNC(p_invoice_date) + v_net_days,
            p_currency_code, v_exch_rate, v_term_id,
            'SUBMITTED', 'UNMATCHED', p_notes
        ) RETURNING INVOICE_ID INTO v_invoice_id;

        COMMIT;
        RETURN v_invoice_id;
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20400, 'Invoice ' || p_invoice_number || ' already exists for this supplier.');
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20401, 'Create invoice failed: ' || SQLERRM);
    END CREATE_INVOICE;

    PROCEDURE ADD_INVOICE_LINE(
        p_invoice_id    IN NUMBER,
        p_po_id         IN NUMBER,
        p_po_line_id    IN NUMBER,
        p_invoiced_qty  IN NUMBER,
        p_unit_price    IN NUMBER,
        p_tax_pct       IN NUMBER DEFAULT 15
    ) IS
        v_line_num    NUMBER;
        v_currency    VARCHAR2(3);
        v_material_id NUMBER;
        v_uom         VARCHAR2(10);
        v_line_amt    NUMBER;
        v_tax_amt     NUMBER;
    BEGIN
        SELECT CURRENCY_CODE INTO v_currency
        FROM SUPPLIER_INVOICE WHERE INVOICE_ID = p_invoice_id;

        BEGIN
            SELECT poi.MATERIAL_ID, mm.UNIT_OF_MEASURE
            INTO v_material_id, v_uom
            FROM PURCHASE_ORDER_ITEMS poi
            JOIN MATERIAL_MASTER mm ON mm.MATERIAL_ID = poi.MATERIAL_ID
            WHERE poi.PO_ITEM_ID = p_po_line_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            v_material_id := NULL; v_uom := NULL;
        END;

        SELECT NVL(MAX(LINE_NUMBER),0)+1 INTO v_line_num
        FROM INVOICE_LINE WHERE INVOICE_ID = p_invoice_id;

        v_line_amt := ROUND(p_invoiced_qty * p_unit_price, 2);
        v_tax_amt  := ROUND(v_line_amt * p_tax_pct / 100, 2);

        INSERT INTO INVOICE_LINE (
            INVOICE_ID, LINE_NUMBER, PO_ID, PO_LINE_ID, MATERIAL_ID,
            INVOICED_QTY, UNIT_OF_MEASURE, INVOICED_UNIT_PRICE,
            LINE_AMOUNT, CURRENCY_CODE, TAX_PCT, TAX_AMOUNT, MATCH_STATUS
        ) VALUES (
            p_invoice_id, v_line_num, p_po_id, p_po_line_id, v_material_id,
            p_invoiced_qty, v_uom, p_unit_price,
            v_line_amt, v_currency, p_tax_pct, v_tax_amt, 'UNMATCHED'
        );

        UPDATE SUPPLIER_INVOICE
        SET SUBTOTAL_AMOUNT = (SELECT NVL(SUM(LINE_AMOUNT),0) FROM INVOICE_LINE WHERE INVOICE_ID = p_invoice_id),
            TAX_AMOUNT      = (SELECT NVL(SUM(TAX_AMOUNT),0)  FROM INVOICE_LINE WHERE INVOICE_ID = p_invoice_id),
            TOTAL_AMOUNT    = (SELECT NVL(SUM(LINE_AMOUNT+TAX_AMOUNT),0) FROM INVOICE_LINE WHERE INVOICE_ID = p_invoice_id),
            TOTAL_AMOUNT_INR = (SELECT NVL(SUM(LINE_AMOUNT+TAX_AMOUNT),0) FROM INVOICE_LINE WHERE INVOICE_ID = p_invoice_id)
                               * EXCHANGE_RATE
        WHERE INVOICE_ID = p_invoice_id;

        COMMIT;
    END ADD_INVOICE_LINE;

    PROCEDURE PERFORM_3WAY_MATCH(
        p_invoice_id IN NUMBER,
        p_matched_by IN VARCHAR2 DEFAULT USER
    ) IS
        v_all_matched       BOOLEAN := TRUE;
        v_any_variance      BOOLEAN := FALSE;
        v_qty_var           NUMBER;
        v_price_var         NUMBER;
        v_qty_var_pct       NUMBER;
        v_price_var_pct     NUMBER;
        v_match_status      VARCHAR2(30);
        v_gr_qty            NUMBER;
        v_gr_txn_id         NUMBER;
        v_po_agreed_price   NUMBER;
        v_po_qty            NUMBER;
    BEGIN
        DELETE FROM INVOICE_MATCH WHERE INVOICE_ID = p_invoice_id;

        FOR il IN (SELECT * FROM INVOICE_LINE WHERE INVOICE_ID = p_invoice_id) LOOP

            BEGIN
                SELECT UNIT_PRICE, ORDERED_QTY INTO v_po_agreed_price, v_po_qty
                FROM PURCHASE_ORDER_ITEMS WHERE PO_ITEM_ID = il.PO_LINE_ID;
            EXCEPTION WHEN OTHERS THEN
                v_po_agreed_price := 0; v_po_qty := 0;
            END;

            BEGIN
                SELECT NVL(SUM(CASE WHEN TRANSACTION_TYPE IN ('RECEIPT','GR') THEN QUANTITY ELSE 0 END), 0),
                       MAX(TRANSACTION_ID)
                INTO v_gr_qty, v_gr_txn_id
                FROM INVENTORY_TRANSACTION
                WHERE REFERENCE_ID = il.PO_ID
                  AND MATERIAL_ID = il.MATERIAL_ID;
            EXCEPTION WHEN OTHERS THEN
                v_gr_qty := 0; v_gr_txn_id := NULL;
            END;

            v_qty_var       := v_gr_qty - il.INVOICED_QTY;
            v_price_var     := il.INVOICED_UNIT_PRICE - v_po_agreed_price;
            v_qty_var_pct   := CASE WHEN v_gr_qty > 0
                               THEN ROUND(ABS(v_qty_var/v_gr_qty)*100, 3) ELSE 100 END;
            v_price_var_pct := CASE WHEN v_po_agreed_price > 0
                               THEN ROUND(ABS(v_price_var/v_po_agreed_price)*100, 3) ELSE 100 END;

            IF v_qty_var_pct <= c_QTY_TOLERANCE_PCT
               AND v_price_var_pct <= c_PRICE_TOLERANCE_PCT THEN
                v_match_status := 'MATCHED';
            ELSIF v_qty_var_pct > c_QTY_TOLERANCE_PCT
               AND v_price_var_pct > c_PRICE_TOLERANCE_PCT THEN
                v_match_status := 'BOTH_VARIANCE';
                v_any_variance := TRUE; v_all_matched := FALSE;
            ELSIF v_qty_var_pct > c_QTY_TOLERANCE_PCT THEN
                v_match_status := 'QTY_VARIANCE';
                v_any_variance := TRUE; v_all_matched := FALSE;
            ELSE
                v_match_status := 'PRICE_VARIANCE';
                v_any_variance := TRUE; v_all_matched := FALSE;
            END IF;

            INSERT INTO INVOICE_MATCH (
                INVOICE_ID, INVOICE_LINE_ID, PO_ID, PO_LINE_ID, GR_TRANSACTION_ID,
                PO_AGREED_PRICE, PO_QTY, GR_QTY_RECEIVED,
                INVOICE_QTY, INVOICE_UNIT_PRICE,
                QTY_VARIANCE, PRICE_VARIANCE, QTY_VARIANCE_PCT, PRICE_VARIANCE_PCT,
                MATCH_STATUS,
                TOLERANCE_APPLIED,
                MATCHED_DATE, MATCHED_BY
            ) VALUES (
                p_invoice_id, il.LINE_ID, il.PO_ID, il.PO_LINE_ID, v_gr_txn_id,
                v_po_agreed_price, v_po_qty, v_gr_qty,
                il.INVOICED_QTY, il.INVOICED_UNIT_PRICE,
                v_qty_var, v_price_var, v_qty_var_pct, v_price_var_pct,
                v_match_status,
                CASE WHEN v_match_status='MATCHED' AND v_price_var_pct > 0 THEN 'Y' ELSE 'N' END,
                SYSDATE, p_matched_by
            );

            UPDATE INVOICE_LINE SET MATCH_STATUS = v_match_status
            WHERE LINE_ID = il.LINE_ID;
        END LOOP;

        UPDATE SUPPLIER_INVOICE
        SET MATCH_STATUS = CASE
                WHEN v_all_matched  THEN 'MATCHED'
                WHEN v_any_variance THEN 'VARIANCE_FLAGGED'
                ELSE 'PARTIAL_MATCH' END,
            STATUS = CASE
                WHEN v_all_matched  THEN 'APPROVED'
                ELSE 'IN_REVIEW' END
        WHERE INVOICE_ID = p_invoice_id;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK;
            RAISE_APPLICATION_ERROR(-20402, '3-way match failed: ' || SQLERRM);
    END PERFORM_3WAY_MATCH;

    PROCEDURE APPROVE_INVOICE(p_invoice_id IN NUMBER, p_approved_by IN VARCHAR2 DEFAULT USER) IS
    BEGIN
        UPDATE SUPPLIER_INVOICE
        SET STATUS = 'APPROVED', APPROVED_BY = p_approved_by, APPROVED_DATE = SYSDATE,
            MATCH_STATUS = 'OVERRIDE_APPROVED'
        WHERE INVOICE_ID = p_invoice_id;
        COMMIT;
    END APPROVE_INVOICE;

    PROCEDURE REJECT_INVOICE(p_invoice_id IN NUMBER, p_reason IN VARCHAR2,
                             p_rejected_by IN VARCHAR2 DEFAULT USER) IS
    BEGIN
        UPDATE SUPPLIER_INVOICE
        SET STATUS = 'REJECTED', NOTES = NVL(NOTES,'') || ' | REJECTED BY ' || p_rejected_by || ': ' || p_reason
        WHERE INVOICE_ID = p_invoice_id;
        COMMIT;
    END REJECT_INVOICE;

    PROCEDURE MARK_PAID(p_invoice_id IN NUMBER, p_payment_reference IN VARCHAR2,
                        p_paid_date IN DATE DEFAULT TRUNC(SYSDATE)) IS
    BEGIN
        UPDATE SUPPLIER_INVOICE
        SET STATUS = 'PAID', PAID_DATE = p_paid_date,
            PAYMENT_REFERENCE = p_payment_reference
        WHERE INVOICE_ID = p_invoice_id AND STATUS = 'APPROVED';
        COMMIT;
    END MARK_PAID;

    FUNCTION GET_MATCHING_DASHBOARD RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT
                COUNT(*) AS TOTAL_INVOICES,
                SUM(CASE WHEN STATUS='APPROVED' AND MATCH_STATUS='MATCHED'    THEN 1 ELSE 0 END) AS CLEAN_MATCHED,
                SUM(CASE WHEN MATCH_STATUS='VARIANCE_FLAGGED'                  THEN 1 ELSE 0 END) AS WITH_VARIANCE,
                SUM(CASE WHEN STATUS='IN_REVIEW'                               THEN 1 ELSE 0 END) AS PENDING_REVIEW,
                SUM(CASE WHEN STATUS='APPROVED'                                THEN 1 ELSE 0 END) AS APPROVED,
                SUM(CASE WHEN STATUS='PAID'                                    THEN 1 ELSE 0 END) AS PAID,
                SUM(CASE WHEN STATUS NOT IN ('PAID','CANCELLED') THEN TOTAL_AMOUNT_INR ELSE 0 END) AS OPEN_LIABILITY_INR,
                SUM(CASE WHEN DUE_DATE < TRUNC(SYSDATE) AND STATUS NOT IN ('PAID','CANCELLED')
                         THEN TOTAL_AMOUNT_INR ELSE 0 END) AS OVERDUE_AMOUNT_INR
            FROM SUPPLIER_INVOICE;
        RETURN v_cur;
    END GET_MATCHING_DASHBOARD;

    FUNCTION GET_AP_AGEING RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT s.SUPPLIER_NAME, s.SUPPLIER_CODE,
                   inv.CURRENCY_CODE,
                   SUM(CASE WHEN TRUNC(SYSDATE)-TRUNC(inv.DUE_DATE) <= 0
                            THEN inv.TOTAL_AMOUNT ELSE 0 END) AS CURRENT_AMT,
                   SUM(CASE WHEN TRUNC(SYSDATE)-TRUNC(inv.DUE_DATE) BETWEEN 1  AND 30
                            THEN inv.TOTAL_AMOUNT ELSE 0 END) AS OVERDUE_1_30,
                   SUM(CASE WHEN TRUNC(SYSDATE)-TRUNC(inv.DUE_DATE) BETWEEN 31 AND 60
                            THEN inv.TOTAL_AMOUNT ELSE 0 END) AS OVERDUE_31_60,
                   SUM(CASE WHEN TRUNC(SYSDATE)-TRUNC(inv.DUE_DATE) BETWEEN 61 AND 90
                            THEN inv.TOTAL_AMOUNT ELSE 0 END) AS OVERDUE_61_90,
                   SUM(CASE WHEN TRUNC(SYSDATE)-TRUNC(inv.DUE_DATE) > 90
                            THEN inv.TOTAL_AMOUNT ELSE 0 END) AS OVERDUE_90_PLUS,
                   SUM(inv.TOTAL_AMOUNT) AS TOTAL_OUTSTANDING
            FROM SUPPLIER_INVOICE inv
            JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = inv.SUPPLIER_ID
            WHERE inv.STATUS NOT IN ('PAID','CANCELLED','REJECTED')
            GROUP BY s.SUPPLIER_NAME, s.SUPPLIER_CODE, inv.CURRENCY_CODE
            ORDER BY TOTAL_OUTSTANDING DESC;
        RETURN v_cur;
    END GET_AP_AGEING;

    FUNCTION GET_SUPPLIER_INVOICES(p_supplier_id IN NUMBER DEFAULT NULL) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT inv.INVOICE_ID, inv.INVOICE_NUMBER,
                   s.SUPPLIER_NAME, s.SUPPLIER_CODE,
                   inv.INVOICE_DATE, inv.DUE_DATE,
                   inv.CURRENCY_CODE, inv.TOTAL_AMOUNT, inv.TOTAL_AMOUNT_INR,
                   inv.STATUS, inv.MATCH_STATUS,
                   TRUNC(SYSDATE) - TRUNC(inv.DUE_DATE) AS DAYS_OVERDUE,
                   pt.TERM_NAME
            FROM SUPPLIER_INVOICE inv
            JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = inv.SUPPLIER_ID
            LEFT JOIN PAYMENT_TERM pt ON pt.TERM_ID = inv.PAYMENT_TERM_ID
            WHERE (p_supplier_id IS NULL OR inv.SUPPLIER_ID = p_supplier_id)
            ORDER BY inv.INVOICE_DATE DESC;
        RETURN v_cur;
    END GET_SUPPLIER_INVOICES;

END PKG_INVOICE_MATCHING;
/
SHOW ERRORS PACKAGE BODY PKG_INVOICE_MATCHING;
