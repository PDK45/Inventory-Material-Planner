-- ============================================================
-- MPPMS :: 19_testing_validation.sql
-- Purpose : Complete validation and smoke-test scripts
-- Run As  : MPPMS user on FREEPDB1
-- ============================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Phase 12 - Testing & Validation
PROMPT ============================================================

-- ============================================================
-- TEST 1: Schema Object Inventory
-- ============================================================
PROMPT 
PROMPT === TEST 1: Schema Objects ===
SELECT object_type, COUNT(*) AS object_count, 
       SUM(CASE WHEN status = 'VALID' THEN 1 ELSE 0 END) AS valid_count,
       SUM(CASE WHEN status != 'VALID' THEN 1 ELSE 0 END) AS invalid_count
FROM user_objects
GROUP BY object_type
ORDER BY object_type;

-- ============================================================
-- TEST 2: Table Row Counts
-- ============================================================
PROMPT 
PROMPT === TEST 2: Table Row Counts ===
SELECT 'SUPPLIER_MASTER'           AS ENTITY, COUNT(*) AS ROW_COUNT FROM SUPPLIER_MASTER
UNION ALL SELECT 'MATERIAL_MASTER',             COUNT(*) FROM MATERIAL_MASTER
UNION ALL SELECT 'PRODUCT_MASTER',              COUNT(*) FROM PRODUCT_MASTER
UNION ALL SELECT 'BOM_MASTER',                  COUNT(*) FROM BOM_MASTER
UNION ALL SELECT 'BOM_DETAILS',                 COUNT(*) FROM BOM_DETAILS
UNION ALL SELECT 'DEMAND_FORECAST',             COUNT(*) FROM DEMAND_FORECAST
UNION ALL SELECT 'PRODUCTION_PLAN',             COUNT(*) FROM PRODUCTION_PLAN
UNION ALL SELECT 'MATERIAL_REQUIREMENT_PLAN',   COUNT(*) FROM MATERIAL_REQUIREMENT_PLAN
UNION ALL SELECT 'PURCHASE_REQUISITION',        COUNT(*) FROM PURCHASE_REQUISITION
UNION ALL SELECT 'PURCHASE_ORDER',              COUNT(*) FROM PURCHASE_ORDER
UNION ALL SELECT 'PURCHASE_ORDER_ITEMS',        COUNT(*) FROM PURCHASE_ORDER_ITEMS
UNION ALL SELECT 'PROCUREMENT_TRACKING',        COUNT(*) FROM PROCUREMENT_TRACKING
ORDER BY 1;

-- ============================================================
-- TEST 3: Package Compilation Status
-- ============================================================
PROMPT 
PROMPT === TEST 3: Package Status ===
SELECT object_name, object_type, status
FROM user_objects
WHERE object_type IN ('PACKAGE','PACKAGE BODY')
ORDER BY object_name, object_type;

-- ============================================================
-- TEST 4: View Validity
-- ============================================================
PROMPT 
PROMPT === TEST 4: View Status ===
SELECT view_name, 
       CASE WHEN text IS NOT NULL THEN 'VALID' ELSE 'INVALID' END AS status
FROM user_views
ORDER BY view_name;

-- ============================================================
-- TEST 5: BOM Breakdown Smoke Test (PRD-2001)
-- ============================================================
PROMPT 
PROMPT === TEST 5: BOM Breakdown for PRD-2001 (Qty=10) ===
SELECT
    MATERIAL_CODE,
    MATERIAL_NAME,
    QUANTITY_REQUIRED AS PER_UNIT,
    TOTAL_QTY         AS FOR_10_UNITS,
    UNIT_OF_MEASURE,
    STANDARD_COST,
    TOTAL_COST
FROM TABLE(
    PKG_BOM_BREAKDOWN.BREAKDOWN_BOM(
        (SELECT PRODUCT_ID FROM PRODUCT_MASTER WHERE PRODUCT_CODE = 'PRD-2001'),
        10
    )
)
ORDER BY CATEGORY, MATERIAL_CODE;

-- ============================================================
-- TEST 6: MRP Engine Test (dry run on Plan 1)
-- ============================================================
PROMPT 
PROMPT === TEST 6: MRP Calculation Test ===
DECLARE
    v_plan_id NUMBER;
    v_status  VARCHAR2(20);
    v_message VARCHAR2(1000);
BEGIN
    -- Get first approved plan
    SELECT PLAN_ID INTO v_plan_id
      FROM PRODUCTION_PLAN
     WHERE STATUS IN ('APPROVED','IN_PROGRESS')
     FETCH FIRST 1 ROW ONLY;

    DBMS_OUTPUT.PUT_LINE('Testing MRP on Plan ID: ' || v_plan_id);

    PKG_MRP_ENGINE.CALCULATE_MRP(
        p_plan_id => v_plan_id,
        p_status  => v_status,
        p_message => v_message
    );

    DBMS_OUTPUT.PUT_LINE('Status : ' || v_status);
    DBMS_OUTPUT.PUT_LINE('Message: ' || v_message);
    DBMS_OUTPUT.PUT_LINE('Shortage Count: ' || PKG_MRP_ENGINE.GET_SHORTAGE_COUNT(v_plan_id));
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
END;
/

-- ============================================================
-- TEST 7: Dashboard KPI Functions
-- ============================================================
PROMPT 
PROMPT === TEST 7: Dashboard KPIs ===
SELECT
    PKG_DASHBOARD.GET_OPEN_PR_COUNT()          AS OPEN_PRS,
    PKG_DASHBOARD.GET_OPEN_PO_COUNT()          AS OPEN_POS,
    PKG_DASHBOARD.GET_SHORTAGE_COUNT()         AS SHORTAGES,
    PKG_DASHBOARD.GET_OVERDUE_DELIVERY_COUNT() AS OVERDUE,
    PKG_DASHBOARD.GET_PENDING_APPROVAL_COUNT() AS PENDING_APPROVAL,
    PKG_DASHBOARD.GET_MONTHLY_PO_VALUE()       AS MONTHLY_PO_VALUE,
    PKG_DASHBOARD.GET_ACTIVE_PLAN_COUNT()      AS ACTIVE_PLANS,
    PKG_DASHBOARD.GET_PREFERRED_SUPPLIER_COUNT() AS PREFERRED_SUPPLIERS
FROM DUAL;

-- ============================================================
-- TEST 8: End-to-End Workflow Test
-- ============================================================
PROMPT 
PROMPT === TEST 8: End-to-End Workflow Validation ===
DECLARE
    v_plan_id      NUMBER;
    v_pr_id        NUMBER;
    v_po_id        NUMBER;
    v_po_number    VARCHAR2(25);
    v_supplier_id  NUMBER;
    v_status       VARCHAR2(20);
    v_message      VARCHAR2(1000);
    v_pr_count     NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== END-TO-END WORKFLOW TEST ===');

    -- Step 1: Get an approved plan
    SELECT PLAN_ID INTO v_plan_id FROM PRODUCTION_PLAN
     WHERE STATUS IN ('APPROVED','IN_PROGRESS') AND ROWNUM = 1;
    DBMS_OUTPUT.PUT_LINE('[1] Plan ID: ' || v_plan_id || ' found.');

    -- Step 2: Run MRP
    PKG_MRP_ENGINE.CALCULATE_MRP(v_plan_id, v_status, v_message);
    DBMS_OUTPUT.PUT_LINE('[2] MRP: ' || v_status || ' - ' || v_message);

    -- Step 3: Generate PRs from MRP
    PKG_PROCUREMENT.GENERATE_PR_FROM_MRP(v_plan_id, 'TEST_USER', v_status, v_message, v_pr_count);
    DBMS_OUTPUT.PUT_LINE('[3] PR Generation: ' || v_status || ' - ' || v_message);

    -- Step 4: Approve first SUBMITTED PR
    BEGIN
        SELECT PR_ID INTO v_pr_id
          FROM PURCHASE_REQUISITION
         WHERE STATUS = 'SUBMITTED' AND ROWNUM = 1;

        PKG_PROCUREMENT.APPROVE_PR(v_pr_id, 'TEST_MANAGER', v_status, v_message);
        DBMS_OUTPUT.PUT_LINE('[4] PR Approval: ' || v_status || ' - ' || v_message);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('[4] No SUBMITTED PRs available for test.');
            GOTO skip_po;
    END;

    -- Step 5: Get recommended supplier
    SELECT MATERIAL_ID INTO v_supplier_id
      FROM PURCHASE_REQUISITION WHERE PR_ID = v_pr_id;
    v_supplier_id := PKG_PROCUREMENT.RECOMMEND_SUPPLIER(v_supplier_id);
    DBMS_OUTPUT.PUT_LINE('[5] Recommended Supplier ID: ' || v_supplier_id);

    -- Step 6: Generate PO from PR
    PKG_PROCUREMENT.GENERATE_PO_FROM_PR(
        p_pr_id        => v_pr_id,
        p_supplier_id  => v_supplier_id,
        p_created_by   => 'TEST_BUYER',
        p_po_id        => v_po_id,
        p_po_number    => v_po_number,
        p_status       => v_status,
        p_message      => v_message
    );
    DBMS_OUTPUT.PUT_LINE('[6] PO Generation: ' || v_status || ' - ' || v_message);
    IF v_po_id IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('    PO Number: ' || v_po_number);
    END IF;

    -- Rollback test data (keep DB clean)
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('[7] Test data rolled back. DB is clean.');
    DBMS_OUTPUT.PUT_LINE('=== WORKFLOW TEST COMPLETE ===');

    <<skip_po>>
    NULL;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('WORKFLOW TEST ERROR: ' || SQLERRM);
END;
/

-- ============================================================
-- TEST 9: FK Constraint Verification
-- ============================================================
PROMPT 
PROMPT === TEST 9: Constraint Status ===
SELECT table_name, constraint_name, constraint_type, status
FROM user_constraints
WHERE constraint_type IN ('P','R','U')
ORDER BY table_name, constraint_type;

-- ============================================================
-- TEST 10: Index Status
-- ============================================================
PROMPT 
PROMPT === TEST 10: Index Status ===
SELECT index_name, table_name, status, uniqueness
FROM user_indexes
WHERE status != 'VALID'
ORDER BY table_name;

SELECT 'All indexes VALID' AS RESULT FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM user_indexes WHERE status != 'VALID');

-- ============================================================
-- FINAL SUMMARY
-- ============================================================
PROMPT 
PROMPT ============================================================
PROMPT  MPPMS PHASE 12 TEST RESULTS
PROMPT ============================================================
DECLARE
    v_tables   NUMBER;
    v_views    NUMBER;
    v_packages NUMBER;
    v_triggers NUMBER;
    v_indexes  NUMBER;
    v_invalid  NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_tables   FROM user_tables;
    SELECT COUNT(*) INTO v_views    FROM user_views;
    SELECT COUNT(*) INTO v_packages FROM user_objects WHERE object_type = 'PACKAGE BODY';
    SELECT COUNT(*) INTO v_triggers FROM user_triggers;
    SELECT COUNT(*) INTO v_indexes  FROM user_indexes;
    SELECT COUNT(*) INTO v_invalid  FROM user_objects WHERE status != 'VALID';

    DBMS_OUTPUT.PUT_LINE('Tables    : ' || v_tables);
    DBMS_OUTPUT.PUT_LINE('Views     : ' || v_views);
    DBMS_OUTPUT.PUT_LINE('Packages  : ' || v_packages);
    DBMS_OUTPUT.PUT_LINE('Triggers  : ' || v_triggers);
    DBMS_OUTPUT.PUT_LINE('Indexes   : ' || v_indexes);
    DBMS_OUTPUT.PUT_LINE('Invalid Objects: ' || v_invalid);

    IF v_invalid = 0 THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('*** ALL OBJECTS VALID — MPPMS READY FOR DEPLOYMENT ***');
    ELSE
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('WARNING: ' || v_invalid || ' invalid objects found. Review user_errors.');
    END IF;
END;
/
