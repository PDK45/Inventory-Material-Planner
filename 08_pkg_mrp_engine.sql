-- ============================================================
-- MPPMS :: 08_pkg_mrp_engine.sql
-- Package: PKG_MRP_ENGINE
-- Purpose: Full MRP calculation engine
-- Run As : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Creating PKG_MRP_ENGINE
PROMPT ============================================================

-- ============================================================
-- PACKAGE SPECIFICATION
-- ============================================================
CREATE OR REPLACE PACKAGE PKG_MRP_ENGINE AS

    -- Run full MRP for a production plan
    -- Explodes BOM, calculates gross/net requirements, writes to MRP table
    PROCEDURE CALCULATE_MRP (
        p_plan_id    IN  NUMBER,
        p_status     OUT VARCHAR2,
        p_message    OUT VARCHAR2
    );

    -- Overloaded: run without OUT params (for APEX process calls)
    PROCEDURE CALCULATE_MRP (
        p_plan_id    IN NUMBER
    );

    -- Get count of materials in shortage for a plan
    FUNCTION GET_SHORTAGE_COUNT (
        p_plan_id IN NUMBER
    ) RETURN NUMBER;

    -- Get total net procurement value for a plan
    FUNCTION GET_PLAN_PROCUREMENT_VALUE (
        p_plan_id IN NUMBER
    ) RETURN NUMBER;

    -- Recalculate MRP net requirement for a single MRP record
    PROCEDURE RECALC_NET_REQUIREMENT (
        p_mrp_id IN NUMBER
    );

END PKG_MRP_ENGINE;
/
SHOW ERRORS PACKAGE PKG_MRP_ENGINE;

-- ============================================================
-- PACKAGE BODY
-- ============================================================
CREATE OR REPLACE PACKAGE BODY PKG_MRP_ENGINE AS

    -- --------------------------------------------------------
    -- Internal: Get current available qty for a material
    -- This is the integration hook with inventory systems.
    -- Currently returns the last known available_qty from MRP
    -- or 0 if no prior record exists.
    -- --------------------------------------------------------
    FUNCTION GET_AVAILABLE_QTY (
        p_material_id IN NUMBER
    ) RETURN NUMBER IS
    BEGIN
        -- Query live available inventory from PKG_INVENTORY
        RETURN PKG_INVENTORY.GET_TOTAL_AVAILABLE_STOCK(p_material_id);
    EXCEPTION
        WHEN OTHERS THEN RETURN 0;
    END GET_AVAILABLE_QTY;

    -- --------------------------------------------------------
    -- Recalculate net requirement for one MRP record
    -- Formula: NET_REQ = MAX(0, GROSS_REQ - AVAIL_QTY + SAFETY_STOCK)
    -- --------------------------------------------------------
    PROCEDURE RECALC_NET_REQUIREMENT (
        p_mrp_id IN NUMBER
    ) IS
    BEGIN
        UPDATE MATERIAL_REQUIREMENT_PLAN
           SET NET_REQUIREMENT   = GREATEST(0, GROSS_REQUIREMENT - AVAILABLE_QTY + SAFETY_STOCK),
               PLANNED_ORDER_QTY = GREATEST(0, GROSS_REQUIREMENT - AVAILABLE_QTY + SAFETY_STOCK),
               CALCULATED_DATE   = SYSDATE
         WHERE MRP_ID = p_mrp_id;
    END RECALC_NET_REQUIREMENT;

    -- --------------------------------------------------------
    -- CALCULATE_MRP (main procedure)
    -- Steps:
    --   1. Validate plan exists and is APPROVED or IN_PROGRESS
    --   2. Delete any prior MRP records for this plan
    --   3. Explode BOM for the product at planned qty
    --   4. For each material: calculate gross req, get available qty,
    --      apply safety stock, calculate net requirement
    --   5. Insert results into MATERIAL_REQUIREMENT_PLAN
    -- --------------------------------------------------------
    PROCEDURE CALCULATE_MRP (
        p_plan_id    IN  NUMBER,
        p_status     OUT VARCHAR2,
        p_message    OUT VARCHAR2
    ) IS
        -- Plan details
        v_product_id        PRODUCTION_PLAN.PRODUCT_ID%TYPE;
        v_planned_qty       PRODUCTION_PLAN.PLANNED_QTY%TYPE;
        v_plan_status       PRODUCTION_PLAN.STATUS%TYPE;
        v_planned_start     PRODUCTION_PLAN.PLANNED_START_DATE%TYPE;

        -- Material details
        v_safety_stock      MATERIAL_MASTER.SAFETY_STOCK%TYPE;
        v_lead_time         MATERIAL_MASTER.LEAD_TIME%TYPE;
        v_avail_qty         NUMBER;
        v_gross_req         NUMBER;
        v_net_req           NUMBER;
        v_required_date     DATE;

        -- Counters
        v_line_count        NUMBER := 0;
        v_shortage_count    NUMBER := 0;

    BEGIN
        p_status  := 'SUCCESS';
        p_message := '';

        -- Step 1: Validate plan
        BEGIN
            SELECT PRODUCT_ID, PLANNED_QTY, STATUS, PLANNED_START_DATE
              INTO v_product_id, v_planned_qty, v_plan_status, v_planned_start
              FROM PRODUCTION_PLAN
             WHERE PLAN_ID = p_plan_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_status  := 'ERROR';
                p_message := 'Production Plan ID ' || p_plan_id || ' not found.';
                RETURN;
        END;

        IF v_plan_status NOT IN ('APPROVED','IN_PROGRESS') THEN
            p_status  := 'ERROR';
            p_message := 'MRP can only run on APPROVED or IN_PROGRESS plans. Current status: ' || v_plan_status;
            RETURN;
        END IF;

        -- Step 2: Validate BOM exists
        IF NOT PKG_BOM_BREAKDOWN.BOM_EXISTS(v_product_id) THEN
            p_status  := 'ERROR';
            p_message := 'No active BOM found for Product ID ' || v_product_id || '. Cannot run MRP.';
            RETURN;
        END IF;

        -- Step 3: Delete prior CALCULATED MRP records for this plan
        -- Keep PR_RAISED records to preserve audit trail
        -- Clear references in PURCHASE_REQUISITION to prevent FK_PR_MRP constraint violations
        UPDATE PURCHASE_REQUISITION
           SET MRP_ID = NULL
         WHERE MRP_ID IN (
             SELECT MRP_ID 
               FROM MATERIAL_REQUIREMENT_PLAN
              WHERE PLAN_ID   = p_plan_id
                AND MRP_STATUS = 'CALCULATED'
         );

        DELETE FROM MATERIAL_REQUIREMENT_PLAN
         WHERE PLAN_ID   = p_plan_id
           AND MRP_STATUS = 'CALCULATED';

        -- Step 4: Explode BOM and insert MRP records
        FOR r IN (
            SELECT
                MATERIAL_ID,
                MATERIAL_CODE,
                TOTAL_QTY,
                LEAD_TIME,
                PREFERRED_SUPPLIER_ID
            FROM TABLE(PKG_BOM_BREAKDOWN.BREAKDOWN_BOM(v_product_id, v_planned_qty))
        ) LOOP
            -- Get material-level details
            BEGIN
                SELECT SAFETY_STOCK
                  INTO v_safety_stock
                  FROM MATERIAL_MASTER
                 WHERE MATERIAL_ID = r.MATERIAL_ID;
            EXCEPTION
                WHEN OTHERS THEN v_safety_stock := 0;
            END;

            -- Available qty (inventory hook)
            v_avail_qty := GET_AVAILABLE_QTY(r.MATERIAL_ID);

            -- Gross requirement = BOM qty * planned qty
            v_gross_req := r.TOTAL_QTY;

            -- Required date = plan start minus lead time
            v_required_date := v_planned_start - NVL(r.LEAD_TIME, 0);

            -- Net requirement formula
            v_net_req := GREATEST(0, v_gross_req - v_avail_qty + v_safety_stock);

            -- Check if MRP record already exists (from prior PR_RAISED status)
            DECLARE
                v_existing_mrp_id NUMBER;
            BEGIN
                SELECT MRP_ID INTO v_existing_mrp_id
                  FROM MATERIAL_REQUIREMENT_PLAN
                 WHERE PLAN_ID = p_plan_id AND MATERIAL_ID = r.MATERIAL_ID
                   AND MRP_STATUS != 'CALCULATED';
                -- Already has a PR_RAISED record — skip, don't overwrite
                NULL;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    -- Insert new MRP record
                    INSERT INTO MATERIAL_REQUIREMENT_PLAN (
                        PLAN_ID, MATERIAL_ID, GROSS_REQUIREMENT,
                        AVAILABLE_QTY, SAFETY_STOCK, NET_REQUIREMENT,
                        PLANNED_ORDER_QTY, REQUIRED_DATE, MRP_STATUS, CALCULATED_DATE
                    ) VALUES (
                        p_plan_id, r.MATERIAL_ID, v_gross_req,
                        v_avail_qty, v_safety_stock, v_net_req,
                        v_net_req, v_required_date, 'CALCULATED', SYSDATE
                    );

                    v_line_count := v_line_count + 1;
                    IF v_net_req > 0 THEN
                        v_shortage_count := v_shortage_count + 1;
                    END IF;
            END;
        END LOOP;

        -- Step 5: Update plan status to IN_PROGRESS if still APPROVED
        IF v_plan_status = 'APPROVED' THEN
            UPDATE PRODUCTION_PLAN
               SET STATUS = 'IN_PROGRESS'
             WHERE PLAN_ID = p_plan_id;
        END IF;

        COMMIT;

        p_status  := 'SUCCESS';
        p_message := 'MRP calculation complete. ' ||
                     v_line_count    || ' material lines processed. ' ||
                     v_shortage_count || ' shortages detected.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_status  := 'ERROR';
            p_message := 'MRP Calculation failed: ' || SQLERRM;
    END CALCULATE_MRP;

    -- --------------------------------------------------------
    -- Overloaded CALCULATE_MRP (no OUT params, for APEX calls)
    -- --------------------------------------------------------
    PROCEDURE CALCULATE_MRP (
        p_plan_id IN NUMBER
    ) IS
        v_status  VARCHAR2(20);
        v_message VARCHAR2(1000);
    BEGIN
        CALCULATE_MRP(p_plan_id, v_status, v_message);
        IF v_status = 'ERROR' THEN
            RAISE_APPLICATION_ERROR(-20001, v_message);
        END IF;
    END CALCULATE_MRP;

    -- --------------------------------------------------------
    -- Get shortage count for a plan
    -- --------------------------------------------------------
    FUNCTION GET_SHORTAGE_COUNT (
        p_plan_id IN NUMBER
    ) RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(*)
          INTO v_count
          FROM MATERIAL_REQUIREMENT_PLAN
         WHERE PLAN_ID         = p_plan_id
           AND NET_REQUIREMENT > 0;
        RETURN v_count;
    EXCEPTION
        WHEN OTHERS THEN RETURN 0;
    END GET_SHORTAGE_COUNT;

    -- --------------------------------------------------------
    -- Get total planned procurement value for a plan
    -- --------------------------------------------------------
    FUNCTION GET_PLAN_PROCUREMENT_VALUE (
        p_plan_id IN NUMBER
    ) RETURN NUMBER IS
        v_value NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(mrp.PLANNED_ORDER_QTY * m.STANDARD_COST), 0)
          INTO v_value
          FROM MATERIAL_REQUIREMENT_PLAN mrp
          JOIN MATERIAL_MASTER           m   ON m.MATERIAL_ID = mrp.MATERIAL_ID
         WHERE mrp.PLAN_ID         = p_plan_id
           AND mrp.NET_REQUIREMENT > 0;
        RETURN v_value;
    EXCEPTION
        WHEN OTHERS THEN RETURN 0;
    END GET_PLAN_PROCUREMENT_VALUE;

END PKG_MRP_ENGINE;
/
SHOW ERRORS PACKAGE BODY PKG_MRP_ENGINE;

PROMPT [SUCCESS] PKG_MRP_ENGINE ready.
