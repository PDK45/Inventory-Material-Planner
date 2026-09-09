-- MPPMS :: RUN_PHASE11_TABLES.sql
-- Runs all Phase 11 table scripts in dependency order
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Running Phase 11 Table Scripts
PROMPT ============================================================

PROMPT [1/6] Vendor Scorecard + Currency Tables...
@35_vendor_scorecard_tables.sql

PROMPT [2/6] Approved Supplier List...
@37_asl_tables.sql

PROMPT [3/6] Invoice Matching...
@39_invoice_matching_tables.sql

PROMPT [4/6] QC Inspection (Steel Parameters)...
@41_qc_inspection_tables.sql

PROMPT [5/6] Standard Costing...
@43_costing_tables.sql

PROMPT [6/6] Lot & Serial Tracking...
@45_lot_serial_tables.sql

PROMPT ============================================================
PROMPT  Phase 11 Tables Complete. Verification:
PROMPT ============================================================
SELECT TABLE_NAME, NUM_ROWS
FROM USER_TABLES
WHERE TABLE_NAME IN (
    'CURRENCY_MASTER','EXCHANGE_RATE',
    'SUPPLIER_SCORECARD','DELIVERY_EVENT',
    'APPROVED_SUPPLIER_LIST','SUPPLIER_MATERIAL_CERT',
    'PAYMENT_TERM','SUPPLIER_INVOICE','INVOICE_LINE','INVOICE_MATCH',
    'QC_PARAMETER','QC_INSPECTION','QC_INSPECTION_LINE','QC_RETURN',
    'COST_PERIOD','MATERIAL_COST','PRICE_VARIANCE_LOG',
    'LOT_MASTER','LOT_TRANSACTION','SERIAL_MASTER','SERIAL_TRANSACTION'
)
ORDER BY TABLE_NAME;
