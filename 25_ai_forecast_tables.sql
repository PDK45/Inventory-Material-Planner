-- ============================================================
-- MPPMS :: 25_ai_forecast_tables.sql
-- Phase A: AI Demand Forecasting Engine
-- Company: Zamil Information Technology Global
-- Purpose: Create all tables needed by PKG_AI_FORECAST
-- Run As : MPPMS user on FREEPDB1
-- ============================================================
--
-- LEARNING NOTE: Why do we need new tables?
-- Our existing DEMAND_FORECAST table stores both manual and AI
-- forecasts, but it does not store the MODEL itself (alpha, beta,
-- gamma), accuracy scores (MAE, MAPE, RMSE), or confidence bands.
-- We need dedicated tables for those. Good ML systems always store:
--   1. The training data (cleaned)
--   2. The model parameters (what was learned)
--   3. The predictions (outputs)
--   4. The accuracy history (how good the model is over time)
-- ============================================================

SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

PROMPT ============================================================
PROMPT  MPPMS Phase A :: Creating AI Forecast Schema Objects
PROMPT ============================================================

-- ============================================================
-- TABLE 1: DEMAND_HISTORY
-- Purpose : Cleaned, pre-processed historical demand used to
--           TRAIN the forecasting model.
--
-- LEARNING: In ML, you always separate raw data from training data.
-- Raw data can have outliers (a one-time emergency order of 10,000
-- units that will never repeat). If you train on that outlier, your
-- model will think demand spikes every year. So we store the
-- "cleaned" version here after outlier scrubbing.
--
-- FORECAST_TYPE column tells us if the row is:
--   ACTUAL    = real historical demand that occurred
--   ADJUSTED  = outlier was detected and value was smoothed
-- ============================================================
CREATE TABLE DEMAND_HISTORY (
    HISTORY_ID        NUMBER          NOT NULL,
    PRODUCT_ID        NUMBER          NOT NULL,
    DEMAND_MONTH      DATE            NOT NULL,  -- Always first of month
    ACTUAL_QTY        NUMBER(15,3)    NOT NULL,  -- Raw observed demand
    CLEANED_QTY       NUMBER(15,3)    NOT NULL,  -- Outlier-adjusted (used for training)
    IS_OUTLIER        VARCHAR2(1)     DEFAULT 'N' NOT NULL,  -- Y/N
    OUTLIER_REASON    VARCHAR2(200),              -- Explanation if adjusted
    DATA_SOURCE       VARCHAR2(20)    DEFAULT 'HISTORICAL' NOT NULL,
    LOADED_DATE       DATE            DEFAULT SYSDATE NOT NULL,
    --
    CONSTRAINT PK_DEMAND_HISTORY  PRIMARY KEY (HISTORY_ID),
    CONSTRAINT FK_DH_PRODUCT      FOREIGN KEY (PRODUCT_ID)
                                  REFERENCES PRODUCT_MASTER(PRODUCT_ID),
    CONSTRAINT UQ_DH_PROD_MONTH   UNIQUE (PRODUCT_ID, DEMAND_MONTH),
    CONSTRAINT CK_DH_ACTUAL_QTY   CHECK (ACTUAL_QTY >= 0),
    CONSTRAINT CK_DH_CLEANED_QTY  CHECK (CLEANED_QTY >= 0),
    CONSTRAINT CK_DH_OUTLIER      CHECK (IS_OUTLIER IN ('Y','N')),
    CONSTRAINT CK_DH_SOURCE       CHECK (DATA_SOURCE IN ('HISTORICAL','MANUAL','SYSTEM'))
);

COMMENT ON TABLE  DEMAND_HISTORY              IS 'Cleaned historical demand used as training data for Holt-Winters model';
COMMENT ON COLUMN DEMAND_HISTORY.CLEANED_QTY  IS 'Outlier-adjusted quantity used for model training. Same as ACTUAL_QTY if no outlier.';
COMMENT ON COLUMN DEMAND_HISTORY.IS_OUTLIER   IS 'Y = this month had abnormal demand. CLEANED_QTY was substituted during training.';

PROMPT [OK] DEMAND_HISTORY created.

-- ============================================================
-- TABLE 2: FORECAST_MODEL_PARAMS
-- Purpose : Stores the TRAINED MODEL for each product.
--           This is what the algorithm LEARNED from history.
--
-- LEARNING: In classical ML, after training you save the model
-- weights to disk (e.g., a .pkl file in Python). In Oracle, we
-- save them in this table. The "weights" for Holt-Winters are
-- the three smoothing factors (alpha, beta, gamma) plus the
-- final level and trend values.
--
-- ALPHA (level smoothing, 0-1):
--   High alpha (0.8) = model reacts fast to recent changes
--   Low alpha (0.2)  = model is more stable, weights history more
--
-- BETA (trend smoothing, 0-1):
--   High beta = trend adapts quickly
--   Low beta  = trend is stable/persistent
--
-- GAMMA (seasonal smoothing, 0-1):
--   High gamma = seasonal pattern updates each year
--   Low gamma  = seasonal pattern is very fixed
--
-- These are found by the optimizer (grid search), not set manually.
-- ============================================================
CREATE TABLE FORECAST_MODEL_PARAMS (
    PARAM_ID            NUMBER          NOT NULL,
    PRODUCT_ID          NUMBER          NOT NULL,
    MODEL_VERSION       NUMBER          DEFAULT 1 NOT NULL,
    -- Learned parameters (the "weights" of the model)
    ALPHA               NUMBER(6,4)     NOT NULL,  -- Level smoothing (0.0 to 1.0)
    BETA                NUMBER(6,4)     NOT NULL,  -- Trend smoothing (0.0 to 1.0)
    GAMMA               NUMBER(6,4)     NOT NULL,  -- Seasonal smoothing (0.0 to 1.0)
    SEASON_LENGTH       NUMBER          DEFAULT 12 NOT NULL,  -- m=12 for monthly
    -- Final state after training (needed to continue forecasting)
    FINAL_LEVEL         NUMBER(15,4),   -- L[n]: last level value
    FINAL_TREND         NUMBER(15,4),   -- B[n]: last trend value
    -- Training accuracy (how well model fits historical data)
    TRAIN_MAE           NUMBER(12,4),   -- Mean Absolute Error on training set
    TRAIN_MAPE          NUMBER(8,4),    -- Mean Absolute Percentage Error (%)
    TRAIN_RMSE          NUMBER(12,4),   -- Root Mean Square Error
    -- Validation accuracy (how well model predicts hold-out data)
    VAL_MAE             NUMBER(12,4),   -- MAE on validation set (last 4 months held out)
    VAL_MAPE            NUMBER(8,4),    -- MAPE on validation set
    -- Data used for training
    TRAINING_MONTHS     NUMBER,         -- How many months of data were used
    TRAINING_FROM       DATE,           -- Start of training window
    TRAINING_TO         DATE,           -- End of training window
    -- Model health
    MODEL_STATUS        VARCHAR2(20)    DEFAULT 'ACTIVE' NOT NULL,
    CONFIDENCE_LEVEL    VARCHAR2(10),   -- EXCELLENT/GOOD/FAIR/POOR
    TRAINED_DATE        DATE            DEFAULT SYSDATE NOT NULL,
    --
    CONSTRAINT PK_FORECAST_PARAMS  PRIMARY KEY (PARAM_ID),
    CONSTRAINT FK_FP_PRODUCT       FOREIGN KEY (PRODUCT_ID)
                                   REFERENCES PRODUCT_MASTER(PRODUCT_ID),
    CONSTRAINT CK_FP_ALPHA         CHECK (ALPHA BETWEEN 0.01 AND 0.99),
    CONSTRAINT CK_FP_BETA          CHECK (BETA  BETWEEN 0.01 AND 0.99),
    CONSTRAINT CK_FP_GAMMA         CHECK (GAMMA BETWEEN 0.01 AND 0.99),
    CONSTRAINT CK_FP_STATUS        CHECK (MODEL_STATUS IN ('ACTIVE','STALE','FAILED','INSUFFICIENT_DATA')),
    CONSTRAINT CK_FP_CONFIDENCE    CHECK (CONFIDENCE_LEVEL IN ('EXCELLENT','GOOD','FAIR','POOR'))
);

COMMENT ON TABLE  FORECAST_MODEL_PARAMS           IS 'Trained Holt-Winters model parameters per product. Stores what the model learned.';
COMMENT ON COLUMN FORECAST_MODEL_PARAMS.ALPHA     IS 'Level smoothing factor optimized by grid search. Higher = more weight on recent data.';
COMMENT ON COLUMN FORECAST_MODEL_PARAMS.BETA      IS 'Trend smoothing factor. Controls how fast trend adapts to new data.';
COMMENT ON COLUMN FORECAST_MODEL_PARAMS.GAMMA     IS 'Seasonal smoothing factor. Controls how fast seasonal pattern updates.';
COMMENT ON COLUMN FORECAST_MODEL_PARAMS.VAL_MAPE  IS 'MAPE on held-out validation set. This is the honest accuracy metric.';

PROMPT [OK] FORECAST_MODEL_PARAMS created.

-- ============================================================
-- TABLE 3: AI_DEMAND_FORECAST
-- Purpose : Model OUTPUTS — the actual predictions.
--           One row per product per future month.
--
-- LEARNING: Three values are stored per forecast point:
--   PREDICTED_QTY = point forecast (best guess)
--   LOWER_BOUND   = 95% confidence lower bound
--   UPPER_BOUND   = 95% confidence upper bound
--
-- The confidence band tells us: "We are 95% sure the actual
-- demand will fall between LOWER_BOUND and UPPER_BOUND."
-- A wide band = model is uncertain. Narrow band = confident.
--
-- Procurement teams use the UPPER_BOUND to decide safety stock
-- (plan for the worst case), while finance uses PREDICTED_QTY
-- for budget planning.
-- ============================================================
CREATE TABLE AI_DEMAND_FORECAST (
    AI_FORECAST_ID    NUMBER          NOT NULL,
    PRODUCT_ID        NUMBER          NOT NULL,
    PARAM_ID          NUMBER          NOT NULL,  -- Which model version made this
    FORECAST_MONTH    DATE            NOT NULL,  -- Always 1st of month
    -- The three forecast values
    PREDICTED_QTY     NUMBER(15,3)    NOT NULL,  -- Point forecast
    LOWER_BOUND       NUMBER(15,3)    NOT NULL,  -- 95% CI lower
    UPPER_BOUND       NUMBER(15,3)    NOT NULL,  -- 95% CI upper
    -- How far into the future this prediction is
    HORIZON_MONTHS    NUMBER          NOT NULL,  -- h=1 = next month, h=12 = 1 year ahead
    -- Uncertainty grows with horizon (stored for transparency)
    PREDICTION_STD    NUMBER(12,4),              -- σ × √h used for CI calculation
    -- Forecast state
    FORECAST_STATUS   VARCHAR2(20)    DEFAULT 'ACTIVE' NOT NULL,
    ACTUAL_QTY        NUMBER(15,3),              -- Filled in when month passes (for accuracy tracking)
    ABSOLUTE_ERROR    NUMBER(15,3),              -- |Actual - Predicted| (computed when actual arrives)
    PCT_ERROR         NUMBER(8,4),               -- % error (computed when actual arrives)
    MODEL_RUN_DATE    DATE            DEFAULT SYSDATE NOT NULL,
    --
    CONSTRAINT PK_AI_FORECAST       PRIMARY KEY (AI_FORECAST_ID),
    CONSTRAINT FK_AIF_PRODUCT       FOREIGN KEY (PRODUCT_ID)
                                    REFERENCES PRODUCT_MASTER(PRODUCT_ID),
    CONSTRAINT FK_AIF_PARAMS        FOREIGN KEY (PARAM_ID)
                                    REFERENCES FORECAST_MODEL_PARAMS(PARAM_ID),
    CONSTRAINT UQ_AIF_PROD_MONTH    UNIQUE (PRODUCT_ID, FORECAST_MONTH),
    CONSTRAINT CK_AIF_QTY          CHECK (PREDICTED_QTY >= 0),
    CONSTRAINT CK_AIF_LOWER        CHECK (LOWER_BOUND >= 0),
    CONSTRAINT CK_AIF_STATUS       CHECK (FORECAST_STATUS IN ('ACTIVE','SUPERSEDED','EVALUATED'))
);

COMMENT ON TABLE  AI_DEMAND_FORECAST             IS 'Holt-Winters model predictions: point forecast + 95% confidence interval per product per month.';
COMMENT ON COLUMN AI_DEMAND_FORECAST.LOWER_BOUND IS '95% confidence lower bound. Demand will exceed this 97.5% of the time.';
COMMENT ON COLUMN AI_DEMAND_FORECAST.UPPER_BOUND IS '95% CI upper bound. Use for safety stock calculation.';
COMMENT ON COLUMN AI_DEMAND_FORECAST.ACTUAL_QTY  IS 'Filled when the forecast month passes. Enables ongoing accuracy tracking.';

PROMPT [OK] AI_DEMAND_FORECAST created.

-- ============================================================
-- TABLE 4: FORECAST_ACCURACY_LOG
-- Purpose : Tracks model accuracy OVER TIME per product.
--           Each time we re-run the model, log a new row.
--
-- LEARNING: Model accuracy drifts over time. Demand patterns
-- change (new competitors, economic changes, new products).
-- By logging accuracy each run, we can detect "model drift":
-- if MAPE is increasing run after run, the model needs retraining
-- with more recent data. This is called "monitoring" in MLOps.
-- ============================================================
CREATE TABLE FORECAST_ACCURACY_LOG (
    LOG_ID            NUMBER          NOT NULL,
    PRODUCT_ID        NUMBER          NOT NULL,
    PARAM_ID          NUMBER,
    RUN_DATE          DATE            DEFAULT SYSDATE NOT NULL,
    -- Metrics from this run
    TRAINING_MAE      NUMBER(12,4),   -- Error on training data
    TRAINING_MAPE     NUMBER(8,4),    -- % error on training data
    TRAINING_RMSE     NUMBER(12,4),   -- RMSE on training data
    VALIDATION_MAE    NUMBER(12,4),   -- Error on held-out data (honest metric)
    VALIDATION_MAPE   NUMBER(8,4),    -- % error on held-out data
    -- Optimizer results
    BEST_ALPHA        NUMBER(6,4),
    BEST_BETA         NUMBER(6,4),
    BEST_GAMMA        NUMBER(6,4),
    COMBINATIONS_TESTED NUMBER,       -- How many alpha/beta/gamma combos we tried
    OPTIMIZATION_SEC  NUMBER(8,2),    -- Seconds the optimizer ran
    -- Data used
    MONTHS_OF_HISTORY NUMBER,
    FORECASTS_GENERATED NUMBER,
    -- Outcome
    ACCURACY_GRADE    VARCHAR2(10),   -- EXCELLENT/GOOD/FAIR/POOR based on MAPE
    RUN_STATUS        VARCHAR2(20)    DEFAULT 'SUCCESS',
    ERROR_MESSAGE     VARCHAR2(500),
    --
    CONSTRAINT PK_ACCURACY_LOG   PRIMARY KEY (LOG_ID),
    CONSTRAINT FK_AL_PRODUCT     FOREIGN KEY (PRODUCT_ID)
                                 REFERENCES PRODUCT_MASTER(PRODUCT_ID),
    CONSTRAINT CK_AL_GRADE       CHECK (ACCURACY_GRADE IN ('EXCELLENT','GOOD','FAIR','POOR','N/A')),
    CONSTRAINT CK_AL_STATUS      CHECK (RUN_STATUS IN ('SUCCESS','FAILED','INSUFFICIENT_DATA','PARTIAL'))
);

COMMENT ON TABLE  FORECAST_ACCURACY_LOG           IS 'MLOps audit log: tracks model accuracy and optimizer results per run for drift detection.';
COMMENT ON COLUMN FORECAST_ACCURACY_LOG.VALIDATION_MAPE IS 'Key metric: MAPE on held-out data. <10%=Excellent, 10-20%=Good, 20-50%=Fair, >50%=Poor.';

PROMPT [OK] FORECAST_ACCURACY_LOG created.

-- ============================================================
-- TABLE 5: SEASONAL_INDEX_STORE
-- Purpose : Stores the 12 seasonal indices (one per month) that
--           the model learns for each product.
--
-- LEARNING: A seasonal index of 1.25 for October means:
-- "October demand is typically 25% ABOVE the baseline average."
-- An index of 0.80 for February means demand is 20% BELOW average.
-- All 12 indices together must multiply to approximately 12.0
-- (they are multiplicative and average to 1.0).
-- ============================================================
CREATE TABLE SEASONAL_INDEX_STORE (
    SEASONAL_ID     NUMBER          NOT NULL,
    PRODUCT_ID      NUMBER          NOT NULL,
    PARAM_ID        NUMBER          NOT NULL,
    MONTH_NUM       NUMBER          NOT NULL,  -- 1=Jan, 2=Feb, ..., 12=Dec
    MONTH_NAME      VARCHAR2(10),              -- JAN, FEB, ..., DEC (display)
    SEASONAL_INDEX  NUMBER(8,5)     NOT NULL,  -- The learned multiplier
    --
    CONSTRAINT PK_SEASONAL_IDX  PRIMARY KEY (SEASONAL_ID),
    CONSTRAINT FK_SI_PRODUCT    FOREIGN KEY (PRODUCT_ID)
                                REFERENCES PRODUCT_MASTER(PRODUCT_ID),
    CONSTRAINT FK_SI_PARAMS     FOREIGN KEY (PARAM_ID)
                                REFERENCES FORECAST_MODEL_PARAMS(PARAM_ID),
    CONSTRAINT UQ_SI_PROD_MONTH UNIQUE (PRODUCT_ID, PARAM_ID, MONTH_NUM),
    CONSTRAINT CK_SI_MONTH      CHECK (MONTH_NUM BETWEEN 1 AND 12),
    CONSTRAINT CK_SI_INDEX      CHECK (SEASONAL_INDEX > 0)
);

COMMENT ON TABLE  SEASONAL_INDEX_STORE              IS 'Learned seasonal multipliers per product per calendar month. Core of the seasonality model.';
COMMENT ON COLUMN SEASONAL_INDEX_STORE.SEASONAL_INDEX IS '>1.0 means above-average demand month, <1.0 means below-average.';

PROMPT [OK] SEASONAL_INDEX_STORE created.

-- ============================================================
-- SEQUENCES
-- ============================================================
CREATE SEQUENCE SEQ_HISTORY_ID      START WITH 1    INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_PARAM_ID        START WITH 1    INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_AI_FORECAST_ID  START WITH 1    INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_ACC_LOG_ID      START WITH 1    INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SEQ_SEASONAL_ID     START WITH 1    INCREMENT BY 1 NOCACHE NOCYCLE;

PROMPT [OK] Sequences created.

-- ============================================================
-- TRIGGERS (auto-populate PKs)
-- ============================================================
CREATE OR REPLACE TRIGGER TRG_DEMAND_HISTORY_BI
    BEFORE INSERT ON DEMAND_HISTORY FOR EACH ROW
BEGIN
    IF :NEW.HISTORY_ID IS NULL THEN
        :NEW.HISTORY_ID := SEQ_HISTORY_ID.NEXTVAL;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER TRG_FORECAST_PARAMS_BI
    BEFORE INSERT ON FORECAST_MODEL_PARAMS FOR EACH ROW
BEGIN
    IF :NEW.PARAM_ID IS NULL THEN
        :NEW.PARAM_ID := SEQ_PARAM_ID.NEXTVAL;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER TRG_AI_FORECAST_BI
    BEFORE INSERT ON AI_DEMAND_FORECAST FOR EACH ROW
BEGIN
    IF :NEW.AI_FORECAST_ID IS NULL THEN
        :NEW.AI_FORECAST_ID := SEQ_AI_FORECAST_ID.NEXTVAL;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER TRG_ACC_LOG_BI
    BEFORE INSERT ON FORECAST_ACCURACY_LOG FOR EACH ROW
BEGIN
    IF :NEW.LOG_ID IS NULL THEN
        :NEW.LOG_ID := SEQ_ACC_LOG_ID.NEXTVAL;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER TRG_SEASONAL_IDX_BI
    BEFORE INSERT ON SEASONAL_INDEX_STORE FOR EACH ROW
BEGIN
    IF :NEW.SEASONAL_ID IS NULL THEN
        :NEW.SEASONAL_ID := SEQ_SEASONAL_ID.NEXTVAL;
    END IF;
    :NEW.MONTH_NAME := TO_CHAR(TO_DATE(:NEW.MONTH_NUM, 'MM'), 'MON');
END;
/

PROMPT [OK] Triggers created.

-- ============================================================
-- INDEXES (for query performance)
-- LEARNING: Without indexes, every query on DEMAND_HISTORY or
-- AI_DEMAND_FORECAST does a full table scan = slow. These indexes
-- make lookups by PRODUCT_ID and FORECAST_MONTH instant.
-- ============================================================
CREATE INDEX IDX_DH_PRODUCT_MONTH  ON DEMAND_HISTORY(PRODUCT_ID, DEMAND_MONTH DESC);
CREATE INDEX IDX_FP_PRODUCT        ON FORECAST_MODEL_PARAMS(PRODUCT_ID, TRAINED_DATE DESC);
CREATE INDEX IDX_AIF_PRODUCT_MONTH ON AI_DEMAND_FORECAST(PRODUCT_ID, FORECAST_MONTH);
CREATE INDEX IDX_AIF_RUN_DATE      ON AI_DEMAND_FORECAST(MODEL_RUN_DATE DESC);
CREATE INDEX IDX_AL_PRODUCT_DATE   ON FORECAST_ACCURACY_LOG(PRODUCT_ID, RUN_DATE DESC);
CREATE INDEX IDX_SI_PRODUCT        ON SEASONAL_INDEX_STORE(PRODUCT_ID, PARAM_ID, MONTH_NUM);

PROMPT [OK] Indexes created.

-- ============================================================
-- VERIFICATION
-- ============================================================
PROMPT
PROMPT ============================================================
PROMPT  Phase A Tables Created:
PROMPT ============================================================
SELECT table_name, num_rows FROM user_tables
WHERE table_name IN (
    'DEMAND_HISTORY', 'FORECAST_MODEL_PARAMS',
    'AI_DEMAND_FORECAST', 'FORECAST_ACCURACY_LOG',
    'SEASONAL_INDEX_STORE'
)
ORDER BY table_name;

PROMPT
PROMPT [SUCCESS] 25_ai_forecast_tables.sql complete.
PROMPT Next Step: Run 26_ai_forecast_history_data.sql
