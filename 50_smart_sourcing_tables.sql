-- ============================================================
-- MPPMS :: 50_smart_sourcing_tables.sql
-- Phase 12: Autonomous Multi-Sourcing Optimizer
-- Tables: SOURCING_OPTIMISATION, SOURCING_ALLOCATION
-- Run As: MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS Phase 12 :: Smart Sourcing Optimizer Tables
PROMPT ============================================================

-- ============================================================
-- TABLE 1: SOURCING_OPTIMISATION
-- One row per optimisation run (triggered per PR or material)
-- ============================================================
CREATE TABLE SOURCING_OPTIMISATION (
    OPTIMISATION_ID         NUMBER          NOT NULL,
    PR_ID                   NUMBER,         -- FK to PURCHASE_REQUISITION (nullable for standalone runs)
    MATERIAL_ID             NUMBER          NOT NULL,
    REQUIRED_QTY            NUMBER(15,3)    NOT NULL,
    -- Strategy selected by user
    STRATEGY                VARCHAR2(20)    DEFAULT 'BALANCED_RISK' NOT NULL,
    -- Objective weights used (stored for audit/explainability)
    WEIGHT_COST             NUMBER(5,2)     DEFAULT 40 NOT NULL,
    WEIGHT_DELIVERY         NUMBER(5,2)     DEFAULT 30 NOT NULL,
    WEIGHT_QUALITY          NUMBER(5,2)     DEFAULT 20 NOT NULL,
    WEIGHT_CURRENCY         NUMBER(5,2)     DEFAULT 10 NOT NULL,
    -- Aggregate optimisation results
    TOTAL_BLENDED_COST_INR  NUMBER(18,2),
    TOTAL_BLENDED_COST_SAR  NUMBER(18,2),
    TOTAL_BLENDED_COST_USD  NUMBER(18,2),
    OPTIMISATION_SCORE      NUMBER(6,2),    -- 0-100, higher is better
    VENDOR_COUNT            NUMBER(3),      -- How many vendors in the split
    EXPECTED_DELIVERY_DATE  DATE,
    STATUS                  VARCHAR2(20)    DEFAULT 'PENDING' NOT NULL,
    -- Audit
    CREATED_BY              VARCHAR2(100)   DEFAULT USER NOT NULL,
    CREATED_DATE            DATE            DEFAULT SYSDATE NOT NULL,
    ACCEPTED_DATE           DATE,
    ACCEPTED_BY             VARCHAR2(100),
    -- Constraints
    CONSTRAINT PK_SOURCING_OPT  PRIMARY KEY (OPTIMISATION_ID),
    CONSTRAINT CK_OPT_STRATEGY  CHECK (STRATEGY IN ('LOWEST_COST','FASTEST_DELIVERY','BALANCED_RISK')),
    CONSTRAINT CK_OPT_STATUS    CHECK (STATUS   IN ('PENDING','OPTIMISED','ACCEPTED','REJECTED','ORDERED')),
    CONSTRAINT CK_WEIGHT_TOTAL  CHECK (WEIGHT_COST + WEIGHT_DELIVERY + WEIGHT_QUALITY + WEIGHT_CURRENCY = 100),
    CONSTRAINT FK_OPT_MATERIAL  FOREIGN KEY (MATERIAL_ID) REFERENCES MATERIAL_MASTER(MATERIAL_ID)
);

COMMENT ON TABLE  SOURCING_OPTIMISATION IS 'Multi-vendor sourcing optimisation runs — records strategy, weights, and blended cost results';
COMMENT ON COLUMN SOURCING_OPTIMISATION.STRATEGY           IS 'LOWEST_COST: min price | FASTEST_DELIVERY: min lead time | BALANCED_RISK: multi-objective';
COMMENT ON COLUMN SOURCING_OPTIMISATION.OPTIMISATION_SCORE IS 'Composite score 0-100 representing how well the recommended split meets all objectives';
COMMENT ON COLUMN SOURCING_OPTIMISATION.WEIGHT_COST        IS 'Percentage weight assigned to cost minimization objective';

CREATE SEQUENCE SEQ_SOURCING_OPT START WITH 1 INCREMENT BY 1 NOCACHE;

PROMPT [OK] SOURCING_OPTIMISATION created.

-- ============================================================
-- TABLE 2: SOURCING_ALLOCATION
-- One row per vendor in the recommended split (child of SOURCING_OPTIMISATION)
-- ============================================================
CREATE TABLE SOURCING_ALLOCATION (
    ALLOCATION_ID           NUMBER          NOT NULL,
    OPTIMISATION_ID         NUMBER          NOT NULL,
    SUPPLIER_ID             NUMBER          NOT NULL,
    SUPPLIER_CODE           VARCHAR2(20),
    SUPPLIER_NAME           VARCHAR2(200),
    ASL_RANK                NUMBER(3),
    -- Allocation details
    ALLOCATION_PCT          NUMBER(6,2)     NOT NULL,  -- e.g. 65.00 = 65%
    ALLOCATED_QTY           NUMBER(15,3)    NOT NULL,
    UNIT_PRICE              NUMBER(15,4)    NOT NULL,
    CURRENCY                VARCHAR2(5)     NOT NULL,  -- INR / SAR / USD
    UNIT_PRICE_INR          NUMBER(15,4),   -- Normalised to INR for comparison
    LINE_TOTAL_INR          NUMBER(18,2),
    EXPECTED_DELIVERY_DAYS  NUMBER(5),
    EXPECTED_DELIVERY_DATE  DATE,
    -- Vendor scoring breakdown (for explainability)
    COST_SCORE              NUMBER(6,2),    -- 0-100 sub-score for this vendor on cost
    DELIVERY_SCORE          NUMBER(6,2),    -- 0-100 sub-score for delivery speed
    QUALITY_SCORE           NUMBER(6,2),    -- 0-100 (from vendor scorecard)
    CURRENCY_SCORE          NUMBER(6,2),    -- 0-100 (based on currency preference)
    COMPOSITE_SCORE         NUMBER(6,2),    -- Weighted combined score
    -- Generated PO reference (populated after acceptance)
    GENERATED_PO_ID         NUMBER,
    -- Constraint
    CONSTRAINT PK_ALLOC         PRIMARY KEY (ALLOCATION_ID),
    CONSTRAINT FK_ALLOC_OPT     FOREIGN KEY (OPTIMISATION_ID) REFERENCES SOURCING_OPTIMISATION(OPTIMISATION_ID) ON DELETE CASCADE,
    CONSTRAINT FK_ALLOC_SUPP    FOREIGN KEY (SUPPLIER_ID)     REFERENCES SUPPLIER_MASTER(SUPPLIER_ID),
    CONSTRAINT CK_ALLOC_PCT     CHECK (ALLOCATION_PCT BETWEEN 0.01 AND 100),
    CONSTRAINT CK_ALLOC_CURR    CHECK (CURRENCY IN ('INR','SAR','USD'))
);

COMMENT ON TABLE  SOURCING_ALLOCATION IS 'Per-vendor allocation in a multi-sourcing split — child of SOURCING_OPTIMISATION';
COMMENT ON COLUMN SOURCING_ALLOCATION.ALLOCATION_PCT     IS 'Percentage of the total requisition quantity assigned to this vendor';
COMMENT ON COLUMN SOURCING_ALLOCATION.COMPOSITE_SCORE    IS 'Weighted score justifying this vendor selection in the split';
COMMENT ON COLUMN SOURCING_ALLOCATION.GENERATED_PO_ID   IS 'PO created after user accepts the recommended split';

CREATE SEQUENCE SEQ_SOURCING_ALLOC START WITH 1 INCREMENT BY 1 NOCACHE;

-- Index for fast lookup of all allocations in an optimisation
CREATE INDEX IDX_ALLOC_OPT_ID ON SOURCING_ALLOCATION(OPTIMISATION_ID);

PROMPT [OK] SOURCING_ALLOCATION created.

-- ============================================================
-- TABLE 3: SOURCING_EXCHANGE_RATE
-- Currency conversion rates for INR/SAR/USD normalisation
-- ============================================================
CREATE TABLE SOURCING_EXCHANGE_RATE (
    RATE_ID                 NUMBER          NOT NULL,
    FROM_CURRENCY           VARCHAR2(5)     NOT NULL,
    TO_CURRENCY             VARCHAR2(5)     DEFAULT 'INR' NOT NULL,
    EXCHANGE_RATE           NUMBER(12,6)    NOT NULL,
    EFFECTIVE_DATE          DATE            DEFAULT SYSDATE NOT NULL,
    IS_ACTIVE               VARCHAR2(1)     DEFAULT 'Y' NOT NULL,
    CONSTRAINT PK_EXCH_RATE    PRIMARY KEY (RATE_ID),
    CONSTRAINT CK_FROM_CURR    CHECK (FROM_CURRENCY IN ('INR','SAR','USD','EUR','GBP')),
    CONSTRAINT CK_TO_CURR      CHECK (TO_CURRENCY   IN ('INR','SAR','USD')),
    CONSTRAINT CK_EXCH_ACTIVE  CHECK (IS_ACTIVE IN ('Y','N'))
);

CREATE SEQUENCE SEQ_EXCH_RATE START WITH 1 INCREMENT BY 1 NOCACHE;

-- Seed current rates (approximate real-world values)
INSERT INTO SOURCING_EXCHANGE_RATE (RATE_ID, FROM_CURRENCY, TO_CURRENCY, EXCHANGE_RATE)
VALUES (SEQ_EXCH_RATE.NEXTVAL, 'SAR', 'INR', 22.15);

INSERT INTO SOURCING_EXCHANGE_RATE (RATE_ID, FROM_CURRENCY, TO_CURRENCY, EXCHANGE_RATE)
VALUES (SEQ_EXCH_RATE.NEXTVAL, 'USD', 'INR', 83.50);

INSERT INTO SOURCING_EXCHANGE_RATE (RATE_ID, FROM_CURRENCY, TO_CURRENCY, EXCHANGE_RATE)
VALUES (SEQ_EXCH_RATE.NEXTVAL, 'INR', 'INR', 1.00);

COMMIT;

PROMPT [OK] SOURCING_EXCHANGE_RATE created and seeded.

PROMPT ============================================================
PROMPT  Phase 12 :: Smart Sourcing Tables COMPLETE
PROMPT ============================================================
