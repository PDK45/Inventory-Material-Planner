-- ============================================================
-- MPPMS :: 21_pkg_inventory.sql
-- Purpose : Complete Inventory & Goods Movement Logic (SAP MIGO)
-- Run As  : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Phase 13 - Creating PKG_INVENTORY Package
PROMPT ============================================================

CREATE OR REPLACE PACKAGE PKG_INVENTORY AS

    -- Goods Receipt against Purchase Order (Movement 101)
    PROCEDURE PROCESS_GOODS_RECEIPT(
        p_po_id          IN NUMBER,
        p_material_id    IN NUMBER,
        p_warehouse_id   IN NUMBER,
        p_bin_id         IN NUMBER,
        p_received_qty   IN NUMBER,
        p_performed_by   IN VARCHAR2,
        p_remarks        IN VARCHAR2,
        p_status         OUT VARCHAR2,
        p_message        OUT VARCHAR2
    );

    -- Goods Issue to Production Plan (Movement 261)
    PROCEDURE PROCESS_GOODS_ISSUE(
        p_plan_id        IN NUMBER,
        p_material_id    IN NUMBER,
        p_warehouse_id   IN NUMBER,
        p_bin_id         IN NUMBER,
        p_issue_qty      IN NUMBER,
        p_performed_by   IN VARCHAR2,
        p_remarks        IN VARCHAR2,
        p_status         OUT VARCHAR2,
        p_message        OUT VARCHAR2
    );

    -- Stock Transfer between Warehouses/Bins (Movement 311)
    PROCEDURE PROCESS_STOCK_TRANSFER(
        p_material_id    IN NUMBER,
        p_from_wh_id     IN NUMBER,
        p_from_bin_id    IN NUMBER,
        p_to_wh_id       IN NUMBER,
        p_to_bin_id      IN NUMBER,
        p_transfer_qty   IN NUMBER,
        p_performed_by   IN VARCHAR2,
        p_remarks        IN VARCHAR2,
        p_status         OUT VARCHAR2,
        p_message        OUT VARCHAR2
    );

    -- Physical Inventory Count Adjustment (Movement 551)
    PROCEDURE PROCESS_STOCK_ADJUSTMENT(
        p_material_id    IN NUMBER,
        p_warehouse_id   IN NUMBER,
        p_bin_id         IN NUMBER,
        p_new_qty_on_hand IN NUMBER,
        p_performed_by   IN VARCHAR2,
        p_remarks        IN VARCHAR2,
        p_status         OUT VARCHAR2,
        p_message        OUT VARCHAR2
    );

    -- Helper functions
    FUNCTION GET_TOTAL_AVAILABLE_STOCK(p_material_id IN NUMBER) RETURN NUMBER;
    FUNCTION GET_STOCK_VALUE(p_material_id IN NUMBER DEFAULT NULL) RETURN NUMBER;
    FUNCTION GET_LOW_STOCK_COUNT RETURN NUMBER;

END PKG_INVENTORY;
/

CREATE OR REPLACE PACKAGE BODY PKG_INVENTORY AS

    -- ------------------------------------------------------------
    -- Helper: Upsert Inventory Balance
    -- ------------------------------------------------------------
    PROCEDURE UPSERT_BALANCE(
        p_material_id  IN NUMBER,
        p_warehouse_id IN NUMBER,
        p_bin_id       IN NUMBER,
        p_delta_qty    IN NUMBER,
        p_stock_type   IN VARCHAR2 DEFAULT 'ON_HAND'
    ) IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_count
          FROM INVENTORY_BALANCE
         WHERE MATERIAL_ID = p_material_id
           AND WAREHOUSE_ID = p_warehouse_id
           AND BIN_ID = p_bin_id;

        IF v_count = 0 THEN
            INSERT INTO INVENTORY_BALANCE (
                MATERIAL_ID, WAREHOUSE_ID, BIN_ID,
                QTY_ON_HAND, QTY_RESERVED, QTY_IN_QUALITY, QTY_BLOCKED
            ) VALUES (
                p_material_id, p_warehouse_id, p_bin_id,
                CASE WHEN p_stock_type = 'ON_HAND' THEN GREATEST(0, p_delta_qty) ELSE 0 END,
                CASE WHEN p_stock_type = 'RESERVED' THEN GREATEST(0, p_delta_qty) ELSE 0 END,
                CASE WHEN p_stock_type = 'QUALITY' THEN GREATEST(0, p_delta_qty) ELSE 0 END,
                CASE WHEN p_stock_type = 'BLOCKED' THEN GREATEST(0, p_delta_qty) ELSE 0 END
            );
        ELSE
            IF p_stock_type = 'ON_HAND' THEN
                UPDATE INVENTORY_BALANCE
                   SET QTY_ON_HAND = GREATEST(0, QTY_ON_HAND + p_delta_qty),
                       LAST_UPDATED_DATE = SYSDATE
                 WHERE MATERIAL_ID = p_material_id AND WAREHOUSE_ID = p_warehouse_id AND BIN_ID = p_bin_id;
            ELSIF p_stock_type = 'RESERVED' THEN
                UPDATE INVENTORY_BALANCE
                   SET QTY_RESERVED = GREATEST(0, QTY_RESERVED + p_delta_qty),
                       LAST_UPDATED_DATE = SYSDATE
                 WHERE MATERIAL_ID = p_material_id AND WAREHOUSE_ID = p_warehouse_id AND BIN_ID = p_bin_id;
            END IF;
        END IF;
    END UPSERT_BALANCE;

    -- ------------------------------------------------------------
    -- 1. PROCESS_GOODS_RECEIPT (Movement 101)
    -- ------------------------------------------------------------
    PROCEDURE PROCESS_GOODS_RECEIPT(
        p_po_id          IN NUMBER,
        p_material_id    IN NUMBER,
        p_warehouse_id   IN NUMBER,
        p_bin_id         IN NUMBER,
        p_received_qty   IN NUMBER,
        p_performed_by   IN VARCHAR2,
        p_remarks        IN VARCHAR2,
        p_status         OUT VARCHAR2,
        p_message        OUT VARCHAR2
    ) IS
        v_po_status     VARCHAR2(25);
        v_unreceived    NUMBER;
    BEGIN
        IF p_received_qty <= 0 THEN
            p_status := 'ERROR';
            p_message := 'Received quantity must be greater than zero.';
            RETURN;
        END IF;

        -- 1. Check PO status
        SELECT ORDER_STATUS INTO v_po_status
          FROM PURCHASE_ORDER WHERE PO_ID = p_po_id;

        IF v_po_status IN ('CANCELLED') THEN
            p_status := 'ERROR';
            p_message := 'Cannot receive items against a CANCELLED Purchase Order.';
            RETURN;
        END IF;

        -- 2. Update stock balance
        UPSERT_BALANCE(p_material_id, p_warehouse_id, p_bin_id, p_received_qty, 'ON_HAND');

        -- 3. Log Goods Receipt transaction
        INSERT INTO INVENTORY_TRANSACTION (
            MOVEMENT_CODE, TRANSACTION_TYPE, MATERIAL_ID, WAREHOUSE_ID, BIN_ID,
            QUANTITY, REFERENCE_TYPE, REFERENCE_ID, PERFORMED_BY, REMARKS
        ) VALUES (
            '101', 'GOODS_RECEIPT', p_material_id, p_warehouse_id, p_bin_id,
            p_received_qty, 'PO', p_po_id, p_performed_by, NVL(p_remarks, 'PO Receipt (MIGO 101)')
        );

        -- 4. Update PO Item received quantity
        UPDATE PURCHASE_ORDER_ITEMS
           SET RECEIVED_QTY = NVL(RECEIVED_QTY, 0) + p_received_qty
         WHERE PO_ID = p_po_id AND MATERIAL_ID = p_material_id;

        -- 5. Check if all items on PO are received
        SELECT COUNT(*) INTO v_unreceived
          FROM PURCHASE_ORDER_ITEMS
         WHERE PO_ID = p_po_id
           AND NVL(RECEIVED_QTY,0) < ORDERED_QTY;

        IF v_unreceived = 0 THEN
            UPDATE PURCHASE_ORDER
               SET ORDER_STATUS = 'RECEIVED'
             WHERE PO_ID = p_po_id;

            UPDATE PROCUREMENT_TRACKING
               SET DELIVERY_STATUS = 'DELIVERED',
                   ACTUAL_DATE = SYSDATE,
                   REMARKS = 'Goods receipt completed in warehouse'
             WHERE PO_ID = p_po_id;
        ELSE
            UPDATE PURCHASE_ORDER
               SET ORDER_STATUS = 'PARTIALLY_RECEIVED'
             WHERE PO_ID = p_po_id;
        END IF;

        COMMIT;
        p_status := 'SUCCESS';
        p_message := 'Goods Receipt of ' || p_received_qty || ' units logged successfully.';
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_status := 'ERROR';
            p_message := 'Error in PROCESS_GOODS_RECEIPT: ' || SQLERRM;
    END PROCESS_GOODS_RECEIPT;

    -- ------------------------------------------------------------
    -- 2. PROCESS_GOODS_ISSUE (Movement 261)
    -- ------------------------------------------------------------
    PROCEDURE PROCESS_GOODS_ISSUE(
        p_plan_id        IN NUMBER,
        p_material_id    IN NUMBER,
        p_warehouse_id   IN NUMBER,
        p_bin_id         IN NUMBER,
        p_issue_qty      IN NUMBER,
        p_performed_by   IN VARCHAR2,
        p_remarks        IN VARCHAR2,
        p_status         OUT VARCHAR2,
        p_message        OUT VARCHAR2
    ) IS
        v_current_stock NUMBER := 0;
    BEGIN
        IF p_issue_qty <= 0 THEN
            p_status := 'ERROR';
            p_message := 'Issue quantity must be greater than zero.';
            RETURN;
        END IF;

        -- Check stock availability
        SELECT NVL(QTY_ON_HAND, 0) INTO v_current_stock
          FROM INVENTORY_BALANCE
         WHERE MATERIAL_ID = p_material_id AND WAREHOUSE_ID = p_warehouse_id AND BIN_ID = p_bin_id;

        IF v_current_stock < p_issue_qty THEN
            p_status := 'ERROR';
            p_message := 'Insufficient stock. On-hand: ' || v_current_stock || ', Requested: ' || p_issue_qty;
            RETURN;
        END IF;

        -- Reduce stock balance
        UPSERT_BALANCE(p_material_id, p_warehouse_id, p_bin_id, -p_issue_qty, 'ON_HAND');

        -- Log transaction
        INSERT INTO INVENTORY_TRANSACTION (
            MOVEMENT_CODE, TRANSACTION_TYPE, MATERIAL_ID, WAREHOUSE_ID, BIN_ID,
            QUANTITY, REFERENCE_TYPE, REFERENCE_ID, PERFORMED_BY, REMARKS
        ) VALUES (
            '261', 'GOODS_ISSUE', p_material_id, p_warehouse_id, p_bin_id,
            p_issue_qty, 'PRODUCTION_PLAN', p_plan_id, p_performed_by, NVL(p_remarks, 'Issue to Production (MIGO 261)')
        );

        COMMIT;
        p_status := 'SUCCESS';
        p_message := 'Goods Issue of ' || p_issue_qty || ' units logged successfully.';
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_status := 'ERROR';
            p_message := 'Error in PROCESS_GOODS_ISSUE: ' || SQLERRM;
    END PROCESS_GOODS_ISSUE;

    -- ------------------------------------------------------------
    -- 3. PROCESS_STOCK_TRANSFER (Movement 311)
    -- ------------------------------------------------------------
    PROCEDURE PROCESS_STOCK_TRANSFER(
        p_material_id    IN NUMBER,
        p_from_wh_id     IN NUMBER,
        p_from_bin_id    IN NUMBER,
        p_to_wh_id       IN NUMBER,
        p_to_bin_id      IN NUMBER,
        p_transfer_qty   IN NUMBER,
        p_performed_by   IN VARCHAR2,
        p_remarks        IN VARCHAR2,
        p_status         OUT VARCHAR2,
        p_message        OUT VARCHAR2
    ) IS
        v_current_stock NUMBER := 0;
    BEGIN
        IF p_transfer_qty <= 0 THEN
            p_status := 'ERROR';
            p_message := 'Transfer quantity must be greater than zero.';
            RETURN;
        END IF;

        SELECT NVL(QTY_ON_HAND, 0) INTO v_current_stock
          FROM INVENTORY_BALANCE
         WHERE MATERIAL_ID = p_material_id AND WAREHOUSE_ID = p_from_wh_id AND BIN_ID = p_from_bin_id;

        IF v_current_stock < p_transfer_qty THEN
            p_status := 'ERROR';
            p_message := 'Insufficient stock at source bin. On-hand: ' || v_current_stock;
            RETURN;
        END IF;

        -- Deduct from source bin
        UPSERT_BALANCE(p_material_id, p_from_wh_id, p_from_bin_id, -p_transfer_qty, 'ON_HAND');
        -- Add to target bin
        UPSERT_BALANCE(p_material_id, p_to_wh_id, p_to_bin_id, p_transfer_qty, 'ON_HAND');

        -- Log transaction
        INSERT INTO INVENTORY_TRANSACTION (
            MOVEMENT_CODE, TRANSACTION_TYPE, MATERIAL_ID, WAREHOUSE_ID, BIN_ID,
            QUANTITY, REFERENCE_TYPE, PERFORMED_BY, REMARKS
        ) VALUES (
            '311', 'TRANSFER', p_material_id, p_from_wh_id, p_from_bin_id,
            p_transfer_qty, 'INTERNAL_TRANSFER', p_performed_by, NVL(p_remarks, 'Stock Transfer (MIGO 311)')
        );

        COMMIT;
        p_status := 'SUCCESS';
        p_message := 'Transferred ' || p_transfer_qty || ' units successfully.';
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_status := 'ERROR';
            p_message := 'Error in PROCESS_STOCK_TRANSFER: ' || SQLERRM;
    END PROCESS_STOCK_TRANSFER;

    -- ------------------------------------------------------------
    -- 4. PROCESS_STOCK_ADJUSTMENT (Movement 551)
    -- ------------------------------------------------------------
    PROCEDURE PROCESS_STOCK_ADJUSTMENT(
        p_material_id    IN NUMBER,
        p_warehouse_id   IN NUMBER,
        p_bin_id         IN NUMBER,
        p_new_qty_on_hand IN NUMBER,
        p_performed_by   IN VARCHAR2,
        p_remarks        IN VARCHAR2,
        p_status         OUT VARCHAR2,
        p_message        OUT VARCHAR2
    ) IS
        v_old_qty NUMBER := 0;
        v_diff    NUMBER := 0;
    BEGIN
        BEGIN
            SELECT NVL(QTY_ON_HAND, 0) INTO v_old_qty
              FROM INVENTORY_BALANCE
             WHERE MATERIAL_ID = p_material_id AND WAREHOUSE_ID = p_warehouse_id AND BIN_ID = p_bin_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_old_qty := 0;
        END;

        v_diff := p_new_qty_on_hand - v_old_qty;

        UPSERT_BALANCE(p_material_id, p_warehouse_id, p_bin_id, v_diff, 'ON_HAND');

        INSERT INTO INVENTORY_TRANSACTION (
            MOVEMENT_CODE, TRANSACTION_TYPE, MATERIAL_ID, WAREHOUSE_ID, BIN_ID,
            QUANTITY, REFERENCE_TYPE, PERFORMED_BY, REMARKS
        ) VALUES (
            '551', 'ADJUSTMENT', p_material_id, p_warehouse_id, p_bin_id,
            ABS(v_diff), 'CYCLE_COUNT', p_performed_by, NVL(p_remarks, 'Stock Adjustment from ' || v_old_qty || ' to ' || p_new_qty_on_hand)
        );

        COMMIT;
        p_status := 'SUCCESS';
        p_message := 'Stock adjusted to ' || p_new_qty_on_hand || ' units.';
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_status := 'ERROR';
            p_message := 'Error in PROCESS_STOCK_ADJUSTMENT: ' || SQLERRM;
    END PROCESS_STOCK_ADJUSTMENT;

    -- ------------------------------------------------------------
    -- HELPER FUNCTIONS
    -- ------------------------------------------------------------
    FUNCTION GET_TOTAL_AVAILABLE_STOCK(p_material_id IN NUMBER) RETURN NUMBER IS
        v_stock NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(QTY_ON_HAND - QTY_RESERVED), 0) INTO v_stock
          FROM INVENTORY_BALANCE
         WHERE MATERIAL_ID = p_material_id;
        RETURN GREATEST(0, v_stock);
    EXCEPTION
        WHEN OTHERS THEN RETURN 0;
    END GET_TOTAL_AVAILABLE_STOCK;

    FUNCTION GET_STOCK_VALUE(p_material_id IN NUMBER DEFAULT NULL) RETURN NUMBER IS
        v_val NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(ib.QTY_ON_HAND * m.STANDARD_COST), 0) INTO v_val
          FROM INVENTORY_BALANCE ib
          JOIN MATERIAL_MASTER   m ON m.MATERIAL_ID = ib.MATERIAL_ID
         WHERE (p_material_id IS NULL OR ib.MATERIAL_ID = p_material_id);
        RETURN v_val;
    EXCEPTION
        WHEN OTHERS THEN RETURN 0;
    END GET_STOCK_VALUE;

    FUNCTION GET_LOW_STOCK_COUNT RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(DISTINCT m.MATERIAL_ID) INTO v_count
          FROM MATERIAL_MASTER m
          LEFT JOIN (
              SELECT MATERIAL_ID, SUM(QTY_ON_HAND) AS TOTAL_STOCK
              FROM INVENTORY_BALANCE
              GROUP BY MATERIAL_ID
          ) ib ON ib.MATERIAL_ID = m.MATERIAL_ID
         WHERE NVL(ib.TOTAL_STOCK, 0) < NVL(m.REORDER_LEVEL, 0);
        RETURN v_count;
    EXCEPTION
        WHEN OTHERS THEN RETURN 0;
    END GET_LOW_STOCK_COUNT;

END PKG_INVENTORY;
/

PROMPT [SUCCESS] Package PKG_INVENTORY compiled successfully.
