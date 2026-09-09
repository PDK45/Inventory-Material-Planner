-- ============================================================
-- MPPMS :: 51_pkg_smart_sourcing.sql
-- Phase 12: PKG_SMART_SOURCING — Autonomous Multi-Sourcing Optimizer
-- Multi-objective weighted scoring with fractional split allocation
-- Run As: MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS Phase 12 :: Creating PKG_SMART_SOURCING
PROMPT ============================================================

CREATE OR REPLACE PACKAGE PKG_SMART_SOURCING AS

    -- --------------------------------------------------------
    -- Main optimizer: runs for a specific material + required qty
    -- Returns OPTIMISATION_ID for the accepted run
    -- Strategy: LOWEST_COST / FASTEST_DELIVERY / BALANCED_RISK
    -- --------------------------------------------------------
    PROCEDURE OPTIMISE_SOURCING (
        p_material_id       IN  NUMBER,
        p_required_qty      IN  NUMBER,
        p_strategy          IN  VARCHAR2 DEFAULT 'BALANCED_RISK',
        p_pr_id             IN  NUMBER   DEFAULT NULL,
        p_optimisation_id   OUT NUMBER,
        p_status            OUT VARCHAR2,
        p_message           OUT VARCHAR2
    );

    -- --------------------------------------------------------
    -- Accept recommended split and generate Purchase Orders
    -- Creates one PO per vendor allocation
    -- --------------------------------------------------------
    PROCEDURE ACCEPT_SPLIT (
        p_optimisation_id   IN  NUMBER,
        p_accepted_by       IN  VARCHAR2,
        p_status            OUT VARCHAR2,
        p_message           OUT VARCHAR2
    );

    -- --------------------------------------------------------
    -- Get recommended allocations for display (for REST/ORDS)
    -- --------------------------------------------------------
    FUNCTION GET_ALLOCATIONS (p_optimisation_id IN NUMBER) RETURN SYS_REFCURSOR;

    -- --------------------------------------------------------
    -- Get optimisation summary header (for REST/ORDS)
    -- --------------------------------------------------------
    FUNCTION GET_OPTIMISATION_SUMMARY (p_optimisation_id IN NUMBER) RETURN SYS_REFCURSOR;

    -- --------------------------------------------------------
    -- Quick ad-hoc optimisation returning ref cursor directly
    -- Used by ORDS GET endpoints for live preview
    -- --------------------------------------------------------
    FUNCTION PREVIEW_OPTIMISATION (
        p_material_id  IN NUMBER,
        p_required_qty IN NUMBER,
        p_strategy     IN VARCHAR2 DEFAULT 'BALANCED_RISK'
    ) RETURN SYS_REFCURSOR;

END PKG_SMART_SOURCING;
/
SHOW ERRORS PACKAGE PKG_SMART_SOURCING;

CREATE OR REPLACE PACKAGE BODY PKG_SMART_SOURCING AS

    -- --------------------------------------------------------
    -- PRIVATE: Convert any currency to INR
    -- --------------------------------------------------------
    FUNCTION TO_INR (p_amount IN NUMBER, p_currency IN VARCHAR2) RETURN NUMBER IS
        v_rate NUMBER := 1;
    BEGIN
        BEGIN
            SELECT EXCHANGE_RATE INTO v_rate
              FROM SOURCING_EXCHANGE_RATE
             WHERE FROM_CURRENCY = p_currency AND TO_CURRENCY = 'INR' AND IS_ACTIVE = 'Y' AND ROWNUM = 1;
        EXCEPTION WHEN OTHERS THEN v_rate := 1;
        END;
        RETURN p_amount * v_rate;
    END TO_INR;

    -- --------------------------------------------------------
    -- PRIVATE: Get objective weights for a given strategy
    -- --------------------------------------------------------
    PROCEDURE GET_STRATEGY_WEIGHTS (
        p_strategy       IN  VARCHAR2,
        p_w_cost         OUT NUMBER,
        p_w_delivery     OUT NUMBER,
        p_w_quality      OUT NUMBER,
        p_w_currency     OUT NUMBER
    ) IS
    BEGIN
        CASE p_strategy
            WHEN 'LOWEST_COST' THEN
                p_w_cost := 70; p_w_delivery := 15; p_w_quality := 10; p_w_currency := 5;
            WHEN 'FASTEST_DELIVERY' THEN
                p_w_cost := 15; p_w_delivery := 65; p_w_quality := 15; p_w_currency := 5;
            ELSE -- BALANCED_RISK
                p_w_cost := 40; p_w_delivery := 30; p_w_quality := 20; p_w_currency := 10;
        END CASE;
    END GET_STRATEGY_WEIGHTS;

    -- --------------------------------------------------------
    -- PRIVATE: Score a single vendor on all objectives (0-100 each)
    -- --------------------------------------------------------
    PROCEDURE SCORE_VENDOR (
        p_supplier_id    IN  NUMBER,
        p_material_id    IN  NUMBER,
        p_min_price_inr  IN  NUMBER,   -- Cheapest vendor price (normalisation anchor)
        p_max_price_inr  IN  NUMBER,
        p_min_lead_days  IN  NUMBER,   -- Fastest vendor lead time
        p_max_lead_days  IN  NUMBER,
        p_cost_score     OUT NUMBER,
        p_delivery_score OUT NUMBER,
        p_quality_score  OUT NUMBER,
        p_currency_score OUT NUMBER
    ) IS
        v_price     NUMBER := 0;
        v_currency  VARCHAR2(5) := 'INR';
        v_lead_time NUMBER := 14;
        v_price_inr NUMBER := 0;
        v_qual_score NUMBER := 50; -- default
    BEGIN
        -- Get ASL contract price and lead time for this vendor/material
        BEGIN
            SELECT a.CONTRACT_PRICE, a.CURRENCY
              INTO v_price, v_currency
              FROM APPROVED_SUPPLIER_LIST a
             WHERE a.SUPPLIER_ID = p_supplier_id AND a.MATERIAL_ID = p_material_id
               AND a.ASL_STATUS = 'APPROVED' AND ROWNUM = 1;
        EXCEPTION WHEN OTHERS THEN v_price := p_max_price_inr; v_currency := 'INR';
        END;

        BEGIN
            SELECT LEAD_TIME INTO v_lead_time FROM SUPPLIER_MASTER WHERE SUPPLIER_ID = p_supplier_id;
        EXCEPTION WHEN OTHERS THEN v_lead_time := p_max_lead_days;
        END;

        -- Get quality score from Vendor Scorecard
        BEGIN
            SELECT NVL(QUALITY_SCORE, 50)
              INTO v_qual_score
              FROM VENDOR_SCORECARD
             WHERE SUPPLIER_ID = p_supplier_id AND ROWNUM = 1
             ORDER BY SCORECARD_DATE DESC;
        EXCEPTION WHEN OTHERS THEN v_qual_score := 50;
        END;

        v_price_inr := TO_INR(v_price, v_currency);

        -- Cost score: 100 = cheapest vendor, 0 = most expensive
        IF p_max_price_inr > p_min_price_inr THEN
            p_cost_score := 100 * (1 - (v_price_inr - p_min_price_inr) / (p_max_price_inr - p_min_price_inr));
        ELSE
            p_cost_score := 100;
        END IF;

        -- Delivery score: 100 = fastest, 0 = slowest
        IF p_max_lead_days > p_min_lead_days THEN
            p_delivery_score := 100 * (1 - (v_lead_time - p_min_lead_days) / (p_max_lead_days - p_min_lead_days));
        ELSE
            p_delivery_score := 100;
        END IF;

        -- Quality score: direct from scorecard (already 0-100)
        p_quality_score := LEAST(100, GREATEST(0, v_qual_score));

        -- Currency score: INR=100 (domestic, no FX risk), SAR=70 (stable peg), USD=50 (volatile)
        p_currency_score := CASE v_currency WHEN 'INR' THEN 100 WHEN 'SAR' THEN 70 ELSE 50 END;

        -- Clamp all scores
        p_cost_score     := LEAST(100, GREATEST(0, NVL(p_cost_score, 0)));
        p_delivery_score := LEAST(100, GREATEST(0, NVL(p_delivery_score, 0)));

    EXCEPTION WHEN OTHERS THEN
        p_cost_score := 50; p_delivery_score := 50; p_quality_score := 50; p_currency_score := 50;
    END SCORE_VENDOR;

    -- --------------------------------------------------------
    -- PRIVATE: Calculate fractional allocation percentages
    -- Allocates higher % to vendors with higher composite scores
    -- using proportional allocation: pct_i = score_i / sum(scores)
    -- --------------------------------------------------------
    PROCEDURE CALCULATE_ALLOCATIONS (
        p_opt_id         IN NUMBER,
        p_total_qty      IN NUMBER,
        p_w_cost         IN NUMBER,
        p_w_delivery     IN NUMBER,
        p_w_quality      IN NUMBER,
        p_w_currency     IN NUMBER
    ) IS
        v_total_score    NUMBER := 0;
        v_alloc_qty_sum  NUMBER := 0;
        v_remainder      NUMBER;

        -- Vendor scoring staging
        TYPE t_vendor_rec IS RECORD (
            supplier_id      NUMBER,
            supplier_code    VARCHAR2(20),
            supplier_name    VARCHAR2(200),
            asl_rank         NUMBER,
            price            NUMBER,
            currency         VARCHAR2(5),
            price_inr        NUMBER,
            lead_time        NUMBER,
            cost_score       NUMBER,
            delivery_score   NUMBER,
            quality_score    NUMBER,
            currency_score   NUMBER,
            composite_score  NUMBER,
            alloc_pct        NUMBER,
            alloc_qty        NUMBER,
            delivery_date    DATE
        );
        TYPE t_vendor_tab IS TABLE OF t_vendor_rec INDEX BY PLS_INTEGER;
        v_vendors        t_vendor_tab;

        v_material_id    NUMBER;
        v_required_qty   NUMBER;
        v_min_price      NUMBER := 9999999999;
        v_max_price      NUMBER := 0;
        v_min_lead       NUMBER := 9999;
        v_max_lead       NUMBER := 0;
        v_idx            PLS_INTEGER := 0;

        -- Blended cost tracking
        v_blended_inr    NUMBER := 0;
        v_blended_sar    NUMBER := 0;
        v_blended_usd    NUMBER := 0;
        v_sar_rate       NUMBER := 22.15;
        v_usd_rate       NUMBER := 83.50;
        v_max_delivery   DATE := SYSDATE;
        v_opt_score      NUMBER := 0;
    BEGIN
        -- Get optimisation target
        SELECT MATERIAL_ID, REQUIRED_QTY INTO v_material_id, v_required_qty
          FROM SOURCING_OPTIMISATION WHERE OPTIMISATION_ID = p_opt_id;

        -- Get exchange rates
        BEGIN SELECT EXCHANGE_RATE INTO v_sar_rate FROM SOURCING_EXCHANGE_RATE WHERE FROM_CURRENCY='SAR' AND TO_CURRENCY='INR' AND IS_ACTIVE='Y' AND ROWNUM=1; EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN SELECT EXCHANGE_RATE INTO v_usd_rate FROM SOURCING_EXCHANGE_RATE WHERE FROM_CURRENCY='USD' AND TO_CURRENCY='INR' AND IS_ACTIVE='Y' AND ROWNUM=1; EXCEPTION WHEN OTHERS THEN NULL; END;

        -- Stage ASL vendors and find min/max for normalisation
        FOR r IN (
            SELECT a.SUPPLIER_ID, s.SUPPLIER_CODE, s.SUPPLIER_NAME, a.PREFERENCE_RANK,
                   a.CONTRACT_PRICE, a.CURRENCY, s.LEAD_TIME
              FROM APPROVED_SUPPLIER_LIST a
              JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = a.SUPPLIER_ID
             WHERE a.MATERIAL_ID = v_material_id AND a.ASL_STATUS = 'APPROVED'
             ORDER BY a.PREFERENCE_RANK
        ) LOOP
            v_idx := v_idx + 1;
            v_vendors(v_idx).supplier_id   := r.SUPPLIER_ID;
            v_vendors(v_idx).supplier_code := r.SUPPLIER_CODE;
            v_vendors(v_idx).supplier_name := r.SUPPLIER_NAME;
            v_vendors(v_idx).asl_rank      := r.PREFERENCE_RANK;
            v_vendors(v_idx).price         := r.CONTRACT_PRICE;
            v_vendors(v_idx).currency      := r.CURRENCY;
            v_vendors(v_idx).price_inr     := TO_INR(r.CONTRACT_PRICE, r.CURRENCY);
            v_vendors(v_idx).lead_time     := NVL(r.LEAD_TIME, 14);

            v_min_price := LEAST(v_min_price, v_vendors(v_idx).price_inr);
            v_max_price := GREATEST(v_max_price, v_vendors(v_idx).price_inr);
            v_min_lead  := LEAST(v_min_lead,  v_vendors(v_idx).lead_time);
            v_max_lead  := GREATEST(v_max_lead, v_vendors(v_idx).lead_time);
        END LOOP;

        IF v_idx = 0 THEN RETURN; END IF; -- No ASL vendors found

        -- Score each vendor and compute composite
        FOR i IN 1..v_idx LOOP
            SCORE_VENDOR(
                p_supplier_id    => v_vendors(i).supplier_id,
                p_material_id    => v_material_id,
                p_min_price_inr  => v_min_price,
                p_max_price_inr  => v_max_price,
                p_min_lead_days  => v_min_lead,
                p_max_lead_days  => v_max_lead,
                p_cost_score     => v_vendors(i).cost_score,
                p_delivery_score => v_vendors(i).delivery_score,
                p_quality_score  => v_vendors(i).quality_score,
                p_currency_score => v_vendors(i).currency_score
            );

            v_vendors(i).composite_score := ROUND(
                (v_vendors(i).cost_score     * p_w_cost     / 100) +
                (v_vendors(i).delivery_score * p_w_delivery / 100) +
                (v_vendors(i).quality_score  * p_w_quality  / 100) +
                (v_vendors(i).currency_score * p_w_currency / 100)
            , 2);

            v_total_score := v_total_score + v_vendors(i).composite_score;
        END LOOP;

        -- Proportional allocation: vendor_pct = vendor_score / total_score
        v_alloc_qty_sum := 0;
        FOR i IN 1..v_idx LOOP
            IF v_total_score > 0 THEN
                v_vendors(i).alloc_pct := ROUND((v_vendors(i).composite_score / v_total_score) * 100, 2);
            ELSE
                v_vendors(i).alloc_pct := ROUND(100 / v_idx, 2);
            END IF;
            v_vendors(i).alloc_qty      := ROUND(v_required_qty * v_vendors(i).alloc_pct / 100, 3);
            v_vendors(i).delivery_date  := SYSDATE + v_vendors(i).lead_time;
            v_alloc_qty_sum             := v_alloc_qty_sum + v_vendors(i).alloc_qty;

            IF v_vendors(i).delivery_date > v_max_delivery THEN
                v_max_delivery := v_vendors(i).delivery_date;
            END IF;
        END LOOP;

        -- Assign rounding remainder to top-scoring vendor
        v_remainder := v_required_qty - v_alloc_qty_sum;
        IF ABS(v_remainder) > 0 AND v_idx > 0 THEN
            v_vendors(1).alloc_qty := v_vendors(1).alloc_qty + v_remainder;
        END IF;

        -- Insert allocation rows
        FOR i IN 1..v_idx LOOP
            DECLARE
                v_line_inr NUMBER := v_vendors(i).alloc_qty * v_vendors(i).price_inr;
            BEGIN
                v_blended_inr := v_blended_inr + v_line_inr;
                IF v_vendors(i).currency = 'SAR' THEN v_blended_sar := v_blended_sar + (v_line_inr / v_sar_rate); END IF;
                IF v_vendors(i).currency = 'USD' THEN v_blended_usd := v_blended_usd + (v_line_inr / v_usd_rate); END IF;

                INSERT INTO SOURCING_ALLOCATION (
                    ALLOCATION_ID, OPTIMISATION_ID, SUPPLIER_ID, SUPPLIER_CODE, SUPPLIER_NAME, ASL_RANK,
                    ALLOCATION_PCT, ALLOCATED_QTY, UNIT_PRICE, CURRENCY, UNIT_PRICE_INR, LINE_TOTAL_INR,
                    EXPECTED_DELIVERY_DAYS, EXPECTED_DELIVERY_DATE,
                    COST_SCORE, DELIVERY_SCORE, QUALITY_SCORE, CURRENCY_SCORE, COMPOSITE_SCORE
                ) VALUES (
                    SEQ_SOURCING_ALLOC.NEXTVAL, p_opt_id, v_vendors(i).supplier_id,
                    v_vendors(i).supplier_code, v_vendors(i).supplier_name, v_vendors(i).asl_rank,
                    v_vendors(i).alloc_pct, v_vendors(i).alloc_qty,
                    v_vendors(i).price, v_vendors(i).currency,
                    v_vendors(i).price_inr, v_vendors(i).alloc_qty * v_vendors(i).price_inr,
                    v_vendors(i).lead_time, v_vendors(i).delivery_date,
                    v_vendors(i).cost_score, v_vendors(i).delivery_score,
                    v_vendors(i).quality_score, v_vendors(i).currency_score,
                    v_vendors(i).composite_score
                );
                v_opt_score := v_opt_score + v_vendors(i).composite_score;
            END;
        END LOOP;

        -- Update optimisation header with blended totals
        UPDATE SOURCING_OPTIMISATION
           SET STATUS                 = 'OPTIMISED',
               TOTAL_BLENDED_COST_INR = ROUND(v_blended_inr, 2),
               TOTAL_BLENDED_COST_SAR = ROUND(v_blended_sar, 2),
               TOTAL_BLENDED_COST_USD = ROUND(v_blended_usd, 2),
               OPTIMISATION_SCORE     = ROUND(v_opt_score / GREATEST(v_idx, 1), 2),
               VENDOR_COUNT           = v_idx,
               EXPECTED_DELIVERY_DATE = v_max_delivery
         WHERE OPTIMISATION_ID = p_opt_id;

    EXCEPTION WHEN OTHERS THEN NULL;
    END CALCULATE_ALLOCATIONS;

    -- ============================================================
    -- PUBLIC: OPTIMISE_SOURCING
    -- ============================================================
    PROCEDURE OPTIMISE_SOURCING (
        p_material_id       IN  NUMBER,
        p_required_qty      IN  NUMBER,
        p_strategy          IN  VARCHAR2 DEFAULT 'BALANCED_RISK',
        p_pr_id             IN  NUMBER   DEFAULT NULL,
        p_optimisation_id   OUT NUMBER,
        p_status            OUT VARCHAR2,
        p_message           OUT VARCHAR2
    ) IS
        v_w_cost     NUMBER;
        v_w_delivery NUMBER;
        v_w_quality  NUMBER;
        v_w_currency NUMBER;
        v_mat_name   VARCHAR2(200);
        v_asl_count  NUMBER;
    BEGIN
        p_status := 'SUCCESS';

        -- Validate material exists
        BEGIN
            SELECT MATERIAL_NAME INTO v_mat_name FROM MATERIAL_MASTER WHERE MATERIAL_ID = p_material_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            p_status  := 'ERROR';
            p_message := 'Material ID ' || p_material_id || ' not found.';
            RETURN;
        END;

        -- Check ASL vendors exist
        SELECT COUNT(*) INTO v_asl_count
          FROM APPROVED_SUPPLIER_LIST
         WHERE MATERIAL_ID = p_material_id AND ASL_STATUS = 'APPROVED';

        IF v_asl_count = 0 THEN
            p_status  := 'ERROR';
            p_message := 'No approved ASL vendors found for material: ' || v_mat_name;
            RETURN;
        END IF;

        -- Get strategy weights
        GET_STRATEGY_WEIGHTS(p_strategy, v_w_cost, v_w_delivery, v_w_quality, v_w_currency);

        -- Insert optimisation header
        INSERT INTO SOURCING_OPTIMISATION (
            OPTIMISATION_ID, PR_ID, MATERIAL_ID, REQUIRED_QTY, STRATEGY,
            WEIGHT_COST, WEIGHT_DELIVERY, WEIGHT_QUALITY, WEIGHT_CURRENCY, STATUS
        ) VALUES (
            SEQ_SOURCING_OPT.NEXTVAL, p_pr_id, p_material_id, p_required_qty,
            p_strategy, v_w_cost, v_w_delivery, v_w_quality, v_w_currency, 'PENDING'
        ) RETURNING OPTIMISATION_ID INTO p_optimisation_id;

        -- Run the allocation engine
        CALCULATE_ALLOCATIONS(p_optimisation_id, p_required_qty, v_w_cost, v_w_delivery, v_w_quality, v_w_currency);

        COMMIT;

        DECLARE v_score NUMBER; v_vendor_cnt NUMBER;
        BEGIN
            SELECT OPTIMISATION_SCORE, VENDOR_COUNT INTO v_score, v_vendor_cnt
              FROM SOURCING_OPTIMISATION WHERE OPTIMISATION_ID = p_optimisation_id;
            p_message := 'Optimisation complete. Strategy: ' || p_strategy
                      || '. ' || v_vendor_cnt || ' vendors in split. '
                      || 'Composite Score: ' || v_score || '/100.';
        END;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_status  := 'ERROR';
            p_message := 'Optimisation failed: ' || SQLERRM;
    END OPTIMISE_SOURCING;

    -- ============================================================
    -- PUBLIC: ACCEPT_SPLIT — create POs from accepted allocations
    -- ============================================================
    PROCEDURE ACCEPT_SPLIT (
        p_optimisation_id   IN  NUMBER,
        p_accepted_by       IN  VARCHAR2,
        p_status            OUT VARCHAR2,
        p_message           OUT VARCHAR2
    ) IS
        v_po_id     NUMBER;
        v_po_count  NUMBER := 0;
        v_material_id NUMBER;
        v_required_qty NUMBER;
    BEGIN
        p_status := 'SUCCESS';

        SELECT MATERIAL_ID, REQUIRED_QTY INTO v_material_id, v_required_qty
          FROM SOURCING_OPTIMISATION WHERE OPTIMISATION_ID = p_optimisation_id AND STATUS = 'OPTIMISED';

        FOR alloc IN (
            SELECT ALLOCATION_ID, SUPPLIER_ID, ALLOCATED_QTY, UNIT_PRICE, CURRENCY, EXPECTED_DELIVERY_DATE
              FROM SOURCING_ALLOCATION WHERE OPTIMISATION_ID = p_optimisation_id
        ) LOOP
            -- Create a Purchase Order for each vendor allocation
            SELECT NVL(MAX(PO_ID),0)+1 INTO v_po_id FROM PURCHASE_ORDER;

            INSERT INTO PURCHASE_ORDER (
                PO_ID, PO_NUMBER, SUPPLIER_ID, PO_DATE, EXPECTED_DELIVERY_DATE,
                STATUS, CURRENCY, TOTAL_AMOUNT, CREATED_BY
            ) VALUES (
                v_po_id,
                'PO-SMART-' || TO_CHAR(SYSDATE,'YYYYMMDD') || '-' || LPAD(v_po_id, 4, '0'),
                alloc.SUPPLIER_ID, SYSDATE, alloc.EXPECTED_DELIVERY_DATE,
                'ISSUED', alloc.CURRENCY,
                alloc.ALLOCATED_QTY * alloc.UNIT_PRICE, p_accepted_by
            );

            INSERT INTO PURCHASE_ORDER_ITEMS (
                PO_ITEM_ID, PO_ID, MATERIAL_ID, QUANTITY_ORDERED, UNIT_PRICE, CURRENCY
            ) VALUES (
                v_po_id * 10, v_po_id, v_material_id,
                alloc.ALLOCATED_QTY, alloc.UNIT_PRICE, alloc.CURRENCY
            );

            UPDATE SOURCING_ALLOCATION
               SET GENERATED_PO_ID = v_po_id
             WHERE ALLOCATION_ID = alloc.ALLOCATION_ID;

            v_po_count := v_po_count + 1;
        END LOOP;

        UPDATE SOURCING_OPTIMISATION
           SET STATUS       = 'ORDERED',
               ACCEPTED_DATE = SYSDATE,
               ACCEPTED_BY  = p_accepted_by
         WHERE OPTIMISATION_ID = p_optimisation_id;

        COMMIT;
        p_message := v_po_count || ' Purchase Orders created successfully from smart sourcing split.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_status  := 'ERROR';
            p_message := 'Accept Split failed: ' || SQLERRM;
    END ACCEPT_SPLIT;

    FUNCTION GET_ALLOCATIONS (p_optimisation_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_rc SYS_REFCURSOR;
    BEGIN
        OPEN v_rc FOR
            SELECT
                a.SUPPLIER_CODE, a.SUPPLIER_NAME, a.ASL_RANK,
                ROUND(a.ALLOCATION_PCT, 2)       AS ALLOCATION_PCT,
                ROUND(a.ALLOCATED_QTY, 3)        AS ALLOCATED_QTY,
                a.UNIT_PRICE, a.CURRENCY,
                ROUND(a.UNIT_PRICE_INR, 2)       AS UNIT_PRICE_INR,
                ROUND(a.LINE_TOTAL_INR, 0)       AS LINE_TOTAL_INR,
                a.EXPECTED_DELIVERY_DAYS,
                TO_CHAR(a.EXPECTED_DELIVERY_DATE,'DD-Mon-YYYY') AS EXPECTED_DELIVERY_DATE,
                ROUND(a.COST_SCORE, 1)           AS COST_SCORE,
                ROUND(a.DELIVERY_SCORE, 1)       AS DELIVERY_SCORE,
                ROUND(a.QUALITY_SCORE, 1)        AS QUALITY_SCORE,
                ROUND(a.CURRENCY_SCORE, 1)       AS CURRENCY_SCORE,
                ROUND(a.COMPOSITE_SCORE, 1)      AS COMPOSITE_SCORE,
                a.GENERATED_PO_ID
              FROM SOURCING_ALLOCATION a
             WHERE a.OPTIMISATION_ID = p_optimisation_id
             ORDER BY a.ALLOCATION_PCT DESC;
        RETURN v_rc;
    END GET_ALLOCATIONS;

    FUNCTION GET_OPTIMISATION_SUMMARY (p_optimisation_id IN NUMBER) RETURN SYS_REFCURSOR IS
        v_rc SYS_REFCURSOR;
    BEGIN
        OPEN v_rc FOR
            SELECT
                o.OPTIMISATION_ID, o.MATERIAL_ID, m.MATERIAL_CODE, m.MATERIAL_NAME,
                o.REQUIRED_QTY, o.STRATEGY,
                o.WEIGHT_COST, o.WEIGHT_DELIVERY, o.WEIGHT_QUALITY, o.WEIGHT_CURRENCY,
                ROUND(o.TOTAL_BLENDED_COST_INR, 0) AS TOTAL_BLENDED_COST_INR,
                ROUND(o.TOTAL_BLENDED_COST_SAR, 2) AS TOTAL_BLENDED_COST_SAR,
                ROUND(o.TOTAL_BLENDED_COST_USD, 2) AS TOTAL_BLENDED_COST_USD,
                ROUND(o.OPTIMISATION_SCORE, 1)     AS OPTIMISATION_SCORE,
                o.VENDOR_COUNT, o.STATUS,
                TO_CHAR(o.EXPECTED_DELIVERY_DATE,'DD-Mon-YYYY') AS EXPECTED_DELIVERY_DATE,
                o.CREATED_BY, o.CREATED_DATE, o.ACCEPTED_BY, o.ACCEPTED_DATE
              FROM SOURCING_OPTIMISATION o
              JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = o.MATERIAL_ID
             WHERE o.OPTIMISATION_ID = p_optimisation_id;
        RETURN v_rc;
    END GET_OPTIMISATION_SUMMARY;

    FUNCTION PREVIEW_OPTIMISATION (
        p_material_id  IN NUMBER,
        p_required_qty IN NUMBER,
        p_strategy     IN VARCHAR2 DEFAULT 'BALANCED_RISK'
    ) RETURN SYS_REFCURSOR IS
        v_opt_id  NUMBER;
        v_status  VARCHAR2(20);
        v_message VARCHAR2(500);
    BEGIN
        OPTIMISE_SOURCING(p_material_id, p_required_qty, p_strategy, NULL, v_opt_id, v_status, v_message);
        RETURN GET_ALLOCATIONS(v_opt_id);
    END PREVIEW_OPTIMISATION;

END PKG_SMART_SOURCING;
/
SHOW ERRORS PACKAGE BODY PKG_SMART_SOURCING;

PROMPT [SUCCESS] PKG_SMART_SOURCING ready.
