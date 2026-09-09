-- ============================================================
-- MPPMS :: 52_phase12_ords_endpoints.sql
-- Phase 12: REST Endpoints for Digital Twin & Smart Sourcing
-- Run As: MPPMS user on FREEPDB1 (ORDS must be enabled)
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS Phase 12 :: Registering ORDS REST Endpoints
PROMPT ============================================================

BEGIN
  ORDS.ENABLE_SCHEMA(
    p_enabled             => TRUE,
    p_schema              => 'MPPMS',
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => 'mppms',
    p_auto_rest_auth      => FALSE
  );
  COMMIT;
END;
/

-- ============================================================
-- MODULE 1: digital-twin
-- ============================================================
BEGIN
  ORDS.DEFINE_MODULE(
    p_module_name    => 'digital-twin',
    p_base_path      => '/digital-twin/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED'
  );

  -- POST /digital-twin/run — Run a new Monte Carlo simulation
  ORDS.DEFINE_TEMPLATE(p_module_name => 'digital-twin', p_pattern => 'run');
  ORDS.DEFINE_HANDLER(
    p_module_name    => 'digital-twin',
    p_pattern        => 'run',
    p_method         => 'POST',
    p_source_type    => ORDS.SOURCE_TYPE_PLSQL,
    p_source         => '
DECLARE
  v_scenario_id NUMBER;
  v_status      VARCHAR2(20);
  v_message     VARCHAR2(1000);
BEGIN
  PKG_DIGITAL_TWIN.RUN_SIMULATION(
    p_scenario_name    => :p_scenario_name,
    p_material_id      => :p_material_id,
    p_shipping_delay   => :p_shipping_delay,
    p_tariff_spike_pct => :p_tariff_spike_pct,
    p_demand_surge_pct => :p_demand_surge_pct,
    p_trial_count      => NVL(:p_trial_count, 1000),
    p_scenario_id      => v_scenario_id,
    p_status           => v_status,
    p_message          => v_message
  );
  :status_code := CASE v_status WHEN ''SUCCESS'' THEN 200 ELSE 500 END;
  APEX_JSON.OPEN_OBJECT;
  APEX_JSON.WRITE(''status'',      v_status);
  APEX_JSON.WRITE(''scenario_id'', v_scenario_id);
  APEX_JSON.WRITE(''message'',     v_message);
  APEX_JSON.CLOSE_OBJECT;
END;',
    p_items_per_page => 0
  );

  -- POST /digital-twin/run-full-chain — Run across all materials
  ORDS.DEFINE_TEMPLATE(p_module_name => 'digital-twin', p_pattern => 'run-full-chain');
  ORDS.DEFINE_HANDLER(
    p_module_name    => 'digital-twin',
    p_pattern        => 'run-full-chain',
    p_method         => 'POST',
    p_source_type    => ORDS.SOURCE_TYPE_PLSQL,
    p_source         => '
DECLARE
  v_scenario_id NUMBER;
  v_status      VARCHAR2(20);
  v_message     VARCHAR2(1000);
BEGIN
  PKG_DIGITAL_TWIN.RUN_FULL_CHAIN_SIMULATION(
    p_scenario_name    => :p_scenario_name,
    p_shipping_delay   => :p_shipping_delay,
    p_tariff_spike_pct => :p_tariff_spike_pct,
    p_demand_surge_pct => :p_demand_surge_pct,
    p_trial_count      => NVL(:p_trial_count, 1000),
    p_scenario_id      => v_scenario_id,
    p_status           => v_status,
    p_message          => v_message
  );
  :status_code := CASE v_status WHEN ''SUCCESS'' THEN 200 ELSE 500 END;
  APEX_JSON.OPEN_OBJECT;
  APEX_JSON.WRITE(''status'',      v_status);
  APEX_JSON.WRITE(''scenario_id'', v_scenario_id);
  APEX_JSON.WRITE(''message'',     v_message);
  APEX_JSON.CLOSE_OBJECT;
END;',
    p_items_per_page => 0
  );

  -- GET /digital-twin/summary/:scenario_id
  ORDS.DEFINE_TEMPLATE(p_module_name => 'digital-twin', p_pattern => 'summary/:scenario_id');
  ORDS.DEFINE_HANDLER(
    p_module_name    => 'digital-twin',
    p_pattern        => 'summary/:scenario_id',
    p_method         => 'GET',
    p_source_type    => ORDS.SOURCE_TYPE_REF_CURSOR,
    p_source         => 'BEGIN :result := PKG_DIGITAL_TWIN.GET_SCENARIO_SUMMARY(:scenario_id); END;',
    p_items_per_page => 1
  );

  -- GET /digital-twin/heatmap/:scenario_id
  ORDS.DEFINE_TEMPLATE(p_module_name => 'digital-twin', p_pattern => 'heatmap/:scenario_id');
  ORDS.DEFINE_HANDLER(
    p_module_name    => 'digital-twin',
    p_pattern        => 'heatmap/:scenario_id',
    p_method         => 'GET',
    p_source_type    => ORDS.SOURCE_TYPE_REF_CURSOR,
    p_source         => 'BEGIN :result := PKG_DIGITAL_TWIN.GET_HEATMAP_DATA(:scenario_id); END;',
    p_items_per_page => 25
  );

  -- GET /digital-twin/histogram/:scenario_id
  ORDS.DEFINE_TEMPLATE(p_module_name => 'digital-twin', p_pattern => 'histogram/:scenario_id');
  ORDS.DEFINE_HANDLER(
    p_module_name    => 'digital-twin',
    p_pattern        => 'histogram/:scenario_id',
    p_method         => 'GET',
    p_source_type    => ORDS.SOURCE_TYPE_REF_CURSOR,
    p_source         => 'BEGIN :result := PKG_DIGITAL_TWIN.GET_EXPOSURE_HISTOGRAM(:scenario_id, 20); END;',
    p_items_per_page => 25
  );

  COMMIT;
END;
/

PROMPT [OK] digital-twin ORDS module registered.

-- ============================================================
-- MODULE 2: smart-sourcing
-- ============================================================
BEGIN
  ORDS.DEFINE_MODULE(
    p_module_name    => 'smart-sourcing',
    p_base_path      => '/smart-sourcing/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED'
  );

  -- POST /smart-sourcing/optimise
  ORDS.DEFINE_TEMPLATE(p_module_name => 'smart-sourcing', p_pattern => 'optimise');
  ORDS.DEFINE_HANDLER(
    p_module_name    => 'smart-sourcing',
    p_pattern        => 'optimise',
    p_method         => 'POST',
    p_source_type    => ORDS.SOURCE_TYPE_PLSQL,
    p_source         => '
DECLARE
  v_opt_id  NUMBER;
  v_status  VARCHAR2(20);
  v_message VARCHAR2(1000);
BEGIN
  PKG_SMART_SOURCING.OPTIMISE_SOURCING(
    p_material_id     => :p_material_id,
    p_required_qty    => :p_required_qty,
    p_strategy        => NVL(:p_strategy, ''BALANCED_RISK''),
    p_pr_id           => :p_pr_id,
    p_optimisation_id => v_opt_id,
    p_status          => v_status,
    p_message         => v_message
  );
  :status_code := CASE v_status WHEN ''SUCCESS'' THEN 200 ELSE 500 END;
  APEX_JSON.OPEN_OBJECT;
  APEX_JSON.WRITE(''status'',           v_status);
  APEX_JSON.WRITE(''optimisation_id'',  v_opt_id);
  APEX_JSON.WRITE(''message'',          v_message);
  APEX_JSON.CLOSE_OBJECT;
END;',
    p_items_per_page => 0
  );

  -- POST /smart-sourcing/accept/:optimisation_id
  ORDS.DEFINE_TEMPLATE(p_module_name => 'smart-sourcing', p_pattern => 'accept/:optimisation_id');
  ORDS.DEFINE_HANDLER(
    p_module_name    => 'smart-sourcing',
    p_pattern        => 'accept/:optimisation_id',
    p_method         => 'POST',
    p_source_type    => ORDS.SOURCE_TYPE_PLSQL,
    p_source         => '
DECLARE
  v_status  VARCHAR2(20);
  v_message VARCHAR2(1000);
BEGIN
  PKG_SMART_SOURCING.ACCEPT_SPLIT(
    p_optimisation_id => :optimisation_id,
    p_accepted_by     => NVL(:p_accepted_by, USER),
    p_status          => v_status,
    p_message         => v_message
  );
  :status_code := CASE v_status WHEN ''SUCCESS'' THEN 200 ELSE 500 END;
  APEX_JSON.OPEN_OBJECT;
  APEX_JSON.WRITE(''status'',  v_status);
  APEX_JSON.WRITE(''message'', v_message);
  APEX_JSON.CLOSE_OBJECT;
END;',
    p_items_per_page => 0
  );

  -- GET /smart-sourcing/allocations/:optimisation_id
  ORDS.DEFINE_TEMPLATE(p_module_name => 'smart-sourcing', p_pattern => 'allocations/:optimisation_id');
  ORDS.DEFINE_HANDLER(
    p_module_name    => 'smart-sourcing',
    p_pattern        => 'allocations/:optimisation_id',
    p_method         => 'GET',
    p_source_type    => ORDS.SOURCE_TYPE_REF_CURSOR,
    p_source         => 'BEGIN :result := PKG_SMART_SOURCING.GET_ALLOCATIONS(:optimisation_id); END;',
    p_items_per_page => 25
  );

  -- GET /smart-sourcing/summary/:optimisation_id
  ORDS.DEFINE_TEMPLATE(p_module_name => 'smart-sourcing', p_pattern => 'summary/:optimisation_id');
  ORDS.DEFINE_HANDLER(
    p_module_name    => 'smart-sourcing',
    p_pattern        => 'summary/:optimisation_id',
    p_method         => 'GET',
    p_source_type    => ORDS.SOURCE_TYPE_REF_CURSOR,
    p_source         => 'BEGIN :result := PKG_SMART_SOURCING.GET_OPTIMISATION_SUMMARY(:optimisation_id); END;',
    p_items_per_page => 1
  );

  COMMIT;
END;
/

PROMPT [OK] smart-sourcing ORDS module registered.

PROMPT ============================================================
PROMPT  Phase 12 :: ORDS Endpoints COMPLETE
PROMPT ============================================================
