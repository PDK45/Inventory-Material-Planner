-- ============================================================
-- MATERIAL PLANNING & PROCUREMENT MANAGEMENT SYSTEM (MPPMS)
-- Script  : 01_create_user.sql
-- Purpose : Create dedicated application schema user
-- Database: FREEPDB1 (Oracle AI Database 26ai)
-- Run As  : SYS AS SYSDBA (connected to FREEPDB1)
-- Author  : MPPMS Build Team
-- Date    : 2026-07-28
-- ============================================================
-- 
-- INSTRUCTIONS:
--   sqlplus sys/your_password@FREEPDB1 as sysdba
--   @01_create_user.sql
-- ============================================================

-- Switch to FREEPDB1 container (if connected as CDB$ROOT)
-- ALTER SESSION SET CONTAINER = FREEPDB1;

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED

PROMPT ============================================================
PROMPT  MPPMS :: Creating Application Schema User
PROMPT ============================================================

-- ------------------------------------------------------------
-- Step 1: Drop existing user if exists (clean re-install)
--         WARNING: Only run this on a fresh install
-- ------------------------------------------------------------
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM dba_users
     WHERE username = 'MPPMS';
    
    IF v_count > 0 THEN
        EXECUTE IMMEDIATE 'DROP USER MPPMS CASCADE';
        DBMS_OUTPUT.PUT_LINE('[INFO] Existing MPPMS user dropped.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[INFO] No existing MPPMS user found. Proceeding with creation.');
    END IF;
END;
/

-- ------------------------------------------------------------
-- Step 2: Create the application schema user
-- ------------------------------------------------------------
CREATE USER MPPMS
    IDENTIFIED BY "MPPMS#2026Secure"   -- Change in production
    DEFAULT TABLESPACE USERS
    TEMPORARY TABLESPACE TEMP
    PROFILE DEFAULT
    ACCOUNT UNLOCK;

PROMPT [OK] User MPPMS created.

-- ------------------------------------------------------------
-- Step 3: Grant core session & object privileges
-- ------------------------------------------------------------
GRANT CREATE SESSION         TO MPPMS;
GRANT CREATE TABLE           TO MPPMS;
GRANT CREATE VIEW            TO MPPMS;
GRANT CREATE SEQUENCE        TO MPPMS;
GRANT CREATE PROCEDURE       TO MPPMS;
GRANT CREATE TRIGGER         TO MPPMS;
GRANT CREATE SYNONYM         TO MPPMS;
GRANT CREATE TYPE            TO MPPMS;
GRANT CREATE JOB             TO MPPMS;   -- For scheduled MRP runs
GRANT UNLIMITED TABLESPACE   TO MPPMS;

PROMPT [OK] Core privileges granted.

-- ------------------------------------------------------------
-- Step 4: Grant APEX-specific privileges
-- ------------------------------------------------------------
-- Allow APEX to parse SQL in this schema
BEGIN
    APEX_UTIL.SET_WORKSPACE(p_workspace => 'MPPMS');
EXCEPTION
    WHEN OTHERS THEN
        NULL; -- Workspace may not exist yet; will be created in Phase 6
END;
/

-- Grant execute on APEX packages
GRANT EXECUTE ON APEX_INSTANCE_ADMIN TO MPPMS;

PROMPT [OK] APEX privileges granted.

-- ------------------------------------------------------------
-- Step 5: Verification
-- ------------------------------------------------------------
PROMPT 
PROMPT ============================================================
PROMPT  Verification: MPPMS User Details
PROMPT ============================================================
SELECT 
    username,
    account_status,
    default_tablespace,
    temporary_tablespace,
    created
FROM dba_users
WHERE username = 'MPPMS';

PROMPT 
PROMPT ============================================================
PROMPT  Verification: MPPMS System Privileges
PROMPT ============================================================
SELECT privilege, admin_option
FROM dba_sys_privs
WHERE grantee = 'MPPMS'
ORDER BY privilege;

PROMPT 
PROMPT ============================================================
PROMPT  [SUCCESS] MPPMS Schema User Ready
PROMPT  Next Step: Run 02_create_tables.sql as MPPMS user
PROMPT ============================================================
