@echo off
:: MPPMS Build Runner
:: Runs all database scripts in the correct order
:: IMPORTANT: Edit the SYS_PASSWORD variable below before running

SET SYS_PASSWORD=oracle
SET MPPMS_PASSWORD=MPPMS#2026Secure
SET DB_CONN=localhost:1521/FREEPDB1
SET SCRIPT_DIR=d:\Apex download\MPPMS

echo ============================================================
echo  MPPMS :: Full Database Build
echo ============================================================

:: --- PHASE 1: Create Schema User (as SYSDBA) ---
echo.
echo [PHASE 1] Creating MPPMS schema user...
sqlplus "sys/%SYS_PASSWORD%@%DB_CONN% as sysdba" @"%SCRIPT_DIR%\01_create_user.sql"
IF %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to create MPPMS user. Check SYS_PASSWORD.
    pause
    exit /b 1
)

:: --- PHASE 1-2: Tables, Sequences, Triggers, Indexes ---
echo.
echo [PHASE 1+2] Creating tables, sequences, triggers, indexes...
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\02_create_tables.sql"
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\03_sequences.sql"
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\04_triggers.sql"
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\05_indexes.sql"

:: --- PHASE 3: Sample Data ---
echo.
echo [PHASE 3] Loading sample data...
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\06_sample_data_part1.sql"
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\06_sample_data_part2.sql"
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\06_sample_data_part3.sql"

:: --- PHASE 13: Inventory Management & Goods Movement ---
echo.
echo [PHASE 13] Creating inventory structures...
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\20_inventory_tables.sql"
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\21_pkg_inventory.sql"
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\22_inventory_views_and_data.sql"

:: --- PHASE 14: Oracle EBS Integration & Receiver Goods Bills ---
echo.
echo [PHASE 14] Creating EBS Integration & Goods Bills structures...
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\31_create_ebs_mock_tables.sql"
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\32_pkg_ebs_sync.sql"
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\24b_receiver_goods_bill.sql"

:: --- PHASE 4: PL/SQL Packages ---
echo.
echo [PHASE 4] Compiling PL/SQL packages...
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\07_pkg_bom_breakdown.sql"
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\08_pkg_mrp_engine.sql"
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\09_pkg_procurement.sql"
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\10_pkg_dashboard.sql"

:: --- PHASE 5: Views ---
echo.
echo [PHASE 5] Creating views...
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\11_views.sql"

:: --- PHASE 6: APEX Workspace ---
echo.
echo [PHASE 6] Setting up APEX workspace...
sqlplus "sys/%SYS_PASSWORD%@%DB_CONN% as sysdba" @"%SCRIPT_DIR%\12_apex_workspace_setup.sql"

:: --- PHASE 12: Validation ---
echo.
echo [PHASE 12] Running validation tests...
sqlplus "mppms/%MPPMS_PASSWORD%@%DB_CONN%" @"%SCRIPT_DIR%\19_testing_validation.sql"

echo.
echo ============================================================
echo  MPPMS DATABASE BUILD COMPLETE
echo.
echo  Next Steps:
echo  1. Open browser: http://localhost:8080/ords/
echo  2. Workspace : MPPMS
echo  3. Username  : MPPMS_ADMIN
echo  4. Password  : Admin#2026
echo  5. Follow: %SCRIPT_DIR%\13_apex_app_build_guide.md
echo ============================================================
pause
