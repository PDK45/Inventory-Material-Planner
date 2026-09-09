-- ============================================================
-- MPPMS :: RUN_PHASE12.sql
-- Master runner for Phase 12: Digital Twin + Smart Sourcing
-- Run As: MPPMS user on FREEPDB1
-- ============================================================
PROMPT ============================================================
PROMPT  MPPMS :: Running Phase 12 Build
PROMPT ============================================================

@@48_digital_twin_tables.sql
@@49_pkg_digital_twin.sql
@@50_smart_sourcing_tables.sql
@@51_pkg_smart_sourcing.sql
@@52_phase12_ords_endpoints.sql

PROMPT ============================================================
PROMPT  Phase 12 :: ALL OBJECTS CREATED SUCCESSFULLY
PROMPT ============================================================
PROMPT  Digital Twin Tables:   SIMULATION_SCENARIO, SIMULATION_TRIAL, SIMULATION_RESULT_HEATMAP
PROMPT  Smart Sourcing Tables: SOURCING_OPTIMISATION, SOURCING_ALLOCATION, SOURCING_EXCHANGE_RATE
PROMPT  Packages:              PKG_DIGITAL_TWIN, PKG_SMART_SOURCING
PROMPT  ORDS Modules:          /digital-twin/, /smart-sourcing/
PROMPT ============================================================
