-- ============================================================
-- MPPMS :: MASTER_BUILD.sql
-- Complete build runner - all phases in order
-- Run STEP 1 as SYS AS SYSDBA, then STEP 2 as MPPMS
-- ============================================================

/*
STEP 1 — Run as SYSDBA:
  sqlplus sys/your_password@FREEPDB1 as sysdba
  @"d:\Apex download\MPPMS\01_create_user.sql"
  @"d:\Apex download\MPPMS\12_apex_workspace_setup.sql"

STEP 2 — Run as MPPMS:
  sqlplus mppms/"MPPMS#2026Secure"@FREEPDB1
  @"d:\Apex download\MPPMS\MASTER_BUILD.sql"
*/

SET DEFINE OFF
PROMPT ============================================================
PROMPT  MPPMS :: FULL DATABASE BUILD (Run as MPPMS user)
PROMPT ============================================================
PROMPT Phase 1+2: Schema Objects
@02_create_tables.sql
@03_sequences.sql
@04_triggers.sql
@05_indexes.sql

PROMPT Phase 3: Sample Data
@06_sample_data_part1.sql
@06_sample_data_part2.sql
@06_sample_data_part3.sql

PROMPT Phase 13: Inventory Management & Goods Movement
@20_inventory_tables.sql
@21_pkg_inventory.sql
@22_inventory_views_and_data.sql

PROMPT Phase 14: Oracle EBS Integration & Receiver Goods Bills
@31_create_ebs_mock_tables.sql
@32_pkg_ebs_sync.sql
@24b_receiver_goods_bill.sql

PROMPT Phase 15: Voice Command ORDS Endpoints
@33_voice_command_apex.sql

PROMPT Phase 4: PL/SQL Packages
@07_pkg_bom_breakdown.sql
@08_pkg_mrp_engine.sql
@09_pkg_procurement.sql
@10_pkg_dashboard.sql

PROMPT Phase 5: Views
@11_views.sql

PROMPT Phase 12: Run Tests
@19_testing_validation.sql

PROMPT 
PROMPT ============================================================
PROMPT  BUILD COMPLETE
PROMPT  MPPMS Database layer is ready.
PROMPT  Next: Log into APEX and follow 13_apex_app_build_guide.md
PROMPT ============================================================
