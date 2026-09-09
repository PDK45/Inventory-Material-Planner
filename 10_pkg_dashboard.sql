-- ============================================================
-- MPPMS :: 10_pkg_dashboard.sql
-- Package: PKG_DASHBOARD
-- Purpose: KPI functions + chart data for APEX Dashboard
-- Run As : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Creating PKG_DASHBOARD
PROMPT ============================================================

CREATE OR REPLACE PACKAGE PKG_DASHBOARD AS

    -- KPI: Count of open (non-closed) Purchase Requisitions
    FUNCTION GET_OPEN_PR_COUNT         RETURN NUMBER;

    -- KPI: Count of open Purchase Orders
    FUNCTION GET_OPEN_PO_COUNT         RETURN NUMBER;

    -- KPI: Materials with net requirement > 0 (any plan)
    FUNCTION GET_SHORTAGE_COUNT        RETURN NUMBER;

    -- KPI: POs past expected delivery date with no actual delivery
    FUNCTION GET_OVERDUE_DELIVERY_COUNT RETURN NUMBER;

    -- KPI: Total PO value this month
    FUNCTION GET_MONTHLY_PO_VALUE      RETURN NUMBER;

    -- KPI: Count of PRs awaiting approval
    FUNCTION GET_PENDING_APPROVAL_COUNT RETURN NUMBER;

    -- KPI: Count of suppliers with rating >= 4.0 (preferred)
    FUNCTION GET_PREFERRED_SUPPLIER_COUNT RETURN NUMBER;

    -- KPI: Total active production plans
    FUNCTION GET_ACTIVE_PLAN_COUNT     RETURN NUMBER;

END PKG_DASHBOARD;
/
SHOW ERRORS PACKAGE PKG_DASHBOARD;

-- ============================================================
-- PACKAGE BODY
-- ============================================================
CREATE OR REPLACE PACKAGE BODY PKG_DASHBOARD AS

    FUNCTION GET_OPEN_PR_COUNT RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(*) INTO v_count
          FROM PURCHASE_REQUISITION
         WHERE STATUS NOT IN ('CLOSED','REJECTED','ORDERED');
        RETURN NVL(v_count, 0);
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END GET_OPEN_PR_COUNT;

    FUNCTION GET_OPEN_PO_COUNT RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(*) INTO v_count
          FROM PURCHASE_ORDER
         WHERE ORDER_STATUS NOT IN ('RECEIVED','CANCELLED');
        RETURN NVL(v_count, 0);
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END GET_OPEN_PO_COUNT;

    FUNCTION GET_SHORTAGE_COUNT RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(DISTINCT MATERIAL_ID) INTO v_count
          FROM MATERIAL_REQUIREMENT_PLAN
         WHERE NET_REQUIREMENT > 0
           AND MRP_STATUS      = 'CALCULATED';
        RETURN NVL(v_count, 0);
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END GET_SHORTAGE_COUNT;

    FUNCTION GET_OVERDUE_DELIVERY_COUNT RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(*) INTO v_count
          FROM PURCHASE_ORDER        po
          JOIN PROCUREMENT_TRACKING  pt ON pt.PO_ID = po.PO_ID
         WHERE po.ORDER_STATUS    NOT IN ('RECEIVED','CANCELLED')
           AND pt.EXPECTED_DATE   <  TRUNC(SYSDATE)
           AND pt.ACTUAL_DATE     IS NULL
           AND pt.DELIVERY_STATUS NOT IN ('DELIVERED','CANCELLED');
        RETURN NVL(v_count, 0);
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END GET_OVERDUE_DELIVERY_COUNT;

    FUNCTION GET_MONTHLY_PO_VALUE RETURN NUMBER IS
        v_value NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(po.TOTAL_VALUE), 0) INTO v_value
          FROM PURCHASE_ORDER po
         WHERE TRUNC(po.ORDER_DATE, 'MM') = TRUNC(SYSDATE, 'MM')
           AND po.ORDER_STATUS != 'CANCELLED';
        RETURN NVL(v_value, 0);
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END GET_MONTHLY_PO_VALUE;

    FUNCTION GET_PENDING_APPROVAL_COUNT RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(*) INTO v_count
          FROM PURCHASE_REQUISITION
         WHERE STATUS = 'SUBMITTED';
        RETURN NVL(v_count, 0);
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END GET_PENDING_APPROVAL_COUNT;

    FUNCTION GET_PREFERRED_SUPPLIER_COUNT RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(*) INTO v_count
          FROM SUPPLIER_MASTER
         WHERE STATUS        = 'ACTIVE'
           AND VENDOR_RATING >= 4.0;
        RETURN NVL(v_count, 0);
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END GET_PREFERRED_SUPPLIER_COUNT;

    FUNCTION GET_ACTIVE_PLAN_COUNT RETURN NUMBER IS
        v_count NUMBER := 0;
    BEGIN
        SELECT COUNT(*) INTO v_count
          FROM PRODUCTION_PLAN
         WHERE STATUS IN ('APPROVED','IN_PROGRESS');
        RETURN NVL(v_count, 0);
    EXCEPTION WHEN OTHERS THEN RETURN 0;
    END GET_ACTIVE_PLAN_COUNT;

END PKG_DASHBOARD;
/
SHOW ERRORS PACKAGE BODY PKG_DASHBOARD;

PROMPT [SUCCESS] PKG_DASHBOARD ready.
