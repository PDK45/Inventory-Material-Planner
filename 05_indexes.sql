-- ============================================================
-- MPPMS :: 05_indexes.sql
-- Run As: MPPMS user connected to FREEPDB1
-- Purpose: Performance indexes on all FK and search columns
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Creating Performance Indexes
PROMPT ============================================================

-- ============================================================
-- SUPPLIER_MASTER
-- ============================================================
CREATE INDEX IDX_SUPPLIER_STATUS
    ON SUPPLIER_MASTER(STATUS);

CREATE INDEX IDX_SUPPLIER_RATING
    ON SUPPLIER_MASTER(VENDOR_RATING DESC);

PROMPT [OK] SUPPLIER_MASTER indexes created.

-- ============================================================
-- MATERIAL_MASTER
-- ============================================================
CREATE INDEX IDX_MATERIAL_SUPPLIER
    ON MATERIAL_MASTER(PREFERRED_SUPPLIER_ID);

CREATE INDEX IDX_MATERIAL_STATUS
    ON MATERIAL_MASTER(STATUS);

CREATE INDEX IDX_MATERIAL_CATEGORY
    ON MATERIAL_MASTER(CATEGORY);

PROMPT [OK] MATERIAL_MASTER indexes created.

-- ============================================================
-- PRODUCT_MASTER
-- ============================================================
CREATE INDEX IDX_PRODUCT_STATUS
    ON PRODUCT_MASTER(STATUS);

CREATE INDEX IDX_PRODUCT_CATEGORY
    ON PRODUCT_MASTER(PRODUCT_CATEGORY);

PROMPT [OK] PRODUCT_MASTER indexes created.

-- ============================================================
-- BOM_MASTER
-- ============================================================
CREATE INDEX IDX_BOM_PRODUCT
    ON BOM_MASTER(PRODUCT_ID);

CREATE INDEX IDX_BOM_STATUS
    ON BOM_MASTER(STATUS);

CREATE INDEX IDX_BOM_EFFECTIVE
    ON BOM_MASTER(EFFECTIVE_DATE DESC);

PROMPT [OK] BOM_MASTER indexes created.

-- ============================================================
-- BOM_DETAILS
-- ============================================================
CREATE INDEX IDX_BOMDET_BOM
    ON BOM_DETAILS(BOM_ID);

CREATE INDEX IDX_BOMDET_MATERIAL
    ON BOM_DETAILS(MATERIAL_ID);

PROMPT [OK] BOM_DETAILS indexes created.

-- ============================================================
-- DEMAND_FORECAST
-- ============================================================
CREATE INDEX IDX_FORECAST_PRODUCT
    ON DEMAND_FORECAST(PRODUCT_ID);

CREATE INDEX IDX_FORECAST_PERIOD
    ON DEMAND_FORECAST(FORECAST_PERIOD DESC);

CREATE INDEX IDX_FORECAST_TYPE
    ON DEMAND_FORECAST(FORECAST_TYPE);

PROMPT [OK] DEMAND_FORECAST indexes created.

-- ============================================================
-- PRODUCTION_PLAN
-- ============================================================
CREATE INDEX IDX_PLAN_PRODUCT
    ON PRODUCTION_PLAN(PRODUCT_ID);

CREATE INDEX IDX_PLAN_STATUS
    ON PRODUCTION_PLAN(STATUS);

CREATE INDEX IDX_PLAN_START_DATE
    ON PRODUCTION_PLAN(PLANNED_START_DATE DESC);

PROMPT [OK] PRODUCTION_PLAN indexes created.

-- ============================================================
-- MATERIAL_REQUIREMENT_PLAN
-- ============================================================
CREATE INDEX IDX_MRP_PLAN
    ON MATERIAL_REQUIREMENT_PLAN(PLAN_ID);

CREATE INDEX IDX_MRP_MATERIAL
    ON MATERIAL_REQUIREMENT_PLAN(MATERIAL_ID);

CREATE INDEX IDX_MRP_STATUS
    ON MATERIAL_REQUIREMENT_PLAN(MRP_STATUS);

CREATE INDEX IDX_MRP_REQUIRED_DATE
    ON MATERIAL_REQUIREMENT_PLAN(REQUIRED_DATE);

-- Composite: shortage detection (net requirement > 0 queries)
CREATE INDEX IDX_MRP_SHORTAGE
    ON MATERIAL_REQUIREMENT_PLAN(PLAN_ID, NET_REQUIREMENT DESC);

PROMPT [OK] MATERIAL_REQUIREMENT_PLAN indexes created.

-- ============================================================
-- PURCHASE_REQUISITION
-- ============================================================
CREATE INDEX IDX_PR_MRP
    ON PURCHASE_REQUISITION(MRP_ID);

CREATE INDEX IDX_PR_MATERIAL
    ON PURCHASE_REQUISITION(MATERIAL_ID);

CREATE INDEX IDX_PR_STATUS
    ON PURCHASE_REQUISITION(STATUS);

CREATE INDEX IDX_PR_PRIORITY
    ON PURCHASE_REQUISITION(PRIORITY);

CREATE INDEX IDX_PR_REQUIRED_DATE
    ON PURCHASE_REQUISITION(REQUIRED_DATE);

CREATE INDEX IDX_PR_CREATED_DATE
    ON PURCHASE_REQUISITION(CREATED_DATE DESC);

PROMPT [OK] PURCHASE_REQUISITION indexes created.

-- ============================================================
-- PURCHASE_ORDER
-- ============================================================
CREATE INDEX IDX_PO_PR
    ON PURCHASE_ORDER(PR_ID);

CREATE INDEX IDX_PO_SUPPLIER
    ON PURCHASE_ORDER(SUPPLIER_ID);

CREATE INDEX IDX_PO_STATUS
    ON PURCHASE_ORDER(ORDER_STATUS);

CREATE INDEX IDX_PO_ORDER_DATE
    ON PURCHASE_ORDER(ORDER_DATE DESC);

CREATE INDEX IDX_PO_DELIVERY_DATE
    ON PURCHASE_ORDER(DELIVERY_DATE);

PROMPT [OK] PURCHASE_ORDER indexes created.

-- ============================================================
-- PURCHASE_ORDER_ITEMS
-- ============================================================
CREATE INDEX IDX_POITEM_PO
    ON PURCHASE_ORDER_ITEMS(PO_ID);

CREATE INDEX IDX_POITEM_MATERIAL
    ON PURCHASE_ORDER_ITEMS(MATERIAL_ID);

PROMPT [OK] PURCHASE_ORDER_ITEMS indexes created.

-- ============================================================
-- PROCUREMENT_TRACKING
-- ============================================================
CREATE INDEX IDX_TRACKING_PO
    ON PROCUREMENT_TRACKING(PO_ID);

CREATE INDEX IDX_TRACKING_STATUS
    ON PROCUREMENT_TRACKING(DELIVERY_STATUS);

CREATE INDEX IDX_TRACKING_EXP_DATE
    ON PROCUREMENT_TRACKING(EXPECTED_DATE);

PROMPT [OK] PROCUREMENT_TRACKING indexes created.

-- ============================================================
-- Verification
-- ============================================================
PROMPT 
PROMPT ============================================================
PROMPT  All MPPMS Indexes
PROMPT ============================================================
SELECT index_name, table_name, uniqueness, status
FROM user_indexes
ORDER BY table_name, index_name;

PROMPT 
PROMPT [SUCCESS] Phase 1 & 2 Complete.
PROMPT All 12 tables, 14 sequences, 14 triggers, and 33 indexes created.
PROMPT Next Step: Run 06_sample_data.sql (Phase 3)
