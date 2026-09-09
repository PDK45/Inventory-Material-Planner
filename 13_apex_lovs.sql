-- ============================================================
-- MPPMS :: 13_apex_lovs.sql
-- Purpose : Shared List of Values for APEX application
-- Run In  : APEX SQL Workshop OR as MPPMS user
--           (These are SQL queries used when creating LOVs
--            in APEX Shared Components > List of Values)
-- ============================================================

/*
HOW TO USE THIS FILE:
  In APEX App Builder:
  1. Shared Components > List of Values > Create
  2. Choose "From Scratch" > name the LOV > paste the SQL query below

  This file documents all LOV queries for the MPPMS application.
  Create each LOV in Shared Components before building forms.
*/

PROMPT ============================================================
PROMPT  MPPMS :: LOV Reference Queries
PROMPT ============================================================

-- ============================================================
-- LOV: LOV_SUPPLIERS (active suppliers only)
-- Display Column : SUPPLIER_NAME | Return Column: SUPPLIER_ID
-- ============================================================
-- Query to use in APEX:
/*
SELECT SUPPLIER_NAME || ' [' || SUPPLIER_CODE || '] (Rating: ' || VENDOR_RATING || ')'
           AS DISPLAY_VALUE,
       SUPPLIER_ID AS RETURN_VALUE
FROM   SUPPLIER_MASTER
WHERE  STATUS = 'ACTIVE'
ORDER BY SUPPLIER_NAME
*/

-- ============================================================
-- LOV: LOV_MATERIALS (active materials only)
-- Display Column : MATERIAL_CODE + NAME | Return: MATERIAL_ID
-- ============================================================
/*
SELECT MATERIAL_CODE || ' - ' || MATERIAL_NAME || ' (' || UNIT_OF_MEASURE || ')'
           AS DISPLAY_VALUE,
       MATERIAL_ID AS RETURN_VALUE
FROM   MATERIAL_MASTER
WHERE  STATUS = 'ACTIVE'
ORDER BY MATERIAL_CODE
*/

-- ============================================================
-- LOV: LOV_PRODUCTS (active products)
-- ============================================================
/*
SELECT PRODUCT_CODE || ' - ' || PRODUCT_NAME AS DISPLAY_VALUE,
       PRODUCT_ID AS RETURN_VALUE
FROM   PRODUCT_MASTER
WHERE  STATUS = 'ACTIVE'
ORDER BY PRODUCT_CODE
*/

-- ============================================================
-- LOV: LOV_ACTIVE_BOMS (for BOM detail, filtered by product)
-- ============================================================
/*
SELECT b.PRODUCT_ID || ' | ' || p.PRODUCT_NAME || ' v' || b.VERSION AS DISPLAY_VALUE,
       b.BOM_ID AS RETURN_VALUE
FROM   BOM_MASTER b
JOIN   PRODUCT_MASTER p ON p.PRODUCT_ID = b.PRODUCT_ID
WHERE  b.STATUS = 'ACTIVE'
ORDER BY p.PRODUCT_NAME, b.VERSION
*/

-- ============================================================
-- LOV: LOV_APPROVED_PLANS (for MRP run)
-- ============================================================
/*
SELECT pp.PLAN_NAME || ' [' || pp.STATUS || '] - ' || p.PRODUCT_NAME AS DISPLAY_VALUE,
       pp.PLAN_ID AS RETURN_VALUE
FROM   PRODUCTION_PLAN pp
JOIN   PRODUCT_MASTER   p ON p.PRODUCT_ID = pp.PRODUCT_ID
WHERE  pp.STATUS IN ('APPROVED','IN_PROGRESS')
ORDER BY pp.PLANNED_START_DATE
*/

-- ============================================================
-- LOV: LOV_APPROVED_PRS (for PO creation)
-- ============================================================
/*
SELECT pr.PR_NUMBER || ' - ' || m.MATERIAL_NAME ||
       ' (Qty: ' || pr.REQUESTED_QTY || ')' AS DISPLAY_VALUE,
       pr.PR_ID AS RETURN_VALUE
FROM   PURCHASE_REQUISITION pr
JOIN   MATERIAL_MASTER       m ON m.MATERIAL_ID = pr.MATERIAL_ID
WHERE  pr.STATUS = 'APPROVED'
ORDER BY pr.CREATED_DATE
*/

-- ============================================================
-- LOV: LOV_SUPPLIER_STATUS (static)
-- ============================================================
/*
SELECT 'Active'   AS DISPLAY_VALUE, 'ACTIVE'   AS RETURN_VALUE FROM DUAL UNION ALL
SELECT 'Inactive' AS DISPLAY_VALUE, 'INACTIVE' AS RETURN_VALUE FROM DUAL
*/

-- ============================================================
-- LOV: LOV_MATERIAL_STATUS (static)
-- ============================================================
/*
SELECT 'Active'   AS DISPLAY_VALUE, 'ACTIVE'   AS RETURN_VALUE FROM DUAL UNION ALL
SELECT 'Inactive' AS DISPLAY_VALUE, 'INACTIVE' AS RETURN_VALUE FROM DUAL
*/

-- ============================================================
-- LOV: LOV_UNIT_OF_MEASURE (static)
-- ============================================================
/*
SELECT 'Each (EA)'     AS D, 'EA'   AS R FROM DUAL UNION ALL
SELECT 'Kilogram (KG)' AS D, 'KG'   AS R FROM DUAL UNION ALL
SELECT 'Litre (LTR)'   AS D, 'LTR'  AS R FROM DUAL UNION ALL
SELECT 'Metre (MTR)'   AS D, 'MTR'  AS R FROM DUAL UNION ALL
SELECT 'Square Metre'  AS D, 'SQM'  AS R FROM DUAL UNION ALL
SELECT 'Roll (ROLL)'   AS D, 'ROLL' AS R FROM DUAL UNION ALL
SELECT 'Box (BOX)'     AS D, 'BOX'  AS R FROM DUAL
*/

-- ============================================================
-- LOV: LOV_PR_STATUS (static)
-- ============================================================
/*
SELECT 'Draft'     AS D, 'DRAFT'     AS R FROM DUAL UNION ALL
SELECT 'Submitted' AS D, 'SUBMITTED' AS R FROM DUAL UNION ALL
SELECT 'Approved'  AS D, 'APPROVED'  AS R FROM DUAL UNION ALL
SELECT 'Rejected'  AS D, 'REJECTED'  AS R FROM DUAL UNION ALL
SELECT 'Ordered'   AS D, 'ORDERED'   AS R FROM DUAL UNION ALL
SELECT 'Closed'    AS D, 'CLOSED'    AS R FROM DUAL
*/

-- ============================================================
-- LOV: LOV_PRIORITY (static)
-- ============================================================
/*
SELECT 'High'   AS D, 'HIGH'   AS R FROM DUAL UNION ALL
SELECT 'Medium' AS D, 'MEDIUM' AS R FROM DUAL UNION ALL
SELECT 'Low'    AS D, 'LOW'    AS R FROM DUAL
*/

-- ============================================================
-- LOV: LOV_PO_STATUS (static)
-- ============================================================
/*
SELECT 'Draft'              AS D, 'DRAFT'              AS R FROM DUAL UNION ALL
SELECT 'Issued'             AS D, 'ISSUED'             AS R FROM DUAL UNION ALL
SELECT 'Acknowledged'       AS D, 'ACKNOWLEDGED'       AS R FROM DUAL UNION ALL
SELECT 'Partially Received' AS D, 'PARTIALLY_RECEIVED' AS R FROM DUAL UNION ALL
SELECT 'Received'           AS D, 'RECEIVED'           AS R FROM DUAL UNION ALL
SELECT 'Cancelled'          AS D, 'CANCELLED'          AS R FROM DUAL
*/

-- ============================================================
-- LOV: LOV_DELIVERY_STATUS (static)
-- ============================================================
/*
SELECT 'Pending'             AS D, 'PENDING'             AS R FROM DUAL UNION ALL
SELECT 'In Transit'          AS D, 'IN_TRANSIT'          AS R FROM DUAL UNION ALL
SELECT 'Partially Delivered' AS D, 'PARTIALLY_DELIVERED' AS R FROM DUAL UNION ALL
SELECT 'Delivered'           AS D, 'DELIVERED'           AS R FROM DUAL UNION ALL
SELECT 'Returned'            AS D, 'RETURNED'            AS R FROM DUAL UNION ALL
SELECT 'Cancelled'           AS D, 'CANCELLED'           AS R FROM DUAL
*/

-- ============================================================
-- LOV: LOV_PLAN_STATUS (static)
-- ============================================================
/*
SELECT 'Draft'       AS D, 'DRAFT'       AS R FROM DUAL UNION ALL
SELECT 'Approved'    AS D, 'APPROVED'    AS R FROM DUAL UNION ALL
SELECT 'In Progress' AS D, 'IN_PROGRESS' AS R FROM DUAL UNION ALL
SELECT 'Completed'   AS D, 'COMPLETED'   AS R FROM DUAL UNION ALL
SELECT 'Cancelled'   AS D, 'CANCELLED'   AS R FROM DUAL
*/

-- ============================================================
-- LOV: LOV_FORECAST_TYPE (static)
-- ============================================================
/*
SELECT 'Manual'     AS D, 'MANUAL'     AS R FROM DUAL UNION ALL
SELECT 'System'     AS D, 'SYSTEM'     AS R FROM DUAL UNION ALL
SELECT 'AI'         AS D, 'AI'         AS R FROM DUAL UNION ALL
SELECT 'Historical' AS D, 'HISTORICAL' AS R FROM DUAL
*/

-- ============================================================
-- LOV: LOV_MRP_STATUS (static)
-- ============================================================
/*
SELECT 'Calculated' AS D, 'CALCULATED' AS R FROM DUAL UNION ALL
SELECT 'PR Raised'  AS D, 'PR_RAISED'  AS R FROM DUAL UNION ALL
SELECT 'Closed'     AS D, 'CLOSED'     AS R FROM DUAL
*/

-- ============================================================
-- LOV: LOV_MATERIAL_CATEGORY (from data)
-- ============================================================
/*
SELECT DISTINCT CATEGORY AS DISPLAY_VALUE, CATEGORY AS RETURN_VALUE
FROM   MATERIAL_MASTER
WHERE  CATEGORY IS NOT NULL
ORDER BY CATEGORY
*/

PROMPT [SUCCESS] LOV queries documented. Use these in APEX Shared Components.
