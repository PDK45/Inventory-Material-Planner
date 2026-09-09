-- ============================================================
-- MPPMS :: 48_digital_twin_tables.sql
-- Phase 12: Digital Twin Supply Chain Stress Tester
-- Tables: SIMULATION_SCENARIO, SIMULATION_TRIAL, SIMULATION_RESULT
-- Run As: MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS Phase 12 :: Digital Twin Simulation Tables
PROMPT ============================================================

-- ============================================================
-- TABLE 1: SIMULATION_SCENARIO
-- Stores the user-defined shock parameters for each simulation run
-- ============================================================
CREATE TABLE SIMULATION_SCENARIO (
    SCENARIO_ID             NUMBER          NOT NULL,
    SCENARIO_NAME           VARCHAR2(200)   NOT NULL,
    MATERIAL_ID             NUMBER,
    -- Shock Parameters (user inputs via sliders)
    SHIPPING_DELAY_DAYS     NUMBER(5,2)     DEFAULT 0  NOT NULL,
    TARIFF_SPIKE_PCT        NUMBER(6,2)     DEFAULT 0  NOT NULL,
    DEMAND_SURGE_PCT        NUMBER(6,2)     DEFAULT 0  NOT NULL,
    -- Simulation config
    TRIAL_COUNT             NUMBER(6)       DEFAULT 1000 NOT NULL,
    SIMULATION_STATUS       VARCHAR2(20)    DEFAULT 'PENDING' NOT NULL,
    -- Aggregate output results
    STOCKOUT_RISK_PCT       NUMBER(6,2),
    P50_EXPOSURE_INR        NUMBER(18,2),
    P95_EXPOSURE_INR        NUMBER(18,2),
    P99_EXPOSURE_INR        NUMBER(18,2),
    AVG_BUFFER_DAYS         NUMBER(8,2),
    SAFE_BUFFER_DAYS        NUMBER(8,2),
    WORST_STOCKOUT_DATE     DATE,
    -- Audit
    CREATED_BY              VARCHAR2(100)   DEFAULT USER NOT NULL,
    CREATED_DATE            DATE            DEFAULT SYSDATE NOT NULL,
    COMPLETED_DATE          DATE,
    -- Constraints
    CONSTRAINT PK_SIM_SCENARIO PRIMARY KEY (SCENARIO_ID),
    CONSTRAINT CK_SIM_STATUS CHECK (SIMULATION_STATUS IN ('PENDING','RUNNING','COMPLETED','FAILED')),
    CONSTRAINT CK_SHIPPING_DELAY CHECK (SHIPPING_DELAY_DAYS BETWEEN 0 AND 365),
    CONSTRAINT CK_TARIFF_SPIKE   CHECK (TARIFF_SPIKE_PCT   BETWEEN 0 AND 500),
    CONSTRAINT CK_DEMAND_SURGE   CHECK (DEMAND_SURGE_PCT   BETWEEN -100 AND 1000),
    CONSTRAINT CK_TRIAL_COUNT    CHECK (TRIAL_COUNT BETWEEN 100 AND 10000),
    CONSTRAINT FK_SIM_MATERIAL   FOREIGN KEY (MATERIAL_ID) REFERENCES MATERIAL_MASTER(MATERIAL_ID)
);

COMMENT ON TABLE  SIMULATION_SCENARIO IS 'Monte Carlo simulation scenarios with user-defined supply chain shock parameters';
COMMENT ON COLUMN SIMULATION_SCENARIO.SHIPPING_DELAY_DAYS IS 'Port/logistics delay injected into simulation (days)';
COMMENT ON COLUMN SIMULATION_SCENARIO.TARIFF_SPIKE_PCT    IS 'Material cost surge percentage (e.g. 15 = 15% tariff increase)';
COMMENT ON COLUMN SIMULATION_SCENARIO.DEMAND_SURGE_PCT    IS 'Unexpected demand change percentage (positive = surge, negative = drop)';
COMMENT ON COLUMN SIMULATION_SCENARIO.STOCKOUT_RISK_PCT   IS 'Percentage of trials that resulted in a stockout event';
COMMENT ON COLUMN SIMULATION_SCENARIO.P95_EXPOSURE_INR    IS '95th percentile worst-case financial exposure in INR';
COMMENT ON COLUMN SIMULATION_SCENARIO.SAFE_BUFFER_DAYS    IS 'Average buffer days remaining across all trials after shocks applied';

CREATE SEQUENCE SEQ_SIMULATION_SCENARIO START WITH 1 INCREMENT BY 1 NOCACHE;

PROMPT [OK] SIMULATION_SCENARIO created.

-- ============================================================
-- TABLE 2: SIMULATION_TRIAL
-- Stores individual trial outputs (one row per trial per scenario)
-- Kept for drill-down analysis and histogram rendering
-- ============================================================
CREATE TABLE SIMULATION_TRIAL (
    TRIAL_ID                NUMBER          NOT NULL,
    SCENARIO_ID             NUMBER          NOT NULL,
    TRIAL_NO                NUMBER(6)       NOT NULL,
    -- Randomised inputs for this trial (drawn from Normal distribution)
    EFFECTIVE_DELAY_DAYS    NUMBER(8,2),
    EFFECTIVE_COST_MULT     NUMBER(8,4),    -- e.g. 1.15 = 15% more expensive
    EFFECTIVE_DEMAND_QTY    NUMBER(15,3),
    -- Trial output
    PROJECTED_STOCK_END     NUMBER(15,3),   -- Inventory balance at end of horizon
    STOCKOUT_OCCURRED       VARCHAR2(1)     DEFAULT 'N' NOT NULL,
    STOCKOUT_DAY            NUMBER(6),      -- Day number of stockout (null if no stockout)
    FINANCIAL_EXPOSURE_INR  NUMBER(18,2),   -- Cost impact of disruption in INR
    BUFFER_DAYS_REMAINING   NUMBER(8,2),
    -- Constraint
    CONSTRAINT PK_SIM_TRIAL    PRIMARY KEY (TRIAL_ID),
    CONSTRAINT FK_TRIAL_SCEN   FOREIGN KEY (SCENARIO_ID) REFERENCES SIMULATION_SCENARIO(SCENARIO_ID) ON DELETE CASCADE,
    CONSTRAINT CK_STOCKOUT_FLG CHECK (STOCKOUT_OCCURRED IN ('Y','N'))
);

COMMENT ON TABLE SIMULATION_TRIAL IS 'Individual Monte Carlo trial outputs for drill-down histogram analysis';

CREATE SEQUENCE SEQ_SIMULATION_TRIAL START WITH 1 INCREMENT BY 1 NOCACHE;

-- Index for fast scenario-level aggregation
CREATE INDEX IDX_TRIAL_SCENARIO ON SIMULATION_TRIAL(SCENARIO_ID, STOCKOUT_OCCURRED);

PROMPT [OK] SIMULATION_TRIAL created.

-- ============================================================
-- TABLE 3: SIMULATION_RESULT_HEATMAP
-- Per-material risk summary for the heatmap UI widget
-- ============================================================
CREATE TABLE SIMULATION_RESULT_HEATMAP (
    HEATMAP_ID              NUMBER          NOT NULL,
    SCENARIO_ID             NUMBER          NOT NULL,
    MATERIAL_ID             NUMBER          NOT NULL,
    MATERIAL_CODE           VARCHAR2(30),
    MATERIAL_NAME           VARCHAR2(200),
    CURRENT_STOCK_QTY       NUMBER(15,3),
    ADJUSTED_DEMAND_QTY     NUMBER(15,3),
    EFFECTIVE_LEAD_DAYS     NUMBER(8,2),
    STOCKOUT_RISK_PCT       NUMBER(6,2),
    FINANCIAL_EXPOSURE_INR  NUMBER(18,2),
    RISK_LEVEL              VARCHAR2(10)    DEFAULT 'GREEN' NOT NULL,  -- GREEN / AMBER / RED
    RECOMMENDATION          VARCHAR2(500),
    CONSTRAINT PK_HEATMAP       PRIMARY KEY (HEATMAP_ID),
    CONSTRAINT FK_HEATMAP_SCEN  FOREIGN KEY (SCENARIO_ID) REFERENCES SIMULATION_SCENARIO(SCENARIO_ID) ON DELETE CASCADE,
    CONSTRAINT CK_RISK_LEVEL    CHECK (RISK_LEVEL IN ('GREEN','AMBER','RED'))
);

COMMENT ON TABLE  SIMULATION_RESULT_HEATMAP IS 'Per-material risk heatmap output for the Digital Twin dashboard UI';
COMMENT ON COLUMN SIMULATION_RESULT_HEATMAP.RISK_LEVEL IS 'GREEN=<20% stockout risk, AMBER=20-60%, RED=>60%';

CREATE SEQUENCE SEQ_SIMULATION_HEATMAP START WITH 1 INCREMENT BY 1 NOCACHE;

PROMPT [OK] SIMULATION_RESULT_HEATMAP created.

PROMPT ============================================================
PROMPT  Phase 12 :: Digital Twin Tables COMPLETE
PROMPT ============================================================
