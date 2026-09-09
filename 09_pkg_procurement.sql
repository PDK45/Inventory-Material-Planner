-- ============================================================
-- MPPMS :: 09_pkg_procurement.sql
-- Package: PKG_PROCUREMENT
-- Purpose: PR generation, PO generation, supplier recommendation
-- Run As : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Creating PKG_PROCUREMENT
PROMPT ============================================================

CREATE OR REPLACE PACKAGE PKG_PROCUREMENT AS

    -- Generate PRs from MRP shortages for a given plan
    PROCEDURE GENERATE_PR_FROM_MRP (
        p_plan_id    IN  NUMBER,
        p_created_by IN  VARCHAR2 DEFAULT 'SYSTEM',
        p_status     OUT VARCHAR2,
        p_message    OUT VARCHAR2,
        p_pr_count   OUT NUMBER
    );

    -- Overloaded: APEX-friendly (raises exception on error)
    PROCEDURE GENERATE_PR_FROM_MRP (
        p_plan_id    IN NUMBER,
        p_created_by IN VARCHAR2 DEFAULT 'SYSTEM'
    );

    -- Generate a PO from an approved PR
    PROCEDURE GENERATE_PO_FROM_PR (
        p_pr_id        IN  NUMBER,
        p_supplier_id  IN  NUMBER,
        p_delivery_days IN NUMBER DEFAULT NULL,
        p_created_by   IN  VARCHAR2 DEFAULT 'BUYER',
        p_po_id        OUT NUMBER,
        p_po_number    OUT VARCHAR2,
        p_status       OUT VARCHAR2,
        p_message      OUT VARCHAR2
    );

    -- Recommend best supplier for a material (by rating + lead time)
    FUNCTION RECOMMEND_SUPPLIER (
        p_material_id IN NUMBER
    ) RETURN NUMBER;

    -- Approve a PR
    PROCEDURE APPROVE_PR (
        p_pr_id      IN  NUMBER,
        p_approved_by IN  VARCHAR2,
        p_status     OUT VARCHAR2,
        p_message    OUT VARCHAR2
    );

    -- Reject a PR
    PROCEDURE REJECT_PR (
        p_pr_id      IN  NUMBER,
        p_rejected_by IN VARCHAR2,
        p_reason      IN VARCHAR2,
        p_status     OUT VARCHAR2,
        p_message    OUT VARCHAR2
    );

    -- Cancel a PO
    PROCEDURE CANCEL_PO (
        p_po_id      IN  NUMBER,
        p_reason     IN  VARCHAR2,
        p_status     OUT VARCHAR2,
        p_message    OUT VARCHAR2
    );

    -- Update PO status
    PROCEDURE UPDATE_PO_STATUS (
        p_po_id      IN  NUMBER,
        p_new_status IN  VARCHAR2,
        p_status     OUT VARCHAR2,
        p_message    OUT VARCHAR2
    );

END PKG_PROCUREMENT;
/
SHOW ERRORS PACKAGE PKG_PROCUREMENT;

-- ============================================================
-- PACKAGE BODY
-- ============================================================
CREATE OR REPLACE PACKAGE BODY PKG_PROCUREMENT AS

    -- --------------------------------------------------------
    -- Recommend best supplier for a material
    -- Logic: Preferred supplier first, then by rating DESC, lead_time ASC
    -- --------------------------------------------------------
    FUNCTION RECOMMEND_SUPPLIER (
        p_material_id IN NUMBER
    ) RETURN NUMBER IS
        v_supplier_id  SUPPLIER_MASTER.SUPPLIER_ID%TYPE;
        v_preferred_id MATERIAL_MASTER.PREFERRED_SUPPLIER_ID%TYPE;
    BEGIN
        -- Get preferred supplier from material master
        SELECT PREFERRED_SUPPLIER_ID
          INTO v_preferred_id
          FROM MATERIAL_MASTER
         WHERE MATERIAL_ID = p_material_id;

        -- Validate preferred supplier is still active
        IF v_preferred_id IS NOT NULL THEN
            DECLARE
                v_status SUPPLIER_MASTER.STATUS%TYPE;
            BEGIN
                SELECT STATUS INTO v_status
                  FROM SUPPLIER_MASTER
                 WHERE SUPPLIER_ID = v_preferred_id;

                IF v_status = 'ACTIVE' THEN
                    RETURN v_preferred_id;
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN NULL;
            END;
        END IF;

        -- Fallback: best active supplier by rating then lead time
        SELECT SUPPLIER_ID
          INTO v_supplier_id
          FROM SUPPLIER_MASTER
         WHERE STATUS = 'ACTIVE'
         ORDER BY VENDOR_RATING DESC, LEAD_TIME ASC
         FETCH FIRST 1 ROW ONLY;

        RETURN v_supplier_id;

    EXCEPTION
        WHEN OTHERS THEN RETURN NULL;
    END RECOMMEND_SUPPLIER;

    -- --------------------------------------------------------
    -- Generate PRs from MRP shortages
    -- --------------------------------------------------------
    PROCEDURE GENERATE_PR_FROM_MRP (
        p_plan_id    IN  NUMBER,
        p_created_by IN  VARCHAR2 DEFAULT 'SYSTEM',
        p_status     OUT VARCHAR2,
        p_message    OUT VARCHAR2,
        p_pr_count   OUT NUMBER
    ) IS
        v_plan_status  PRODUCTION_PLAN.STATUS%TYPE;
        v_pr_id        PURCHASE_REQUISITION.PR_ID%TYPE;
        v_existing     NUMBER;
        v_count        NUMBER := 0;
    BEGIN
        p_status   := 'SUCCESS';
        p_pr_count := 0;

        -- Validate plan
        BEGIN
            SELECT STATUS INTO v_plan_status
              FROM PRODUCTION_PLAN WHERE PLAN_ID = p_plan_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_status  := 'ERROR';
                p_message := 'Plan ID ' || p_plan_id || ' not found.';
                RETURN;
        END;

        IF v_plan_status NOT IN ('APPROVED','IN_PROGRESS') THEN
            p_status  := 'ERROR';
            p_message := 'Plan must be APPROVED or IN_PROGRESS to generate PRs. Status: ' || v_plan_status;
            RETURN;
        END IF;

        -- Loop through MRP shortages for this plan
        FOR r IN (
            SELECT
                mrp.MRP_ID,
                mrp.MATERIAL_ID,
                mrp.PLANNED_ORDER_QTY,
                mrp.REQUIRED_DATE,
                m.LEAD_TIME
            FROM MATERIAL_REQUIREMENT_PLAN mrp
            JOIN MATERIAL_MASTER           m   ON m.MATERIAL_ID = mrp.MATERIAL_ID
            WHERE mrp.PLAN_ID         = p_plan_id
              AND mrp.NET_REQUIREMENT > 0
              AND mrp.MRP_STATUS      = 'CALCULATED'
            ORDER BY mrp.REQUIRED_DATE
        ) LOOP
            -- Check if PR already exists for this MRP record
            SELECT COUNT(*) INTO v_existing
              FROM PURCHASE_REQUISITION
             WHERE MRP_ID = r.MRP_ID;

            IF v_existing = 0 THEN
                -- Determine priority based on lead time and required date
                DECLARE
                    v_priority VARCHAR2(10);
                    v_days_to_required NUMBER;
                BEGIN
                    v_days_to_required := r.REQUIRED_DATE - SYSDATE;
                    IF v_days_to_required <= NVL(r.LEAD_TIME, 7) THEN
                        v_priority := 'HIGH';
                    ELSIF v_days_to_required <= NVL(r.LEAD_TIME, 7) * 1.5 THEN
                        v_priority := 'MEDIUM';
                    ELSE
                        v_priority := 'LOW';
                    END IF;

                    -- Insert PR (PR_NUMBER auto-generated by trigger)
                    INSERT INTO PURCHASE_REQUISITION (
                        MRP_ID, MATERIAL_ID, REQUESTED_QTY,
                        REQUIRED_DATE, PRIORITY, STATUS,
                        JUSTIFICATION, REQUESTED_BY, CREATED_DATE
                    ) VALUES (
                        r.MRP_ID, r.MATERIAL_ID, r.PLANNED_ORDER_QTY,
                        r.REQUIRED_DATE, v_priority, 'SUBMITTED',
                        'System-generated from MRP Plan ID: ' || p_plan_id,
                        p_created_by, SYSDATE
                    );

                    v_count := v_count + 1;
                END;

                -- Update MRP status to PR_RAISED
                UPDATE MATERIAL_REQUIREMENT_PLAN
                   SET MRP_STATUS = 'PR_RAISED'
                 WHERE MRP_ID = r.MRP_ID;
            END IF;
        END LOOP;

        COMMIT;
        p_pr_count := v_count;
        p_message  := v_count || ' Purchase Requisition(s) generated from MRP Plan ' || p_plan_id || '.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_status  := 'ERROR';
            p_message := 'GENERATE_PR_FROM_MRP failed: ' || SQLERRM;
    END GENERATE_PR_FROM_MRP;

    -- Overloaded (APEX-friendly)
    PROCEDURE GENERATE_PR_FROM_MRP (
        p_plan_id    IN NUMBER,
        p_created_by IN VARCHAR2 DEFAULT 'SYSTEM'
    ) IS
        v_status  VARCHAR2(20);
        v_message VARCHAR2(1000);
        v_count   NUMBER;
    BEGIN
        GENERATE_PR_FROM_MRP(p_plan_id, p_created_by, v_status, v_message, v_count);
        IF v_status = 'ERROR' THEN
            RAISE_APPLICATION_ERROR(-20002, v_message);
        END IF;
    END GENERATE_PR_FROM_MRP;

    -- --------------------------------------------------------
    -- Approve a PR
    -- --------------------------------------------------------
    PROCEDURE APPROVE_PR (
        p_pr_id       IN  NUMBER,
        p_approved_by IN  VARCHAR2,
        p_status      OUT VARCHAR2,
        p_message     OUT VARCHAR2
    ) IS
        v_current_status PURCHASE_REQUISITION.STATUS%TYPE;
    BEGIN
        SELECT STATUS INTO v_current_status
          FROM PURCHASE_REQUISITION WHERE PR_ID = p_pr_id;

        IF v_current_status NOT IN ('SUBMITTED','DRAFT') THEN
            p_status  := 'ERROR';
            p_message := 'PR cannot be approved. Current status: ' || v_current_status;
            RETURN;
        END IF;

        UPDATE PURCHASE_REQUISITION
           SET STATUS        = 'APPROVED',
               APPROVED_BY   = p_approved_by,
               APPROVED_DATE = SYSDATE
         WHERE PR_ID = p_pr_id;

        COMMIT;
        p_status  := 'SUCCESS';
        p_message := 'PR approved successfully.';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_status  := 'ERROR';
            p_message := 'PR ID ' || p_pr_id || ' not found.';
        WHEN OTHERS THEN
            ROLLBACK;
            p_status  := 'ERROR';
            p_message := 'APPROVE_PR failed: ' || SQLERRM;
    END APPROVE_PR;

    -- --------------------------------------------------------
    -- Reject a PR
    -- --------------------------------------------------------
    PROCEDURE REJECT_PR (
        p_pr_id       IN  NUMBER,
        p_rejected_by IN  VARCHAR2,
        p_reason      IN  VARCHAR2,
        p_status      OUT VARCHAR2,
        p_message     OUT VARCHAR2
    ) IS
        v_current_status PURCHASE_REQUISITION.STATUS%TYPE;
    BEGIN
        SELECT STATUS INTO v_current_status
          FROM PURCHASE_REQUISITION WHERE PR_ID = p_pr_id;

        IF v_current_status NOT IN ('SUBMITTED','DRAFT') THEN
            p_status  := 'ERROR';
            p_message := 'PR cannot be rejected. Current status: ' || v_current_status;
            RETURN;
        END IF;

        UPDATE PURCHASE_REQUISITION
           SET STATUS      = 'REJECTED',
               APPROVED_BY = p_rejected_by || ' [REJECTED: ' || SUBSTR(p_reason,1,200) || ']',
               APPROVED_DATE = SYSDATE
         WHERE PR_ID = p_pr_id;

        COMMIT;
        p_status  := 'SUCCESS';
        p_message := 'PR rejected.';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_status  := 'ERROR';
            p_message := 'PR ID ' || p_pr_id || ' not found.';
        WHEN OTHERS THEN
            ROLLBACK;
            p_status  := 'ERROR';
            p_message := 'REJECT_PR failed: ' || SQLERRM;
    END REJECT_PR;

    -- --------------------------------------------------------
    -- Generate PO from an approved PR
    -- --------------------------------------------------------
    PROCEDURE GENERATE_PO_FROM_PR (
        p_pr_id         IN  NUMBER,
        p_supplier_id   IN  NUMBER,
        p_delivery_days IN  NUMBER DEFAULT NULL,
        p_created_by    IN  VARCHAR2 DEFAULT 'BUYER',
        p_po_id         OUT NUMBER,
        p_po_number     OUT VARCHAR2,
        p_status        OUT VARCHAR2,
        p_message       OUT VARCHAR2
    ) IS
        v_pr_status      PURCHASE_REQUISITION.STATUS%TYPE;
        v_material_id    PURCHASE_REQUISITION.MATERIAL_ID%TYPE;
        v_requested_qty  PURCHASE_REQUISITION.REQUESTED_QTY%TYPE;
        v_supplier_status SUPPLIER_MASTER.STATUS%TYPE;
        v_lead_time      SUPPLIER_MASTER.LEAD_TIME%TYPE;
        v_std_cost       MATERIAL_MASTER.STANDARD_COST%TYPE;
        v_delivery_date  DATE;
        v_new_po_id      NUMBER;
    BEGIN
        p_status := 'SUCCESS';

        -- Validate PR
        BEGIN
            SELECT STATUS, MATERIAL_ID, REQUESTED_QTY
              INTO v_pr_status, v_material_id, v_requested_qty
              FROM PURCHASE_REQUISITION WHERE PR_ID = p_pr_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_status  := 'ERROR';
                p_message := 'PR ID ' || p_pr_id || ' not found.';
                RETURN;
        END;

        IF v_pr_status != 'APPROVED' THEN
            p_status  := 'ERROR';
            p_message := 'PR must be APPROVED before generating PO. Status: ' || v_pr_status;
            RETURN;
        END IF;

        -- Validate supplier
        BEGIN
            SELECT STATUS, LEAD_TIME
              INTO v_supplier_status, v_lead_time
              FROM SUPPLIER_MASTER WHERE SUPPLIER_ID = p_supplier_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_status  := 'ERROR';
                p_message := 'Supplier ID ' || p_supplier_id || ' not found.';
                RETURN;
        END;

        IF v_supplier_status != 'ACTIVE' THEN
            p_status  := 'ERROR';
            p_message := 'Supplier is not ACTIVE. Cannot raise PO.';
            RETURN;
        END IF;

        -- Get standard cost for line item pricing
        SELECT STANDARD_COST INTO v_std_cost
          FROM MATERIAL_MASTER WHERE MATERIAL_ID = v_material_id;

        -- Calculate delivery date
        v_delivery_date := SYSDATE + NVL(p_delivery_days, v_lead_time);

        -- Insert PO header (PO_NUMBER auto-generated by trigger)
        INSERT INTO PURCHASE_ORDER (
            PR_ID, SUPPLIER_ID, ORDER_DATE, DELIVERY_DATE,
            ORDER_STATUS, TERMS, CREATED_BY, CREATED_DATE
        ) VALUES (
            p_pr_id, p_supplier_id, SYSDATE, v_delivery_date,
            'ISSUED', 'Standard Terms. Net 30 Days.', p_created_by, SYSDATE
        ) RETURNING PO_ID, PO_NUMBER INTO v_new_po_id, p_po_number;

        -- Insert PO line item
        INSERT INTO PURCHASE_ORDER_ITEMS (
            PO_ID, MATERIAL_ID, ORDERED_QTY, UNIT_PRICE, RECEIVED_QTY
        ) VALUES (
            v_new_po_id, v_material_id, v_requested_qty, v_std_cost, 0
        );

        -- Create initial tracking record
        INSERT INTO PROCUREMENT_TRACKING (
            PO_ID, EXPECTED_DATE, DELIVERY_STATUS, REMARKS, UPDATED_BY
        ) VALUES (
            v_new_po_id, v_delivery_date, 'PENDING',
            'PO issued. Awaiting supplier acknowledgement.', p_created_by
        );

        -- Update PR status to ORDERED
        UPDATE PURCHASE_REQUISITION
           SET STATUS = 'ORDERED'
         WHERE PR_ID = p_pr_id;

        COMMIT;

        p_po_id   := v_new_po_id;
        p_status  := 'SUCCESS';
        p_message := 'PO ' || p_po_number || ' generated successfully for PR ' || p_pr_id || '.';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_status  := 'ERROR';
            p_message := 'GENERATE_PO_FROM_PR failed: ' || SQLERRM;
    END GENERATE_PO_FROM_PR;

    -- --------------------------------------------------------
    -- Cancel a PO
    -- --------------------------------------------------------
    PROCEDURE CANCEL_PO (
        p_po_id   IN  NUMBER,
        p_reason  IN  VARCHAR2,
        p_status  OUT VARCHAR2,
        p_message OUT VARCHAR2
    ) IS
        v_current_status PURCHASE_ORDER.ORDER_STATUS%TYPE;
    BEGIN
        SELECT ORDER_STATUS INTO v_current_status
          FROM PURCHASE_ORDER WHERE PO_ID = p_po_id;

        IF v_current_status IN ('RECEIVED','CANCELLED') THEN
            p_status  := 'ERROR';
            p_message := 'PO cannot be cancelled. Current status: ' || v_current_status;
            RETURN;
        END IF;

        UPDATE PURCHASE_ORDER
           SET ORDER_STATUS = 'CANCELLED'
         WHERE PO_ID = p_po_id;

        INSERT INTO PROCUREMENT_TRACKING (
            PO_ID, DELIVERY_STATUS, REMARKS, UPDATED_BY
        ) VALUES (
            p_po_id, 'CANCELLED',
            'PO Cancelled. Reason: ' || SUBSTR(p_reason, 1, 500),
            USER
        );

        COMMIT;
        p_status  := 'SUCCESS';
        p_message := 'PO ID ' || p_po_id || ' cancelled successfully.';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_status  := 'ERROR';
            p_message := 'PO ID ' || p_po_id || ' not found.';
        WHEN OTHERS THEN
            ROLLBACK;
            p_status  := 'ERROR';
            p_message := 'CANCEL_PO failed: ' || SQLERRM;
    END CANCEL_PO;

    -- --------------------------------------------------------
    -- Update PO Status
    -- --------------------------------------------------------
    PROCEDURE UPDATE_PO_STATUS (
        p_po_id      IN  NUMBER,
        p_new_status IN  VARCHAR2,
        p_status     OUT VARCHAR2,
        p_message    OUT VARCHAR2
    ) IS
        v_valid_status NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_valid_status
          FROM PURCHASE_ORDER
         WHERE PO_ID = p_po_id;

        IF v_valid_status = 0 THEN
            p_status  := 'ERROR';
            p_message := 'PO ID ' || p_po_id || ' not found.';
            RETURN;
        END IF;

        UPDATE PURCHASE_ORDER
           SET ORDER_STATUS = p_new_status
         WHERE PO_ID = p_po_id;

        -- Add tracking entry
        INSERT INTO PROCUREMENT_TRACKING (
            PO_ID, DELIVERY_STATUS, REMARKS, UPDATED_BY
        ) VALUES (
            p_po_id, p_new_status,
            'Status updated to: ' || p_new_status, USER
        );

        COMMIT;
        p_status  := 'SUCCESS';
        p_message := 'PO status updated to ' || p_new_status || '.';
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_status  := 'ERROR';
            p_message := 'UPDATE_PO_STATUS failed: ' || SQLERRM;
    END UPDATE_PO_STATUS;

END PKG_PROCUREMENT;
/
SHOW ERRORS PACKAGE BODY PKG_PROCUREMENT;

PROMPT [SUCCESS] PKG_PROCUREMENT ready.
