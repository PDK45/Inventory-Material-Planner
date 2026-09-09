-- ============================================================
-- MPPMS :: 02_create_tables.sql
-- Run As: MPPMS user connected to FREEPDB1
-- sqlplus mppms/"MPPMS#2026Secure"@FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Creating Tables (Build Order: FK-dependency aware)
PROMPT ============================================================

-- ============================================================
-- TABLE 1: SUPPLIER_MASTER
-- ============================================================
CREATE TABLE SUPPLIER_MASTER (
    SUPPLIER_ID       NUMBER          NOT NULL,
    SUPPLIER_CODE     VARCHAR2(20)    NOT NULL,
    SUPPLIER_NAME     VARCHAR2(200)   NOT NULL,
    CONTACT_PERSON    VARCHAR2(100),
    EMAIL             VARCHAR2(150),
    PHONE             VARCHAR2(30),
    ADDRESS           VARCHAR2(500),
    LEAD_TIME         NUMBER(5)       DEFAULT 0 NOT NULL,
    VENDOR_RATING     NUMBER(3,1)     DEFAULT 0,
    STATUS            VARCHAR2(10)    DEFAULT 'ACTIVE' NOT NULL,
    CREATED_DATE      DATE            DEFAULT SYSDATE NOT NULL,
    -- Constraints
    CONSTRAINT PK_SUPPLIER        PRIMARY KEY (SUPPLIER_ID),
    CONSTRAINT UQ_SUPPLIER_CODE   UNIQUE (SUPPLIER_CODE),
    CONSTRAINT CK_SUPPLIER_STATUS CHECK (STATUS IN ('ACTIVE','INACTIVE')),
    CONSTRAINT CK_VENDOR_RATING   CHECK (VENDOR_RATING BETWEEN 0 AND 5),
    CONSTRAINT CK_LEAD_TIME_SUP   CHECK (LEAD_TIME >= 0)
);

COMMENT ON TABLE  SUPPLIER_MASTER             IS 'Master table for all approved vendors and suppliers';
COMMENT ON COLUMN SUPPLIER_MASTER.SUPPLIER_CODE IS 'Unique supplier code e.g. SUP-1001';
COMMENT ON COLUMN SUPPLIER_MASTER.LEAD_TIME     IS 'Standard lead time in days';
COMMENT ON COLUMN SUPPLIER_MASTER.VENDOR_RATING IS 'Rating 0-5 based on performance';

PROMPT [OK] SUPPLIER_MASTER created.

-- ============================================================
-- TABLE 2: MATERIAL_MASTER
-- ============================================================
CREATE TABLE MATERIAL_MASTER (
    MATERIAL_ID           NUMBER        NOT NULL,
    MATERIAL_CODE         VARCHAR2(30)  NOT NULL,
    MATERIAL_NAME         VARCHAR2(200) NOT NULL,
    CATEGORY              VARCHAR2(100),
    UNIT_OF_MEASURE       VARCHAR2(20)  NOT NULL,
    SAFETY_STOCK          NUMBER(15,3)  DEFAULT 0 NOT NULL,
    REORDER_LEVEL         NUMBER(15,3)  DEFAULT 0 NOT NULL,
    LEAD_TIME             NUMBER(5)     DEFAULT 0 NOT NULL,
    STANDARD_COST         NUMBER(15,4)  DEFAULT 0 NOT NULL,
    PREFERRED_SUPPLIER_ID NUMBER,
    STATUS                VARCHAR2(10)  DEFAULT 'ACTIVE' NOT NULL,
    CREATED_DATE          DATE          DEFAULT SYSDATE NOT NULL,
    -- Constraints
    CONSTRAINT PK_MATERIAL          PRIMARY KEY (MATERIAL_ID),
    CONSTRAINT UQ_MATERIAL_CODE     UNIQUE (MATERIAL_CODE),
    CONSTRAINT FK_MATERIAL_SUPPLIER FOREIGN KEY (PREFERRED_SUPPLIER_ID)
                                    REFERENCES SUPPLIER_MASTER(SUPPLIER_ID),
    CONSTRAINT CK_MATERIAL_STATUS   CHECK (STATUS IN ('ACTIVE','INACTIVE')),
    CONSTRAINT CK_SAFETY_STOCK      CHECK (SAFETY_STOCK >= 0),
    CONSTRAINT CK_REORDER_LEVEL     CHECK (REORDER_LEVEL >= 0),
    CONSTRAINT CK_STANDARD_COST     CHECK (STANDARD_COST >= 0),
    CONSTRAINT CK_LEAD_TIME_MAT     CHECK (LEAD_TIME >= 0)
);

COMMENT ON TABLE  MATERIAL_MASTER IS 'Master table for raw materials, components, and consumables';

PROMPT [OK] MATERIAL_MASTER created.

-- ============================================================
-- TABLE 3: PRODUCT_MASTER
-- ============================================================
CREATE TABLE PRODUCT_MASTER (
    PRODUCT_ID        NUMBER        NOT NULL,
    PRODUCT_CODE      VARCHAR2(30)  NOT NULL,
    PRODUCT_NAME      VARCHAR2(200) NOT NULL,
    PRODUCT_CATEGORY  VARCHAR2(100),
    DESCRIPTION       VARCHAR2(1000),
    STATUS            VARCHAR2(10)  DEFAULT 'ACTIVE' NOT NULL,
    CREATED_DATE      DATE          DEFAULT SYSDATE NOT NULL,
    -- Constraints
    CONSTRAINT PK_PRODUCT        PRIMARY KEY (PRODUCT_ID),
    CONSTRAINT UQ_PRODUCT_CODE   UNIQUE (PRODUCT_CODE),
    CONSTRAINT CK_PRODUCT_STATUS CHECK (STATUS IN ('ACTIVE','INACTIVE'))
);

COMMENT ON TABLE PRODUCT_MASTER IS 'Finished goods and assemblies subject to demand planning';

PROMPT [OK] PRODUCT_MASTER created.

-- ============================================================
-- TABLE 4: BOM_MASTER (Bill of Materials Header)
-- ============================================================
CREATE TABLE BOM_MASTER (
    BOM_ID          NUMBER       NOT NULL,
    PRODUCT_ID      NUMBER       NOT NULL,
    VERSION         VARCHAR2(10) NOT NULL,
    EFFECTIVE_DATE  DATE         NOT NULL,
    STATUS          VARCHAR2(10) DEFAULT 'ACTIVE' NOT NULL,
    CREATED_DATE    DATE         DEFAULT SYSDATE NOT NULL,
    -- Constraints
    CONSTRAINT PK_BOM          PRIMARY KEY (BOM_ID),
    CONSTRAINT FK_BOM_PRODUCT  FOREIGN KEY (PRODUCT_ID)
                               REFERENCES PRODUCT_MASTER(PRODUCT_ID),
    CONSTRAINT UQ_BOM_PROD_VER UNIQUE (PRODUCT_ID, VERSION),
    CONSTRAINT CK_BOM_STATUS   CHECK (STATUS IN ('ACTIVE','INACTIVE','DRAFT'))
);

COMMENT ON TABLE BOM_MASTER IS 'Bill of Materials header. Each product can have multiple versioned BOMs';

PROMPT [OK] BOM_MASTER created.

-- ============================================================
-- TABLE 5: BOM_DETAILS (Bill of Materials Lines)
-- ============================================================
CREATE TABLE BOM_DETAILS (
    BOM_DETAIL_ID     NUMBER       NOT NULL,
    BOM_ID            NUMBER       NOT NULL,
    MATERIAL_ID       NUMBER       NOT NULL,
    QUANTITY_REQUIRED NUMBER(15,4) NOT NULL,
    UNIT_OF_MEASURE   VARCHAR2(20),
    REMARKS           VARCHAR2(500),
    -- Constraints
    CONSTRAINT PK_BOM_DETAIL       PRIMARY KEY (BOM_DETAIL_ID),
    CONSTRAINT FK_BOMDET_BOM       FOREIGN KEY (BOM_ID)
                                   REFERENCES BOM_MASTER(BOM_ID) ON DELETE CASCADE,
    CONSTRAINT FK_BOMDET_MATERIAL  FOREIGN KEY (MATERIAL_ID)
                                   REFERENCES MATERIAL_MASTER(MATERIAL_ID),
    CONSTRAINT UQ_BOM_MATERIAL     UNIQUE (BOM_ID, MATERIAL_ID),
    CONSTRAINT CK_QTY_REQUIRED     CHECK (QUANTITY_REQUIRED > 0)
);

COMMENT ON TABLE BOM_DETAILS IS 'BOM line items: material components and quantities per finished good';

PROMPT [OK] BOM_DETAILS created.

-- ============================================================
-- TABLE 6: DEMAND_FORECAST
-- ============================================================
CREATE TABLE DEMAND_FORECAST (
    FORECAST_ID     NUMBER       NOT NULL,
    PRODUCT_ID      NUMBER       NOT NULL,
    FORECAST_PERIOD DATE         NOT NULL,
    FORECAST_QTY    NUMBER(15,3) NOT NULL,
    FORECAST_TYPE   VARCHAR2(20) DEFAULT 'MANUAL' NOT NULL,
    CREATED_BY      VARCHAR2(50),
    CREATED_DATE    DATE         DEFAULT SYSDATE NOT NULL,
    -- Constraints
    CONSTRAINT PK_FORECAST         PRIMARY KEY (FORECAST_ID),
    CONSTRAINT FK_FORECAST_PRODUCT FOREIGN KEY (PRODUCT_ID)
                                   REFERENCES PRODUCT_MASTER(PRODUCT_ID),
    CONSTRAINT CK_FORECAST_QTY     CHECK (FORECAST_QTY > 0),
    CONSTRAINT CK_FORECAST_TYPE    CHECK (FORECAST_TYPE IN ('MANUAL','SYSTEM','AI','HISTORICAL'))
);

COMMENT ON TABLE DEMAND_FORECAST IS 'Periodic demand forecasts per product used to drive production planning';

PROMPT [OK] DEMAND_FORECAST created.

-- ============================================================
-- TABLE 7: PRODUCTION_PLAN
-- ============================================================
CREATE TABLE PRODUCTION_PLAN (
    PLAN_ID             NUMBER        NOT NULL,
    PRODUCT_ID          NUMBER        NOT NULL,
    PLAN_NAME           VARCHAR2(100),
    PLANNED_QTY         NUMBER(15,3)  NOT NULL,
    PLANNED_START_DATE  DATE          NOT NULL,
    PLANNED_END_DATE    DATE          NOT NULL,
    STATUS              VARCHAR2(20)  DEFAULT 'DRAFT' NOT NULL,
    APPROVED_BY         VARCHAR2(100),
    APPROVED_DATE       DATE,
    CREATED_BY          VARCHAR2(50),
    CREATED_DATE        DATE          DEFAULT SYSDATE NOT NULL,
    -- Constraints
    CONSTRAINT PK_PLAN          PRIMARY KEY (PLAN_ID),
    CONSTRAINT FK_PLAN_PRODUCT  FOREIGN KEY (PRODUCT_ID)
                                REFERENCES PRODUCT_MASTER(PRODUCT_ID),
    CONSTRAINT CK_PLAN_STATUS   CHECK (STATUS IN ('DRAFT','APPROVED','IN_PROGRESS','COMPLETED','CANCELLED')),
    CONSTRAINT CK_PLAN_QTY      CHECK (PLANNED_QTY > 0),
    CONSTRAINT CK_PLAN_DATES    CHECK (PLANNED_END_DATE >= PLANNED_START_DATE)
);

COMMENT ON TABLE PRODUCTION_PLAN IS 'Production planning header driving MRP calculations';

PROMPT [OK] PRODUCTION_PLAN created.

-- ============================================================
-- TABLE 8: MATERIAL_REQUIREMENT_PLAN (MRP)
-- ============================================================
CREATE TABLE MATERIAL_REQUIREMENT_PLAN (
    MRP_ID              NUMBER       NOT NULL,
    PLAN_ID             NUMBER       NOT NULL,
    MATERIAL_ID         NUMBER       NOT NULL,
    GROSS_REQUIREMENT   NUMBER(15,3) DEFAULT 0 NOT NULL,
    AVAILABLE_QTY       NUMBER(15,3) DEFAULT 0 NOT NULL,
    SAFETY_STOCK        NUMBER(15,3) DEFAULT 0 NOT NULL,
    NET_REQUIREMENT     NUMBER(15,3) DEFAULT 0 NOT NULL,
    PLANNED_ORDER_QTY   NUMBER(15,3) DEFAULT 0 NOT NULL,
    REQUIRED_DATE       DATE         NOT NULL,
    MRP_STATUS          VARCHAR2(20) DEFAULT 'CALCULATED' NOT NULL,
    CALCULATED_DATE     DATE         DEFAULT SYSDATE,
    -- Constraints
    CONSTRAINT PK_MRP           PRIMARY KEY (MRP_ID),
    CONSTRAINT FK_MRP_PLAN      FOREIGN KEY (PLAN_ID)
                                REFERENCES PRODUCTION_PLAN(PLAN_ID),
    CONSTRAINT FK_MRP_MATERIAL  FOREIGN KEY (MATERIAL_ID)
                                REFERENCES MATERIAL_MASTER(MATERIAL_ID),
    CONSTRAINT CK_MRP_STATUS    CHECK (MRP_STATUS IN ('CALCULATED','PR_RAISED','CLOSED')),
    CONSTRAINT CK_GROSS_REQ     CHECK (GROSS_REQUIREMENT >= 0)
);

COMMENT ON TABLE MATERIAL_REQUIREMENT_PLAN IS 'System-calculated material requirements per production plan';

PROMPT [OK] MATERIAL_REQUIREMENT_PLAN created.

-- ============================================================
-- TABLE 9: PURCHASE_REQUISITION
-- ============================================================
CREATE TABLE PURCHASE_REQUISITION (
    PR_ID           NUMBER        NOT NULL,
    PR_NUMBER       VARCHAR2(25)  NOT NULL,
    MRP_ID          NUMBER,
    MATERIAL_ID     NUMBER        NOT NULL,
    REQUESTED_QTY   NUMBER(15,3)  NOT NULL,
    REQUIRED_DATE   DATE          NOT NULL,
    PRIORITY        VARCHAR2(10)  DEFAULT 'MEDIUM' NOT NULL,
    STATUS          VARCHAR2(20)  DEFAULT 'DRAFT' NOT NULL,
    JUSTIFICATION   VARCHAR2(1000),
    REQUESTED_BY    VARCHAR2(100),
    APPROVED_BY     VARCHAR2(100),
    APPROVED_DATE   DATE,
    CREATED_DATE    DATE          DEFAULT SYSDATE NOT NULL,
    -- Constraints
    CONSTRAINT PK_PR          PRIMARY KEY (PR_ID),
    CONSTRAINT UQ_PR_NUMBER   UNIQUE (PR_NUMBER),
    CONSTRAINT FK_PR_MRP      FOREIGN KEY (MRP_ID)
                              REFERENCES MATERIAL_REQUIREMENT_PLAN(MRP_ID),
    CONSTRAINT FK_PR_MATERIAL FOREIGN KEY (MATERIAL_ID)
                              REFERENCES MATERIAL_MASTER(MATERIAL_ID),
    CONSTRAINT CK_PR_PRIORITY CHECK (PRIORITY IN ('HIGH','MEDIUM','LOW')),
    CONSTRAINT CK_PR_STATUS   CHECK (STATUS IN ('DRAFT','SUBMITTED','APPROVED','REJECTED','ORDERED','CLOSED')),
    CONSTRAINT CK_PR_QTY      CHECK (REQUESTED_QTY > 0)
);

COMMENT ON TABLE PURCHASE_REQUISITION IS 'Internal purchase requests raised from MRP or manually';

PROMPT [OK] PURCHASE_REQUISITION created.

-- ============================================================
-- TABLE 10: PURCHASE_ORDER
-- ============================================================
CREATE TABLE PURCHASE_ORDER (
    PO_ID           NUMBER        NOT NULL,
    PR_ID           NUMBER,
    SUPPLIER_ID     NUMBER        NOT NULL,
    PO_NUMBER       VARCHAR2(25)  NOT NULL,
    ORDER_DATE      DATE          DEFAULT SYSDATE NOT NULL,
    DELIVERY_DATE   DATE          NOT NULL,
    ORDER_STATUS    VARCHAR2(25)  DEFAULT 'DRAFT' NOT NULL,
    TOTAL_VALUE     NUMBER(18,4)  DEFAULT 0,
    TERMS           VARCHAR2(500),
    CREATED_BY      VARCHAR2(100),
    CREATED_DATE    DATE          DEFAULT SYSDATE NOT NULL,
    -- Constraints
    CONSTRAINT PK_PO           PRIMARY KEY (PO_ID),
    CONSTRAINT UQ_PO_NUMBER    UNIQUE (PO_NUMBER),
    CONSTRAINT FK_PO_PR        FOREIGN KEY (PR_ID)
                               REFERENCES PURCHASE_REQUISITION(PR_ID),
    CONSTRAINT FK_PO_SUPPLIER  FOREIGN KEY (SUPPLIER_ID)
                               REFERENCES SUPPLIER_MASTER(SUPPLIER_ID),
    CONSTRAINT CK_PO_STATUS    CHECK (ORDER_STATUS IN (
                                   'DRAFT','ISSUED','ACKNOWLEDGED',
                                   'PARTIALLY_RECEIVED','RECEIVED','CANCELLED')),
    CONSTRAINT CK_PO_DATES     CHECK (DELIVERY_DATE >= ORDER_DATE)
);

COMMENT ON TABLE PURCHASE_ORDER IS 'Purchase order headers raised to approved suppliers';

PROMPT [OK] PURCHASE_ORDER created.

-- ============================================================
-- TABLE 11: PURCHASE_ORDER_ITEMS
-- ============================================================
CREATE TABLE PURCHASE_ORDER_ITEMS (
    PO_ITEM_ID    NUMBER       NOT NULL,
    PO_ID         NUMBER       NOT NULL,
    MATERIAL_ID   NUMBER       NOT NULL,
    ORDERED_QTY   NUMBER(15,3) NOT NULL,
    UNIT_PRICE    NUMBER(15,4) NOT NULL,
    TOTAL_VALUE   NUMBER(18,4) GENERATED ALWAYS AS (ORDERED_QTY * UNIT_PRICE) VIRTUAL,
    RECEIVED_QTY  NUMBER(15,3) DEFAULT 0,
    REMARKS       VARCHAR2(500),
    -- Constraints
    CONSTRAINT PK_PO_ITEM        PRIMARY KEY (PO_ITEM_ID),
    CONSTRAINT FK_POITEM_PO      FOREIGN KEY (PO_ID)
                                 REFERENCES PURCHASE_ORDER(PO_ID) ON DELETE CASCADE,
    CONSTRAINT FK_POITEM_MAT     FOREIGN KEY (MATERIAL_ID)
                                 REFERENCES MATERIAL_MASTER(MATERIAL_ID),
    CONSTRAINT UQ_PO_MATERIAL    UNIQUE (PO_ID, MATERIAL_ID),
    CONSTRAINT CK_ORDERED_QTY    CHECK (ORDERED_QTY > 0),
    CONSTRAINT CK_UNIT_PRICE     CHECK (UNIT_PRICE >= 0),
    CONSTRAINT CK_RECEIVED_QTY   CHECK (RECEIVED_QTY >= 0)
);

COMMENT ON TABLE PURCHASE_ORDER_ITEMS IS 'Line items for each purchase order. TOTAL_VALUE is a virtual computed column';

PROMPT [OK] PURCHASE_ORDER_ITEMS created.

-- ============================================================
-- TABLE 12: PROCUREMENT_TRACKING
-- ============================================================
CREATE TABLE PROCUREMENT_TRACKING (
    TRACKING_ID       NUMBER        NOT NULL,
    PO_ID             NUMBER        NOT NULL,
    EXPECTED_DATE     DATE,
    ACTUAL_DATE       DATE,
    DELIVERY_STATUS   VARCHAR2(30)  DEFAULT 'PENDING' NOT NULL,
    REMARKS           VARCHAR2(1000),
    UPDATED_BY        VARCHAR2(100),
    UPDATED_DATE      DATE          DEFAULT SYSDATE NOT NULL,
    -- Constraints
    CONSTRAINT PK_TRACKING         PRIMARY KEY (TRACKING_ID),
    CONSTRAINT FK_TRACKING_PO      FOREIGN KEY (PO_ID)
                                   REFERENCES PURCHASE_ORDER(PO_ID),
    CONSTRAINT CK_DELIVERY_STATUS  CHECK (DELIVERY_STATUS IN (
                                       'PENDING','IN_TRANSIT','PARTIALLY_DELIVERED',
                                       'DELIVERED','RETURNED','CANCELLED'))
);

COMMENT ON TABLE PROCUREMENT_TRACKING IS 'Real-time delivery tracking per purchase order';

PROMPT [OK] PROCUREMENT_TRACKING created.

-- ============================================================
-- Final Verification
-- ============================================================
PROMPT 
PROMPT ============================================================
PROMPT  Verification: All MPPMS Tables
PROMPT ============================================================
SELECT 
    table_name,
    num_rows,
    status
FROM user_tables
ORDER BY table_name;

PROMPT 
PROMPT ============================================================
PROMPT  Verification: All Constraints
PROMPT ============================================================
SELECT 
    table_name,
    constraint_name,
    constraint_type,
    status
FROM user_constraints
ORDER BY table_name, constraint_type;

PROMPT 
PROMPT [SUCCESS] All 12 tables created successfully.
PROMPT Next Step: Run 03_sequences.sql
