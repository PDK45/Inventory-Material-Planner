-- ============================================================
-- MPPMS :: 47_new_ords_endpoints.sql
-- Purpose : ORDS REST API Definitions for 6 Enterprise Modules
-- Run As  : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

PROMPT Publishing Phase 11 Enterprise Modules via ORDS REST API...

BEGIN
    ORDS.ENABLE_SCHEMA(
        p_enabled             => TRUE,
        p_schema              => 'MPPMS',
        p_url_mapping_type    => 'BASE_PATH',
        p_url_mapping_pattern => 'mppms',
        p_auto_rest_auth      => FALSE
    );

    -- 1. Vendor Scorecard API
    ORDS.DEFINE_MODULE(
        p_module_name    => 'mppms.vendor_scorecard',
        p_base_path      => 'vendor-scorecard/',
        p_status         => 'PUBLISHED'
    );
    ORDS.DEFINE_TEMPLATE(p_module_name => 'mppms.vendor_scorecard', p_pattern => 'summary');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'mppms.vendor_scorecard', p_pattern => 'summary',
        p_method => 'GET', p_source_type => ORDS.SOURCE_TYPE_PLSQL,
        p_source => 'BEGIN :rc := PKG_VENDOR_SCORECARD.GET_ALL_SCORECARDS; END;'
    );

    -- 2. ASL API
    ORDS.DEFINE_MODULE(
        p_module_name    => 'mppms.asl',
        p_base_path      => 'asl/',
        p_status         => 'PUBLISHED'
    );
    ORDS.DEFINE_TEMPLATE(p_module_name => 'mppms.asl', p_pattern => 'dashboard');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'mppms.asl', p_pattern => 'dashboard',
        p_method => 'GET', p_source_type => ORDS.SOURCE_TYPE_PLSQL,
        p_source => 'BEGIN :rc := PKG_ASL.GET_ASL_DASHBOARD; END;'
    );

    -- 3. Invoice Matching API
    ORDS.DEFINE_MODULE(
        p_module_name    => 'mppms.invoice_matching',
        p_base_path      => 'invoice-matching/',
        p_status         => 'PUBLISHED'
    );
    ORDS.DEFINE_TEMPLATE(p_module_name => 'mppms.invoice_matching', p_pattern => 'dashboard');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'mppms.invoice_matching', p_pattern => 'dashboard',
        p_method => 'GET', p_source_type => ORDS.SOURCE_TYPE_PLSQL,
        p_source => 'BEGIN :rc := PKG_INVOICE_MATCHING.GET_MATCHING_DASHBOARD; END;'
    );
    ORDS.DEFINE_TEMPLATE(p_module_name => 'mppms.invoice_matching', p_pattern => 'ageing');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'mppms.invoice_matching', p_pattern => 'ageing',
        p_method => 'GET', p_source_type => ORDS.SOURCE_TYPE_PLSQL,
        p_source => 'BEGIN :rc := PKG_INVOICE_MATCHING.GET_AP_AGEING; END;'
    );

    -- 4. QC Inspection API
    ORDS.DEFINE_MODULE(
        p_module_name    => 'mppms.qc',
        p_base_path      => 'qc/',
        p_status         => 'PUBLISHED'
    );
    ORDS.DEFINE_TEMPLATE(p_module_name => 'mppms.qc', p_pattern => 'pending');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'mppms.qc', p_pattern => 'pending',
        p_method => 'GET', p_source_type => ORDS.SOURCE_TYPE_PLSQL,
        p_source => 'BEGIN :rc := PKG_QC_INSPECTION.GET_PENDING_INSPECTIONS; END;'
    );
    ORDS.DEFINE_TEMPLATE(p_module_name => 'mppms.qc', p_pattern => 'rejection-analysis');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'mppms.qc', p_pattern => 'rejection-analysis',
        p_method => 'GET', p_source_type => ORDS.SOURCE_TYPE_PLSQL,
        p_source => 'BEGIN :rc := PKG_QC_INSPECTION.GET_REJECTION_ANALYSIS(6); END;'
    );

    -- 5. Costing API
    ORDS.DEFINE_MODULE(
        p_module_name    => 'mppms.costing',
        p_base_path      => 'costing/',
        p_status         => 'PUBLISHED'
    );
    ORDS.DEFINE_TEMPLATE(p_module_name => 'mppms.costing', p_pattern => 'valuation');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'mppms.costing', p_pattern => 'valuation',
        p_method => 'GET', p_source_type => ORDS.SOURCE_TYPE_PLSQL,
        p_source => 'BEGIN :rc := PKG_COSTING.GET_INVENTORY_VALUATION(NULL, ''SAR''); END;'
    );

    -- 6. Lot & Serial Tracking API
    ORDS.DEFINE_MODULE(
        p_module_name    => 'mppms.lot_serial',
        p_base_path      => 'lot-serial/',
        p_status         => 'PUBLISHED'
    );
    ORDS.DEFINE_TEMPLATE(p_module_name => 'mppms.lot_serial', p_pattern => 'register');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'mppms.lot_serial', p_pattern => 'register',
        p_method => 'GET', p_source_type => ORDS.SOURCE_TYPE_PLSQL,
        p_source => 'BEGIN :rc := PKG_LOT_SERIAL.GET_LOT_REGISTER; END;'
    );
    ORDS.DEFINE_TEMPLATE(p_module_name => 'mppms.lot_serial', p_pattern => 'expiring');
    ORDS.DEFINE_HANDLER(
        p_module_name => 'mppms.lot_serial', p_pattern => 'expiring',
        p_method => 'GET', p_source_type => ORDS.SOURCE_TYPE_PLSQL,
        p_source => 'BEGIN :rc := PKG_LOT_SERIAL.GET_EXPIRING_LOTS(90); END;'
    );

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] ORDS REST endpoints for Phase 11 Enterprise Modules successfully defined!');
END;
/
