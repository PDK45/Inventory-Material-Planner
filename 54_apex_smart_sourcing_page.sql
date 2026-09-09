-- ============================================================
-- MPPMS :: 54_apex_smart_sourcing_page.sql
-- Phase 12: Oracle APEX Page — Smart Sourcing Optimizer
-- Creates Page 31 in the MPPMS APEX application
-- Run As: MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS Phase 12 :: Building APEX Smart Sourcing Page (Page 31)
PROMPT ============================================================

DECLARE
  v_app_id  NUMBER;
  v_page_id NUMBER := 31;
BEGIN
  SELECT APPLICATION_ID INTO v_app_id
    FROM APEX_APPLICATIONS WHERE ALIAS = 'MPPMS' AND ROWNUM = 1;

  APEX_APPLICATION_PAGE.CREATE_PAGE(
    p_application_id  => v_app_id,
    p_page_id         => v_page_id,
    p_name            => 'Smart Sourcing Optimizer',
    p_alias           => 'SMART-SOURCING',
    p_page_mode       => 'NORMAL',
    p_step_title      => 'Smart Sourcing Optimizer',
    p_step_sub_title  => 'Autonomous Multi-Vendor Split Allocation Engine'
  );
END;
/

-- ============================================================
-- REGION 1: Optimisation Parameters
-- ============================================================
DECLARE
  v_app_id NUMBER;
BEGIN
  SELECT APPLICATION_ID INTO v_app_id
    FROM APEX_APPLICATIONS WHERE ALIAS = 'MPPMS' AND ROWNUM = 1;

  APEX_APPLICATION_PAGE_REGIONS.CREATE_REGION(
    p_application_id   => v_app_id,
    p_page_id          => 31,
    p_region_name      => 'Optimisation Parameters',
    p_region_template  => 'Standard',
    p_display_sequence => 10,
    p_region_type      => 'STATIC_CONTENT'
  );
END;
/

-- Page Items: Material, Qty, Strategy
DECLARE
  v_app_id NUMBER;
  v_plug_id NUMBER;
BEGIN
  SELECT APPLICATION_ID INTO v_app_id
    FROM APEX_APPLICATIONS WHERE ALIAS = 'MPPMS' AND ROWNUM = 1;

  SELECT REGION_ID INTO v_plug_id
    FROM APEX_APPLICATION_PAGE_REGIONS
   WHERE APPLICATION_ID = v_app_id AND PAGE_ID = 31 AND REGION_NAME = 'Optimisation Parameters';

  -- P31_MATERIAL_ID — LOV from MATERIAL_MASTER
  APEX_APPLICATION_PAGE_ITEMS.CREATE_PAGE_ITEM(
    p_application_id   => v_app_id,
    p_page_id          => 31,
    p_name             => 'P31_MATERIAL_ID',
    p_item_sequence    => 10,
    p_item_plug_id     => v_plug_id,
    p_prompt           => 'Material SKU',
    p_display_as       => 'NATIVE_SELECT_LIST',
    p_lov              => 'SELECT MATERIAL_NAME || '' ('' || MATERIAL_CODE || '')'' d, MATERIAL_ID r FROM MATERIAL_MASTER WHERE STATUS = ''ACTIVE'' ORDER BY MATERIAL_NAME',
    p_lov_display_null => 'YES',
    p_lov_null_text    => '-- Select Material --',
    p_field_template   => 'Required - Floating Label',
    p_is_required      => 'Y',
    p_item_template_options => '#DEFAULT#'
  );

  -- P31_REQUIRED_QTY
  APEX_APPLICATION_PAGE_ITEMS.CREATE_PAGE_ITEM(
    p_application_id   => v_app_id,
    p_page_id          => 31,
    p_name             => 'P31_REQUIRED_QTY',
    p_item_sequence    => 20,
    p_item_plug_id     => v_plug_id,
    p_prompt           => 'Required Quantity',
    p_display_as       => 'NATIVE_NUMBER_FIELD',
    p_cSize            => 20,
    p_field_template   => 'Required - Floating Label',
    p_is_required      => 'Y',
    p_item_template_options => '#DEFAULT#'
  );

  -- P31_STRATEGY — radio group
  APEX_APPLICATION_PAGE_ITEMS.CREATE_PAGE_ITEM(
    p_application_id   => v_app_id,
    p_page_id          => 31,
    p_name             => 'P31_STRATEGY',
    p_item_sequence    => 30,
    p_item_plug_id     => v_plug_id,
    p_item_default     => 'BALANCED_RISK',
    p_prompt           => 'Optimisation Strategy',
    p_display_as       => 'NATIVE_RADIOGROUP',
    p_lov              => 'STATIC:💰 Lowest Cost;LOWEST_COST,🚚 Fastest Delivery;FASTEST_DELIVERY,⚖️ Balanced Risk;BALANCED_RISK',
    p_field_template   => 'Required - Floating Label',
    p_is_required      => 'Y',
    p_item_template_options => '#DEFAULT#'
  );

  -- P31_OPTIMISATION_ID — hidden output
  APEX_APPLICATION_PAGE_ITEMS.CREATE_PAGE_ITEM(
    p_application_id   => v_app_id,
    p_page_id          => 31,
    p_name             => 'P31_OPTIMISATION_ID',
    p_item_sequence    => 40,
    p_item_plug_id     => v_plug_id,
    p_prompt           => 'Optimisation ID',
    p_display_as       => 'NATIVE_HIDDEN',
    p_is_required      => 'N'
  );
END;
/

-- ============================================================
-- PROCESS: Run Optimisation
-- ============================================================
DECLARE
  v_app_id NUMBER;
BEGIN
  SELECT APPLICATION_ID INTO v_app_id
    FROM APEX_APPLICATIONS WHERE ALIAS = 'MPPMS' AND ROWNUM = 1;

  APEX_APPLICATION_PAGE_PROCESSES.CREATE_PAGE_PROCESS(
    p_application_id    => v_app_id,
    p_page_id           => 31,
    p_process_sequence  => 10,
    p_process_point     => 'AFTER_SUBMIT',
    p_process_type      => 'NATIVE_PLSQL',
    p_process_name      => 'Run Smart Sourcing Optimisation',
    p_process_sql_clob  => '
DECLARE
  v_opt_id  NUMBER;
  v_status  VARCHAR2(20);
  v_message VARCHAR2(1000);
BEGIN
  PKG_SMART_SOURCING.OPTIMISE_SOURCING(
    p_material_id     => :P31_MATERIAL_ID,
    p_required_qty    => :P31_REQUIRED_QTY,
    p_strategy        => NVL(:P31_STRATEGY, ''BALANCED_RISK''),
    p_pr_id           => NULL,
    p_optimisation_id => v_opt_id,
    p_status          => v_status,
    p_message         => v_message
  );
  :P31_OPTIMISATION_ID := v_opt_id;
  IF v_status = ''ERROR'' THEN
    APEX_ERROR.ADD_ERROR(p_message => v_message, p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
  ELSE
    APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := ''✅ '' || v_message;
  END IF;
END;',
    p_when_button_pressed => 'OPTIMISE'
  );
END;
/

-- ============================================================
-- PROCESS: Accept Split and Generate POs
-- ============================================================
DECLARE
  v_app_id NUMBER;
BEGIN
  SELECT APPLICATION_ID INTO v_app_id
    FROM APEX_APPLICATIONS WHERE ALIAS = 'MPPMS' AND ROWNUM = 1;

  APEX_APPLICATION_PAGE_PROCESSES.CREATE_PAGE_PROCESS(
    p_application_id    => v_app_id,
    p_page_id           => 31,
    p_process_sequence  => 20,
    p_process_point     => 'AFTER_SUBMIT',
    p_process_type      => 'NATIVE_PLSQL',
    p_process_name      => 'Accept Sourcing Split',
    p_process_sql_clob  => '
DECLARE
  v_status  VARCHAR2(20);
  v_message VARCHAR2(1000);
BEGIN
  PKG_SMART_SOURCING.ACCEPT_SPLIT(
    p_optimisation_id => :P31_OPTIMISATION_ID,
    p_accepted_by     => :APP_USER,
    p_status          => v_status,
    p_message         => v_message
  );
  IF v_status = ''ERROR'' THEN
    APEX_ERROR.ADD_ERROR(p_message => v_message, p_display_location => APEX_ERROR.C_INLINE_IN_NOTIFICATION);
  ELSE
    APEX_APPLICATION.G_PRINT_SUCCESS_MESSAGE := ''🎉 '' || v_message;
  END IF;
END;',
    p_when_button_pressed => 'ACCEPT_SPLIT'
  );
END;
/

-- ============================================================
-- REGION 2: Allocation Results Report (Interactive Report)
-- ============================================================
DECLARE
  v_app_id NUMBER;
BEGIN
  SELECT APPLICATION_ID INTO v_app_id
    FROM APEX_APPLICATIONS WHERE ALIAS = 'MPPMS' AND ROWNUM = 1;

  APEX_APPLICATION_PAGE_REGIONS.CREATE_REGION(
    p_application_id     => v_app_id,
    p_page_id            => 31,
    p_region_name        => 'Recommended Vendor Split',
    p_region_template    => 'Standard',
    p_display_sequence   => 30,
    p_region_type        => 'NATIVE_IR',
    p_region_source      => '
SELECT
  SUPPLIER_CODE,
  SUPPLIER_NAME,
  CASE ASL_RANK WHEN 1 THEN ''⭐ Rank 1'' WHEN 2 THEN ''⭐⭐ Rank 2'' ELSE ''Rank '' || ASL_RANK END AS ASL_RANK,
  TO_CHAR(ALLOCATION_PCT,''990.00'') || ''%'' AS ALLOCATION_PCT,
  ROUND(ALLOCATED_QTY, 3)     AS ALLOCATED_QTY,
  UNIT_PRICE || '' '' || CURRENCY AS CONTRACT_PRICE,
  CURRENCY,
  ''₹'' || TO_CHAR(ROUND(LINE_TOTAL_INR,0),''999,999,999'') AS LINE_TOTAL_INR,
  EXPECTED_DELIVERY_DAYS || '' days'' AS LEAD_TIME,
  EXPECTED_DELIVERY_DATE,
  ROUND(COST_SCORE, 1)        AS COST_SCORE,
  ROUND(DELIVERY_SCORE, 1)    AS DELIVERY_SCORE,
  ROUND(QUALITY_SCORE, 1)     AS QUALITY_SCORE,
  ROUND(CURRENCY_SCORE, 1)    AS CURRENCY_SCORE,
  ROUND(COMPOSITE_SCORE, 1)   AS COMPOSITE_SCORE
FROM SOURCING_ALLOCATION
WHERE OPTIMISATION_ID = :P31_OPTIMISATION_ID
ORDER BY ALLOCATION_PCT DESC',
    p_ajax_enabled       => 'Y',
    p_query_num_rows     => 25
  );
END;
/

-- ============================================================
-- REGION 3: Optimisation Summary KPIs (Static HTML + PL/SQL)
-- ============================================================
DECLARE
  v_app_id NUMBER;
BEGIN
  SELECT APPLICATION_ID INTO v_app_id
    FROM APEX_APPLICATIONS WHERE ALIAS = 'MPPMS' AND ROWNUM = 1;

  APEX_APPLICATION_PAGE_REGIONS.CREATE_REGION(
    p_application_id   => v_app_id,
    p_page_id          => 31,
    p_region_name      => 'Optimisation Summary',
    p_region_template  => 'Standard',
    p_display_sequence => 20,
    p_region_type      => 'NATIVE_PLSQL_DYNAMIC_CONTENT',
    p_region_source    => '
DECLARE
  v_score   NUMBER := 0;
  v_vendors NUMBER := 0;
  v_inr     NUMBER := 0;
  v_sar     NUMBER := 0;
  v_usd     NUMBER := 0;
  v_strat   VARCHAR2(20) := ''—'';
  v_del     VARCHAR2(30) := ''—'';
BEGIN
  IF :P31_OPTIMISATION_ID IS NOT NULL THEN
    SELECT OPTIMISATION_SCORE, VENDOR_COUNT,
           NVL(TOTAL_BLENDED_COST_INR,0), NVL(TOTAL_BLENDED_COST_SAR,0), NVL(TOTAL_BLENDED_COST_USD,0),
           STRATEGY, TO_CHAR(EXPECTED_DELIVERY_DATE,''DD-Mon-YYYY'')
      INTO v_score, v_vendors, v_inr, v_sar, v_usd, v_strat, v_del
      FROM SOURCING_OPTIMISATION
     WHERE OPTIMISATION_ID = :P31_OPTIMISATION_ID;
  END IF;

  HTP.P(''<div class="apex-kpi-row" style="display:flex;gap:20px;flex-wrap:wrap;margin-bottom:16px;">'');
  HTP.P(''<div class="apex-kpi-card"><span class="kpi-label">Strategy</span><span class="kpi-value">'' || v_strat || ''</span></div>'');
  HTP.P(''<div class="apex-kpi-card"><span class="kpi-label">Vendors in Split</span><span class="kpi-value">'' || v_vendors || ''</span></div>'');
  HTP.P(''<div class="apex-kpi-card"><span class="kpi-label">Composite Score</span><span class="kpi-value">'' || v_score || '' / 100</span></div>'');
  HTP.P(''<div class="apex-kpi-card"><span class="kpi-label">Blended Cost (INR)</span><span class="kpi-value">₹'' || TO_CHAR(ROUND(v_inr,0),''999,999,999'') || ''</span></div>'');
  HTP.P(''<div class="apex-kpi-card"><span class="kpi-label">Blended Cost (SAR)</span><span class="kpi-value">ر.س '' || TO_CHAR(ROUND(v_sar,0),''999,999'') || ''</span></div>'');
  HTP.P(''<div class="apex-kpi-card"><span class="kpi-label">Expected Delivery</span><span class="kpi-value">'' || v_del || ''</span></div>'');
  HTP.P(''</div>'');
END;'
  );
END;
/

PROMPT [SUCCESS] APEX Smart Sourcing Page 31 created.
PROMPT ============================================================
PROMPT  Phase 12 :: APEX Smart Sourcing Page COMPLETE
PROMPT ============================================================
