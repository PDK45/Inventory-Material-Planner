-- ============================================================
-- MPPMS :: 04_triggers.sql
-- Run As: MPPMS user connected to FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Creating Triggers
PROMPT ============================================================

-- ============================================================
-- TRIGGER 1: SUPPLIER_MASTER - Auto PK
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_SUPPLIER_BI
    BEFORE INSERT ON SUPPLIER_MASTER
    FOR EACH ROW
BEGIN
    IF :NEW.SUPPLIER_ID IS NULL THEN
        :NEW.SUPPLIER_ID := SEQ_SUPPLIER_ID.NEXTVAL;
    END IF;
    IF :NEW.CREATED_DATE IS NULL THEN
        :NEW.CREATED_DATE := SYSDATE;
    END IF;
END TRG_SUPPLIER_BI;
/
PROMPT [OK] TRG_SUPPLIER_BI created.

-- ============================================================
-- TRIGGER 2: MATERIAL_MASTER - Auto PK
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_MATERIAL_BI
    BEFORE INSERT ON MATERIAL_MASTER
    FOR EACH ROW
BEGIN
    IF :NEW.MATERIAL_ID IS NULL THEN
        :NEW.MATERIAL_ID := SEQ_MATERIAL_ID.NEXTVAL;
    END IF;
    IF :NEW.CREATED_DATE IS NULL THEN
        :NEW.CREATED_DATE := SYSDATE;
    END IF;
END TRG_MATERIAL_BI;
/
PROMPT [OK] TRG_MATERIAL_BI created.

-- ============================================================
-- TRIGGER 3: PRODUCT_MASTER - Auto PK
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_PRODUCT_BI
    BEFORE INSERT ON PRODUCT_MASTER
    FOR EACH ROW
BEGIN
    IF :NEW.PRODUCT_ID IS NULL THEN
        :NEW.PRODUCT_ID := SEQ_PRODUCT_ID.NEXTVAL;
    END IF;
    IF :NEW.CREATED_DATE IS NULL THEN
        :NEW.CREATED_DATE := SYSDATE;
    END IF;
END TRG_PRODUCT_BI;
/
PROMPT [OK] TRG_PRODUCT_BI created.

-- ============================================================
-- TRIGGER 4: BOM_MASTER - Auto PK
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_BOM_BI
    BEFORE INSERT ON BOM_MASTER
    FOR EACH ROW
BEGIN
    IF :NEW.BOM_ID IS NULL THEN
        :NEW.BOM_ID := SEQ_BOM_ID.NEXTVAL;
    END IF;
    IF :NEW.CREATED_DATE IS NULL THEN
        :NEW.CREATED_DATE := SYSDATE;
    END IF;
END TRG_BOM_BI;
/
PROMPT [OK] TRG_BOM_BI created.

-- ============================================================
-- TRIGGER 5: BOM_DETAILS - Auto PK
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_BOM_DETAIL_BI
    BEFORE INSERT ON BOM_DETAILS
    FOR EACH ROW
BEGIN
    IF :NEW.BOM_DETAIL_ID IS NULL THEN
        :NEW.BOM_DETAIL_ID := SEQ_BOM_DETAIL_ID.NEXTVAL;
    END IF;
END TRG_BOM_DETAIL_BI;
/
PROMPT [OK] TRG_BOM_DETAIL_BI created.

-- ============================================================
-- TRIGGER 6: DEMAND_FORECAST - Auto PK
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_FORECAST_BI
    BEFORE INSERT ON DEMAND_FORECAST
    FOR EACH ROW
BEGIN
    IF :NEW.FORECAST_ID IS NULL THEN
        :NEW.FORECAST_ID := SEQ_FORECAST_ID.NEXTVAL;
    END IF;
    IF :NEW.CREATED_DATE IS NULL THEN
        :NEW.CREATED_DATE := SYSDATE;
    END IF;
END TRG_FORECAST_BI;
/
PROMPT [OK] TRG_FORECAST_BI created.

-- ============================================================
-- TRIGGER 7: PRODUCTION_PLAN - Auto PK
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_PLAN_BI
    BEFORE INSERT ON PRODUCTION_PLAN
    FOR EACH ROW
BEGIN
    IF :NEW.PLAN_ID IS NULL THEN
        :NEW.PLAN_ID := SEQ_PLAN_ID.NEXTVAL;
    END IF;
    IF :NEW.CREATED_DATE IS NULL THEN
        :NEW.CREATED_DATE := SYSDATE;
    END IF;
END TRG_PLAN_BI;
/
PROMPT [OK] TRG_PLAN_BI created.

-- ============================================================
-- TRIGGER 8: MATERIAL_REQUIREMENT_PLAN - Auto PK
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_MRP_BI
    BEFORE INSERT ON MATERIAL_REQUIREMENT_PLAN
    FOR EACH ROW
BEGIN
    IF :NEW.MRP_ID IS NULL THEN
        :NEW.MRP_ID := SEQ_MRP_ID.NEXTVAL;
    END IF;
    IF :NEW.CALCULATED_DATE IS NULL THEN
        :NEW.CALCULATED_DATE := SYSDATE;
    END IF;
    -- Auto-calculate net requirement
    :NEW.NET_REQUIREMENT := GREATEST(
        0,
        :NEW.GROSS_REQUIREMENT - :NEW.AVAILABLE_QTY + :NEW.SAFETY_STOCK
    );
    -- Planned order qty = net requirement (can be adjusted by lot sizing later)
    :NEW.PLANNED_ORDER_QTY := :NEW.NET_REQUIREMENT;
END TRG_MRP_BI;
/
PROMPT [OK] TRG_MRP_BI created.

-- ============================================================
-- TRIGGER 9: PURCHASE_REQUISITION - Auto PK + PR Number
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_PR_BI
    BEFORE INSERT ON PURCHASE_REQUISITION
    FOR EACH ROW
BEGIN
    IF :NEW.PR_ID IS NULL THEN
        :NEW.PR_ID := SEQ_PR_ID.NEXTVAL;
    END IF;
    IF :NEW.PR_NUMBER IS NULL THEN
        :NEW.PR_NUMBER := 'PR-' || TO_CHAR(SYSDATE,'YYYY') || '-' ||
                          LPAD(SEQ_PR_NUMBER.NEXTVAL, 5, '0');
    END IF;
    IF :NEW.CREATED_DATE IS NULL THEN
        :NEW.CREATED_DATE := SYSDATE;
    END IF;
END TRG_PR_BI;
/
PROMPT [OK] TRG_PR_BI created.

-- ============================================================
-- TRIGGER 10: PURCHASE_ORDER - Auto PK + PO Number
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_PO_BI
    BEFORE INSERT ON PURCHASE_ORDER
    FOR EACH ROW
BEGIN
    IF :NEW.PO_ID IS NULL THEN
        :NEW.PO_ID := SEQ_PO_ID.NEXTVAL;
    END IF;
    IF :NEW.PO_NUMBER IS NULL THEN
        :NEW.PO_NUMBER := 'PO-' || TO_CHAR(SYSDATE,'YYYY') || '-' ||
                          LPAD(SEQ_PO_NUMBER.NEXTVAL, 5, '0');
    END IF;
    IF :NEW.ORDER_DATE IS NULL THEN
        :NEW.ORDER_DATE := SYSDATE;
    END IF;
    IF :NEW.CREATED_DATE IS NULL THEN
        :NEW.CREATED_DATE := SYSDATE;
    END IF;
END TRG_PO_BI;
/
PROMPT [OK] TRG_PO_BI created.

-- ============================================================
-- TRIGGER 11: PURCHASE_ORDER_ITEMS - Auto PK
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_PO_ITEM_BI
    BEFORE INSERT ON PURCHASE_ORDER_ITEMS
    FOR EACH ROW
BEGIN
    IF :NEW.PO_ITEM_ID IS NULL THEN
        :NEW.PO_ITEM_ID := SEQ_PO_ITEM_ID.NEXTVAL;
    END IF;
END TRG_PO_ITEM_BI;
/
PROMPT [OK] TRG_PO_ITEM_BI created.

-- ============================================================
-- TRIGGER 12: PROCUREMENT_TRACKING - Auto PK
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_TRACKING_BI
    BEFORE INSERT ON PROCUREMENT_TRACKING
    FOR EACH ROW
BEGIN
    IF :NEW.TRACKING_ID IS NULL THEN
        :NEW.TRACKING_ID := SEQ_TRACKING_ID.NEXTVAL;
    END IF;
    IF :NEW.UPDATED_DATE IS NULL THEN
        :NEW.UPDATED_DATE := SYSDATE;
    END IF;
END TRG_TRACKING_BI;
/
PROMPT [OK] TRG_TRACKING_BI created.

-- ============================================================
-- TRIGGER 13: PO Total Value Rollup (AFTER INSERT/UPDATE on items)
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_PO_TOTAL_AIU
    AFTER INSERT OR UPDATE OR DELETE ON PURCHASE_ORDER_ITEMS
    FOR EACH ROW
DECLARE
    v_delta NUMBER := 0;
    v_po_id NUMBER;
BEGIN
    IF INSERTING THEN
        v_delta := NVL(:NEW.ORDERED_QTY, 0) * NVL(:NEW.UNIT_PRICE, 0);
        v_po_id := :NEW.PO_ID;
    ELSIF UPDATING THEN
        v_delta := (NVL(:NEW.ORDERED_QTY, 0) * NVL(:NEW.UNIT_PRICE, 0)) - 
                   (NVL(:OLD.ORDERED_QTY, 0) * NVL(:OLD.UNIT_PRICE, 0));
        v_po_id := :NEW.PO_ID;
    ELSIF DELETING THEN
        v_delta := - (NVL(:OLD.ORDERED_QTY, 0) * NVL(:OLD.UNIT_PRICE, 0));
        v_po_id := :OLD.PO_ID;
    END IF;

    UPDATE PURCHASE_ORDER po
       SET po.TOTAL_VALUE = NVL(po.TOTAL_VALUE, 0) + v_delta
     WHERE po.PO_ID = v_po_id;
END TRG_PO_TOTAL_AIU;
/
PROMPT [OK] TRG_PO_TOTAL_AIU (PO total rollup) created.

-- ============================================================
-- TRIGGER 14: PROCUREMENT_TRACKING - Update timestamp on change
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_TRACKING_BU
    BEFORE UPDATE ON PROCUREMENT_TRACKING
    FOR EACH ROW
BEGIN
    :NEW.UPDATED_DATE := SYSDATE;
END TRG_TRACKING_BU;
/
PROMPT [OK] TRG_TRACKING_BU created.

-- Verification
PROMPT 
SELECT trigger_name, table_name, trigger_type, status
FROM user_triggers
ORDER BY table_name;

PROMPT [SUCCESS] All 14 triggers created. Next Step: Run 05_indexes.sql
