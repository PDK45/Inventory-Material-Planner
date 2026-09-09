-- ============================================================
-- MPPMS :: 17_apex_pages_reports.sql
-- Purpose : APEX page specs for Reports Module
-- Pages   : 110 (Material Planning), 120 (Procurement),
--           130 (Supplier), 140 (PO Report)
-- ============================================================

/*
=================================================================
PAGE 110 — MATERIAL PLANNING REPORT
=================================================================
Page Type  : Report Page (Interactive Report + Chart)
Page #     : 110
Title      : Material Planning Report
Description: Demand vs Plan coverage with MRP requirement analysis

REGION 1: Demand vs Plan Coverage (IR)
Title: Demand & Production Coverage Analysis
*/
SELECT
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    p.PRODUCT_CATEGORY,
    TO_CHAR(df.FORECAST_PERIOD,'Mon-YYYY')       AS PERIOD,
    df.FORECAST_PERIOD,
    df.FORECAST_QTY,
    df.FORECAST_TYPE,
    NVL(pp.PLAN_NAME, '-- No Plan --')           AS PLAN_NAME,
    NVL(pp.PLANNED_QTY, 0)                       AS PLANNED_QTY,
    NVL(pp.STATUS, 'NO_PLAN')                    AS PLAN_STATUS,
    NVL(pp.PLANNED_QTY,0) - df.FORECAST_QTY     AS QTY_GAP,
    CASE
        WHEN pp.PLAN_ID IS NULL                  THEN 'No Plan'
        WHEN pp.PLANNED_QTY >= df.FORECAST_QTY  THEN 'Fully Covered'
        WHEN pp.PLANNED_QTY  > 0                THEN 'Partial'
        ELSE 'Not Covered'
    END                                          AS COVERAGE_STATUS,
    ROUND(NVL(pp.PLANNED_QTY,0) / NULLIF(df.FORECAST_QTY,0) * 100, 1) AS COVERAGE_PCT
FROM DEMAND_FORECAST   df
JOIN PRODUCT_MASTER    p   ON p.PRODUCT_ID  = df.PRODUCT_ID
LEFT JOIN PRODUCTION_PLAN pp ON pp.PRODUCT_ID = df.PRODUCT_ID
                            AND TRUNC(pp.PLANNED_START_DATE,'MM') = TRUNC(df.FORECAST_PERIOD,'MM')
WHERE (:P110_PRODUCT_ID IS NULL OR df.PRODUCT_ID = :P110_PRODUCT_ID)
  AND (:P110_PERIOD_FROM IS NULL OR df.FORECAST_PERIOD >= :P110_PERIOD_FROM)
  AND (:P110_PERIOD_TO   IS NULL OR df.FORECAST_PERIOD <= :P110_PERIOD_TO)
ORDER BY df.FORECAST_PERIOD DESC, p.PRODUCT_CODE;

/*
REGION 2: MRP Material Requirement Summary (IR)
Title: Material Requirements by Plan
*/
SELECT
    pp.PLAN_NAME,
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    m.CATEGORY,
    m.UNIT_OF_MEASURE,
    mrp.GROSS_REQUIREMENT,
    mrp.AVAILABLE_QTY,
    mrp.NET_REQUIREMENT,
    mrp.PLANNED_ORDER_QTY,
    TO_CHAR(mrp.REQUIRED_DATE,'DD-Mon-YYYY')     AS REQUIRED_DATE,
    mrp.MRP_STATUS,
    m.STANDARD_COST,
    mrp.PLANNED_ORDER_QTY * m.STANDARD_COST      AS ESTIMATED_COST,
    CASE WHEN mrp.NET_REQUIREMENT > 0 THEN 'SHORTAGE' ELSE 'OK' END AS STATUS_FLAG
FROM MATERIAL_REQUIREMENT_PLAN mrp
JOIN PRODUCTION_PLAN            pp ON pp.PLAN_ID    = mrp.PLAN_ID
JOIN PRODUCT_MASTER             p  ON p.PRODUCT_ID  = pp.PRODUCT_ID
JOIN MATERIAL_MASTER            m  ON m.MATERIAL_ID  = mrp.MATERIAL_ID
WHERE (:P110_PLAN_ID IS NULL OR mrp.PLAN_ID = :P110_PLAN_ID)
ORDER BY mrp.REQUIRED_DATE, mrp.NET_REQUIREMENT DESC;

/*
REGION 3: Coverage Chart (JET Bar Chart)
Title: Demand vs Planned Quantity by Period
*/
SELECT
    TO_CHAR(df.FORECAST_PERIOD,'Mon-YY')  AS PERIOD,
    'Forecast'                             AS SERIES,
    SUM(df.FORECAST_QTY)                   AS VALUE
FROM DEMAND_FORECAST df
WHERE df.FORECAST_PERIOD >= ADD_MONTHS(TRUNC(SYSDATE,'MM'),-3)
  AND df.FORECAST_PERIOD <= ADD_MONTHS(TRUNC(SYSDATE,'MM'), 6)
GROUP BY df.FORECAST_PERIOD
UNION ALL
SELECT
    TO_CHAR(pp.PLANNED_START_DATE,'Mon-YY') AS PERIOD,
    'Planned'                                AS SERIES,
    SUM(pp.PLANNED_QTY)                      AS VALUE
FROM PRODUCTION_PLAN pp
WHERE pp.PLANNED_START_DATE >= ADD_MONTHS(TRUNC(SYSDATE,'MM'),-3)
  AND pp.STATUS NOT IN ('CANCELLED')
GROUP BY pp.PLANNED_START_DATE
ORDER BY 1, 2;

/*
FILTER ITEMS (Page 110, above regions):
  P110_PRODUCT_ID  : Select | LOV: LOV_PRODUCTS | Allow Null | Label: Product
  P110_PLAN_ID     : Select | LOV: LOV_APPROVED_PLANS | Allow Null | Label: Plan
  P110_PERIOD_FROM : Date   | Label: Period From | Format: MM/YYYY
  P110_PERIOD_TO   : Date   | Label: Period To   | Format: MM/YYYY
  SEARCH Button    : Submit page (refreshes all regions)
  RESET Button     : Clear all filter items + submit

EXPORT: Excel + PDF on both IR regions

=================================================================
PAGE 120 — PROCUREMENT REPORT
=================================================================
Page Type  : Report Page (3 regions)
Page #     : 120
Title      : Procurement Report

REGION 1: PR Aging Analysis
*/
SELECT
    pr.PR_NUMBER,
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    pr.PRIORITY,
    pr.STATUS,
    pr.REQUESTED_QTY,
    pr.REQUESTED_QTY * m.STANDARD_COST           AS ESTIMATED_VALUE,
    TO_CHAR(pr.REQUIRED_DATE,'DD-Mon-YYYY')       AS REQUIRED_DATE,
    TO_CHAR(pr.CREATED_DATE,'DD-Mon-YYYY')        AS CREATED_DATE,
    TRUNC(SYSDATE) - TRUNC(pr.CREATED_DATE)       AS AGE_DAYS,
    CASE
        WHEN TRUNC(SYSDATE) - TRUNC(pr.CREATED_DATE) > 14 THEN 'Overdue'
        WHEN TRUNC(SYSDATE) - TRUNC(pr.CREATED_DATE) > 7  THEN 'Aging'
        ELSE 'Normal'
    END                                           AS AGING_STATUS,
    pr.REQUESTED_BY,
    pr.APPROVED_BY
FROM PURCHASE_REQUISITION pr
JOIN MATERIAL_MASTER       m  ON m.MATERIAL_ID = pr.MATERIAL_ID
WHERE (:P120_PR_STATUS IS NULL OR pr.STATUS = :P120_PR_STATUS)
  AND (:P120_DATE_FROM IS NULL OR pr.CREATED_DATE >= :P120_DATE_FROM)
ORDER BY pr.PRIORITY, pr.REQUIRED_DATE;

/*
REGION 2: PO Spend by Month (Chart + Table)
*/
SELECT
    TO_CHAR(po.ORDER_DATE,'Mon-YYYY')     AS MONTH,
    po.ORDER_DATE,
    COUNT(po.PO_ID)                       AS PO_COUNT,
    SUM(po.TOTAL_VALUE)                   AS TOTAL_SPEND,
    COUNT(CASE WHEN po.ORDER_STATUS = 'CANCELLED' THEN 1 END) AS CANCELLED_COUNT
FROM PURCHASE_ORDER po
WHERE po.ORDER_DATE >= ADD_MONTHS(SYSDATE, -12)
  AND (:P120_SUPPLIER_ID IS NULL OR po.SUPPLIER_ID = :P120_SUPPLIER_ID)
GROUP BY TO_CHAR(po.ORDER_DATE,'Mon-YYYY'), TRUNC(po.ORDER_DATE,'MM')
ORDER BY TRUNC(po.ORDER_DATE,'MM');

/*
REGION 3: Open PO Summary
*/
SELECT
    po.PO_NUMBER,
    s.SUPPLIER_NAME,
    po.ORDER_STATUS,
    TO_CHAR(po.ORDER_DATE,'DD-Mon-YYYY')          AS ORDER_DATE,
    TO_CHAR(po.DELIVERY_DATE,'DD-Mon-YYYY')       AS DELIVERY_DATE,
    po.TOTAL_VALUE,
    TRUNC(po.DELIVERY_DATE) - TRUNC(SYSDATE)      AS DAYS_TO_DELIVERY,
    pt.DELIVERY_STATUS                            AS TRACKING_STATUS
FROM PURCHASE_ORDER       po
JOIN SUPPLIER_MASTER       s  ON s.SUPPLIER_ID = po.SUPPLIER_ID
LEFT JOIN (SELECT PO_ID, DELIVERY_STATUS, ROW_NUMBER() OVER (PARTITION BY PO_ID ORDER BY UPDATED_DATE DESC) RN
             FROM PROCUREMENT_TRACKING) pt ON pt.PO_ID = po.PO_ID AND pt.RN = 1
WHERE po.ORDER_STATUS NOT IN ('RECEIVED','CANCELLED')
  AND (:P120_SUPPLIER_ID IS NULL OR po.SUPPLIER_ID = :P120_SUPPLIER_ID)
ORDER BY po.DELIVERY_DATE;

/*
FILTER ITEMS:
  P120_PR_STATUS   : Select | LOV: LOV_PR_STATUS
  P120_SUPPLIER_ID : Select | LOV: LOV_SUPPLIERS
  P120_DATE_FROM   : Date
  P120_DATE_TO     : Date

=================================================================
PAGE 130 — SUPPLIER PERFORMANCE REPORT
=================================================================
Page Type  : Report + Charts
Page #     : 130

REGION 1: Supplier Scorecard (IR)
*/
SELECT
    s.SUPPLIER_CODE,
    s.SUPPLIER_NAME,
    s.STATUS,
    s.VENDOR_RATING,
    CASE
        WHEN s.VENDOR_RATING >= 4.5 THEN 'A'
        WHEN s.VENDOR_RATING >= 4.0 THEN 'B'
        WHEN s.VENDOR_RATING >= 3.5 THEN 'C'
        ELSE 'D'
    END                                            AS GRADE,
    s.LEAD_TIME                                    AS STD_LEAD_DAYS,
    COUNT(po.PO_ID)                                AS TOTAL_POS,
    COUNT(CASE WHEN po.ORDER_STATUS = 'RECEIVED'   THEN 1 END) AS COMPLETED_POS,
    COUNT(CASE WHEN po.ORDER_STATUS = 'CANCELLED'  THEN 1 END) AS CANCELLED_POS,
    COUNT(CASE WHEN po.ORDER_STATUS NOT IN ('RECEIVED','CANCELLED') THEN 1 END) AS OPEN_POS,
    NVL(SUM(CASE WHEN po.ORDER_STATUS != 'CANCELLED' THEN po.TOTAL_VALUE END),0) AS TOTAL_SPEND,
    ROUND(
        COUNT(CASE WHEN po.ORDER_STATUS = 'RECEIVED' AND po.DELIVERY_DATE >= po.ORDER_DATE THEN 1 END)
        * 100.0 / NULLIF(COUNT(CASE WHEN po.ORDER_STATUS = 'RECEIVED' THEN 1 END),0), 1
    )                                              AS ON_TIME_RATE
FROM SUPPLIER_MASTER         s
LEFT JOIN PURCHASE_ORDER     po ON po.SUPPLIER_ID = s.SUPPLIER_ID
WHERE (:P130_STATUS IS NULL OR s.STATUS = :P130_STATUS)
GROUP BY s.SUPPLIER_ID, s.SUPPLIER_CODE, s.SUPPLIER_NAME,
         s.STATUS, s.VENDOR_RATING, s.LEAD_TIME
ORDER BY s.VENDOR_RATING DESC, TOTAL_SPEND DESC;

/*
REGION 2: Top Suppliers by Spend (Bar Chart)
*/
SELECT
    s.SUPPLIER_NAME                   AS LABEL,
    NVL(SUM(po.TOTAL_VALUE),0)        AS VALUE
FROM SUPPLIER_MASTER       s
LEFT JOIN PURCHASE_ORDER   po ON po.SUPPLIER_ID = s.SUPPLIER_ID
                              AND po.ORDER_STATUS != 'CANCELLED'
GROUP BY s.SUPPLIER_NAME
ORDER BY VALUE DESC
FETCH FIRST 5 ROWS ONLY;

/*
REGION 3: Material Count per Supplier
*/
SELECT
    s.SUPPLIER_NAME,
    COUNT(m.MATERIAL_ID)  AS MATERIAL_COUNT
FROM SUPPLIER_MASTER   s
LEFT JOIN MATERIAL_MASTER m ON m.PREFERRED_SUPPLIER_ID = s.SUPPLIER_ID
GROUP BY s.SUPPLIER_ID, s.SUPPLIER_NAME
ORDER BY MATERIAL_COUNT DESC;

/*
COLUMN HIGHLIGHTS:
  GRADE A → Green bold | B → Blue | C → Orange | D → Red
  ON_TIME_RATE < 80 → Red | 80-95 → Orange | >95 → Green

=================================================================
PAGE 140 — PURCHASE ORDER REPORT
=================================================================
Page Type : Interactive Report (print-ready)
Page #    : 140
Title     : Purchase Order Report

IR SQL:
*/
SELECT
    po.PO_NUMBER,
    po.ORDER_STATUS,
    TO_CHAR(po.ORDER_DATE,'DD-Mon-YYYY')           AS ORDER_DATE,
    TO_CHAR(po.DELIVERY_DATE,'DD-Mon-YYYY')        AS DELIVERY_DATE,
    s.SUPPLIER_CODE,
    s.SUPPLIER_NAME,
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    m.CATEGORY,
    poi.ORDERED_QTY,
    m.UNIT_OF_MEASURE,
    poi.UNIT_PRICE,
    poi.TOTAL_VALUE,
    poi.RECEIVED_QTY,
    poi.ORDERED_QTY - NVL(poi.RECEIVED_QTY,0)     AS OUTSTANDING_QTY,
    pt.DELIVERY_STATUS                             AS TRACKING_STATUS,
    TO_CHAR(pt.EXPECTED_DATE,'DD-Mon-YYYY')        AS EXPECTED_DELIVERY,
    TO_CHAR(pt.ACTUAL_DATE,'DD-Mon-YYYY')          AS ACTUAL_DELIVERY,
    pr.PR_NUMBER                                   AS SOURCE_PR
FROM PURCHASE_ORDER        po
JOIN SUPPLIER_MASTER        s   ON s.SUPPLIER_ID  = po.SUPPLIER_ID
JOIN PURCHASE_ORDER_ITEMS   poi ON poi.PO_ID       = po.PO_ID
JOIN MATERIAL_MASTER        m   ON m.MATERIAL_ID   = poi.MATERIAL_ID
LEFT JOIN PURCHASE_REQUISITION pr ON pr.PR_ID      = po.PR_ID
LEFT JOIN (
    SELECT PO_ID, DELIVERY_STATUS, EXPECTED_DATE, ACTUAL_DATE,
           ROW_NUMBER() OVER (PARTITION BY PO_ID ORDER BY UPDATED_DATE DESC) RN
    FROM PROCUREMENT_TRACKING
) pt ON pt.PO_ID = po.PO_ID AND pt.RN = 1
WHERE (:P140_SUPPLIER_ID IS NULL OR po.SUPPLIER_ID = :P140_SUPPLIER_ID)
  AND (:P140_STATUS IS NULL OR po.ORDER_STATUS = :P140_STATUS)
  AND (:P140_DATE_FROM IS NULL OR po.ORDER_DATE >= :P140_DATE_FROM)
  AND (:P140_DATE_TO   IS NULL OR po.ORDER_DATE <= :P140_DATE_TO)
ORDER BY po.ORDER_DATE DESC, po.PO_NUMBER;

/*
AGGREGATES:
  TOTAL_VALUE : SUM → Grand Total
  ORDERED_QTY : SUM per PO

CHART REGION: PO Status Distribution (Donut)
*/
SELECT ORDER_STATUS AS LABEL, COUNT(*) AS VALUE
FROM   PURCHASE_ORDER
GROUP  BY ORDER_STATUS
ORDER  BY COUNT(*) DESC;

PROMPT [SUCCESS] Reports module SQL ready (Pages 110, 120, 130, 140).
