-- ============================================================
-- MPPMS :: 32_pkg_ebs_sync.sql
-- Run As: MPPMS user connected to FREEPDB1
-- Purpose: Creating PKG_EBS_SYNC to synchronize EBS tables with MPPMS
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Creating PKG_EBS_SYNC Package Spec & Body
PROMPT ============================================================

CREATE OR REPLACE PACKAGE PKG_EBS_SYNC AS

    -- Synchronize items from MTL_SYSTEM_ITEMS to MATERIAL_MASTER
    PROCEDURE SYNC_ITEMS;

    -- Synchronize POs from PO_HEADERS_ALL/PO_LINES_ALL to PURCHASE_ORDER/PURCHASE_ORDER_ITEMS
    PROCEDURE SYNC_POS;

    -- Seed mock data into EBS tables for testing
    PROCEDURE SEED_EBS_MOCK_DATA;

    -- Run all sync routines sequentially
    PROCEDURE RUN_FULL_SYNC;

END PKG_EBS_SYNC;
/

CREATE OR REPLACE PACKAGE BODY PKG_EBS_SYNC AS

    PROCEDURE SYNC_ITEMS IS
    BEGIN
        -- Sync from MTL_SYSTEM_ITEMS to MATERIAL_MASTER
        MERGE INTO MATERIAL_MASTER dest
        USING (
            SELECT 
                inventory_item_id AS item_id,
                segment1 AS item_code,
                NVL(description, segment1) AS item_name,
                NVL(item_type, 'ZAMIL_FAB') AS cat,
                NVL(primary_uom_code, 'MT') AS uom,
                NVL(list_price_per_unit, 0) AS std_cost
            FROM mtl_system_items
        ) src
        ON (dest.MATERIAL_ID = src.item_id)
        WHEN MATCHED THEN
            UPDATE SET 
                dest.MATERIAL_CODE = src.item_code,
                dest.MATERIAL_NAME = src.item_name,
                dest.CATEGORY = src.cat,
                dest.UNIT_OF_MEASURE = src.uom,
                dest.STANDARD_COST = src.std_cost
        WHEN NOT MATCHED THEN
            INSERT (MATERIAL_ID, MATERIAL_CODE, MATERIAL_NAME, CATEGORY, UNIT_OF_MEASURE, SAFETY_STOCK, REORDER_LEVEL, LEAD_TIME, STANDARD_COST, STATUS)
            VALUES (src.item_id, src.item_code, src.item_name, src.cat, src.uom, 100, 200, 7, src.std_cost, 'ACTIVE');

        COMMIT;
    END SYNC_ITEMS;

    PROCEDURE SYNC_POS IS
        v_supplier_count NUMBER;
    BEGIN
        -- Ensure that mock supplier (SUP-1001) exists for FK constraints
        SELECT COUNT(*) INTO v_supplier_count FROM SUPPLIER_MASTER WHERE SUPPLIER_CODE = 'SUP-1001';
        IF v_supplier_count = 0 THEN
            INSERT INTO SUPPLIER_MASTER (SUPPLIER_ID, SUPPLIER_CODE, SUPPLIER_NAME, STATUS)
            VALUES (101, 'SUP-1001', 'Zamil Steel Industries', 'ACTIVE');
        END IF;

        -- Sync PO Headers
        MERGE INTO PURCHASE_ORDER dest
        USING (
            SELECT 
                po_header_id AS header_id,
                segment1 AS po_num,
                (SELECT SUPPLIER_ID FROM SUPPLIER_MASTER WHERE SUPPLIER_CODE = 'SUP-1001') AS supp_id,
                NVL(creation_date, SYSDATE) AS ord_date,
                NVL(approved_date, NVL(creation_date, SYSDATE) + 14) AS del_date,
                CASE WHEN authorization_status = 'APPROVED' THEN 'ISSUED' ELSE 'DRAFT' END AS stat,
                NVL(note_to_vendor, 'Standard EBS PO Terms') AS po_terms
            FROM po_headers_all
        ) src
        ON (dest.PO_ID = src.header_id)
        WHEN MATCHED THEN
            UPDATE SET 
                dest.PO_NUMBER = src.po_num,
                dest.SUPPLIER_ID = src.supp_id,
                dest.ORDER_DATE = src.ord_date,
                dest.DELIVERY_DATE = src.del_date,
                dest.ORDER_STATUS = src.stat,
                dest.TERMS = src.po_terms
        WHEN NOT MATCHED THEN
            INSERT (PO_ID, SUPPLIER_ID, PO_NUMBER, ORDER_DATE, DELIVERY_DATE, ORDER_STATUS, TERMS)
            VALUES (src.header_id, src.supp_id, src.po_num, src.ord_date, src.del_date, src.stat, src.po_terms);

        -- Sync PO Lines
        MERGE INTO PURCHASE_ORDER_ITEMS dest
        USING (
            SELECT 
                po_line_id AS line_id,
                po_header_id AS header_id,
                item_id AS mat_id,
                NVL(quantity, 0) AS qty,
                NVL(unit_price, 0) AS price,
                note_to_vendor AS line_remarks
            FROM PO_LINES_ALL
            WHERE item_id IN (SELECT MATERIAL_ID FROM MATERIAL_MASTER)
        ) src
        ON (dest.PO_ITEM_ID = src.line_id)
        WHEN MATCHED THEN
            UPDATE SET 
                dest.PO_ID = src.header_id,
                dest.MATERIAL_ID = src.mat_id,
                dest.ORDERED_QTY = src.qty,
                dest.UNIT_PRICE = src.price,
                dest.REMARKS = src.line_remarks
        WHEN NOT MATCHED THEN
            INSERT (PO_ITEM_ID, PO_ID, MATERIAL_ID, ORDERED_QTY, UNIT_PRICE, RECEIVED_QTY, REMARKS)
            VALUES (src.line_id, src.header_id, src.mat_id, src.qty, src.price, 0, src.line_remarks);

        COMMIT;
    END SYNC_POS;

    PROCEDURE SEED_EBS_MOCK_DATA IS
    BEGIN
        -- Clear EBS mock tables
        DELETE FROM mtl_system_items;
        DELETE FROM po_headers_all;
        DELETE FROM PO_LINES_ALL;
        DELETE FROM mtl_onhand_quantities;

        -- 1. Insert into mtl_system_items
        INSERT INTO mtl_system_items (inventory_item_id, organization_id, segment1, description, primary_uom_code, item_type, list_price_per_unit)
        VALUES (5001, 101, 'ZML-ST-BEAM-H', 'Zamil H-Beam Structural Steel Grade 50', 'MT', 'ZAMIL_FAB', 120.00);

        INSERT INTO mtl_system_items (inventory_item_id, organization_id, segment1, description, primary_uom_code, item_type, list_price_per_unit)
        VALUES (5002, 101, 'ZML-ST-COL-PEB', 'Zamil PEB Column Section 400x200', 'MT', 'ZAMIL_FAB', 145.00);

        INSERT INTO mtl_system_items (inventory_item_id, organization_id, segment1, description, primary_uom_code, item_type, list_price_per_unit)
        VALUES (5003, 101, 'ZML-ACC-BOLT-KIT', 'Zamil High-Strength Anchor Bolt M24 Kit', 'SET', 'ZAMIL_ACC', 18.50);

        INSERT INTO mtl_system_items (inventory_item_id, organization_id, segment1, description, primary_uom_code, item_type, list_price_per_unit)
        VALUES (5004, 101, 'ZML-PANEL-ROOF', 'Zamil Double Skin Insulated Roof Panel 50mm', 'SFT', 'ZAMIL_PANEL', 85.00);

        INSERT INTO mtl_system_items (inventory_item_id, organization_id, segment1, description, primary_uom_code, item_type, list_price_per_unit)
        VALUES (5005, 101, 'ZML-PANEL-WALL', 'Zamil Polyurethane Wall Cladding Panel 40mm', 'SFT', 'ZAMIL_PANEL', 78.00);

        -- 2. Insert into po_headers_all
        INSERT INTO po_headers_all (po_header_id, segment1, vendor_id, creation_date, approved_date, authorization_status, note_to_vendor)
        VALUES (2001, 'ZML-PO-2026-0001', 101, SYSDATE - 5, SYSDATE - 4, 'APPROVED', 'Urgent structural fabrication project delivery');

        -- 3. Insert into PO_LINES_ALL
        INSERT INTO PO_LINES_ALL (po_line_id, po_header_id, line_num, item_id, quantity, unit_price, note_to_vendor)
        VALUES (3001, 2001, 1, 5001, 800, 120.00, 'Zamil H-Beam Grade 50');

        INSERT INTO PO_LINES_ALL (po_line_id, po_header_id, line_num, item_id, quantity, unit_price, note_to_vendor)
        VALUES (3002, 2001, 2, 5002, 600, 145.00, 'PEB Column Section');

        INSERT INTO PO_LINES_ALL (po_line_id, po_header_id, line_num, item_id, quantity, unit_price, note_to_vendor)
        VALUES (3003, 2001, 3, 5003, 1200, 18.50, 'Anchor Bolts M24');

        COMMIT;
    END SEED_EBS_MOCK_DATA;

    PROCEDURE RUN_FULL_SYNC IS
    BEGIN
        SYNC_ITEMS;
        SYNC_POS;
    END RUN_FULL_SYNC;

END PKG_EBS_SYNC;
/
SHOW ERRORS;
