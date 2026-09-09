-- MPPMS :: RUN_PHASE11_PACKAGES.sql
-- Compiles all Phase 11 PL/SQL packages in correct dependency order
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

PROMPT ============================================================
PROMPT  MPPMS :: Compiling Phase 11 Packages
PROMPT ============================================================

PROMPT [1/6] PKG_VENDOR_SCORECARD (+ currency converter)...
@36_pkg_vendor_scorecard.sql

PROMPT [2/6] PKG_ASL...
@38_pkg_asl.sql

PROMPT [3/6] PKG_INVOICE_MATCHING...
@40_pkg_invoice_matching.sql

PROMPT [4/6] PKG_QC_INSPECTION...
@42_pkg_qc_inspection.sql

PROMPT [5/6] PKG_COSTING...
@44_pkg_costing.sql

PROMPT [6/6] PKG_LOT_SERIAL...
@46_pkg_lot_serial.sql

PROMPT ============================================================
PROMPT  Verification: Invalid Objects Check
PROMPT ============================================================
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS
FROM USER_OBJECTS
WHERE OBJECT_NAME IN (
    'PKG_VENDOR_SCORECARD','PKG_ASL','PKG_INVOICE_MATCHING',
    'PKG_QC_INSPECTION','PKG_COSTING','PKG_LOT_SERIAL'
)
ORDER BY OBJECT_NAME, OBJECT_TYPE;
