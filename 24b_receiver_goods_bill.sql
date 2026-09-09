-- ============================================================
-- MPPMS :: 24b_receiver_goods_bill.sql
-- Run As: MPPMS user connected to FREEPDB1
-- Purpose: Receiver Goods Bill (RGB) Schema & Processing Package
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Phase 14 - Creating Receiver Goods Bill Schema
PROMPT ============================================================

-- ------------------------------------------------------------
-- 1. DROP EXISTING OBJECTS (If they exist)
-- ------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE RECEIVER_GOODS_BILL_ITEMS CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE RECEIVER_GOODS_BILL CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_BILL_ID';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_BILL_ITEM_ID';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE SEQ_BILL_NUMBER';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- ------------------------------------------------------------
-- 2. CREATE TABLES
-- ------------------------------------------------------------
CREATE TABLE RECEIVER_GOODS_BILL (
    BILL_ID          NUMBER         NOT NULL,
    BILL_NUMBER      VARCHAR2(30)   NOT NULL,
    PO_ID            NUMBER,
    DELIVERY_NOTE    VARCHAR2(50),
    RECEIVED_DATE    DATE           DEFAULT SYSDATE NOT NULL,
    RECEIVED_BY      VARCHAR2(100)  DEFAULT USER NOT NULL,
    STATUS           VARCHAR2(20)   DEFAULT 'DRAFT' NOT NULL,
    REMARKS          VARCHAR2(255),
    CREATED_DATE     DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT PK_GOODS_BILL PRIMARY KEY (BILL_ID),
    CONSTRAINT UQ_BILL_NUMBER UNIQUE (BILL_NUMBER),
    CONSTRAINT FK_BILL_PO FOREIGN KEY (PO_ID) REFERENCES PURCHASE_ORDER(PO_ID),
    CONSTRAINT CK_BILL_STATUS CHECK (STATUS IN ('DRAFT', 'COMPLETED', 'QA_REJECTED'))
);

CREATE TABLE RECEIVER_GOODS_BILL_ITEMS (
    BILL_ITEM_ID      NUMBER         NOT NULL,
    BILL_ID           NUMBER         NOT NULL,
    MATERIAL_ID       NUMBER         NOT NULL,
    QUANTITY_RECEIVED NUMBER         NOT NULL,
    WAREHOUSE_ID      NUMBER         NOT NULL,
    BIN_ID            NUMBER         NOT NULL,
    REMARKS           VARCHAR2(255),
    CONSTRAINT PK_GOODS_BILL_ITEM PRIMARY KEY (BILL_ITEM_ID),
    CONSTRAINT FK_ITEM_BILL FOREIGN KEY (BILL_ID) REFERENCES RECEIVER_GOODS_BILL(BILL_ID) ON DELETE CASCADE,
    CONSTRAINT FK_ITEM_MATERIAL FOREIGN KEY (MATERIAL_ID) REFERENCES MATERIAL_MASTER(MATERIAL_ID),
    CONSTRAINT FK_ITEM_WH FOREIGN KEY (WAREHOUSE_ID) REFERENCES WAREHOUSE_MASTER(WAREHOUSE_ID),
    CONSTRAINT FK_ITEM_BIN FOREIGN KEY (BIN_ID) REFERENCES STORAGE_BIN(BIN_ID),
    CONSTRAINT CK_ITEM_QTY CHECK (QUANTITY_RECEIVED >= 0)
);

-- ------------------------------------------------------------
-- 3. CREATE SEQUENCES
-- ------------------------------------------------------------
CREATE SEQUENCE SEQ_BILL_ID         START WITH 3001 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_BILL_ITEM_ID    START WITH 4001 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_BILL_NUMBER     START WITH 1001 INCREMENT BY 1 NOCACHE NOCYCLE;

-- ------------------------------------------------------------
-- 4. CREATE TRIGGERS
-- ------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_BILL_BI
    BEFORE INSERT ON RECEIVER_GOODS_BILL
    FOR EACH ROW
BEGIN
    IF :NEW.BILL_ID IS NULL THEN
        :NEW.BILL_ID := SEQ_BILL_ID.NEXTVAL;
    END IF;
    IF :NEW.BILL_NUMBER IS NULL THEN
        :NEW.BILL_NUMBER := 'RGB-' || TO_CHAR(SYSDATE, 'YYYY') || '-' || LPAD(SEQ_BILL_NUMBER.NEXTVAL, 6, '0');
    END IF;
END;
/

CREATE OR REPLACE TRIGGER TRG_BILL_ITEM_BI
    BEFORE INSERT ON RECEIVER_GOODS_BILL_ITEMS
    FOR EACH ROW
BEGIN
    IF :NEW.BILL_ITEM_ID IS NULL THEN
        :NEW.BILL_ITEM_ID := SEQ_BILL_ITEM_ID.NEXTVAL;
    END IF;
END;
/

-- ------------------------------------------------------------
-- 5. CREATE PACKAGE SPEC & BODY
-- ------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_RECEIVER_GOODS_BILL AS

    -- Create new Receiver Goods Bill
    PROCEDURE CREATE_BILL(
        p_po_id          IN NUMBER,
        p_delivery_note  IN VARCHAR2,
        p_received_by    IN VARCHAR2,
        p_remarks        IN VARCHAR2,
        p_bill_id        OUT NUMBER,
        p_bill_number    OUT VARCHAR2
    );

    -- Add line item to draft Goods Bill
    PROCEDURE ADD_BILL_ITEM(
        p_bill_id        IN NUMBER,
        p_material_id    IN NUMBER,
        p_qty_received   IN NUMBER,
        p_warehouse_id   IN NUMBER,
        p_bin_id         IN NUMBER,
        p_remarks        IN VARCHAR2
    );

    -- Post and finalize Goods Bill, committing inventory movement
    PROCEDURE POST_BILL(
        p_bill_id        IN NUMBER,
        p_status         OUT VARCHAR2,
        p_message        OUT VARCHAR2
    );

    -- Seed Zamil Steel Procurement Data
    PROCEDURE SEED_ZAMIL_DATA;

END PKG_RECEIVER_GOODS_BILL;
/

CREATE OR REPLACE PACKAGE BODY PKG_RECEIVER_GOODS_BILL AS

    PROCEDURE CREATE_BILL(
        p_po_id          IN NUMBER,
        p_delivery_note  IN VARCHAR2,
        p_received_by    IN VARCHAR2,
        p_remarks        IN VARCHAR2,
        p_bill_id        OUT NUMBER,
        p_bill_number    OUT VARCHAR2
    ) IS
        v_id NUMBER;
        v_num VARCHAR2(30);
    BEGIN
        v_id := SEQ_BILL_ID.NEXTVAL;
        v_num := 'RGB-' || TO_CHAR(SYSDATE, 'YYYY') || '-' || LPAD(SEQ_BILL_NUMBER.NEXTVAL, 6, '0');
        
        INSERT INTO RECEIVER_GOODS_BILL (
            BILL_ID, BILL_NUMBER, PO_ID, DELIVERY_NOTE, RECEIVED_BY, STATUS, REMARKS
        ) VALUES (
            v_id, v_num, p_po_id, p_delivery_note, p_received_by, 'DRAFT', p_remarks
        );
        
        p_bill_id := v_id;
        p_bill_number := v_num;
    END CREATE_BILL;

    PROCEDURE ADD_BILL_ITEM(
        p_bill_id        IN NUMBER,
        p_material_id    IN NUMBER,
        p_qty_received   IN NUMBER,
        p_warehouse_id   IN NUMBER,
        p_bin_id         IN NUMBER,
        p_remarks        IN VARCHAR2
    ) IS
    BEGIN
        INSERT INTO RECEIVER_GOODS_BILL_ITEMS (
            BILL_ID, MATERIAL_ID, QUANTITY_RECEIVED, WAREHOUSE_ID, BIN_ID, REMARKS
        ) VALUES (
            p_bill_id, p_material_id, p_qty_received, p_warehouse_id, p_bin_id, p_remarks
        );
    END ADD_BILL_ITEM;

    PROCEDURE POST_BILL(
        p_bill_id        IN NUMBER,
        p_status         OUT VARCHAR2,
        p_message        OUT VARCHAR2
    ) IS
        v_po_id NUMBER;
        v_received_by VARCHAR2(100);
        v_bill_remarks VARCHAR2(255);
        v_status VARCHAR2(20);
        v_item_status VARCHAR2(20);
        v_item_msg VARCHAR2(255);
        v_uom VARCHAR2(20);
        v_item_code VARCHAR2(30);
        v_item_name VARCHAR2(200);
    BEGIN
        -- Lock and check bill status
        SELECT PO_ID, RECEIVED_BY, REMARKS, STATUS
          INTO v_po_id, v_received_by, v_bill_remarks, v_status
          FROM RECEIVER_GOODS_BILL
         WHERE BILL_ID = p_bill_id
           FOR UPDATE;

        IF v_status <> 'DRAFT' THEN
            p_status := 'ERROR';
            p_message := 'Bill is already posted or QA rejected.';
            RETURN;
        END IF;

        -- Process each line item in the bill using PKG_INVENTORY.PROCESS_GOODS_RECEIPT
        FOR item IN (
            SELECT MATERIAL_ID, QUANTITY_RECEIVED, WAREHOUSE_ID, BIN_ID, REMARKS
              FROM RECEIVER_GOODS_BILL_ITEMS
             WHERE BILL_ID = p_bill_id
        ) LOOP
            -- Call core inventory process (Mvt 101 Goods Receipt)
            PKG_INVENTORY.PROCESS_GOODS_RECEIPT(
                p_po_id          => v_po_id,
                p_material_id    => item.MATERIAL_ID,
                p_warehouse_id   => item.WAREHOUSE_ID,
                p_bin_id         => item.BIN_ID,
                p_received_qty   => item.QUANTITY_RECEIVED,
                p_performed_by   => v_received_by,
                p_remarks        => NVL(item.REMARKS, v_bill_remarks),
                p_status         => v_item_status,
                p_message        => v_item_msg
            );

            IF v_item_status = 'ERROR' THEN
                RAISE_APPLICATION_ERROR(-20001, 'Goods receipt process failed for line item: ' || v_item_msg);
            END IF;

            -- Fetch item details for EBS alignment
            SELECT UNIT_OF_MEASURE, MATERIAL_CODE, MATERIAL_NAME
              INTO v_uom, v_item_code, v_item_name
              FROM MATERIAL_MASTER
             WHERE MATERIAL_ID = item.MATERIAL_ID;

            -- 1. Insert into EBS Transaction Staging Interface (MTL_TRANSACTIONS_INTERFACE)
            INSERT INTO mtl_transactions_interface (
                transaction_interface_id, transaction_header_id, source_code,
                source_line_id, source_header_id, process_flag,
                last_update_date, creation_date, created_by,
                inventory_item_id, organization_id, transaction_quantity,
                transaction_uom, transaction_date, subinventory_code,
                locator_id, transaction_mode, transaction_type_id,
                transaction_action_id, transaction_source_type_id
            ) VALUES (
                SEQ_TRANSACTION_ID.NEXTVAL, p_bill_id, 'MPPMS_PORTAL',
                item.MATERIAL_ID, v_po_id, 1,
                SYSDATE, SYSDATE, 1001,
                item.MATERIAL_ID, item.WAREHOUSE_ID, item.QUANTITY_RECEIVED,
                SUBSTR(v_uom, 1, 3), SYSDATE, 'RAW_MAT',
                item.BIN_ID, 3, 18,
                27, 1
            );

            -- 2. Update/Merge into EBS On-hand Stock Balances (MTL_ONHAND_QUANTITIES)
            MERGE INTO mtl_onhand_quantities target
            USING (
                SELECT 
                    item.WAREHOUSE_ID AS org_id,
                    item.MATERIAL_ID AS item_id,
                    v_item_code AS item_code,
                    v_item_name AS item_desc,
                    SUBSTR(v_uom, 1, 3) AS item_uom,
                    item.QUANTITY_RECEIVED AS qty
                FROM dual
            ) source
            ON (target.inventory_item_id = source.item_id AND target.organization_id = source.org_id)
            WHEN MATCHED THEN
                UPDATE SET target.total_qoh = target.total_qoh + source.qty
            WHEN NOT MATCHED THEN
                INSERT (organization_id, inventory_item_id, padded_concatenated_segments, total_qoh, item_description, primary_uom_code, organization_code)
                VALUES (source.org_id, source.item_id, source.item_code, source.qty, source.item_desc, source.item_uom, 'ZML');

            -- 3. Log EBS Receiving Transaction (RCV_TRANSACTIONS_V)
            INSERT INTO rcv_transactions_v (
                rcv_transaction_id, transaction_date, transaction_type, quantity, 
                unit_of_measure, po_header_id, item_id, item_description, to_organization_id,
                receipt_num, source_document_code
            ) VALUES (
                SEQ_TRANSACTION_ID.NEXTVAL, SYSDATE, 'RECEIVE', item.QUANTITY_RECEIVED,
                v_uom, v_po_id, item.MATERIAL_ID, v_item_name, item.WAREHOUSE_ID,
                (SELECT BILL_NUMBER FROM RECEIVER_GOODS_BILL WHERE BILL_ID = p_bill_id), 'PO'
            );

        END LOOP;

        -- Update bill status to completed
        UPDATE RECEIVER_GOODS_BILL
           SET STATUS = 'COMPLETED'
         WHERE BILL_ID = p_bill_id;

        COMMIT;
        p_status := 'SUCCESS';
        p_message := 'Receiver Goods Bill posted successfully, and committed to warehouse inventory & EBS interface.';
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_status := 'ERROR';
            p_message := 'Post bill failed: ' || SQLERRM;
    END POST_BILL;

    PROCEDURE SEED_ZAMIL_DATA IS
        v_po_id NUMBER;
        v_bill_id NUMBER;
        v_bill_num VARCHAR2(30);
    BEGIN
        -- Clear current demo materials/POs/receipts in correct dependency order
        DELETE FROM INVENTORY_TRANSACTION;
        DELETE FROM INVENTORY_BALANCE;
        DELETE FROM RECEIVER_GOODS_BILL_ITEMS;
        DELETE FROM RECEIVER_GOODS_BILL;
        DELETE FROM PROCUREMENT_TRACKING;
        DELETE FROM PURCHASE_ORDER_ITEMS;
        DELETE FROM PURCHASE_ORDER;
        DELETE FROM PURCHASE_REQUISITION;
        DELETE FROM MATERIAL_REQUIREMENT_PLAN;
        DELETE FROM BOM_DETAILS;
        DELETE FROM BOM_MASTER;
        DELETE FROM MATERIAL_MASTER;

        -- 1. Insert Zamil Structural Steel Materials
        INSERT INTO MATERIAL_MASTER (MATERIAL_ID, MATERIAL_CODE, MATERIAL_NAME, CATEGORY, UNIT_OF_MEASURE, SAFETY_STOCK, REORDER_LEVEL, STANDARD_COST, PREFERRED_SUPPLIER_ID)
        VALUES (5001, 'ZML-ST-BEAM-H', 'Zamil H-Beam Structural Steel Grade 50', 'Structural Steel', 'MT', 500, 1000, 120.00, (SELECT SUPPLIER_ID FROM SUPPLIER_MASTER WHERE SUPPLIER_CODE='SUP-1001'));

        INSERT INTO MATERIAL_MASTER (MATERIAL_ID, MATERIAL_CODE, MATERIAL_NAME, CATEGORY, UNIT_OF_MEASURE, SAFETY_STOCK, REORDER_LEVEL, STANDARD_COST, PREFERRED_SUPPLIER_ID)
        VALUES (5002, 'ZML-ST-COL-PEB', 'Zamil PEB Column Section 400x200', 'Structural Steel', 'MT', 300, 600, 145.00, (SELECT SUPPLIER_ID FROM SUPPLIER_MASTER WHERE SUPPLIER_CODE='SUP-1001'));

        INSERT INTO MATERIAL_MASTER (MATERIAL_ID, MATERIAL_CODE, MATERIAL_NAME, CATEGORY, UNIT_OF_MEASURE, SAFETY_STOCK, REORDER_LEVEL, STANDARD_COST, PREFERRED_SUPPLIER_ID)
        VALUES (5003, 'ZML-ACC-BOLT-KIT', 'Zamil High-Strength Anchor Bolt M24 Kit', 'Fasteners', 'SET', 1000, 2000, 18.50, (SELECT SUPPLIER_ID FROM SUPPLIER_MASTER WHERE SUPPLIER_CODE='SUP-1002'));

        INSERT INTO MATERIAL_MASTER (MATERIAL_ID, MATERIAL_CODE, MATERIAL_NAME, CATEGORY, UNIT_OF_MEASURE, SAFETY_STOCK, REORDER_LEVEL, STANDARD_COST, PREFERRED_SUPPLIER_ID)
        VALUES (5004, 'ZML-PANEL-ROOF', 'Zamil Double Skin Insulated Roof Panel 50mm', 'Panels', 'SFT', 200, 500, 85.00, (SELECT SUPPLIER_ID FROM SUPPLIER_MASTER WHERE SUPPLIER_CODE='SUP-1003'));

        INSERT INTO MATERIAL_MASTER (MATERIAL_ID, MATERIAL_CODE, MATERIAL_NAME, CATEGORY, UNIT_OF_MEASURE, SAFETY_STOCK, REORDER_LEVEL, STANDARD_COST, PREFERRED_SUPPLIER_ID)
        VALUES (5005, 'ZML-PANEL-WALL', 'Zamil Polyurethane Wall Cladding Panel 40mm', 'Panels', 'SFT', 250, 600, 78.00, (SELECT SUPPLIER_ID FROM SUPPLIER_MASTER WHERE SUPPLIER_CODE='SUP-1003'));

        -- 2. Insert Zamil PO Header & Lines
        -- PO 1
        INSERT INTO PURCHASE_ORDER (PO_ID, SUPPLIER_ID, PO_NUMBER, ORDER_STATUS, DELIVERY_DATE)
        VALUES (2001, (SELECT SUPPLIER_ID FROM SUPPLIER_MASTER WHERE SUPPLIER_CODE='SUP-1001'), 'ZML-PO-2026-0001', 'ISSUED', SYSDATE + 7);

        INSERT INTO PURCHASE_ORDER_ITEMS (PO_ITEM_ID, PO_ID, MATERIAL_ID, ORDERED_QTY, UNIT_PRICE, RECEIVED_QTY)
        VALUES (3001, 2001, 5001, 800, 120.00, 0);

        INSERT INTO PURCHASE_ORDER_ITEMS (PO_ITEM_ID, PO_ID, MATERIAL_ID, ORDERED_QTY, UNIT_PRICE, RECEIVED_QTY)
        VALUES (3002, 2001, 5002, 400, 145.00, 0);

        -- PO 2
        INSERT INTO PURCHASE_ORDER (PO_ID, SUPPLIER_ID, PO_NUMBER, ORDER_STATUS, DELIVERY_DATE)
        VALUES (2002, (SELECT SUPPLIER_ID FROM SUPPLIER_MASTER WHERE SUPPLIER_CODE='SUP-1002'), 'ZML-PO-2026-0002', 'ISSUED', SYSDATE + 5);

        INSERT INTO PURCHASE_ORDER_ITEMS (PO_ITEM_ID, PO_ID, MATERIAL_ID, ORDERED_QTY, UNIT_PRICE, RECEIVED_QTY)
        VALUES (3003, 2002, 5003, 3000, 18.50, 0);

        -- 3. Generate a pre-completed Receiver Goods Bill for ZML-PO-2026-0001
        CREATE_BILL(
            p_po_id         => 2001,
            p_delivery_note => 'ZML-DN-994821',
            p_received_by   => 'ZAMIL_WH_CLERK',
            p_remarks       => 'Zamil Steel structural beam partial shipment receipt',
            p_bill_id       => v_bill_id,
            p_bill_number   => v_bill_num
        );

        -- Add line items
        ADD_BILL_ITEM(v_bill_id, 5001, 500, 101, 501, 'Received 500 units H-Beams');
        ADD_BILL_ITEM(v_bill_id, 5002, 200, 101, 501, 'Received 200 units PEB Columns');

        -- Post the bill (commits stock and updates PO item counts)
        DECLARE
            v_st VARCHAR2(20);
            v_msg VARCHAR2(255);
        BEGIN
            POST_BILL(v_bill_id, v_st, v_msg);
        END;

        COMMIT;
    END SEED_ZAMIL_DATA;

END PKG_RECEIVER_GOODS_BILL;
/

PROMPT [SUCCESS] Package PKG_RECEIVER_GOODS_BILL compiled.
