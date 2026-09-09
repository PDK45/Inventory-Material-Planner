-- ============================================================
-- MPPMS :: 14_apex_pages_masters.sql
-- Purpose : Page-level SQL for Masters Module
--           Supplier Master, Material Master, Product Master
-- Use In  : APEX SQL Workshop > SQL Commands
--           OR reference when building pages in App Builder
-- ============================================================

/*
=================================================================
PAGE 10 — SUPPLIER MASTER (Interactive Report)
=================================================================
Page Type    : Interactive Report
Page Number  : 10
Page Name    : Supplier Master
Navigation   : Masters > Supplier Master
Icon         : fa-truck
Breadcrumb   : Home > Masters > Supplier Master

REGION SETTINGS:
  Region Title : Supplier Directory
  Region Type  : Interactive Report
  Source Query : (below)
  Template     : Standard

IR REGION SQL:
*/
-- Copy this as the IR Source Query on Page 10
SELECT
    SUPPLIER_ID,
    SUPPLIER_CODE,
    SUPPLIER_NAME,
    CONTACT_PERSON,
    EMAIL,
    PHONE,
    LEAD_TIME || ' days'                    AS LEAD_TIME_DISPLAY,
    LEAD_TIME,
    VENDOR_RATING,
    CASE
        WHEN VENDOR_RATING >= 4.5 THEN 'A'
        WHEN VENDOR_RATING >= 4.0 THEN 'B'
        WHEN VENDOR_RATING >= 3.5 THEN 'C'
        ELSE 'D'
    END                                     AS GRADE,
    STATUS,
    TO_CHAR(CREATED_DATE,'DD-Mon-YYYY')     AS CREATED_DATE_DISP,
    CREATED_DATE,
    -- Link to form page (Page 11)
    APEX_UTIL.PREPARE_URL(
        'f?p=&APP_ID.:11:&SESSION.::NO::P11_SUPPLIER_ID:' || SUPPLIER_ID
    )                                       AS EDIT_LINK
FROM SUPPLIER_MASTER
ORDER BY SUPPLIER_CODE;

/*
IR COLUMN SETTINGS (set in APEX IR Column Attributes):
  SUPPLIER_ID     : Hidden = Yes
  EDIT_LINK       : Hidden = Yes (used by row action)
  VENDOR_RATING   : Format Mask = FM999990.0
  GRADE           : Display As = Badge (use HTML Expression below)
  STATUS          : Display As = use Column Link or Badge

HTML Expression for GRADE column:
  <span class="t-Badge t-Badge--#CASE GRADE WHEN 'A' THEN 'success' WHEN 'B' THEN 'info' WHEN 'C' THEN 'warning' ELSE 'danger' END#">
    <span class="t-Badge-label">#GRADE#</span>
  </span>

HTML Expression for STATUS column:
  <span class="t-Badge t-Badge--#CASE STATUS WHEN 'ACTIVE' THEN 'success' ELSE 'danger' END#">
    <span class="t-Badge-label">#STATUS#</span>
  </span>

IR ATTRIBUTES:
  Enable Search      : Yes
  Enable Sort        : Yes
  Enable Filter      : Yes
  Enable Download    : CSV, Excel, PDF
  Report Rows/Page   : 15
  Pagination Type    : Row Ranges in Select List

TOOLBAR BUTTONS:
  + Create Button:
    Button Name  : BTN_CREATE_SUPPLIER
    Label        : + New Supplier
    Button Style : Hot (Primary)
    Action       : Redirect to Page 11 (P11_SUPPLIER_ID = empty)
    CSS          : t-Button--hot

PAGE PROCESS (Delete):
  Name     : Delete Supplier
  Sequence : 10
  Process  : PL/SQL
  Code     :
    BEGIN
        DELETE FROM SUPPLIER_MASTER WHERE SUPPLIER_ID = :P10_SUPPLIER_ID;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -2292 THEN
                APEX_ERROR.ADD_ERROR(
                    p_message => 'Cannot delete supplier. Materials or Purchase Orders reference this supplier.',
                    p_display_location => apex_error.c_inline_in_notification
                );
            ELSE
                RAISE;
            END IF;
    END;

=================================================================
PAGE 11 — SUPPLIER MASTER FORM (Modal Dialog)
=================================================================
Page Type    : Form (Modal Dialog)
Page Number  : 11
Page Name    : Supplier Form
Dialog Title : &P11_FORM_TITLE. (set dynamically)
Width        : 800px
Height       : Auto

ITEMS (in order, 2-column layout):

  P11_SUPPLIER_ID      Hidden, PK, Source: DB Column SUPPLIER_ID
  P11_FORM_TITLE       Hidden, Source: PL/SQL: IF :P11_SUPPLIER_ID IS NULL THEN RETURN 'New Supplier'; ELSE RETURN 'Edit Supplier'; END IF;

  [ROW 1]
  P11_SUPPLIER_CODE    Text Field   | Label: Supplier Code   | Max 20 | Required | Uppercase
  P11_SUPPLIER_NAME    Text Field   | Label: Supplier Name   | Max 200 | Required

  [ROW 2]
  P11_CONTACT_PERSON   Text Field   | Label: Contact Person  | Max 100
  P11_EMAIL            Email Field  | Label: Email           | Max 150

  [ROW 3]
  P11_PHONE            Text Field   | Label: Phone           | Max 30
  P11_STATUS           Select List  | Label: Status          | LOV: LOV_SUPPLIER_STATUS | Required | Default: ACTIVE

  [ROW 4]
  P11_LEAD_TIME        Number Field | Label: Lead Time (Days) | Min: 0 | Default: 0
  P11_VENDOR_RATING    Number Field | Label: Vendor Rating (0-5) | Min: 0 | Max: 5

  [ROW 5 - Full Width]
  P11_ADDRESS          Textarea     | Label: Address | Rows: 3 | Max 500

VALIDATIONS:
  1. Name: VAL_SUPPLIER_CODE_UNIQUE
     Type: PL/SQL Function (returns error text)
     Code:
       DECLARE v_count NUMBER;
       BEGIN
         SELECT COUNT(*) INTO v_count FROM SUPPLIER_MASTER
          WHERE SUPPLIER_CODE = :P11_SUPPLIER_CODE
            AND (SUPPLIER_ID != :P11_SUPPLIER_ID OR :P11_SUPPLIER_ID IS NULL);
         IF v_count > 0 THEN RETURN 'Supplier Code already exists.'; END IF;
         RETURN NULL;
       END;
     When: Item is NOT NULL: P11_SUPPLIER_CODE

  2. Name: VAL_EMAIL_FORMAT
     Type: Regular Expression
     Expression: ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$
     Item: P11_EMAIL
     Error: Please enter a valid email address.
     When: Item is NOT NULL: P11_EMAIL

  3. Name: VAL_VENDOR_RATING
     Type: Item is between values
     Item: P11_VENDOR_RATING  | Min: 0 | Max: 5
     Error: Vendor Rating must be between 0 and 5.

PROCESSES:
  Process 1: Save Supplier
    Sequence : 10
    Type     : Automatic Row Processing (DML)
    Table    : SUPPLIER_MASTER
    Columns  : All P11_ items
    Insert Row When: :P11_SUPPLIER_ID IS NULL
    Success Message: Supplier saved successfully.

BUTTONS:
  CANCEL  → Dialog Cancel
  SAVE    → Submit Page (Hot/Primary)
  DELETE  → Submit (only show when P11_SUPPLIER_ID IS NOT NULL)
             Confirmation: Are you sure you want to delete this supplier?

DYNAMIC ACTIONS:
  DA1: On page load — Set form title
    Event   : Page Load
    Action  : Execute JavaScript
    Code    : apex.item('P11_FORM_TITLE').setValue($v('P11_SUPPLIER_ID') ? 'Edit Supplier' : 'New Supplier');

=================================================================
PAGE 20 — MATERIAL MASTER (Interactive Report)
=================================================================
Page Type    : Interactive Report
Page Number  : 20
Page Name    : Material Master

IR REGION SQL:
*/
SELECT
    m.MATERIAL_ID,
    m.MATERIAL_CODE,
    m.MATERIAL_NAME,
    m.CATEGORY,
    m.UNIT_OF_MEASURE,
    m.SAFETY_STOCK,
    m.REORDER_LEVEL,
    m.LEAD_TIME,
    m.STANDARD_COST,
    TO_CHAR(m.STANDARD_COST,'FM999,999,990.00')  AS COST_DISPLAY,
    s.SUPPLIER_NAME                              AS PREFERRED_SUPPLIER,
    s.VENDOR_RATING,
    m.STATUS,
    -- Reorder alert
    CASE
        WHEN m.SAFETY_STOCK <= m.REORDER_LEVEL THEN 'REORDER'
        ELSE 'OK'
    END                                          AS STOCK_STATUS
FROM MATERIAL_MASTER  m
LEFT JOIN SUPPLIER_MASTER s ON s.SUPPLIER_ID = m.PREFERRED_SUPPLIER_ID
ORDER BY m.CATEGORY, m.MATERIAL_CODE;

/*
COLUMN SETTINGS:
  MATERIAL_ID           : Hidden
  STANDARD_COST         : Hidden (use COST_DISPLAY)
  COST_DISPLAY          : Label = Standard Cost (INR)
  STOCK_STATUS HTML Expr:
    <span class="t-Badge t-Badge--#CASE STOCK_STATUS WHEN 'REORDER' THEN 'danger' ELSE 'success' END#">
      <span class="t-Badge-label">#STOCK_STATUS#</span>
    </span>
  STATUS HTML Expression:
    <span class="t-Badge t-Badge--#CASE STATUS WHEN 'ACTIVE' THEN 'success' ELSE 'danger' END#">
      <span class="t-Badge-label">#STATUS#</span>
    </span>

IR DEFAULT REPORT COLUMNS (in order):
  MATERIAL_CODE, MATERIAL_NAME, CATEGORY, UNIT_OF_MEASURE,
  SAFETY_STOCK, REORDER_LEVEL, LEAD_TIME, COST_DISPLAY,
  PREFERRED_SUPPLIER, STOCK_STATUS, STATUS

TOOLBAR: + New Material button → Page 21

=================================================================
PAGE 21 — MATERIAL MASTER FORM (Modal Dialog)
=================================================================
Width: 900px

ITEMS (3-column layout):
  P21_MATERIAL_ID         Hidden PK
  
  [ROW 1]
  P21_MATERIAL_CODE       Text  | Required | Max 30 | Uppercase
  P21_MATERIAL_NAME       Text  | Required | Max 200
  P21_STATUS              Select | LOV: LOV_MATERIAL_STATUS | Default: ACTIVE

  [ROW 2]
  P21_CATEGORY            Select | LOV: LOV_MATERIAL_CATEGORY | Required
  P21_UNIT_OF_MEASURE     Select | LOV: LOV_UNIT_OF_MEASURE | Required
  P21_LEAD_TIME           Number | Label: Lead Time (Days) | Default: 0

  [ROW 3]
  P21_SAFETY_STOCK        Number | Label: Safety Stock | Default: 0
  P21_REORDER_LEVEL       Number | Label: Reorder Level | Default: 0
  P21_STANDARD_COST       Number | Label: Standard Cost (INR) | Format: 999,999,990.0000

  [ROW 4 - Full Width]
  P21_PREFERRED_SUPPLIER_ID  Select | Label: Preferred Supplier | LOV: LOV_SUPPLIERS | Allow Null: Yes

VALIDATIONS:
  1. Material Code unique (same pattern as supplier)
  2. Safety Stock >= 0
  3. Standard Cost >= 0
  4. Reorder Level >= 0

PROCESS: DML on MATERIAL_MASTER

=================================================================
PAGE 30 — PRODUCT MASTER (Interactive Report)
=================================================================
Page Type  : Interactive Report
Page Number: 30
Page Name  : Product Master

IR REGION SQL:
*/
SELECT
    p.PRODUCT_ID,
    p.PRODUCT_CODE,
    p.PRODUCT_NAME,
    p.PRODUCT_CATEGORY,
    p.DESCRIPTION,
    p.STATUS,
    -- BOM count
    (SELECT COUNT(*) FROM BOM_MASTER b
      WHERE b.PRODUCT_ID = p.PRODUCT_ID
        AND b.STATUS = 'ACTIVE')             AS ACTIVE_BOM_COUNT,
    -- Forecast count
    (SELECT COUNT(*) FROM DEMAND_FORECAST df
      WHERE df.PRODUCT_ID = p.PRODUCT_ID
        AND TRUNC(df.FORECAST_PERIOD,'MM') >= TRUNC(SYSDATE,'MM')) AS FORECAST_COUNT
FROM PRODUCT_MASTER p
ORDER BY p.PRODUCT_CATEGORY, p.PRODUCT_CODE;

/*
COLUMN SETTINGS:
  PRODUCT_ID  : Hidden
  STATUS      : Badge (ACTIVE=success, INACTIVE=danger)
  ACTIVE_BOM_COUNT : Label = Active BOMs
  FORECAST_COUNT   : Label = Open Forecasts

ACTION BUTTONS (in IR Row Actions):
  View BOM    → Redirect to Page 40 (filter by product)
  New Forecast → Redirect to Page 51 (P51_PRODUCT_ID = #PRODUCT_ID#)

=================================================================
PAGE 31 — PRODUCT MASTER FORM (Modal Dialog)
=================================================================
Width: 800px

ITEMS:
  P31_PRODUCT_ID       Hidden PK
  
  [ROW 1]
  P31_PRODUCT_CODE     Text  | Required | Max 30 | Uppercase
  P31_PRODUCT_NAME     Text  | Required | Max 200

  [ROW 2]
  P31_PRODUCT_CATEGORY Select | LOV: (SELECT DISTINCT PRODUCT_CATEGORY, PRODUCT_CATEGORY FROM PRODUCT_MASTER UNION ALL SELECT 'Machinery','Machinery' FROM DUAL UNION ALL SELECT 'Electrical','Electrical' FROM DUAL UNION ALL SELECT 'Mechanical','Mechanical' FROM DUAL ORDER BY 1) | Allow null | Return: typed value
  P31_STATUS           Select | LOV: LOV_SUPPLIER_STATUS | Default: ACTIVE

  [ROW 3 - Full Width]
  P31_DESCRIPTION      Textarea | Max 1000 | Rows: 4

VALIDATIONS:
  1. Product Code unique

PROCESS: DML on PRODUCT_MASTER

=================================================================
DYNAMIC ACTIONS — ALL MASTER PAGES
=================================================================

DA: Show Success / Error Notification after DML
  Event  : After Refresh (on IR region)
  Action : Show Notification

DA: Confirm Delete
  Event  : Click on Delete Button
  Action : Confirm Dialog
  Message: This will permanently delete the record. Active references will prevent deletion.

DA: Close Dialog on Success
  Event  : Dialog Closed
  Action : Refresh Interactive Report region

=================================================================
APEX PROCESSES — MASTER PAGES COMMON PATTERN
=================================================================

After Save Process (all master forms):
  -- Show notification count in menu badge
  APEX_UTIL.SET_SESSION_STATE(
      p_name  => 'APP_MSG',
      p_value => 'Record saved successfully.'
  );

=================================================================
ROW SELECTOR + BULK ACTIONS (Page 10, 20, 30)
=================================================================
Enable on IR:
  Row Selector: Yes
  Bulk Delete  : Process with DELETE WHERE SUPPLIER_ID IN (APEX_STRING.SPLIT(:P10_SELECTED_ROWS,':'))

*/

PROMPT [SUCCESS] Masters module SQL reference file created.
PROMPT Use this file as your exact specification when building
PROMPT pages 10, 11, 20, 21, 30, 31 in APEX App Builder.
