-- ============================================================
-- MPPMS :: 11_views.sql
-- Purpose : All reporting and APEX data source views
-- Run As  : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Creating Reporting Views (Phase 5)
PROMPT ============================================================

-- ============================================================
-- VIEW 1: VW_MATERIAL_AVAILABILITY
-- Purpose: Material master enriched with reorder status
--          Acts as inventory integration hook
-- ============================================================
CREATE OR REPLACE VIEW VW_MATERIAL_AVAILABILITY AS
SELECT
    m.MATERIAL_ID,
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    m.CATEGORY,
    m.UNIT_OF_MEASURE,
    m.SAFETY_STOCK,
    m.REORDER_LEVEL,
    m.STANDARD_COST,
    m.LEAD_TIME,
    m.STATUS,
    s.SUPPLIER_NAME          AS PREFERRED_SUPPLIER,
    s.LEAD_TIME              AS SUPPLIER_LEAD_TIME,
    s.VENDOR_RATING,
    -- Reorder alert: 1 = needs replenishment (below reorder level)
    CASE
        WHEN m.SAFETY_STOCK <= m.REORDER_LEVEL THEN 'REORDER'
        ELSE 'OK'
    END                      AS STOCK_STATUS,
    CASE
        WHEN m.SAFETY_STOCK <= m.REORDER_LEVEL THEN 'danger'
        WHEN m.SAFETY_STOCK <= m.REORDER_LEVEL * 1.25 THEN 'warning'
        ELSE 'success'
    END                      AS STATUS_COLOR  -- Used in APEX badge styling
FROM MATERIAL_MASTER    m
LEFT JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = m.PREFERRED_SUPPLIER_ID;

COMMENT ON TABLE VW_MATERIAL_AVAILABILITY IS 'Material master with stock status and preferred supplier details';
PROMPT [OK] VW_MATERIAL_AVAILABILITY created.

-- ============================================================
-- VIEW 2: VW_MRP_SUMMARY
-- Purpose: MRP records joined with material and plan details
--          Primary source for MRP page and shortage detection
-- ============================================================
CREATE OR REPLACE VIEW VW_MRP_SUMMARY AS
SELECT
    mrp.MRP_ID,
    mrp.PLAN_ID,
    pp.PLAN_NAME,
    pp.STATUS                  AS PLAN_STATUS,
    pp.PLANNED_START_DATE,
    pp.PLANNED_END_DATE,
    pr.PRODUCT_CODE,
    pr.PRODUCT_NAME,
    mrp.MATERIAL_ID,
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    m.CATEGORY                 AS MATERIAL_CATEGORY,
    m.UNIT_OF_MEASURE,
    m.STANDARD_COST,
    mrp.GROSS_REQUIREMENT,
    mrp.AVAILABLE_QTY,
    mrp.SAFETY_STOCK,
    mrp.NET_REQUIREMENT,
    mrp.PLANNED_ORDER_QTY,
    mrp.REQUIRED_DATE,
    mrp.MRP_STATUS,
    mrp.CALCULATED_DATE,
    -- Shortage indicator
    CASE
        WHEN mrp.NET_REQUIREMENT > 0 THEN 'YES'
        ELSE 'NO'
    END                         AS SHORTAGE_FLAG,
    -- Estimated procurement cost
    mrp.PLANNED_ORDER_QTY * m.STANDARD_COST AS ESTIMATED_COST,
    -- Days until required
    TRUNC(mrp.REQUIRED_DATE) - TRUNC(SYSDATE) AS DAYS_TO_REQUIRED,
    -- Urgency for APEX badges
    CASE
        WHEN TRUNC(mrp.REQUIRED_DATE) - TRUNC(SYSDATE) < 0  THEN 'OVERDUE'
        WHEN TRUNC(mrp.REQUIRED_DATE) - TRUNC(SYSDATE) <= 7 THEN 'URGENT'
        WHEN TRUNC(mrp.REQUIRED_DATE) - TRUNC(SYSDATE) <= 14 THEN 'SOON'
        ELSE 'NORMAL'
    END                         AS URGENCY
FROM MATERIAL_REQUIREMENT_PLAN  mrp
JOIN PRODUCTION_PLAN             pp  ON pp.PLAN_ID    = mrp.PLAN_ID
JOIN PRODUCT_MASTER              pr  ON pr.PRODUCT_ID = pp.PRODUCT_ID
JOIN MATERIAL_MASTER             m   ON m.MATERIAL_ID  = mrp.MATERIAL_ID;

COMMENT ON TABLE VW_MRP_SUMMARY IS 'MRP results with full plan, product and material context';
PROMPT [OK] VW_MRP_SUMMARY created.

-- ============================================================
-- VIEW 3: VW_SHORTAGE_ALERT
-- Purpose: Materials with active shortages needing procurement
--          Used by Dashboard shortage KPI and alert list
-- ============================================================
CREATE OR REPLACE VIEW VW_SHORTAGE_ALERT AS
SELECT
    mrp.MRP_ID,
    mrp.PLAN_ID,
    pp.PLAN_NAME,
    m.MATERIAL_ID,
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    m.UNIT_OF_MEASURE,
    m.LEAD_TIME                AS MATERIAL_LEAD_TIME,
    mrp.GROSS_REQUIREMENT,
    mrp.AVAILABLE_QTY,
    mrp.NET_REQUIREMENT,
    mrp.PLANNED_ORDER_QTY,
    mrp.REQUIRED_DATE,
    TRUNC(mrp.REQUIRED_DATE) - TRUNC(SYSDATE) AS DAYS_TO_REQUIRED,
    mrp.PLANNED_ORDER_QTY * m.STANDARD_COST   AS ESTIMATED_COST,
    s.SUPPLIER_NAME            AS PREFERRED_SUPPLIER,
    s.LEAD_TIME                AS SUPPLIER_LEAD_TIME,
    s.VENDOR_RATING,
    -- Can we still order in time?
    CASE
        WHEN (TRUNC(mrp.REQUIRED_DATE) - TRUNC(SYSDATE)) >= NVL(s.LEAD_TIME, m.LEAD_TIME)
             THEN 'ON_TRACK'
        ELSE 'CRITICAL'
    END                        AS PROCUREMENT_FEASIBILITY
FROM MATERIAL_REQUIREMENT_PLAN  mrp
JOIN PRODUCTION_PLAN             pp  ON pp.PLAN_ID    = mrp.PLAN_ID
JOIN MATERIAL_MASTER             m   ON m.MATERIAL_ID  = mrp.MATERIAL_ID
LEFT JOIN SUPPLIER_MASTER        s   ON s.SUPPLIER_ID  = m.PREFERRED_SUPPLIER_ID
WHERE mrp.NET_REQUIREMENT > 0
  AND mrp.MRP_STATUS      = 'CALCULATED'
ORDER BY mrp.REQUIRED_DATE, mrp.NET_REQUIREMENT DESC;

COMMENT ON TABLE VW_SHORTAGE_ALERT IS 'Active material shortages with procurement feasibility indicator';
PROMPT [OK] VW_SHORTAGE_ALERT created.

-- ============================================================
-- VIEW 4: VW_PR_DASHBOARD
-- Purpose: Purchase Requisitions with full detail for PR list page
-- ============================================================
CREATE OR REPLACE VIEW VW_PR_DASHBOARD AS
SELECT
    pr.PR_ID,
    pr.PR_NUMBER,
    pr.STATUS,
    pr.PRIORITY,
    pr.REQUESTED_QTY,
    pr.REQUIRED_DATE,
    pr.CREATED_DATE,
    pr.REQUESTED_BY,
    pr.APPROVED_BY,
    pr.APPROVED_DATE,
    pr.JUSTIFICATION,
    m.MATERIAL_ID,
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    m.UNIT_OF_MEASURE,
    m.STANDARD_COST,
    pr.REQUESTED_QTY * m.STANDARD_COST     AS ESTIMATED_VALUE,
    -- Aging in days
    TRUNC(SYSDATE) - TRUNC(pr.CREATED_DATE) AS AGE_DAYS,
    -- Days until required
    TRUNC(pr.REQUIRED_DATE) - TRUNC(SYSDATE) AS DAYS_TO_REQUIRED,
    -- MRP link
    pr.MRP_ID,
    pp.PLAN_NAME,
    -- Priority color for APEX badges
    CASE pr.PRIORITY
        WHEN 'HIGH'   THEN 'danger'
        WHEN 'MEDIUM' THEN 'warning'
        WHEN 'LOW'    THEN 'success'
    END                                     AS PRIORITY_COLOR,
    -- Status color
    CASE pr.STATUS
        WHEN 'DRAFT'     THEN 't-Button--simple'
        WHEN 'SUBMITTED' THEN 'u-color-7'
        WHEN 'APPROVED'  THEN 'u-color-13'
        WHEN 'REJECTED'  THEN 'u-color-1'
        WHEN 'ORDERED'   THEN 'u-color-15'
        WHEN 'CLOSED'    THEN 'u-color-8'
    END                                     AS STATUS_CSS
FROM PURCHASE_REQUISITION          pr
JOIN MATERIAL_MASTER                m   ON m.MATERIAL_ID = pr.MATERIAL_ID
LEFT JOIN MATERIAL_REQUIREMENT_PLAN mrp ON mrp.MRP_ID    = pr.MRP_ID
LEFT JOIN PRODUCTION_PLAN           pp  ON pp.PLAN_ID     = mrp.PLAN_ID;

COMMENT ON TABLE VW_PR_DASHBOARD IS 'Purchase Requisitions enriched with material details, aging, and APEX display attributes';
PROMPT [OK] VW_PR_DASHBOARD created.

-- ============================================================
-- VIEW 5: VW_PO_HEADER
-- Purpose: Purchase Order headers with supplier details
-- ============================================================
CREATE OR REPLACE VIEW VW_PO_HEADER AS
SELECT
    po.PO_ID,
    po.PO_NUMBER,
    po.ORDER_STATUS,
    po.ORDER_DATE,
    po.DELIVERY_DATE,
    po.TOTAL_VALUE,
    po.TERMS,
    po.CREATED_BY,
    po.CREATED_DATE,
    s.SUPPLIER_ID,
    s.SUPPLIER_CODE,
    s.SUPPLIER_NAME,
    s.CONTACT_PERSON,
    s.EMAIL                   AS SUPPLIER_EMAIL,
    s.PHONE                   AS SUPPLIER_PHONE,
    s.VENDOR_RATING,
    s.LEAD_TIME               AS SUPPLIER_LEAD_TIME,
    -- Days to delivery
    TRUNC(po.DELIVERY_DATE) - TRUNC(SYSDATE) AS DAYS_TO_DELIVERY,
    -- Is it overdue?
    CASE
        WHEN po.ORDER_STATUS NOT IN ('RECEIVED','CANCELLED')
         AND po.DELIVERY_DATE < SYSDATE
        THEN 'YES' ELSE 'NO'
    END                       AS IS_OVERDUE,
    -- Line item count
    (SELECT COUNT(*) FROM PURCHASE_ORDER_ITEMS poi WHERE poi.PO_ID = po.PO_ID) AS LINE_COUNT,
    -- PR reference
    po.PR_ID,
    pr.PR_NUMBER              AS SOURCE_PR_NUMBER,
    -- Status color
    CASE po.ORDER_STATUS
        WHEN 'DRAFT'              THEN 'u-color-8'
        WHEN 'ISSUED'             THEN 'u-color-7'
        WHEN 'ACKNOWLEDGED'       THEN 'u-color-6'
        WHEN 'PARTIALLY_RECEIVED' THEN 'u-color-4'
        WHEN 'RECEIVED'           THEN 'u-color-13'
        WHEN 'CANCELLED'          THEN 'u-color-1'
    END                       AS STATUS_CSS
FROM PURCHASE_ORDER            po
JOIN SUPPLIER_MASTER            s   ON s.SUPPLIER_ID = po.SUPPLIER_ID
LEFT JOIN PURCHASE_REQUISITION  pr  ON pr.PR_ID       = po.PR_ID;

COMMENT ON TABLE VW_PO_HEADER IS 'Purchase Order headers with supplier details and delivery status flags';
PROMPT [OK] VW_PO_HEADER created.

-- ============================================================
-- VIEW 6: VW_PO_LINE_DETAIL
-- Purpose: PO line items with material and PO header detail
-- ============================================================
CREATE OR REPLACE VIEW VW_PO_LINE_DETAIL AS
SELECT
    poi.PO_ITEM_ID,
    poi.PO_ID,
    po.PO_NUMBER,
    po.ORDER_STATUS,
    po.ORDER_DATE,
    po.DELIVERY_DATE,
    s.SUPPLIER_NAME,
    poi.MATERIAL_ID,
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    m.CATEGORY,
    m.UNIT_OF_MEASURE,
    poi.ORDERED_QTY,
    poi.UNIT_PRICE,
    poi.TOTAL_VALUE,
    poi.RECEIVED_QTY,
    poi.ORDERED_QTY - NVL(poi.RECEIVED_QTY, 0)  AS OUTSTANDING_QTY,
    poi.REMARKS
FROM PURCHASE_ORDER_ITEMS  poi
JOIN PURCHASE_ORDER         po  ON po.PO_ID         = poi.PO_ID
JOIN SUPPLIER_MASTER        s   ON s.SUPPLIER_ID     = po.SUPPLIER_ID
JOIN MATERIAL_MASTER        m   ON m.MATERIAL_ID     = poi.MATERIAL_ID;

COMMENT ON TABLE VW_PO_LINE_DETAIL IS 'PO line items with full material and header context';
PROMPT [OK] VW_PO_LINE_DETAIL created.

-- ============================================================
-- VIEW 7: VW_PROCUREMENT_STATUS
-- Purpose: Combined PO + tracking for tracking page
-- ============================================================
CREATE OR REPLACE VIEW VW_PROCUREMENT_STATUS AS
SELECT
    pt.TRACKING_ID,
    pt.PO_ID,
    po.PO_NUMBER,
    po.ORDER_STATUS,
    po.ORDER_DATE,
    po.DELIVERY_DATE,
    po.TOTAL_VALUE,
    s.SUPPLIER_NAME,
    s.CONTACT_PERSON,
    s.PHONE                    AS SUPPLIER_PHONE,
    pt.EXPECTED_DATE,
    pt.ACTUAL_DATE,
    pt.DELIVERY_STATUS,
    pt.REMARKS,
    pt.UPDATED_BY,
    pt.UPDATED_DATE,
    -- Overdue flag
    CASE
        WHEN pt.DELIVERY_STATUS NOT IN ('DELIVERED','CANCELLED','RETURNED')
         AND pt.EXPECTED_DATE   <  TRUNC(SYSDATE)
        THEN 'YES' ELSE 'NO'
    END                        AS IS_OVERDUE,
    -- Days overdue (positive = overdue)
    CASE
        WHEN pt.ACTUAL_DATE IS NOT NULL
        THEN TRUNC(pt.ACTUAL_DATE) - TRUNC(pt.EXPECTED_DATE)
        ELSE TRUNC(SYSDATE) - TRUNC(pt.EXPECTED_DATE)
    END                        AS DELAY_DAYS,
    -- Material summary (first item for display)
    (SELECT m.MATERIAL_NAME FROM PURCHASE_ORDER_ITEMS poi
      JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = poi.MATERIAL_ID
     WHERE poi.PO_ID = po.PO_ID AND ROWNUM = 1) AS PRIMARY_MATERIAL,
    -- Status color
    CASE pt.DELIVERY_STATUS
        WHEN 'PENDING'             THEN 'u-color-8'
        WHEN 'IN_TRANSIT'          THEN 'u-color-7'
        WHEN 'PARTIALLY_DELIVERED' THEN 'u-color-4'
        WHEN 'DELIVERED'           THEN 'u-color-13'
        WHEN 'RETURNED'            THEN 'u-color-1'
        WHEN 'CANCELLED'           THEN 'u-color-1'
    END                        AS STATUS_CSS
FROM PROCUREMENT_TRACKING      pt
JOIN PURCHASE_ORDER             po  ON po.PO_ID       = pt.PO_ID
JOIN SUPPLIER_MASTER            s   ON s.SUPPLIER_ID  = po.SUPPLIER_ID;

COMMENT ON TABLE VW_PROCUREMENT_STATUS IS 'Procurement tracking with PO header, supplier and delay analysis';
PROMPT [OK] VW_PROCUREMENT_STATUS created.

-- ============================================================
-- VIEW 8: VW_SUPPLIER_PERFORMANCE
-- Purpose: Supplier KPIs - PO volume, on-time rate, value
-- ============================================================
CREATE OR REPLACE VIEW VW_SUPPLIER_PERFORMANCE AS
SELECT
    s.SUPPLIER_ID,
    s.SUPPLIER_CODE,
    s.SUPPLIER_NAME,
    s.VENDOR_RATING,
    s.LEAD_TIME               AS STANDARD_LEAD_TIME,
    s.STATUS,
    -- PO Counts
    COUNT(po.PO_ID)           AS TOTAL_PO_COUNT,
    COUNT(CASE WHEN po.ORDER_STATUS = 'RECEIVED'  THEN 1 END) AS COMPLETED_PO_COUNT,
    COUNT(CASE WHEN po.ORDER_STATUS = 'CANCELLED' THEN 1 END) AS CANCELLED_PO_COUNT,
    -- Total PO Value
    NVL(SUM(CASE WHEN po.ORDER_STATUS != 'CANCELLED' THEN po.TOTAL_VALUE END), 0) AS TOTAL_PO_VALUE,
    -- On-time delivery rate
    CASE
        WHEN COUNT(CASE WHEN po.ORDER_STATUS = 'RECEIVED' THEN 1 END) = 0 THEN NULL
        ELSE ROUND(
            COUNT(CASE WHEN po.ORDER_STATUS = 'RECEIVED'
                        AND po.DELIVERY_DATE >= SYSDATE THEN 1 END) * 100.0 /
            NULLIF(COUNT(CASE WHEN po.ORDER_STATUS = 'RECEIVED' THEN 1 END), 0), 1)
    END                       AS ON_TIME_RATE_PCT,
    -- Active open POs
    COUNT(CASE WHEN po.ORDER_STATUS NOT IN ('RECEIVED','CANCELLED') THEN 1 END) AS OPEN_PO_COUNT,
    -- Performance grade
    CASE
        WHEN s.VENDOR_RATING >= 4.5 THEN 'A'
        WHEN s.VENDOR_RATING >= 4.0 THEN 'B'
        WHEN s.VENDOR_RATING >= 3.5 THEN 'C'
        ELSE 'D'
    END                       AS PERFORMANCE_GRADE
FROM SUPPLIER_MASTER            s
LEFT JOIN PURCHASE_ORDER        po ON po.SUPPLIER_ID = s.SUPPLIER_ID
GROUP BY
    s.SUPPLIER_ID, s.SUPPLIER_CODE, s.SUPPLIER_NAME,
    s.VENDOR_RATING, s.LEAD_TIME, s.STATUS;

COMMENT ON TABLE VW_SUPPLIER_PERFORMANCE IS 'Supplier performance KPIs: PO volume, value, on-time delivery rate';
PROMPT [OK] VW_SUPPLIER_PERFORMANCE created.

-- ============================================================
-- VIEW 9: VW_DEMAND_VS_PLAN
-- Purpose: Demand forecast vs production plan comparison
-- ============================================================
CREATE OR REPLACE VIEW VW_DEMAND_VS_PLAN AS
SELECT
    p.PRODUCT_ID,
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    p.PRODUCT_CATEGORY,
    df.FORECAST_ID,
    df.FORECAST_PERIOD,
    TO_CHAR(df.FORECAST_PERIOD, 'Mon-YYYY') AS PERIOD_LABEL,
    df.FORECAST_QTY,
    df.FORECAST_TYPE,
    pp.PLAN_ID,
    pp.PLAN_NAME,
    pp.PLANNED_QTY,
    pp.STATUS                               AS PLAN_STATUS,
    pp.PLANNED_START_DATE,
    -- Gap analysis
    NVL(pp.PLANNED_QTY, 0) - df.FORECAST_QTY AS QTY_GAP,
    CASE
        WHEN pp.PLAN_ID IS NULL              THEN 'NO_PLAN'
        WHEN pp.PLANNED_QTY >= df.FORECAST_QTY THEN 'COVERED'
        WHEN pp.PLANNED_QTY > 0             THEN 'PARTIAL'
        ELSE 'SHORTAGE'
    END                                     AS COVERAGE_STATUS
FROM DEMAND_FORECAST              df
JOIN PRODUCT_MASTER               p   ON p.PRODUCT_ID  = df.PRODUCT_ID
LEFT JOIN PRODUCTION_PLAN         pp  ON pp.PRODUCT_ID = df.PRODUCT_ID
                                     AND TRUNC(pp.PLANNED_START_DATE,'MM') = TRUNC(df.FORECAST_PERIOD,'MM')
ORDER BY p.PRODUCT_CODE, df.FORECAST_PERIOD;

COMMENT ON TABLE VW_DEMAND_VS_PLAN IS 'Demand forecast vs production plan coverage analysis';
PROMPT [OK] VW_DEMAND_VS_PLAN created.

-- ============================================================
-- VIEW 10: VW_BOM_BREAKDOWN
-- Purpose: Flat BOM view with all material details
--          Used by BOM viewer page in APEX
-- ============================================================
CREATE OR REPLACE VIEW VW_BOM_BREAKDOWN AS
SELECT
    bm.BOM_ID,
    bm.VERSION,
    bm.EFFECTIVE_DATE,
    bm.STATUS                  AS BOM_STATUS,
    p.PRODUCT_ID,
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    p.PRODUCT_CATEGORY,
    bd.BOM_DETAIL_ID,
    m.MATERIAL_ID,
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    m.CATEGORY                 AS MATERIAL_CATEGORY,
    bd.QUANTITY_REQUIRED,
    m.UNIT_OF_MEASURE,
    m.STANDARD_COST,
    bd.QUANTITY_REQUIRED * m.STANDARD_COST AS LINE_COST,
    m.LEAD_TIME                AS MATERIAL_LEAD_TIME,
    s.SUPPLIER_NAME            AS PREFERRED_SUPPLIER,
    bd.REMARKS
FROM BOM_MASTER                bm
JOIN PRODUCT_MASTER            p   ON p.PRODUCT_ID  = bm.PRODUCT_ID
JOIN BOM_DETAILS               bd  ON bd.BOM_ID      = bm.BOM_ID
JOIN MATERIAL_MASTER           m   ON m.MATERIAL_ID  = bd.MATERIAL_ID
LEFT JOIN SUPPLIER_MASTER      s   ON s.SUPPLIER_ID  = m.PREFERRED_SUPPLIER_ID
ORDER BY p.PRODUCT_CODE, m.CATEGORY, m.MATERIAL_CODE;

COMMENT ON TABLE VW_BOM_BREAKDOWN IS 'Flat BOM breakdown with all material and supplier details';
PROMPT [OK] VW_BOM_BREAKDOWN created.

-- ============================================================
-- Final Verification
-- ============================================================
PROMPT 
PROMPT ============================================================
PROMPT  All MPPMS Views
PROMPT ============================================================
SELECT view_name
FROM user_views
ORDER BY view_name;

PROMPT 
PROMPT ============================================================
PROMPT  PHASE 5 COMPLETE
PROMPT  10 views created:
PROMPT    VW_MATERIAL_AVAILABILITY  - Material stock status
PROMPT    VW_MRP_SUMMARY            - MRP results with context
PROMPT    VW_SHORTAGE_ALERT         - Active shortages needing action
PROMPT    VW_PR_DASHBOARD           - PR list with aging + colors
PROMPT    VW_PO_HEADER              - PO headers with supplier info
PROMPT    VW_PO_LINE_DETAIL         - PO line items detail
PROMPT    VW_PROCUREMENT_STATUS     - Tracking + PO + supplier combined
PROMPT    VW_SUPPLIER_PERFORMANCE   - Supplier KPIs and grades
PROMPT    VW_DEMAND_VS_PLAN         - Forecast vs plan gap analysis
PROMPT    VW_BOM_BREAKDOWN           - Flat BOM with all details
PROMPT
PROMPT  Next Step: Phase 6 - APEX Application Setup
PROMPT ============================================================
