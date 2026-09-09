-- ============================================================
-- MPPMS :: 12_apex_workspace_setup.sql
-- Purpose : Create APEX Workspace mapped to MPPMS schema
-- Run As  : SYS AS SYSDBA connected to FREEPDB1
-- ============================================================
SET ECHO ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: APEX Workspace Setup
PROMPT ============================================================

-- Step 1: Create APEX Workspace named MPPMS if not exists
DECLARE
    v_workspace_id NUMBER;
BEGIN
    SELECT workspace_id INTO v_workspace_id
      FROM apex_workspaces
     WHERE workspace = 'MPPMS';
    
    DBMS_OUTPUT.PUT_LINE('[INFO] Workspace MPPMS already exists (ID: ' || v_workspace_id || ').');
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        APEX_INSTANCE_ADMIN.ADD_WORKSPACE(
            p_workspace      => 'MPPMS',
            p_primary_schema => 'MPPMS'
        );
        DBMS_OUTPUT.PUT_LINE('[OK] Workspace MPPMS created.');
END;
/

-- Step 2: Set Security Group ID context and Create Admin Users
DECLARE
    v_workspace_id NUMBER;
BEGIN
    SELECT workspace_id INTO v_workspace_id
      FROM apex_workspaces
     WHERE workspace = 'MPPMS';

    -- Set security group ID for APEX_UTIL user management
    APEX_UTIL.SET_SECURITY_GROUP_ID(p_security_group_id => v_workspace_id);

    -- Create workspace admin (MPPMS_ADMIN)
    IF NOT APEX_UTIL.IS_USERNAME_UNIQUE(p_username => 'MPPMS_ADMIN') THEN
        DBMS_OUTPUT.PUT_LINE('[INFO] User MPPMS_ADMIN already exists.');
    ELSE
        APEX_UTIL.CREATE_USER(
            p_user_name                    => 'MPPMS_ADMIN',
            p_email_address                => 'admin@mppms.local',
            p_web_password                 => 'Admin#2026',
            p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
            p_change_password_on_first_use => 'N'
        );
        DBMS_OUTPUT.PUT_LINE('[OK] User MPPMS_ADMIN created.');
    END IF;

    -- Create planner user
    IF NOT APEX_UTIL.IS_USERNAME_UNIQUE(p_username => 'PLANNER01') THEN
        DBMS_OUTPUT.PUT_LINE('[INFO] User PLANNER01 already exists.');
    ELSE
        APEX_UTIL.CREATE_USER(
            p_user_name                    => 'PLANNER01',
            p_email_address                => 'planner01@mppms.local',
            p_web_password                 => 'Planner#2026',
            p_developer_privs              => '',
            p_change_password_on_first_use => 'N'
        );
        DBMS_OUTPUT.PUT_LINE('[OK] User PLANNER01 created.');
    END IF;

    -- Create buyer user
    IF NOT APEX_UTIL.IS_USERNAME_UNIQUE(p_username => 'BUYER01') THEN
        DBMS_OUTPUT.PUT_LINE('[INFO] User BUYER01 already exists.');
    ELSE
        APEX_UTIL.CREATE_USER(
            p_user_name                    => 'BUYER01',
            p_email_address                => 'buyer01@mppms.local',
            p_web_password                 => 'Buyer#2026',
            p_developer_privs              => '',
            p_change_password_on_first_use => 'N'
        );
        DBMS_OUTPUT.PUT_LINE('[OK] User BUYER01 created.');
    END IF;

    COMMIT;
END;
/

PROMPT 
PROMPT ============================================================
PROMPT  Verification: APEX Workspace & Users
PROMPT ============================================================
SELECT workspace_id, workspace, primary_schema
FROM apex_workspaces
WHERE workspace = 'MPPMS';

SELECT user_name, email, is_admin, account_locked
FROM apex_workspace_apex_users
WHERE workspace_name = 'MPPMS';

PROMPT 
PROMPT ============================================================
PROMPT  [SUCCESS] APEX Workspace Setup Complete
PROMPT  Workspace  : MPPMS
PROMPT  Schema     : MPPMS
PROMPT  Admin User : MPPMS_ADMIN / Admin#2026
PROMPT ============================================================
