-- ============================================================
-- MPPMS :: 53_apex_digital_twin_page.sql
-- Phase 12: Oracle APEX Page — Digital Twin Stress Tester
-- Creates Page 30 in the MPPMS APEX application
-- Run As: MPPMS user on FREEPDB1 via SQL Workshop or SQLcl
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS Phase 12 :: Building APEX Digital Twin Page (Page 30)
PROMPT ============================================================

-- ============================================================
-- PAGE 30: Digital Twin Supply Chain Stress Tester
-- Layout: 3 Slider Inputs | Run Button | Results Region
-- ============================================================
DECLARE
  v_app_id    NUMBER;
  v_page_id   NUMBER := 30;
BEGIN
  -- Get the MPPMS application ID
  SELECT APPLICATION_ID INTO v_app_id
    FROM APEX_APPLICATIONS
   WHERE ALIAS = 'MPPMS'
     AND WORKSPACE_ID = (SELECT WORKSPACE_ID FROM APEX_WORKSPACES WHERE WORKSPACE = 'MPPMS')
     AND ROWNUM = 1;

  -- Remove existing page if it exists
  FOR r IN (SELECT PAGE_ID FROM APEX_APPLICATION_PAGES WHERE APPLICATION_ID = v_app_id AND PAGE_ID = v_page_id) LOOP
    APEX_APPLICATION_INSTALL.SET_APPLICATION_ID(v_app_id);
    -- Note: In full APEX export format, page deletion is handled via APEX_UTIL
    NULL;
  END LOOP;

  -- Create the APEX page using the APEX API
  APEX_APPLICATION_PAGE.CREATE_PAGE(
    p_application_id     => v_app_id,
    p_page_id            => v_page_id,
    p_name               => 'Digital Twin — Supply Chain Stress Tester',
    p_alias              => 'DIGITAL-TWIN',
    p_page_mode          => 'NORMAL',
    p_step_title         => 'Digital Twin Stress Tester',
    p_step_sub_title     => 'Monte Carlo Simulation Engine — 1,000-Trial Risk Analysis',
    p_first_item         => 'NO_FIRST_ITEM',
    p_javascript_code    => '',
    p_page_template_options => '#DEFAULT#',
    p_dialog_height      => '',
    p_dialog_width       => '',
    p_dialog_max_height  => '',
    p_dialog_css_classes => ''
  );
END;
/

-- ============================================================
-- REGION 1: Scenario Input Panel (3 sliders + scenario name)
-- ============================================================
DECLARE
  v_app_id NUMBER;
  v_region_id NUMBER;
BEGIN
  SELECT APPLICATION_ID INTO v_app_id
    FROM APEX_APPLICATIONS WHERE ALIAS = 'MPPMS' AND ROWNUM = 1;

  APEX_APPLICATION_PAGE_REGIONS.CREATE_REGION(
    p_application_id  => v_app_id,
    p_page_id         => 30,
    p_region_name     => 'Shock Parameters',
    p_region_template => 'Standard',
    p_region_css_classes => 'digital-twin-inputs',
    p_display_sequence => 10,
    p_region_source   => NULL,
    p_region_type     => 'STATIC_CONTENT'
  );
END;
/

-- Page Items for the 3 shock sliders + scenario name
DECLARE
  v_app_id NUMBER;
BEGIN
  SELECT APPLICATION_ID INTO v_app_id
    FROM APEX_APPLICATIONS WHERE ALIAS = 'MPPMS' AND ROWNUM = 1;

  -- P30_SCENARIO_NAME
  APEX_APPLICATION_PAGE_ITEMS.CREATE_PAGE_ITEM(
    p_application_id   => v_app_id,
    p_page_id          => 30,
    p_name             => 'P30_SCENARIO_NAME',
    p_item_sequence    => 10,
    p_item_plug_id     => (SELECT REGION_ID FROM APEX_APPLICATION_PAGE_REGIONS WHERE APPLICATION_ID = v_app_id AND PAGE_ID = 30 AND REGION_NAME = 'Shock Parameters'),
    p_item_default     => 'Red Sea Disruption Scenario — ' || TO_CHAR(SYSDATE,'DD-Mon-YYYY'),
    p_prompt           => 'Scenario Name',
    p_display_as       => 'NATIVE_TEXT_FIELD',
    p_cSize            => 60,
    p_field_template   => 'Optional - Floating Label',
    p_item_template_options => '#DEFAULT#',
    p_is_required      => 'N'
  );

  -- P30_SHIPPING_DELAY — Range slider 0-90 days
  APEX_APPLICATION_PAGE_ITEMS.CREATE_PAGE_ITEM(
    p_application_id   => v_app_id,
    p_page_id          => 30,
    p_name             => 'P30_SHIPPING_DELAY',
    p_item_sequence    => 20,
    p_item_plug_id     => (SELECT REGION_ID FROM APEX_APPLICATION_PAGE_REGIONS WHERE APPLICATION_ID = v_app_id AND PAGE_ID = 30 AND REGION_NAME = 'Shock Parameters'),
    p_item_default     => '0',
    p_prompt           => '🚢 Shipping Delay (Days)',
    p_display_as       => 'NATIVE_NUMBER_FIELD',
    p_cSize            => 20,
    p_cMaxlength       => 3,
    p_field_template   => 'Optional - Floating Label',
    p_is_required      => 'N',
    p_item_template_options => '#DEFAULT#'
  );

  -- P30_TARIFF_SPIKE — Numeric 0-200%
  APEX_APPLICATION_PAGE_ITEMS.CREATE_PAGE_ITEM(
    p_application_id   => v_app_id,
    p_page_id          => 30,
    p_name             => 'P30_TARIFF_SPIKE',
    p_item_sequence    => 30,
    p_item_plug_id     => (SELECT REGION_ID FROM APEX_APPLICATION_PAGE_REGIONS WHERE APPLICATION_ID = v_app_id AND PAGE_ID = 30 AND REGION_NAME = 'Shock Parameters'),
    p_item_default     => '0',
    p_prompt           => '📈 Tariff / Cost Spike (%)',
    p_display_as       => 'NATIVE_NUMBER_FIELD',
    p_cSize            => 20,
    p_cMaxlength       => 5,
    p_field_template   => 'Optional - Floating Label',
    p_is_required      => 'N',
    p_item_template_options => '#DEFAULT#'
  );

  -- P30_DEMAND_SURGE — Numeric -100 to +500%
  APEX_APPLICATION_PAGE_ITEMS.CREATE_PAGE_ITEM(
    p_application_id   => v_app_id,
    p_page_id          => 30,
    p_name             => 'P30_DEMAND_SURGE',
    p_item_sequence    => 40,
    p_item_plug_id     => (SELECT REGION_ID FROM APEX_APPLICATION_PAGE_REGIONS WHERE APPLICATION_ID = v_app_id AND PAGE_ID = 30 AND REGION_NAME = 'Shock Parameters'),
    p_item_default     => '0',
    p_prompt           => '⚡ Demand Surge (%)',
    p_display_as       => 'NATIVE_NUMBER_FIELD',
    p_cSize            => 20,
    p_cMaxlength       => 5,
    p_field_template   => 'Optional - Floating Label',
    p_is_required      => 'N',
    p_item_template_options => '#DEFAULT#'
  );

  -- P30_TRIAL_COUNT — number of trials
  APEX_APPLICATION_PAGE_ITEMS.CREATE_PAGE_ITEM(
    p_application_id   => v_app_id,
    p_page_id          => 30,
    p_name             => 'P30_TRIAL_COUNT',
    p_item_sequence    => 50,
    p_item_plug_id     => (SELECT REGION_ID FROM APEX_APPLICATION_PAGE_REGIONS WHERE APPLICATION_ID = v_app_id AND PAGE_ID = 30 AND REGION_NAME = 'Shock Parameters'),
    p_item_default     => '1000',
    p_prompt           => '🎲 Number of Trials',
    p_display_as       => 'NATIVE_SELECT_LIST',
    p_lov              => 'STATIC:100;100,500;500,1000;1000,5000;5000',
    p_field_template   => 'Optional - Floating Label',
    p_is_required      => 'N',
    p_item_template_options => '#DEFAULT#'
  );

  -- P30_SCENARIO_ID — Hidden output
  APEX_APPLICATION_PAGE_ITEMS.CREATE_PAGE_ITEM(
    p_application_id   => v_app_id,
    p_page_id          => 30,
    p_name             => 'P30_SCENARIO_ID',
    p_item_sequence    => 60,
    p_item_plug_id     => (SELECT REGION_ID FROM APEX_APPLICATION_PAGE_REGIONS WHERE APPLICATION_ID = v_app_id AND PAGE_ID = 30 AND REGION_NAME = 'Shock Parameters'),
    p_prompt           => 'Scenario ID',
    p_display_as       => 'NATIVE_HIDDEN',
    p_is_required      => 'N'
  );
END;
/

-- ============================================================
-- PROCESS: Run Monte Carlo Simulation
-- ============================================================
DECLARE
  v_app_id NUMBER;
BEGIN
  SELECT APPLICATION_ID INTO v_app_id
    FROM APEX_APPLICATIONS WHERE ALIAS = 'MPPMS' AND ROWNUM = 1;

  APEX_APPLICATION_PAGE_PROCESSES.CREATE_PAGE_PROCESS(
    p_application_id    => v_app_id,
    p_page_id           => 30,
    p_process_sequence  => 10,
    p_process_point     => 'AFTER_SUBMIT',
    p_process_type      => 'NATIVE_PLSQL',
    p_process_name      => 'Run Monte Carlo Simulation',
    p_process_sql_clob  => '
DECLARE
  v_scenario_id NUMBER;
  v_status      VARCHAR2(20);
  v_message     VARCHAR2(1000);
BEGIN
  PKG_DIGITAL_TWIN.RUN_FULL_CHAIN_SIMULATION(
    p_scenario_name    => :P30_SCENARIO_NAME,
    p_shipping_delay   => NVL(:P30_SHIPPING_DELAY, 0),
    p_tariff_spike_pct => NVL(:P30_TARIFF_SPIKE, 0),
    p_demand_surge_pct => NVL(:P30_DEMAND_SURGE, 0),
    p_trial_count      => NVL(:P30_TRIAL_COUNT, 1000),
    p_scenario_id      => v_scenario_id,
    p_status           => v_status,
    p_message          => v_message
  );
  :P30_SCENARIO_ID := v_scenario_id;
  IF v_status = ''ERROR'' THEN
    APEX_ERROR.ADD_ERROR(p_message => v_message, p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
  ELSE
    APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := ''✅ '' || v_message;
  END IF;
END;',
    p_when_button_pressed => 'RUN_SIMULATION'
  );
END;
/

-- ============================================================
-- REGION 2: Heatmap Results Report
-- ============================================================
DECLARE
  v_app_id NUMBER;
BEGIN
  SELECT APPLICATION_ID INTO v_app_id
    FROM APEX_APPLICATIONS WHERE ALIAS = 'MPPMS' AND ROWNUM = 1;

  APEX_APPLICATION_PAGE_REGIONS.CREATE_REGION(
    p_application_id     => v_app_id,
    p_page_id            => 30,
    p_region_name        => 'Material Risk Heatmap',
    p_region_template    => 'Standard',
    p_display_sequence   => 30,
    p_region_type        => 'NATIVE_IR',
    p_region_source      => '
SELECT
  RISK_LEVEL,
  MATERIAL_CODE,
  MATERIAL_NAME,
  ROUND(CURRENT_STOCK_QTY, 2)       AS CURRENT_STOCK,
  ROUND(ADJUSTED_DEMAND_QTY, 2)     AS ADJUSTED_DEMAND,
  ROUND(EFFECTIVE_LEAD_DAYS, 1)     AS EFFECTIVE_LEAD_DAYS,
  ROUND(STOCKOUT_RISK_PCT, 1) || ''%'' AS STOCKOUT_RISK,
  ''₹'' || TO_CHAR(ROUND(FINANCIAL_EXPOSURE_INR,0),''999,999,999'') AS FINANCIAL_EXPOSURE_INR,
  RECOMMENDATION
FROM SIMULATION_RESULT_HEATMAP
WHERE SCENARIO_ID = :P30_SCENARIO_ID
ORDER BY STOCKOUT_RISK_PCT DESC',
    p_ajax_enabled          => 'Y',
    p_query_row_template    => 1,
    p_query_num_rows        => 25
  );
END;
/

PROMPT [SUCCESS] APEX Digital Twin Page 30 created.
PROMPT ============================================================
PROMPT  Phase 12 :: APEX Digital Twin Page COMPLETE
PROMPT ============================================================
