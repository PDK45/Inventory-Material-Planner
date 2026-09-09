-- ============================================================
-- MPPMS :: 22b_test_inventory.sql
-- Purpose : Comprehensive unit testing for PKG_INVENTORY Goods Movements
-- Run As  : MPPMS user on FREEPDB1
-- ============================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON
SET ECHO OFF
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Unit Testing Inventory and Goods Movements (MIGO)
PROMPT ============================================================

DECLARE
    v_status  VARCHAR2(20);
    v_message VARCHAR2(1000);
    
    -- Test inputs
    v_material_id   NUMBER := 5001;        -- CR Steel Sheet 2mm
    v_warehouse_id  NUMBER := 101;         -- WH-RAW-01
    v_bin_src       NUMBER := 501;         -- BIN-A1-RACK1
    v_bin_dest      NUMBER := 502;         -- BIN-A2-RACK2
    v_po_id         NUMBER := 1;           -- PO-2026-20001
    v_plan_id       NUMBER := 1;           -- PLAN-2026-00001
    
    -- Variables to hold balances
    v_qty_before    NUMBER;
    v_qty_after     NUMBER;
    v_src_bal       NUMBER;
    v_dest_bal      NUMBER;
    
    PROCEDURE print_header(p_title VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));
        DBMS_OUTPUT.PUT_LINE('>>> ' || p_title);
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));
    END print_header;

BEGIN
    -- Ensure clean rollback at the end of the test script
    SAVEPOINT inv_test_start;
    
    -- ------------------------------------------------------------
    -- TEST 1: Initial Stock State
    -- ------------------------------------------------------------
    print_header('TEST 1: Initial Stock and Stock Valuation');
    
    SELECT QTY_ON_HAND INTO v_qty_before
      FROM INVENTORY_BALANCE
     WHERE MATERIAL_ID = v_material_id 
       AND WAREHOUSE_ID = v_warehouse_id 
       AND BIN_ID = v_bin_src;
       
    DBMS_OUTPUT.PUT_LINE('Material ID: ' || v_material_id || ' in Bin: ' || v_bin_src);
    DBMS_OUTPUT.PUT_LINE('Initial On-Hand Stock: ' || v_qty_before || ' units');
    DBMS_OUTPUT.PUT_LINE('Total Available Stock (All bins): ' || PKG_INVENTORY.GET_TOTAL_AVAILABLE_STOCK(v_material_id) || ' units');
    DBMS_OUTPUT.PUT_LINE('Total Schema Stock Value: SR ' || TO_CHAR(PKG_INVENTORY.GET_STOCK_VALUE(), '999,999,990.00'));
    DBMS_OUTPUT.PUT_LINE('Total Low Stock Materials count: ' || PKG_INVENTORY.GET_LOW_STOCK_COUNT);

    -- ------------------------------------------------------------
    -- TEST 2: PROCESS_GOODS_RECEIPT (MIGO 101 - PO Receipt)
    -- ------------------------------------------------------------
    print_header('TEST 2: Goods Receipt (MIGO 101) against PO');
    
    PKG_INVENTORY.PROCESS_GOODS_RECEIPT(
        p_po_id        => v_po_id,
        p_material_id  => v_material_id,
        p_warehouse_id => v_warehouse_id,
        p_bin_id       => v_bin_src,
        p_received_qty => 500,
        p_performed_by => 'TEST_STOREKEEPER',
        p_remarks      => 'Test PO Receipt 500 units',
        p_status       => v_status,
        p_message      => v_message
    );
    
    DBMS_OUTPUT.PUT_LINE('GR Status : ' || v_status);
    DBMS_OUTPUT.PUT_LINE('GR Message: ' || v_message);
    
    SELECT QTY_ON_HAND INTO v_qty_after
      FROM INVENTORY_BALANCE
     WHERE MATERIAL_ID = v_material_id 
       AND WAREHOUSE_ID = v_warehouse_id 
       AND BIN_ID = v_bin_src;
       
    DBMS_OUTPUT.PUT_LINE('New On-Hand Stock: ' || v_qty_after || ' (Expected: ' || (v_qty_before + 500) || ')');

    -- ------------------------------------------------------------
    -- TEST 3: PROCESS_STOCK_TRANSFER (MIGO 311 - Warehouse Bin Transfer)
    -- ------------------------------------------------------------
    print_header('TEST 3: Internal Stock Transfer (MIGO 311)');
    
    SELECT QTY_ON_HAND INTO v_src_bal
      FROM INVENTORY_BALANCE
     WHERE MATERIAL_ID = v_material_id AND WAREHOUSE_ID = v_warehouse_id AND BIN_ID = v_bin_src;
     
    -- Get or initialize destination bin stock
    BEGIN
        SELECT QTY_ON_HAND INTO v_dest_bal
          FROM INVENTORY_BALANCE
         WHERE MATERIAL_ID = v_material_id AND WAREHOUSE_ID = v_warehouse_id AND BIN_ID = v_bin_dest;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_dest_bal := 0;
    END;
    
    DBMS_OUTPUT.PUT_LINE('Before Transfer: Source Bin=' || v_src_bal || ', Destination Bin=' || v_dest_bal);
    
    PKG_INVENTORY.PROCESS_STOCK_TRANSFER(
        p_material_id  => v_material_id,
        p_from_wh_id   => v_warehouse_id,
        p_from_bin_id  => v_bin_src,
        p_to_wh_id     => v_warehouse_id,
        p_to_bin_id    => v_bin_dest,
        p_transfer_qty => 300,
        p_performed_by => 'TEST_FORKLIFT_OP',
        p_remarks      => 'Bin replenishment',
        p_status       => v_status,
        p_message      => v_message
    );
    
    DBMS_OUTPUT.PUT_LINE('Transfer Status : ' || v_status);
    DBMS_OUTPUT.PUT_LINE('Transfer Message: ' || v_message);
    
    SELECT QTY_ON_HAND INTO v_src_bal
      FROM INVENTORY_BALANCE
     WHERE MATERIAL_ID = v_material_id AND WAREHOUSE_ID = v_warehouse_id AND BIN_ID = v_bin_src;
     
    SELECT QTY_ON_HAND INTO v_dest_bal
      FROM INVENTORY_BALANCE
     WHERE MATERIAL_ID = v_material_id AND WAREHOUSE_ID = v_warehouse_id AND BIN_ID = v_bin_dest;
     
    DBMS_OUTPUT.PUT_LINE('After Transfer : Source Bin=' || v_src_bal || ', Destination Bin=' || v_dest_bal);

    -- ------------------------------------------------------------
    -- TEST 4: PROCESS_GOODS_ISSUE (MIGO 261 - Shopfloor Issue)
    -- ------------------------------------------------------------
    print_header('TEST 4: Goods Issue (MIGO 261) to Production Plan');
    
    SELECT QTY_ON_HAND INTO v_qty_before
      FROM INVENTORY_BALANCE
     WHERE MATERIAL_ID = v_material_id AND WAREHOUSE_ID = v_warehouse_id AND BIN_ID = v_bin_src;
     
    PKG_INVENTORY.PROCESS_GOODS_ISSUE(
        p_plan_id      => v_plan_id,
        p_material_id  => v_material_id,
        p_warehouse_id => v_warehouse_id,
        p_bin_id       => v_bin_src,
        p_issue_qty    => 200,
        p_performed_by => 'TEST_PRODUCTION_SUPER',
        p_remarks      => 'Production run issue',
        p_status       => v_status,
        p_message      => v_message
    );
    
    DBMS_OUTPUT.PUT_LINE('GI Status : ' || v_status);
    DBMS_OUTPUT.PUT_LINE('GI Message: ' || v_message);
    
    SELECT QTY_ON_HAND INTO v_qty_after
      FROM INVENTORY_BALANCE
     WHERE MATERIAL_ID = v_material_id AND WAREHOUSE_ID = v_warehouse_id AND BIN_ID = v_bin_src;
     
    DBMS_OUTPUT.PUT_LINE('New Source Bin Stock: ' || v_qty_after || ' (Expected: ' || (v_qty_before - 200) || ')');

    -- ------------------------------------------------------------
    -- TEST 5: PROCESS_STOCK_ADJUSTMENT (MIGO 551 - Physical Inventory / Cycle Count)
    -- ------------------------------------------------------------
    print_header('TEST 5: Physical Stock Adjustment (MIGO 551)');
    
    SELECT QTY_ON_HAND INTO v_qty_before
      FROM INVENTORY_BALANCE
     WHERE MATERIAL_ID = v_material_id AND WAREHOUSE_ID = v_warehouse_id AND BIN_ID = v_bin_src;
     
    DBMS_OUTPUT.PUT_LINE('Current stock recorded in source bin: ' || v_qty_before);
    
    -- Force adjust to 1350 units
    PKG_INVENTORY.PROCESS_STOCK_ADJUSTMENT(
        p_material_id     => v_material_id,
        p_warehouse_id    => v_warehouse_id,
        p_bin_id          => v_bin_src,
        p_new_qty_on_hand => 1350,
        p_performed_by    => 'TEST_AUDITOR',
        p_remarks         => 'Cycle count audit adjustment',
        p_status          => v_status,
        p_message         => v_message
    );
    
    DBMS_OUTPUT.PUT_LINE('Adjustment Status : ' || v_status);
    DBMS_OUTPUT.PUT_LINE('Adjustment Message: ' || v_message);
    
    SELECT QTY_ON_HAND INTO v_qty_after
      FROM INVENTORY_BALANCE
     WHERE MATERIAL_ID = v_material_id AND WAREHOUSE_ID = v_warehouse_id AND BIN_ID = v_bin_src;
     
    DBMS_OUTPUT.PUT_LINE('Final Bin stock after Audit: ' || v_qty_after || ' (Expected: 1350)');

    -- ------------------------------------------------------------
    -- TEST 6: Transaction Ledger Verification
    -- ------------------------------------------------------------
    print_header('TEST 6: Transaction Ledger MIGO Logs');
    
    FOR r IN (
        SELECT TRANSACTION_NUM, MOVEMENT_CODE, TRANSACTION_TYPE, QUANTITY, PERFORMED_BY, REMARKS
          FROM INVENTORY_TRANSACTION
         WHERE PERFORMED_BY LIKE 'TEST_%'
         ORDER BY TRANSACTION_DATE ASC
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(r.TRANSACTION_NUM || ' | Mvt:' || r.MOVEMENT_CODE || ' | ' || RPAD(r.TRANSACTION_TYPE, 15, ' ') || ' | Qty:' || r.QUANTITY || ' | User:' || r.PERFORMED_BY);
    END LOOP;

    -- Manual Cleanup Section to restore seed data (since COMMIT was executed inside package procedures)
    print_header('CLEANUP: Restoring Seed Data');
    
    DELETE FROM INVENTORY_TRANSACTION WHERE PERFORMED_BY LIKE 'TEST_%';
    
    UPDATE INVENTORY_BALANCE
       SET QTY_ON_HAND = 1200, QTY_RESERVED = 200, QTY_IN_QUALITY = 0, QTY_BLOCKED = 0
     WHERE MATERIAL_ID = 5001 AND BIN_ID = 501;
     
    DELETE FROM INVENTORY_BALANCE 
     WHERE MATERIAL_ID = 5001 AND BIN_ID = 502;
     
    UPDATE PURCHASE_ORDER_ITEMS
       SET RECEIVED_QTY = 1200
     WHERE PO_ID = 1 AND MATERIAL_ID = 5001;
     
    UPDATE PURCHASE_ORDER
       SET ORDER_STATUS = 'RECEIVED'
     WHERE PO_ID = 1;
     
    UPDATE PROCUREMENT_TRACKING
       SET DELIVERY_STATUS = 'DELIVERED',
           ACTUAL_DATE = SYSDATE,
           REMARKS = 'Goods receipt completed in warehouse'
     WHERE PO_ID = 1;
     
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));
    DBMS_OUTPUT.PUT_LINE('>>> UNIT TESTING COMPLETED: Data successfully cleaned up and restored. <<<');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));

EXCEPTION
    WHEN OTHERS THEN
        -- Attempt cleanup even on failure
        DELETE FROM INVENTORY_TRANSACTION WHERE PERFORMED_BY LIKE 'TEST_%';
        UPDATE INVENTORY_BALANCE SET QTY_ON_HAND = 1200, QTY_RESERVED = 200 WHERE MATERIAL_ID = 5001 AND BIN_ID = 501;
        DELETE FROM INVENTORY_BALANCE WHERE MATERIAL_ID = 5001 AND BIN_ID = 502;
        UPDATE PURCHASE_ORDER_ITEMS SET RECEIVED_QTY = 1200 WHERE PO_ID = 1 AND MATERIAL_ID = 5001;
        UPDATE PURCHASE_ORDER SET ORDER_STATUS = 'RECEIVED' WHERE PO_ID = 1;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('CRITICAL TEST ERROR: ' || SQLERRM);
END;
/
