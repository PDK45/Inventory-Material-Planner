-- ============================================================
-- MPPMS :: 15_apex_pages_planning.sql
-- Purpose : APEX page specs for Planning Module
--           BOM, Demand Forecast, Production Plan, MRP
-- Pages   : 40, 41, 50, 51, 60, 61, 70, 71
-- ============================================================

/*
=================================================================
PAGE 40 — BILL OF MATERIALS (Master Report)
=================================================================
Page Type : Interactive Report
Page #    : 40
Title     : Bill of Materials

IR REGION SQL (BOM Headers):
*/
SELECT
    b.BOM_ID,
    b.VERSION,
    TO_CHAR(b.EFFECTIVE_DATE,'DD-Mon-YYYY') AS EFFECTIVE_DATE_DISP,
    b.EFFECTIVE_DATE,
    b.STATUS                                AS BOM_STATUS,
    p.PRODUCT_ID,
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    p.PRODUCT_CATEGORY,
    -- Component count
    (SELECT COUNT(*) FROM BOM_DETAILS bd WHERE bd.BOM_ID = b.BOM_ID) AS COMPONENT_COUNT,
    -- Total material cost per unit
    (SELECT NVL(SUM(bd.QUANTITY_REQUIRED * m.STANDARD_COST),0)
       FROM BOM_DETAILS bd
       JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = bd.MATERIAL_ID
      WHERE bd.BOM_ID = b.BOM_ID)           AS UNIT_MATERIAL_COST
FROM BOM_MASTER      b
JOIN PRODUCT_MASTER  p ON p.PRODUCT_ID = b.PRODUCT_ID
ORDER BY p.PRODUCT_CODE, b.VERSION;

/*
COLUMN SETTINGS:
  BOM_ID, PRODUCT_ID     : Hidden
  UNIT_MATERIAL_COST     : Format Mask FM999,999,990.00 | Label: Unit Mat. Cost (INR)
  BOM_STATUS             : Badge (ACTIVE=success, INACTIVE=danger, DRAFT=info)
  COMPONENT_COUNT        : Label: Components

TOOLBAR BUTTON: + New BOM → Page 41
Row Action   : View Components → Redirect Page 42 filtered by BOM_ID
               Breakdown BOM → Runs APEX Process calling PKG_BOM_BREAKDOWN

=================================================================
PAGE 41 — BOM MASTER FORM (Modal)
=================================================================
Width: 700px

ITEMS:
  P41_BOM_ID          Hidden PK
  P41_PRODUCT_ID      Select  | LOV: LOV_PRODUCTS | Required | Label: Product
  P41_VERSION         Text    | Required | Max 10 | Placeholder: e.g. V1.0
  P41_EFFECTIVE_DATE  Date    | Required | Format: DD-MON-YYYY | Default: SYSDATE
  P41_STATUS          Select  | LOV: (ACTIVE/INACTIVE/DRAFT) | Default: DRAFT

VALIDATION:
  Product + Version combination must be unique.
  Code:
    SELECT COUNT(*) INTO v_count FROM BOM_MASTER
     WHERE PRODUCT_ID = :P41_PRODUCT_ID AND VERSION = :P41_VERSION
       AND (BOM_ID != :P41_BOM_ID OR :P41_BOM_ID IS NULL);
    IF v_count > 0 THEN RETURN 'This product already has a BOM with version ' || :P41_VERSION; END IF;

PROCESS: DML on BOM_MASTER

=================================================================
PAGE 42 — BOM DETAILS (Child IR — shown below BOM header)
=================================================================
Page Type : Interactive Report (sub-page inside Page 40 as region)
            OR separate page 42 opened from Page 40 row action.

IR SQL (parameterized by :P42_BOM_ID):
*/
SELECT
    bd.BOM_DETAIL_ID,
    bd.BOM_ID,
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    m.CATEGORY,
    bd.QUANTITY_REQUIRED,
    m.UNIT_OF_MEASURE,
    m.STANDARD_COST,
    bd.QUANTITY_REQUIRED * m.STANDARD_COST  AS LINE_COST,
    m.LEAD_TIME                             AS MAT_LEAD_TIME,
    s.SUPPLIER_NAME                         AS PREFERRED_SUPPLIER,
    bd.REMARKS
FROM BOM_DETAILS       bd
JOIN MATERIAL_MASTER   m ON m.MATERIAL_ID  = bd.MATERIAL_ID
LEFT JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = m.PREFERRED_SUPPLIER_ID
WHERE bd.BOM_ID = :P42_BOM_ID
ORDER BY m.CATEGORY, m.MATERIAL_CODE;

/*
BOM DETAIL FORM ITEMS (Page 43 or inline IG):
  P43_BOM_DETAIL_ID   : Hidden PK
  P43_BOM_ID          : Hidden (passed from parent)
  P43_MATERIAL_ID     : Select | LOV: LOV_MATERIALS | Required
  P43_QUANTITY_REQUIRED: Number | Required | Min: 0.001
  P43_REMARKS         : Text

NOTE: Consider using Interactive Grid on Page 42 for inline editing.
      IG Source: BOM_DETAILS table filtered by :P42_BOM_ID

=================================================================
PAGE 50 — DEMAND FORECAST (Interactive Report)
=================================================================
Page Type : Interactive Report
Page #    : 50

IR SQL:
*/
SELECT
    df.FORECAST_ID,
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    p.PRODUCT_CATEGORY,
    TO_CHAR(df.FORECAST_PERIOD,'Mon-YYYY')  AS PERIOD_LABEL,
    df.FORECAST_PERIOD,
    df.FORECAST_QTY,
    df.FORECAST_TYPE,
    df.CREATED_BY,
    TO_CHAR(df.CREATED_DATE,'DD-Mon-YYYY')  AS CREATED_DATE_DISP,
    df.PRODUCT_ID
FROM DEMAND_FORECAST df
JOIN PRODUCT_MASTER  p  ON p.PRODUCT_ID = df.PRODUCT_ID
ORDER BY df.FORECAST_PERIOD DESC, p.PRODUCT_CODE;

/*
CHART REGION (below IR on Page 50):
  Region Type : Chart (AnyChart or JET Chart)
  Chart Type  : Bar Chart (grouped)
  Title       : Demand Forecast by Period
  SQL:
*/
SELECT
    TO_CHAR(df.FORECAST_PERIOD,'Mon-YYYY') AS PERIOD,
    p.PRODUCT_NAME                          AS SERIES,
    SUM(df.FORECAST_QTY)                    AS VALUE
FROM DEMAND_FORECAST df
JOIN PRODUCT_MASTER  p ON p.PRODUCT_ID = df.PRODUCT_ID
WHERE df.FORECAST_PERIOD >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -6)
GROUP BY df.FORECAST_PERIOD, p.PRODUCT_NAME
ORDER BY df.FORECAST_PERIOD;

/*
=================================================================
PAGE 51 — DEMAND FORECAST FORM (Modal)
=================================================================
Width: 650px

ITEMS:
  P51_FORECAST_ID     : Hidden PK
  P51_PRODUCT_ID      : Select  | LOV: LOV_PRODUCTS | Required
  P51_FORECAST_PERIOD : Date    | Required | Format: MM/YYYY (first of month)
                        Before DB: always set to first day: TRUNC(:P51_FORECAST_PERIOD,'MM')
  P51_FORECAST_QTY    : Number  | Required | Min: 1 | Label: Forecast Quantity
  P51_FORECAST_TYPE   : Select  | LOV: LOV_FORECAST_TYPE | Default: MANUAL
  P51_CREATED_BY      : Text    | Default: APP_USER | Read Only

PROCESS: DML on DEMAND_FORECAST

=================================================================
PAGE 60 — PRODUCTION PLAN (Interactive Report)
=================================================================
Page Type : Interactive Report
Page #    : 60

IR SQL:
*/
SELECT
    pp.PLAN_ID,
    pp.PLAN_NAME,
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    pp.PLANNED_QTY,
    TO_CHAR(pp.PLANNED_START_DATE,'DD-Mon-YYYY') AS START_DATE_DISP,
    TO_CHAR(pp.PLANNED_END_DATE,'DD-Mon-YYYY')   AS END_DATE_DISP,
    pp.PLANNED_START_DATE,
    pp.PLANNED_END_DATE,
    pp.PLANNED_END_DATE - pp.PLANNED_START_DATE  AS DURATION_DAYS,
    pp.STATUS,
    pp.APPROVED_BY,
    pp.CREATED_BY,
    -- MRP status
    (SELECT COUNT(*) FROM MATERIAL_REQUIREMENT_PLAN mrp
      WHERE mrp.PLAN_ID = pp.PLAN_ID)             AS MRP_LINE_COUNT,
    (SELECT COUNT(*) FROM MATERIAL_REQUIREMENT_PLAN mrp
      WHERE mrp.PLAN_ID = pp.PLAN_ID
        AND mrp.NET_REQUIREMENT > 0)               AS SHORTAGE_COUNT
FROM PRODUCTION_PLAN  pp
JOIN PRODUCT_MASTER   p  ON p.PRODUCT_ID = pp.PRODUCT_ID
ORDER BY pp.PLANNED_START_DATE DESC;

/*
COLUMN: STATUS — use badge:
  DRAFT=t-Badge--info | APPROVED=t-Badge--success | IN_PROGRESS=t-Badge--warning
  COMPLETED=t-Badge--success | CANCELLED=t-Badge--danger

ACTION BUTTONS on each row (3 buttons):
  [Edit]          → Page 61
  [Run MRP]       → APEX Process (calls PKG_MRP_ENGINE.CALCULATE_MRP)
  [Generate PRs]  → APEX Process (calls PKG_PROCUREMENT.GENERATE_PR_FROM_MRP)
  — Show [Run MRP] only when STATUS = APPROVED or IN_PROGRESS
  — Show [Generate PRs] only when MRP_LINE_COUNT > 0

BUTTON: Run MRP
  Process Type : PL/SQL
  Code:
    DECLARE
        v_status  VARCHAR2(20);
        v_message VARCHAR2(1000);
    BEGIN
        PKG_MRP_ENGINE.CALCULATE_MRP(
            p_plan_id => :P60_PLAN_ID,
            p_status  => v_status,
            p_message => v_message
        );
        IF v_status = 'SUCCESS' THEN
            APEX_ERROR.ADD_ERROR(
                p_message          => v_message,
                p_display_location => apex_error.c_inline_in_notification
            );
        ELSE
            RAISE_APPLICATION_ERROR(-20001, v_message);
        END IF;
    END;

BUTTON: Generate PRs
  Process Type: PL/SQL
  Code:
    DECLARE
        v_status  VARCHAR2(20);
        v_message VARCHAR2(1000);
        v_count   NUMBER;
    BEGIN
        PKG_PROCUREMENT.GENERATE_PR_FROM_MRP(
            p_plan_id    => :P60_PLAN_ID,
            p_created_by => :APP_USER,
            p_status     => v_status,
            p_message    => v_message,
            p_pr_count   => v_count
        );
        IF v_status != 'SUCCESS' THEN
            RAISE_APPLICATION_ERROR(-20002, v_message);
        END IF;
        APEX_ERROR.ADD_ERROR(
            p_message          => v_message,
            p_display_location => apex_error.c_inline_in_notification
        );
    END;

=================================================================
PAGE 61 — PRODUCTION PLAN FORM (Modal)
=================================================================
Width: 800px

ITEMS:
  P61_PLAN_ID          : Hidden PK
  P61_PRODUCT_ID       : Select  | LOV: LOV_PRODUCTS | Required
  P61_PLAN_NAME        : Text    | Required | Max 100
  P61_PLANNED_QTY      : Number  | Required | Min: 1 | Label: Planned Quantity
  P61_PLANNED_START_DATE: Date   | Required | Format: DD/MM/YYYY
  P61_PLANNED_END_DATE  : Date   | Required | Format: DD/MM/YYYY
  P61_STATUS           : Select  | LOV: LOV_PLAN_STATUS | Default: DRAFT
  P61_APPROVED_BY      : Text    | Max 100 (visible only when STATUS != DRAFT)
  P61_CREATED_BY       : Hidden  | Default: APP_USER

VALIDATIONS:
  1. End Date >= Start Date
     Type : PL/SQL
     Code : IF :P61_PLANNED_END_DATE < :P61_PLANNED_START_DATE THEN RETURN 'End Date must be on or after Start Date.'; END IF; RETURN NULL;
  2. Planned Qty > 0

=================================================================
PAGE 70 — MATERIAL REQUIREMENT PLAN (Interactive Report)
=================================================================
Page Type : Interactive Report
Page #    : 70
Note      : This page is READ-ONLY (system-calculated).
            Users trigger MRP from Page 60.

IR SQL:
*/
SELECT
    mrp.MRP_ID,
    mrp.PLAN_ID,
    pp.PLAN_NAME,
    pp.STATUS                                    AS PLAN_STATUS,
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    m.CATEGORY,
    m.UNIT_OF_MEASURE,
    mrp.GROSS_REQUIREMENT,
    mrp.AVAILABLE_QTY,
    mrp.SAFETY_STOCK,
    mrp.NET_REQUIREMENT,
    mrp.PLANNED_ORDER_QTY,
    TO_CHAR(mrp.REQUIRED_DATE,'DD-Mon-YYYY')     AS REQUIRED_DATE_DISP,
    mrp.REQUIRED_DATE,
    mrp.MRP_STATUS,
    TRUNC(mrp.REQUIRED_DATE) - TRUNC(SYSDATE)   AS DAYS_TO_REQUIRED,
    m.STANDARD_COST,
    mrp.PLANNED_ORDER_QTY * m.STANDARD_COST      AS ESTIMATED_COST,
    -- Shortage highlight
    CASE WHEN mrp.NET_REQUIREMENT > 0 THEN 'YES' ELSE 'NO' END AS SHORTAGE_FLAG
FROM MATERIAL_REQUIREMENT_PLAN mrp
JOIN PRODUCTION_PLAN            pp ON pp.PLAN_ID    = mrp.PLAN_ID
JOIN PRODUCT_MASTER             p  ON p.PRODUCT_ID  = pp.PRODUCT_ID
JOIN MATERIAL_MASTER            m  ON m.MATERIAL_ID  = mrp.MATERIAL_ID
ORDER BY mrp.REQUIRED_DATE, mrp.NET_REQUIREMENT DESC;

/*
ROW HIGHLIGHTING (in IR Attributes > Highlighting):
  Color Rows where SHORTAGE_FLAG = 'YES': Background #FFEBEE (light red)
  Color Rows where DAYS_TO_REQUIRED < 0 : Background #F3E5F5 (overdue purple)

COLUMN: NET_REQUIREMENT
  Conditional Formatting: > 0 = Red Bold

COLUMN: ESTIMATED_COST
  Format: FM999,999,990.00
  Aggregate: Sum

FILTER ITEMS above IR:
  P70_PLAN_ID    : Select | LOV: LOV_APPROVED_PLANS | Submit on Change
  P70_SHORTAGE   : Checkbox | Label: Show Shortages Only
  Add WHERE clause to IR:
    AND (:P70_PLAN_ID IS NULL OR mrp.PLAN_ID = :P70_PLAN_ID)
    AND (:P70_SHORTAGE IS NULL OR mrp.NET_REQUIREMENT > 0)

=================================================================
PAGE 71 — MRP DETAIL (Read-Only Modal)
=================================================================
Shows single MRP record detail with:
  - Material info
  - Gross/Net requirement breakdown
  - Preferred supplier info
  - Link to create manual PR

SQL:
*/
SELECT
    mrp.*,
    m.MATERIAL_CODE, m.MATERIAL_NAME, m.UNIT_OF_MEASURE,
    m.STANDARD_COST, m.LEAD_TIME,
    pp.PLAN_NAME, pp.PLANNED_START_DATE, pp.PLANNED_END_DATE,
    p.PRODUCT_NAME, p.PRODUCT_CODE,
    s.SUPPLIER_NAME, s.LEAD_TIME AS SUP_LEAD_TIME, s.VENDOR_RATING,
    mrp.PLANNED_ORDER_QTY * m.STANDARD_COST AS ESTIMATED_COST
FROM MATERIAL_REQUIREMENT_PLAN mrp
JOIN MATERIAL_MASTER   m  ON m.MATERIAL_ID  = mrp.MATERIAL_ID
JOIN PRODUCTION_PLAN   pp ON pp.PLAN_ID     = mrp.PLAN_ID
JOIN PRODUCT_MASTER    p  ON p.PRODUCT_ID   = pp.PRODUCT_ID
LEFT JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = m.PREFERRED_SUPPLIER_ID
WHERE mrp.MRP_ID = :P71_MRP_ID;

PROMPT [SUCCESS] Planning module APEX page specs created.
