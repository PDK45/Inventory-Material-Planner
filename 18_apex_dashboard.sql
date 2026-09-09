-- ============================================================
-- MPPMS :: 18_apex_dashboard.sql
-- Purpose : Complete Dashboard page specification (Page 1)
-- Page    : 1
-- ============================================================

/*
=================================================================
PAGE 1 — MPPMS DASHBOARD
=================================================================
Page Type    : Blank Page (manual layout with regions)
Page #       : 1
Title        : Dashboard
Nav Position : First item in menu
Template     : Minimal (No Side Column) OR Standard

LAYOUT STRUCTURE:
  ┌─────────────────────────────────────────────────────────┐
  │  ROW 1: 4 KPI Cards (each 3-col wide in 12-col grid)   │
  ├────────────────────┬────────────────────────────────────┤
  │  ROW 2 LEFT (8col) │  ROW 2 RIGHT (4col)                │
  │  Monthly Spend     │  PR Status Donut Chart              │
  │  Bar Chart         │                                    │
  ├────────────────────┴────────────────────────────────────┤
  │  ROW 3: 3 Tables (Open PRs, Recent POs, Deliveries)    │
  └─────────────────────────────────────────────────────────┘

=================================================================
ROW 1: KPI CARDS (4 regions — use "Cards" template or HTML region)
=================================================================

--- KPI CARD 1: Open Purchase Requisitions ---
Region Type : PL/SQL Dynamic Content
Position    : Content Body
Column Span : 3 (of 12)
CSS Classes : mppms-kpi-card

PL/SQL Code:
*/
DECLARE
    v_count  NUMBER := PKG_DASHBOARD.GET_OPEN_PR_COUNT();
    v_pending NUMBER := PKG_DASHBOARD.GET_PENDING_APPROVAL_COUNT();
BEGIN
    HTP.P(
        '<div class="mppms-kpi-card">' ||
        '<div class="mppms-kpi-value">' || v_count || '</div>' ||
        '<div class="mppms-kpi-label">Open Requisitions</div>' ||
        '<div style="margin-top:8px;font-size:0.78rem;color:#78909C;">' ||
        v_pending || ' awaiting approval</div>' ||
        '<a href="f?p=&APP_ID.:80:&SESSION." style="display:block;margin-top:12px;' ||
        'font-size:0.8rem;color:#1565C0;text-decoration:none;font-weight:600;">' ||
        'View All PRs &rarr;</a></div>'
    );
END;
/

/*
--- KPI CARD 2: Open Purchase Orders ---
PL/SQL Code:
*/
DECLARE
    v_open    NUMBER := PKG_DASHBOARD.GET_OPEN_PO_COUNT();
    v_overdue NUMBER := PKG_DASHBOARD.GET_OVERDUE_DELIVERY_COUNT();
BEGIN
    HTP.P(
        '<div class="mppms-kpi-card' || CASE WHEN v_overdue > 0 THEN ' mppms-kpi-warning' ELSE '' END || '">' ||
        '<div class="mppms-kpi-value">' || v_open || '</div>' ||
        '<div class="mppms-kpi-label">Open Purchase Orders</div>' ||
        '<div style="margin-top:8px;font-size:0.78rem;color:' ||
        CASE WHEN v_overdue > 0 THEN '#E65100' ELSE '#78909C' END || ';">' ||
        v_overdue || ' overdue</div>' ||
        '<a href="f?p=&APP_ID.:90:&SESSION." style="display:block;margin-top:12px;' ||
        'font-size:0.8rem;color:#1565C0;text-decoration:none;font-weight:600;">' ||
        'View All POs &rarr;</a></div>'
    );
END;
/

/*
--- KPI CARD 3: Material Shortages ---
PL/SQL Code:
*/
DECLARE
    v_shortage NUMBER := PKG_DASHBOARD.GET_SHORTAGE_COUNT();
BEGIN
    HTP.P(
        '<div class="mppms-kpi-card' || CASE WHEN v_shortage > 0 THEN ' mppms-kpi-danger' ELSE ' mppms-kpi-success' END || '">' ||
        '<div class="mppms-kpi-value">' || v_shortage || '</div>' ||
        '<div class="mppms-kpi-label">Material Shortages</div>' ||
        '<div style="margin-top:8px;font-size:0.78rem;color:' ||
        CASE WHEN v_shortage > 0 THEN '#C62828' ELSE '#2E7D32' END || ';">' ||
        CASE WHEN v_shortage > 0 THEN 'Immediate action required' ELSE 'No shortages detected' END ||
        '</div>' ||
        '<a href="f?p=&APP_ID.:70:&SESSION." style="display:block;margin-top:12px;' ||
        'font-size:0.8rem;color:#1565C0;text-decoration:none;font-weight:600;">' ||
        'View MRP &rarr;</a></div>'
    );
END;
/

/*
--- KPI CARD 4: Active Production Plans ---
PL/SQL Code:
*/
DECLARE
    v_plans    NUMBER := PKG_DASHBOARD.GET_ACTIVE_PLAN_COUNT();
    v_monthly  NUMBER := PKG_DASHBOARD.GET_MONTHLY_PO_VALUE();
BEGIN
    HTP.P(
        '<div class="mppms-kpi-card mppms-kpi-success">' ||
        '<div class="mppms-kpi-value">' || v_plans || '</div>' ||
        '<div class="mppms-kpi-label">Active Plans</div>' ||
        '<div style="margin-top:8px;font-size:0.78rem;color:#78909C;">' ||
        'Monthly PO Value: &#8377;' ||
        TO_CHAR(v_monthly,'FM999,999,990') || '</div>' ||
        '<a href="f?p=&APP_ID.:60:&SESSION." style="display:block;margin-top:12px;' ||
        'font-size:0.8rem;color:#1565C0;text-decoration:none;font-weight:600;">' ||
        'View Plans &rarr;</a></div>'
    );
END;
/

/*
=================================================================
ROW 2 LEFT: Monthly Procurement Spend (Bar Chart)
=================================================================
Region Type : JET Chart
Region Title: Monthly Procurement Spend (Last 12 Months)
Column Span : 8

Chart Settings:
  Type         : Bar
  Orientation  : Vertical
  X-Axis Label : Month
  Y-Axis Label : PO Value (INR)
  Color        : #1565C0
  Legend       : Hidden

Chart SQL:
*/
SELECT
    TO_CHAR(TRUNC(po.ORDER_DATE,'MM'),'Mon-YY') AS LABEL,
    TRUNC(po.ORDER_DATE,'MM')                    AS ORDER_DATE,
    NVL(SUM(po.TOTAL_VALUE),0)                   AS VALUE
FROM PURCHASE_ORDER po
WHERE po.ORDER_DATE >= ADD_MONTHS(TRUNC(SYSDATE,'MM'),-11)
  AND po.ORDER_STATUS != 'CANCELLED'
GROUP BY TRUNC(po.ORDER_DATE,'MM')
ORDER BY TRUNC(po.ORDER_DATE,'MM');

/*
=================================================================
ROW 2 RIGHT: PR Status Distribution (Donut Chart)
=================================================================
Region Type : JET Chart
Region Title: PR Status Breakdown
Column Span : 4

Chart SQL:
*/
SELECT
    STATUS    AS LABEL,
    COUNT(*)  AS VALUE
FROM PURCHASE_REQUISITION
WHERE STATUS NOT IN ('CLOSED')
GROUP BY STATUS
ORDER BY COUNT(*) DESC;

/*
Chart Colors (map to status):
  SUBMITTED = #F57F17 (amber)
  APPROVED  = #2E7D32 (green)
  DRAFT     = #546E7A (grey)
  ORDERED   = #1565C0 (blue)
  REJECTED  = #C62828 (red)

=================================================================
ROW 3 LEFT: Material Shortages Alert List
=================================================================
Region Type : Classic Report (styled as alert list)
Region Title: ⚠ Material Shortage Alerts
Column Span : 4

SQL:
*/
SELECT
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    mrp.NET_REQUIREMENT,
    m.UNIT_OF_MEASURE,
    TO_CHAR(mrp.REQUIRED_DATE,'DD-Mon-YYYY')   AS REQUIRED_DATE,
    TRUNC(mrp.REQUIRED_DATE) - TRUNC(SYSDATE)  AS DAYS_LEFT,
    s.SUPPLIER_NAME
FROM MATERIAL_REQUIREMENT_PLAN mrp
JOIN MATERIAL_MASTER   m ON m.MATERIAL_ID  = mrp.MATERIAL_ID
JOIN PRODUCTION_PLAN   pp ON pp.PLAN_ID    = mrp.PLAN_ID
LEFT JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = m.PREFERRED_SUPPLIER_ID
WHERE mrp.NET_REQUIREMENT > 0
  AND mrp.MRP_STATUS = 'CALCULATED'
ORDER BY mrp.REQUIRED_DATE, mrp.NET_REQUIREMENT DESC
FETCH FIRST 8 ROWS ONLY;

/*
HTML Expression for each row (Report Template: Custom):
  <div style="padding:10px;border-left:3px solid #C62828;margin-bottom:8px;background:#FFF8F8;border-radius:4px;">
    <strong style="color:#1565C0;">#MATERIAL_CODE#</strong> — #MATERIAL_NAME#<br>
    <span style="color:#C62828;font-weight:600;">Short: #NET_REQUIREMENT# #UNIT_OF_MEASURE#</span>
    <span style="float:right;color:#78909C;font-size:0.8rem;">#DAYS_LEFT# days left</span><br>
    <span style="font-size:0.8rem;color:#546E7A;">Due: #REQUIRED_DATE# | Supplier: #SUPPLIER_NAME#</span>
  </div>

=================================================================
ROW 3 MIDDLE: Pending PR Approvals
=================================================================
Region Type : Classic Report
Region Title: Pending Approvals
Column Span : 4

SQL:
*/
SELECT
    pr.PR_NUMBER,
    m.MATERIAL_NAME,
    pr.PRIORITY,
    pr.REQUESTED_QTY || ' ' || m.UNIT_OF_MEASURE  AS QTY,
    TO_CHAR(pr.REQUIRED_DATE,'DD-Mon-YYYY')        AS REQUIRED_BY,
    TRUNC(SYSDATE) - TRUNC(pr.CREATED_DATE)        AS AGE_DAYS,
    pr.REQUESTED_BY,
    pr.PR_ID
FROM PURCHASE_REQUISITION pr
JOIN MATERIAL_MASTER       m ON m.MATERIAL_ID = pr.MATERIAL_ID
WHERE pr.STATUS = 'SUBMITTED'
ORDER BY
    CASE pr.PRIORITY WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
    pr.REQUIRED_DATE
FETCH FIRST 8 ROWS ONLY;

/*
HTML Expression (row):
  <div style="padding:10px;border-left:3px solid #F57F17;margin-bottom:8px;background:#FFFDE7;border-radius:4px;">
    <strong>#PR_NUMBER#</strong>
    <span class="t-Badge t-Badge--#CASE PRIORITY WHEN 'HIGH' THEN 'danger' WHEN 'MEDIUM' THEN 'warning' ELSE 'success' END#"
          style="float:right;font-size:0.7rem;">#PRIORITY#</span><br>
    #MATERIAL_NAME#<br>
    <span style="font-size:0.8rem;color:#546E7A;">Qty: #QTY# | By: #REQUIRED_BY# | Age: #AGE_DAYS# days</span><br>
    <a href="f?p=&APP_ID.:81:&SESSION.::NO::P81_PR_ID:#PR_ID#"
       style="font-size:0.8rem;color:#1565C0;font-weight:600;">Review &rarr;</a>
  </div>

=================================================================
ROW 3 RIGHT: Upcoming Deliveries (Next 14 Days)
=================================================================
Region Type : Classic Report
Region Title: Upcoming Deliveries
Column Span : 4

SQL:
*/
SELECT
    po.PO_NUMBER,
    s.SUPPLIER_NAME,
    TO_CHAR(pt.EXPECTED_DATE,'DD-Mon-YYYY')    AS EXPECTED_DATE,
    TRUNC(pt.EXPECTED_DATE) - TRUNC(SYSDATE)  AS DAYS_AWAY,
    pt.DELIVERY_STATUS,
    po.TOTAL_VALUE,
    po.PO_ID
FROM PROCUREMENT_TRACKING  pt
JOIN PURCHASE_ORDER         po ON po.PO_ID       = pt.PO_ID
JOIN SUPPLIER_MASTER        s  ON s.SUPPLIER_ID  = po.SUPPLIER_ID
WHERE pt.DELIVERY_STATUS NOT IN ('DELIVERED','CANCELLED','RETURNED')
  AND pt.EXPECTED_DATE BETWEEN TRUNC(SYSDATE) AND TRUNC(SYSDATE) + 14
ORDER BY pt.EXPECTED_DATE
FETCH FIRST 8 ROWS ONLY;

/*
HTML Expression:
  <div style="padding:10px;border-left:3px solid #1565C0;margin-bottom:8px;background:#E3F2FD;border-radius:4px;">
    <strong>#PO_NUMBER#</strong>
    <span style="float:right;color:#E65100;font-weight:600;">In #DAYS_AWAY# days</span><br>
    #SUPPLIER_NAME#<br>
    <span style="font-size:0.8rem;color:#546E7A;">
      Expected: #EXPECTED_DATE# | Status: #DELIVERY_STATUS#
    </span><br>
    <a href="f?p=&APP_ID.:101:&SESSION.::NO::P101_PO_ID:#PO_ID#"
       style="font-size:0.8rem;color:#1565C0;font-weight:600;">Update Tracking &rarr;</a>
  </div>

=================================================================
ROW 4: Recent Purchase Orders (Full-width IR)
=================================================================
Region Type : Interactive Report (display only, no edit)
Region Title: Recent Purchase Orders
Column Span : 12 (full width)
Max Rows    : 10

SQL:
*/
SELECT
    po.PO_NUMBER,
    po.ORDER_STATUS,
    s.SUPPLIER_NAME,
    TO_CHAR(po.ORDER_DATE,'DD-Mon-YYYY')        AS ORDER_DATE,
    TO_CHAR(po.DELIVERY_DATE,'DD-Mon-YYYY')     AS DELIVERY_DATE,
    po.TOTAL_VALUE,
    (SELECT COUNT(*) FROM PURCHASE_ORDER_ITEMS poi WHERE poi.PO_ID = po.PO_ID) AS LINES,
    pt.DELIVERY_STATUS                          AS TRACKING
FROM PURCHASE_ORDER       po
JOIN SUPPLIER_MASTER       s  ON s.SUPPLIER_ID = po.SUPPLIER_ID
LEFT JOIN (
    SELECT PO_ID, DELIVERY_STATUS
    FROM PROCUREMENT_TRACKING
    WHERE UPDATED_DATE = (SELECT MAX(x.UPDATED_DATE) FROM PROCUREMENT_TRACKING x WHERE x.PO_ID = PROCUREMENT_TRACKING.PO_ID)
) pt ON pt.PO_ID = po.PO_ID
ORDER BY po.ORDER_DATE DESC
FETCH FIRST 10 ROWS ONLY;

/*
=================================================================
PAGE 1 — GLOBAL SETTINGS & DYNAMIC REFRESH
=================================================================

PAGE ATTRIBUTES:
  Page Alias         : DASHBOARD
  Page Template      : Minimal No Column (for full-width dashboard)
  Inline CSS         : (paste MPPMS custom CSS from guide step 2)

PAGE PROCESSES (Before Header):
  Process: Refresh Dashboard KPIs
  Type   : PL/SQL
  Code   :
    APEX_UTIL.SET_SESSION_STATE('OPEN_PR_COUNT',    PKG_DASHBOARD.GET_OPEN_PR_COUNT());
    APEX_UTIL.SET_SESSION_STATE('OPEN_PO_COUNT',    PKG_DASHBOARD.GET_OPEN_PO_COUNT());
    APEX_UTIL.SET_SESSION_STATE('SHORTAGE_COUNT',   PKG_DASHBOARD.GET_SHORTAGE_COUNT());
    APEX_UTIL.SET_SESSION_STATE('OVERDUE_COUNT',    PKG_DASHBOARD.GET_OVERDUE_DELIVERY_COUNT());

DYNAMIC ACTION: Auto-refresh dashboard every 5 minutes
  Event   : Page Load
  Action  : Execute JavaScript
  Code    :
    setInterval(function() {
        apex.region('kpi-region-1').refresh();
        apex.region('kpi-region-2').refresh();
        apex.region('kpi-region-3').refresh();
        apex.region('kpi-region-4').refresh();
        apex.region('chart-spend').refresh();
        apex.region('chart-pr-status').refresh();
    }, 300000); // 5 minutes

=================================================================
APEX BREADCRUMBS (all pages)
=================================================================
Create a shared breadcrumb called MPPMS_BREADCRUMB with:
  Entry 1: Home → Page 1
  Entry 2: Masters → (no page)
    Entry 2.1: Supplier Master → Page 10
    Entry 2.2: Material Master → Page 20
    Entry 2.3: Product Master  → Page 30
  Entry 3: Planning → (no page)
    ... (continue for all pages)

=================================================================
APEX APPLICATION GLOBAL ITEMS (create in Shared Components)
=================================================================
  APP_USER_NAME      : Populated by :APP_USER
  OPEN_PR_COUNT      : Populated by PKG_DASHBOARD.GET_OPEN_PR_COUNT()
  SHORTAGE_COUNT     : Populated by PKG_DASHBOARD.GET_SHORTAGE_COUNT()

These can be shown in the top navigation bar as notification badges.

Navigation Bar Entry to show badge:
  Label      : PRs (#OPEN_PR_COUNT#)
  Target     : Page 80
  Condition  : OPEN_PR_COUNT > 0

*/

PROMPT [SUCCESS] Dashboard page spec complete (Page 1).
PROMPT All 4 KPI cards, 2 charts, 3 alert lists, and 1 IR fully specified.
