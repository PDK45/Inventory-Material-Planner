-- ============================================================
-- MPPMS :: RUN_PHASE1_PHASE2.sql
-- Master runner: Execute entire Phase 1 & 2 in correct order
-- ============================================================
-- INSTRUCTIONS:
--
-- STEP 1 (as SYSDBA in FREEPDB1):
--   sqlplus sys/your_password@FREEPDB1 as sysdba
--   @01_create_user.sql
--
-- STEP 2 (as MPPMS user):
--   CONNECT mppms/"MPPMS#2026Secure"@FREEPDB1
--   @02_create_tables.sql
--   @03_sequences.sql
--   @04_triggers.sql
--   @05_indexes.sql
-- ============================================================
-- 
-- OR: Run this file as MPPMS (after user is created by SYSDBA):
--
PROMPT ============================================================
PROMPT  MPPMS :: Full Phase 1+2 Build
PROMPT ============================================================

@@02_create_tables.sql
@@03_sequences.sql
@@04_triggers.sql
@@05_indexes.sql

PROMPT 
PROMPT ============================================================
PROMPT  PHASE 1 + PHASE 2 COMPLETE
PROMPT  Database objects created:
PROMPT    - 12 Tables (fully normalized, 3NF)
PROMPT    - 14 Sequences (PKs + document numbers)
PROMPT    - 14 Triggers (BI + business logic)
PROMPT    - 33 Indexes (FK + performance)
PROMPT 
PROMPT  Next: Run 06_sample_data.sql for Phase 3
PROMPT ============================================================
