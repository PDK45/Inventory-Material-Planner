-- ============================================================
-- MPPMS :: 07_pkg_bom_breakdown.sql
-- Package: PKG_BOM_BREAKDOWN
-- Purpose: BOM breakdown and structure retrieval
-- Run As : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Creating PKG_BOM_BREAKDOWN
PROMPT ============================================================

-- ============================================================
-- PACKAGE SPECIFICATION
-- ============================================================
CREATE OR REPLACE PACKAGE PKG_BOM_BREAKDOWN AS

    -- Record type for BOM breakdown result
    TYPE T_BOM_LINE IS RECORD (
        MATERIAL_ID       MATERIAL_MASTER.MATERIAL_ID%TYPE,
        MATERIAL_CODE     MATERIAL_MASTER.MATERIAL_CODE%TYPE,
        MATERIAL_NAME     MATERIAL_MASTER.MATERIAL_NAME%TYPE,
        UNIT_OF_MEASURE   MATERIAL_MASTER.UNIT_OF_MEASURE%TYPE,
        QUANTITY_REQUIRED BOM_DETAILS.QUANTITY_REQUIRED%TYPE,
        TOTAL_QTY         NUMBER,
        STANDARD_COST     MATERIAL_MASTER.STANDARD_COST%TYPE,
        TOTAL_COST        NUMBER,
        CATEGORY          MATERIAL_MASTER.CATEGORY%TYPE,
        LEAD_TIME         MATERIAL_MASTER.LEAD_TIME%TYPE,
        PREFERRED_SUPPLIER_ID MATERIAL_MASTER.PREFERRED_SUPPLIER_ID%TYPE
    );

    TYPE T_BOM_TABLE IS TABLE OF T_BOM_LINE;

    -- Breakdown BOM for a product at a given production quantity
    -- Returns flat list of all materials with total quantities
    FUNCTION BREAKDOWN_BOM (
        p_product_id IN NUMBER,
        p_qty        IN NUMBER DEFAULT 1,
        p_version    IN VARCHAR2 DEFAULT NULL
    ) RETURN T_BOM_TABLE PIPELINED;

    -- Get active BOM ID for a product
    FUNCTION GET_ACTIVE_BOM_ID (
        p_product_id IN NUMBER
    ) RETURN NUMBER;

    -- Validate BOM exists for product
    FUNCTION BOM_EXISTS (
        p_product_id IN NUMBER
    ) RETURN BOOLEAN;

    -- Get total material cost for a production quantity
    FUNCTION GET_BOM_MATERIAL_COST (
        p_product_id IN NUMBER,
        p_qty        IN NUMBER DEFAULT 1
    ) RETURN NUMBER;

END PKG_BOM_BREAKDOWN;
/
SHOW ERRORS PACKAGE PKG_BOM_BREAKDOWN;

-- ============================================================
-- PACKAGE BODY
-- ============================================================
CREATE OR REPLACE PACKAGE BODY PKG_BOM_BREAKDOWN AS

    -- --------------------------------------------------------
    -- Get Active BOM ID for a product
    -- --------------------------------------------------------
    FUNCTION GET_ACTIVE_BOM_ID (
        p_product_id IN NUMBER
    ) RETURN NUMBER IS
        v_bom_id BOM_MASTER.BOM_ID%TYPE;
    BEGIN
        SELECT BOM_ID
          INTO v_bom_id
          FROM BOM_MASTER
         WHERE PRODUCT_ID = p_product_id
           AND STATUS     = 'ACTIVE'
           AND EFFECTIVE_DATE <= SYSDATE
         ORDER BY EFFECTIVE_DATE DESC
         FETCH FIRST 1 ROW ONLY;

        RETURN v_bom_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END GET_ACTIVE_BOM_ID;

    -- --------------------------------------------------------
    -- Check if active BOM exists for a product
    -- --------------------------------------------------------
    FUNCTION BOM_EXISTS (
        p_product_id IN NUMBER
    ) RETURN BOOLEAN IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*)
          INTO v_count
          FROM BOM_MASTER
         WHERE PRODUCT_ID = p_product_id
           AND STATUS     = 'ACTIVE';

        RETURN (v_count > 0);
    END BOM_EXISTS;

    -- --------------------------------------------------------
    -- Breakdown BOM - returns pipelined result set
    -- This is the core function consumed by MRP engine
    -- --------------------------------------------------------
    FUNCTION BREAKDOWN_BOM (
        p_product_id IN NUMBER,
        p_qty        IN NUMBER DEFAULT 1,
        p_version    IN VARCHAR2 DEFAULT NULL
    ) RETURN T_BOM_TABLE PIPELINED IS

        v_bom_id   BOM_MASTER.BOM_ID%TYPE;
        v_line     T_BOM_LINE;

        CURSOR c_bom_lines (p_bom_id IN NUMBER) IS
            SELECT
                m.MATERIAL_ID,
                m.MATERIAL_CODE,
                m.MATERIAL_NAME,
                m.UNIT_OF_MEASURE,
                bd.QUANTITY_REQUIRED,
                bd.QUANTITY_REQUIRED * p_qty      AS TOTAL_QTY,
                m.STANDARD_COST,
                (bd.QUANTITY_REQUIRED * p_qty)
                    * m.STANDARD_COST             AS TOTAL_COST,
                m.CATEGORY,
                m.LEAD_TIME,
                m.PREFERRED_SUPPLIER_ID
            FROM BOM_DETAILS    bd
            JOIN MATERIAL_MASTER m ON m.MATERIAL_ID = bd.MATERIAL_ID
            WHERE bd.BOM_ID = p_bom_id
              AND m.STATUS  = 'ACTIVE'
            ORDER BY m.CATEGORY, m.MATERIAL_CODE;

    BEGIN
        -- Input validation
        IF p_product_id IS NULL OR p_qty <= 0 THEN
            RETURN;
        END IF;

        -- Resolve BOM ID
        IF p_version IS NOT NULL THEN
            BEGIN
                SELECT BOM_ID INTO v_bom_id
                  FROM BOM_MASTER
                 WHERE PRODUCT_ID = p_product_id
                   AND VERSION    = p_version
                   AND STATUS     = 'ACTIVE';
            EXCEPTION
                WHEN NO_DATA_FOUND THEN RETURN;
            END;
        ELSE
            v_bom_id := GET_ACTIVE_BOM_ID(p_product_id);
            IF v_bom_id IS NULL THEN RETURN; END IF;
        END IF;

        -- Pipe each BOM line
        FOR r IN c_bom_lines(v_bom_id) LOOP
            v_line.MATERIAL_ID           := r.MATERIAL_ID;
            v_line.MATERIAL_CODE         := r.MATERIAL_CODE;
            v_line.MATERIAL_NAME         := r.MATERIAL_NAME;
            v_line.UNIT_OF_MEASURE       := r.UNIT_OF_MEASURE;
            v_line.QUANTITY_REQUIRED     := r.QUANTITY_REQUIRED;
            v_line.TOTAL_QTY             := r.TOTAL_QTY;
            v_line.STANDARD_COST         := r.STANDARD_COST;
            v_line.TOTAL_COST            := r.TOTAL_COST;
            v_line.CATEGORY              := r.CATEGORY;
            v_line.LEAD_TIME             := r.LEAD_TIME;
            v_line.PREFERRED_SUPPLIER_ID := r.PREFERRED_SUPPLIER_ID;
            PIPE ROW(v_line);
        END LOOP;

    EXCEPTION
        WHEN OTHERS THEN
            -- Log error and return empty result rather than crashing
            DBMS_OUTPUT.PUT_LINE('PKG_BOM_BREAKDOWN.BREAKDOWN_BOM Error: ' || SQLERRM);
            RETURN;
    END BREAKDOWN_BOM;

    -- --------------------------------------------------------
    -- Get total material cost for a given production qty
    -- --------------------------------------------------------
    FUNCTION GET_BOM_MATERIAL_COST (
        p_product_id IN NUMBER,
        p_qty        IN NUMBER DEFAULT 1
    ) RETURN NUMBER IS
        v_total_cost NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(TOTAL_COST), 0)
          INTO v_total_cost
          FROM TABLE(PKG_BOM_BREAKDOWN.BREAKDOWN_BOM(p_product_id, p_qty));

        RETURN v_total_cost;
    EXCEPTION
        WHEN OTHERS THEN RETURN 0;
    END GET_BOM_MATERIAL_COST;

END PKG_BOM_BREAKDOWN;
/
SHOW ERRORS PACKAGE BODY PKG_BOM_BREAKDOWN;

PROMPT [OK] PKG_BOM_BREAKDOWN created.

-- Quick sanity test (uncomment to verify after data load)
-- SELECT * FROM TABLE(PKG_BOM_BREAKDOWN.BREAKDOWN_BOM(
--     (SELECT PRODUCT_ID FROM PRODUCT_MASTER WHERE PRODUCT_CODE='PRD-2001'), 120));

PROMPT [SUCCESS] PKG_BOM_BREAKDOWN ready.
