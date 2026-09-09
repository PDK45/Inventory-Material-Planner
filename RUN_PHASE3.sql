-- MPPMS :: RUN_PHASE3.sql
-- Master runner for Phase 3 Sample Data
-- Run As: MPPMS user on FREEPDB1
PROMPT ============================================================
PROMPT  MPPMS :: Phase 3 - Loading All Sample Data
PROMPT ============================================================
@@06_sample_data_part1.sql
@@06_sample_data_part2.sql
@@06_sample_data_part3.sql
PROMPT [SUCCESS] All Phase 3 seed data loaded.
