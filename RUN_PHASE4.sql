-- ============================================================
-- MPPMS :: RUN_PHASE4.sql
-- Master runner for Phase 4 - PL/SQL Packages
-- Run As: MPPMS user on FREEPDB1
-- ============================================================
PROMPT ============================================================
PROMPT  MPPMS :: Phase 4 - Compiling PL/SQL Packages
PROMPT ============================================================

@@07_pkg_bom_breakdown.sql
@@08_pkg_mrp_engine.sql
@@09_pkg_procurement.sql
@@10_pkg_dashboard.sql

PROMPT 
PROMPT ============================================================
PROMPT  Verification: Package Compilation Status
PROMPT ============================================================
SELECT object_name, object_type, status, last_ddl_time
FROM user_objects
WHERE object_type IN ('PACKAGE','PACKAGE BODY')
ORDER BY object_name, object_type;

PROMPT 
PROMPT ============================================================
PROMPT  PHASE 4 COMPLETE
PROMPT  Packages created:
PROMPT    - PKG_BOM_BREAKDOWN  (BOM breakdown engine)
PROMPT    - PKG_MRP_ENGINE     (MRP calculation + shortage detection)
PROMPT    - PKG_PROCUREMENT    (PR/PO generation + approval workflows)
PROMPT    - PKG_DASHBOARD      (KPI functions for dashboard)
PROMPT
PROMPT  Quick Smoke Test (paste & run to verify):
PROMPT  SELECT PKG_DASHBOARD.GET_OPEN_PR_COUNT FROM DUAL;
PROMPT  SELECT PKG_DASHBOARD.GET_SHORTAGE_COUNT FROM DUAL;
PROMPT  Next Step: Run 11_views.sql (Phase 5)
PROMPT ============================================================
