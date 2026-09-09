-- ============================================================
-- MPPMS :: 24_apex_pages_inventory.sql
-- Purpose : Inventory & Goods Movement APEX Page Specifications
-- Pages   : 150, 160, 170
-- ============================================================

/*
=================================================================
PAGE 150 — REAL-TIME INVENTORY STOCK OVERVIEW
=================================================================
Page Type : Interactive Report (IR) with Summary Cards
Page #    : 150
Title     : Inventory Stock & Bin Monitor
Navigation: Main Menu -> Inventory -> Stock Overview

REGION 1: Inventory KPI Summary Bar
-----------------------------------------------------------------
Card 1: Total On-Hand Stock Value (INR)
  SQL: SELECT '₹' || TO_CHAR(PKG_INVENTORY.GET_STOCK_VALUE(), 'FM999,999,990') FROM DUAL;
Card 2: Low Stock & Critical Items
  SQL: SELECT PKG_INVENTORY.GET_LOW_STOCK_COUNT() FROM DUAL;
Card 3: Active Warehouses & Bins
  SQL: SELECT COUNT(DISTINCT WAREHOUSE_ID) || ' WHs / ' || COUNT(DISTINCT BIN_ID) || ' Bins' FROM STORAGE_BIN;

REGION 2: Stock Overview Interactive Report
-----------------------------------------------------------------
SQL Source:
*/
SELECT
    s.BALANCE_ID,
    s.MATERIAL_CODE,
    s.MATERIAL_NAME,
    s.MATERIAL_CATEGORY,
    s.UNIT_OF_MEASURE,
    s.WAREHOUSE_CODE,
    s.WAREHOUSE_NAME,
    s.BIN_CODE,
    s.ZONE_NAME,
    s.QTY_ON_HAND,
    s.QTY_RESERVED,
    s.QTY_AVAILABLE,
    s.QTY_IN_QUALITY,
    s.QTY_BLOCKED,
    s.STOCK_VALUE,
    s.MIN_STOCK_LEVEL,
    s.REORDER_POINT,
    s.STOCK_STATUS,
    s.LAST_UPDATED_DATE
FROM VW_INVENTORY_STOCK s
ORDER BY s.WAREHOUSE_CODE, s.MATERIAL_CODE;

/*
Column Configuration:
  - STOCK_STATUS: HTML Expression
    <span class="mppms-badge mppms-badge-#CASE STOCK_STATUS WHEN 'CRITICAL' THEN 'danger' WHEN 'LOW' THEN 'warning' ELSE 'success' END#">#STOCK_STATUS#</span>
  - STOCK_VALUE: Format Mask `FMR999,999,990.00`
  - QTY_AVAILABLE: Highlight Red if QTY_AVAILABLE <= SAFETY_STOCK

PAGE BUTTONS:
  - Button "Receive Stock (MIGO 101)" -> Opens Page 160 Modal (P160_MOVEMENT_CODE=101)
  - Button "Issue Stock (MIGO 261)"   -> Opens Page 160 Modal (P160_MOVEMENT_CODE=261)
  - Button "Stock Transfer"           -> Opens Page 160 Modal (P160_MOVEMENT_CODE=311)

=================================================================
PAGE 160 — GOODS MOVEMENT TRANSACTION FORM (MIGO MODAL)
=================================================================
Page Type : Modal Dialog
Page #    : 160
Title     : Goods Movement (MIGO Receipt / Issue / Transfer)

ITEMS:
  P160_MOVEMENT_CODE  : Select List (Static LOV: 101-Goods Receipt PO, 261-Goods Issue Production, 311-Stock Transfer, 551-Stock Adjustment)
  P160_MATERIAL_ID    : Select List (SQL: SELECT MATERIAL_CODE || ' - ' || MATERIAL_NAME d, MATERIAL_ID r FROM MATERIAL_MASTER ORDER BY MATERIAL_NAME)
  P160_WAREHOUSE_ID   : Select List (SQL: SELECT WAREHOUSE_CODE || ' - ' || WAREHOUSE_NAME d, WAREHOUSE_ID r FROM WAREHOUSE_MASTER WHERE STATUS='ACTIVE')
  P160_BIN_ID         : Select List (Cascading LOV on P160_WAREHOUSE_ID: SELECT BIN_CODE d, BIN_ID r FROM STORAGE_BIN WHERE WAREHOUSE_ID = :P160_WAREHOUSE_ID)
  P160_QUANTITY       : Number Field (Min: 1)
  P160_PO_ID          : Select List (Conditional on Movement=101: SELECT PO_NUMBER d, PO_ID r FROM PURCHASE_ORDER WHERE ORDER_STATUS IN ('ISSUED','ACKNOWLEDGED'))
  P160_PLAN_ID        : Select List (Conditional on Movement=261: SELECT 'Plan #' || PLAN_ID d, PLAN_ID r FROM PRODUCTION_PLAN WHERE STATUS IN ('APPROVED','IN_PROGRESS'))
  P160_REMARKS        : Textarea

PROCESS: "Execute Goods Movement" (On Submit)
Type   : PL/SQL Code
Code   :
*/
DECLARE
    v_status  VARCHAR2(20);
    v_message VARCHAR2(1000);
BEGIN
    IF :P160_MOVEMENT_CODE = '101' THEN
        PKG_INVENTORY.PROCESS_GOODS_RECEIPT(
            p_po_id          => :P160_PO_ID,
            p_material_id    => :P160_MATERIAL_ID,
            p_warehouse_id   => :P160_WAREHOUSE_ID,
            p_bin_id         => :P160_BIN_ID,
            p_received_qty   => :P160_QUANTITY,
            p_performed_by   => :APP_USER,
            p_remarks        => :P160_REMARKS,
            p_status         => v_status,
            p_message        => v_message
        );
    ELSIF :P160_MOVEMENT_CODE = '261' THEN
        PKG_INVENTORY.PROCESS_GOODS_ISSUE(
            p_plan_id        => :P160_PLAN_ID,
            p_material_id    => :P160_MATERIAL_ID,
            p_warehouse_id   => :P160_WAREHOUSE_ID,
            p_bin_id         => :P160_BIN_ID,
            p_issue_qty      => :P160_QUANTITY,
            p_performed_by   => :APP_USER,
            p_remarks        => :P160_REMARKS,
            p_status         => v_status,
            p_message        => v_message
        );
    ELSIF :P160_MOVEMENT_CODE = '551' THEN
        PKG_INVENTORY.PROCESS_STOCK_ADJUSTMENT(
            p_material_id    => :P160_MATERIAL_ID,
            p_warehouse_id   => :P160_WAREHOUSE_ID,
            p_bin_id         => :P160_BIN_ID,
            p_new_qty_on_hand=> :P160_QUANTITY,
            p_performed_by   => :APP_USER,
            p_remarks        => :P160_REMARKS,
            p_status         => v_status,
            p_message        => v_message
        );
    END IF;

    IF v_status = 'ERROR' THEN
        apex_error.add_error (
            p_message          => v_message,
            p_display_location => apex_error.c_inline_in_notification
        );
    END IF;
END;
/

/*
=================================================================
PAGE 170 — INVENTORY TRANSACTION AUDIT HISTORY
=================================================================
Page Type : Interactive Report (IR)
Page #    : 170
Title     : Goods Movement Audit Log
Navigation: Main Menu -> Inventory -> Transaction History

SQL Source:
*/
SELECT
    l.TRANSACTION_ID,
    l.TRANSACTION_NUM,
    l.MOVEMENT_CODE,
    l.TRANSACTION_TYPE,
    l.MATERIAL_CODE,
    l.MATERIAL_NAME,
    l.UNIT_OF_MEASURE,
    l.WAREHOUSE_CODE,
    l.BIN_CODE,
    l.QUANTITY,
    l.TRANSACTION_VALUE,
    l.REFERENCE_TYPE,
    l.REFERENCE_ID,
    l.PERFORMED_BY,
    l.REMARKS,
    l.TRANSACTION_TIME
FROM VW_GOODS_MOVEMENT_LOG l
ORDER BY l.TRANSACTION_DATE DESC;

/*
Column Configuration:
  - MOVEMENT_CODE: HTML Expression
    <span class="mppms-badge mppms-badge-#CASE MOVEMENT_CODE WHEN '101' THEN 'success' WHEN '261' THEN 'info' ELSE 'warning' END#">#MOVEMENT_CODE# - #TRANSACTION_TYPE#</span>
  - TRANSACTION_VALUE: Format Mask `FMR999,999,990.00`
*/

PROMPT [SUCCESS] Inventory APEX Page Specs (150, 160, 170) complete.
