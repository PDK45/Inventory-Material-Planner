-- ============================================================
-- MPPMS :: 16_apex_pages_procurement.sql
-- Purpose : APEX page specs for Procurement Module
--           Purchase Requisition, Purchase Order, Tracking
-- Pages   : 80, 81, 90, 91, 92, 100, 101
-- ============================================================

/*
=================================================================
PAGE 80 — PURCHASE REQUISITION (Interactive Report)
=================================================================
Page Type : Interactive Report
Page #    : 80
Title     : Purchase Requisitions

IR SQL:
*/
SELECT
    pr.PR_ID,
    pr.PR_NUMBER,
    pr.STATUS,
    pr.PRIORITY,
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    m.UNIT_OF_MEASURE,
    pr.REQUESTED_QTY,
    TO_CHAR(pr.REQUIRED_DATE,'DD-Mon-YYYY')     AS REQUIRED_DATE_DISP,
    pr.REQUIRED_DATE,
    TRUNC(SYSDATE) - TRUNC(pr.CREATED_DATE)     AS AGE_DAYS,
    TRUNC(pr.REQUIRED_DATE) - TRUNC(SYSDATE)    AS DAYS_TO_REQUIRED,
    pr.REQUESTED_QTY * m.STANDARD_COST          AS ESTIMATED_VALUE,
    pr.REQUESTED_BY,
    pr.APPROVED_BY,
    TO_CHAR(pr.CREATED_DATE,'DD-Mon-YYYY')      AS CREATED_DATE_DISP,
    pr.JUSTIFICATION,
    pp.PLAN_NAME,
    pr.MRP_ID,
    pr.MATERIAL_ID
FROM PURCHASE_REQUISITION          pr
JOIN MATERIAL_MASTER                m   ON m.MATERIAL_ID = pr.MATERIAL_ID
LEFT JOIN MATERIAL_REQUIREMENT_PLAN mrp ON mrp.MRP_ID    = pr.MRP_ID
LEFT JOIN PRODUCTION_PLAN           pp  ON pp.PLAN_ID     = mrp.PLAN_ID
ORDER BY pr.PRIORITY,
         CASE pr.STATUS WHEN 'SUBMITTED' THEN 1 WHEN 'APPROVED' THEN 2 ELSE 3 END,
         pr.REQUIRED_DATE;

/*
COLUMN HTML EXPRESSIONS:

STATUS Badge:
  <span class="t-Badge t-Badge--#CASE STATUS
    WHEN 'DRAFT'     THEN 'info'
    WHEN 'SUBMITTED' THEN 'warning'
    WHEN 'APPROVED'  THEN 'success'
    WHEN 'REJECTED'  THEN 'danger'
    WHEN 'ORDERED'   THEN 'success'
    WHEN 'CLOSED'    THEN 'neutral'
    ELSE 'neutral' END#">
    <span class="t-Badge-label">#STATUS#</span>
  </span>

PRIORITY Badge:
  <span class="t-Badge t-Badge--#CASE PRIORITY WHEN 'HIGH' THEN 'danger' WHEN 'MEDIUM' THEN 'warning' ELSE 'success' END#">
    <span class="t-Badge-label">#PRIORITY#</span>
  </span>

AGE_DAYS — Conditional Format:
  > 14 days = red | 7-14 days = orange | < 7 = normal

ESTIMATED_VALUE:
  Format: FM999,999,990.00
  Aggregate: SUM

FILTER BAR ITEMS (above IR):
  P80_STATUS_FILTER : Select | LOV: LOV_PR_STATUS | Label: Filter by Status
  P80_PRIORITY_FILTER: Select | LOV: LOV_PRIORITY | Label: Filter by Priority
  — Add to WHERE:
    AND (:P80_STATUS_FILTER IS NULL OR pr.STATUS = :P80_STATUS_FILTER)
    AND (:P80_PRIORITY_FILTER IS NULL OR pr.PRIORITY = :P80_PRIORITY_FILTER)

ACTION BUTTONS (Row-level, via IR Link columns):

  [Edit/View]     → Page 81 with PR_ID
  [Approve]       → Visible when STATUS = 'SUBMITTED'
    Process (APEX Process called on button click or from modal):
      DECLARE v_s VARCHAR2(20); v_m VARCHAR2(1000);
      BEGIN
          PKG_PROCUREMENT.APPROVE_PR(
              p_pr_id      => :P80_SELECTED_PR_ID,
              p_approved_by => :APP_USER,
              p_status     => v_s,
              p_message    => v_m);
          IF v_s = 'ERROR' THEN RAISE_APPLICATION_ERROR(-20003, v_m); END IF;
      END;

  [Convert to PO] → Visible when STATUS = 'APPROVED'
                    Redirect to Page 91 with P91_PR_ID = PR_ID

  [Reject]        → Visible when STATUS = 'SUBMITTED'
    Opens reject confirmation dialog, runs REJECT_PR

TOOLBAR BUTTONS:
  + New Requisition → Page 81 (blank form)

=================================================================
PAGE 81 — PURCHASE REQUISITION FORM (Modal Dialog)
=================================================================
Width: 850px

ITEMS:
  P81_PR_ID            : Hidden PK
  P81_PR_NUMBER        : Text | Read Only | Label: PR Number | Default: (auto-generated)

  [ROW 1]
  P81_MATERIAL_ID      : Select  | LOV: LOV_MATERIALS | Required | Label: Material
  P81_PRIORITY         : Select  | LOV: LOV_PRIORITY  | Required | Default: MEDIUM

  [ROW 2]
  P81_REQUESTED_QTY    : Number  | Required | Min: 0.001 | Label: Requested Quantity
  P81_REQUIRED_DATE    : Date    | Required | Format: DD/MM/YYYY | Label: Required By Date

  [ROW 3]
  P81_STATUS           : Select  | LOV: LOV_PR_STATUS | Default: DRAFT
  P81_REQUESTED_BY     : Text    | Default: APP_USER | Max: 100

  [ROW 4 - Full Width]
  P81_JUSTIFICATION    : Textarea | Max 1000 | Rows: 3 | Label: Justification / Remarks

  [ROW 5 - Read Only section, visible when APPROVED]
  P81_APPROVED_BY      : Text    | Read Only | Label: Approved By
  P81_APPROVED_DATE    : Date    | Read Only | Label: Approval Date

DYNAMIC ACTION: On Change of P81_MATERIAL_ID
  Action: Execute PL/SQL + Set Page Items
  Code:
    SELECT m.STANDARD_COST, s.SUPPLIER_NAME
      INTO :P81_STD_COST, :P81_PREF_SUPPLIER
      FROM MATERIAL_MASTER m
      LEFT JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = m.PREFERRED_SUPPLIER_ID
     WHERE m.MATERIAL_ID = :P81_MATERIAL_ID;
  Set Page Items: P81_STD_COST, P81_PREF_SUPPLIER (display only)

  Display Items (read-only, shown after material selection):
    P81_STD_COST      : Number | Read Only | Label: Unit Cost (INR)
    P81_PREF_SUPPLIER : Text   | Read Only | Label: Recommended Supplier

VALIDATIONS:
  1. Required Date must be future date
     IF :P81_REQUIRED_DATE <= SYSDATE THEN RETURN 'Required Date must be in the future.'; END IF;
  2. Requested Qty > 0

BUTTONS:
  CANCEL  : Dialog Cancel
  SAVE    : Submit (DML)
  APPROVE : Only shown when STATUS = 'SUBMITTED' | calls APPROVE_PR
  REJECT  : Only shown when STATUS = 'SUBMITTED'

=================================================================
PAGE 90 — PURCHASE ORDER (Interactive Report)
=================================================================
Page Type : Interactive Report
Page #    : 90
Title     : Purchase Orders

IR SQL:
*/
SELECT
    po.PO_ID,
    po.PO_NUMBER,
    po.ORDER_STATUS,
    s.SUPPLIER_CODE,
    s.SUPPLIER_NAME,
    s.VENDOR_RATING,
    TO_CHAR(po.ORDER_DATE,'DD-Mon-YYYY')         AS ORDER_DATE_DISP,
    TO_CHAR(po.DELIVERY_DATE,'DD-Mon-YYYY')      AS DELIVERY_DATE_DISP,
    po.ORDER_DATE,
    po.DELIVERY_DATE,
    po.TOTAL_VALUE,
    TO_CHAR(po.TOTAL_VALUE,'FM999,999,990.00')   AS TOTAL_VALUE_DISP,
    TRUNC(po.DELIVERY_DATE) - TRUNC(SYSDATE)     AS DAYS_TO_DELIVERY,
    CASE
        WHEN po.ORDER_STATUS NOT IN ('RECEIVED','CANCELLED')
         AND po.DELIVERY_DATE < SYSDATE
        THEN 'YES' ELSE 'NO'
    END                                          AS IS_OVERDUE,
    (SELECT COUNT(*) FROM PURCHASE_ORDER_ITEMS poi WHERE poi.PO_ID = po.PO_ID) AS LINE_COUNT,
    po.PR_ID,
    pr.PR_NUMBER                                 AS SOURCE_PR,
    po.CREATED_BY,
    po.TERMS
FROM PURCHASE_ORDER            po
JOIN SUPPLIER_MASTER            s   ON s.SUPPLIER_ID = po.SUPPLIER_ID
LEFT JOIN PURCHASE_REQUISITION  pr  ON pr.PR_ID       = po.PR_ID
ORDER BY po.ORDER_DATE DESC;

/*
ROW HIGHLIGHTING:
  IS_OVERDUE = 'YES' → Background: #FFEBEE (light red)

STATUS Badge colors:
  DRAFT='info' | ISSUED='warning' | ACKNOWLEDGED='u-color-6'
  PARTIALLY_RECEIVED='u-color-4' | RECEIVED='success' | CANCELLED='danger'

ACTION BUTTONS per row:
  [View/Edit Lines]  → Page 92 (PO Line Items)
  [Track Delivery]   → Page 100
  [Cancel PO]        → Visible when not RECEIVED/CANCELLED
                       Confirm dialog + calls PKG_PROCUREMENT.CANCEL_PO

TOOLBAR: + New PO → Page 91

=================================================================
PAGE 91 — PURCHASE ORDER FORM (Modal)
=================================================================
Width: 850px
Note: Supplier Recommendation auto-populated based on selected PR material

ITEMS:
  P91_PO_ID            : Hidden PK
  P91_PO_NUMBER        : Text | Read Only | auto-generated

  [ROW 1]
  P91_PR_ID            : Select | LOV: LOV_APPROVED_PRS | Allow Null | Label: Source PR

  [ROW 2 - auto-populated on PR selection]
  P91_SUPPLIER_ID      : Select | LOV: LOV_SUPPLIERS | Required | Label: Supplier

  [ROW 3]
  P91_ORDER_DATE       : Date   | Default: SYSDATE | Format: DD/MM/YYYY | Read Only
  P91_DELIVERY_DATE    : Date   | Required | Format: DD/MM/YYYY | Label: Expected Delivery

  [ROW 4]
  P91_ORDER_STATUS     : Select | LOV: LOV_PO_STATUS | Default: DRAFT
  P91_CREATED_BY       : Hidden | Default: APP_USER

  [ROW 5 - Full Width]
  P91_TERMS            : Textarea | Rows: 2 | Max 500

  [READ ONLY display - supplier details]
  P91_SUPPLIER_RATING  : Display Only | Label: Supplier Rating
  P91_SUPPLIER_PHONE   : Display Only | Label: Supplier Phone
  P91_SUPPLIER_EMAIL   : Display Only | Label: Supplier Email

DYNAMIC ACTION: On Change of P91_PR_ID (auto-recommend supplier)
  PL/SQL:
    SELECT PKG_PROCUREMENT.RECOMMEND_SUPPLIER(MATERIAL_ID)
      INTO :P91_SUPPLIER_ID
      FROM PURCHASE_REQUISITION
     WHERE PR_ID = :P91_PR_ID;
  Refresh: P91_SUPPLIER_ID

DYNAMIC ACTION: On Change of P91_SUPPLIER_ID (show supplier details)
  PL/SQL:
    SELECT VENDOR_RATING, PHONE, EMAIL
      INTO :P91_SUPPLIER_RATING, :P91_SUPPLIER_PHONE, :P91_SUPPLIER_EMAIL
      FROM SUPPLIER_MASTER WHERE SUPPLIER_ID = :P91_SUPPLIER_ID;
  Items to Submit: P91_SUPPLIER_ID
  Set Items: P91_SUPPLIER_RATING, P91_SUPPLIER_PHONE, P91_SUPPLIER_EMAIL

PROCESS on Submit: DML on PURCHASE_ORDER
  After Insert: Create initial PROCUREMENT_TRACKING row:
    INSERT INTO PROCUREMENT_TRACKING(PO_ID, EXPECTED_DATE, DELIVERY_STATUS, REMARKS, UPDATED_BY)
    VALUES (:P91_PO_ID, :P91_DELIVERY_DATE, 'PENDING', 'PO Created', :APP_USER);

=================================================================
PAGE 92 — PO LINE ITEMS (Interactive Grid)
=================================================================
Page Type : Interactive Grid (editable)
Page #    : 92
Source    : PURCHASE_ORDER_ITEMS (filtered by P92_PO_ID)

IG SQL:
*/
SELECT
    POI.PO_ITEM_ID,
    POI.PO_ID,
    POI.MATERIAL_ID,
    M.MATERIAL_CODE,
    M.MATERIAL_NAME,
    M.UNIT_OF_MEASURE,
    POI.ORDERED_QTY,
    POI.UNIT_PRICE,
    POI.TOTAL_VALUE,        -- Virtual computed column (read only)
    POI.RECEIVED_QTY,
    POI.ORDERED_QTY - NVL(POI.RECEIVED_QTY,0) AS OUTSTANDING_QTY,
    POI.REMARKS
FROM PURCHASE_ORDER_ITEMS POI
JOIN MATERIAL_MASTER M ON M.MATERIAL_ID = POI.MATERIAL_ID
WHERE POI.PO_ID = :P92_PO_ID;

/*
IG COLUMN SETTINGS:
  PO_ITEM_ID    : Hidden | PK
  PO_ID         : Hidden
  MATERIAL_ID   : Popup LOV | LOV: LOV_MATERIALS | Required
  MATERIAL_CODE : Display Only (auto from MATERIAL_ID)
  ORDERED_QTY   : Number | Editable | Required
  UNIT_PRICE    : Number | Editable | Required
  TOTAL_VALUE   : Display Only (computed virtual) | Format: 999,999,990.00
  RECEIVED_QTY  : Number | Editable | Default: 0
  OUTSTANDING_QTY: Display Only

IG SETTINGS:
  Enable Add Row    : Yes
  Enable Delete Row : Yes
  Save              : Automatic (after each change) or manual Save button
  Lost Update Check : Yes

=================================================================
PAGE 100 — PROCUREMENT TRACKING (Interactive Report)
=================================================================
Page Type : Interactive Report
Page #    : 100
Title     : Procurement Tracking

IR SQL:
*/
SELECT
    pt.TRACKING_ID,
    po.PO_NUMBER,
    po.ORDER_STATUS,
    s.SUPPLIER_NAME,
    s.CONTACT_PERSON,
    s.PHONE                                      AS SUPPLIER_PHONE,
    TO_CHAR(po.ORDER_DATE,'DD-Mon-YYYY')         AS ORDER_DATE_DISP,
    TO_CHAR(pt.EXPECTED_DATE,'DD-Mon-YYYY')      AS EXPECTED_DATE_DISP,
    TO_CHAR(pt.ACTUAL_DATE,'DD-Mon-YYYY')        AS ACTUAL_DATE_DISP,
    pt.EXPECTED_DATE,
    pt.ACTUAL_DATE,
    pt.DELIVERY_STATUS,
    pt.REMARKS,
    CASE
        WHEN pt.ACTUAL_DATE IS NOT NULL
        THEN TRUNC(pt.ACTUAL_DATE) - TRUNC(pt.EXPECTED_DATE)
        WHEN pt.DELIVERY_STATUS NOT IN ('DELIVERED','CANCELLED')
        THEN TRUNC(SYSDATE) - TRUNC(pt.EXPECTED_DATE)
        ELSE 0
    END                                          AS DELAY_DAYS,
    po.TOTAL_VALUE,
    pt.PO_ID,
    pt.UPDATED_BY,
    TO_CHAR(pt.UPDATED_DATE,'DD-Mon-YYYY HH24:MI') AS LAST_UPDATED
FROM PROCUREMENT_TRACKING  pt
JOIN PURCHASE_ORDER         po ON po.PO_ID       = pt.PO_ID
JOIN SUPPLIER_MASTER        s  ON s.SUPPLIER_ID  = po.SUPPLIER_ID
ORDER BY
    CASE WHEN pt.DELIVERY_STATUS NOT IN ('DELIVERED','CANCELLED') THEN 0 ELSE 1 END,
    pt.EXPECTED_DATE;

/*
ROW HIGHLIGHTING:
  DELAY_DAYS > 0 AND DELIVERY_STATUS NOT IN ('DELIVERED','CANCELLED') → Red background

DELIVERY_STATUS Badge:
  PENDING='info' | IN_TRANSIT='warning' | PARTIALLY_DELIVERED='u-color-4'
  DELIVERED='success' | RETURNED/CANCELLED='danger'

ACTION BUTTON per row: [Update Status] → Page 101

=================================================================
PAGE 101 — TRACKING UPDATE FORM (Modal)
=================================================================
Width: 700px
Title: Update Delivery Status

ITEMS:
  P101_TRACKING_ID     : Hidden PK
  P101_PO_ID           : Hidden

  [INFO - Read Only]
  P101_PO_NUMBER       : Display Only | Label: PO Number
  P101_SUPPLIER_NAME   : Display Only | Label: Supplier
  P101_TOTAL_VALUE     : Display Only | Label: PO Value

  [EDITABLE]
  P101_DELIVERY_STATUS : Select | LOV: LOV_DELIVERY_STATUS | Required
  P101_EXPECTED_DATE   : Date   | Format: DD/MM/YYYY
  P101_ACTUAL_DATE     : Date   | Format: DD/MM/YYYY (visible when DELIVERED/PARTIALLY)
  P101_REMARKS         : Textarea | Max 1000 | Rows: 3 | Required

  P101_UPDATED_BY      : Hidden | Default: APP_USER

DYNAMIC ACTION: On Change of P101_DELIVERY_STATUS
  If value = 'DELIVERED' or 'PARTIALLY_DELIVERED':
    Show: P101_ACTUAL_DATE
  Else:
    Hide: P101_ACTUAL_DATE

PROCESS on Save:
  DML on PROCUREMENT_TRACKING

POST-SAVE PROCESS: Update PO status to match delivery status
  Code:
    DECLARE v_s VARCHAR2(20); v_m VARCHAR2(1000);
    BEGIN
        CASE :P101_DELIVERY_STATUS
            WHEN 'DELIVERED' THEN
                PKG_PROCUREMENT.UPDATE_PO_STATUS(
                    :P101_PO_ID, 'RECEIVED', v_s, v_m);
            WHEN 'PARTIALLY_DELIVERED' THEN
                PKG_PROCUREMENT.UPDATE_PO_STATUS(
                    :P101_PO_ID, 'PARTIALLY_RECEIVED', v_s, v_m);
            ELSE NULL;
        END CASE;
    END;

=================================================================
PROCUREMENT MODULE — COMMON DYNAMIC ACTIONS
=================================================================

DA: Refresh PR count badge in navigation
  After any PR status change:
    APEX_UTIL.SET_SESSION_STATE('OPEN_PR_COUNT',
        PKG_DASHBOARD.GET_OPEN_PR_COUNT());

DA: Show confirmation before Cancel PO
  Trigger: Click on Cancel PO button
  Confirm message: 'This will cancel the Purchase Order and cannot be undone. Proceed?'
  On Confirm: Execute CANCEL_PO process

*/

PROMPT [SUCCESS] Procurement module APEX page specs created.
PROMPT Pages: 80 (PR List), 81 (PR Form), 90 (PO List),
PROMPT        91 (PO Form), 92 (PO Lines IG), 100 (Tracking), 101 (Tracking Form)
