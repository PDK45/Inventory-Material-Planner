-- ============================================================
-- MPPMS :: 33_voice_command_apex.sql
-- Purpose : Voice Command Feature — ORDS REST Endpoints
-- Adds voice/stock, voice/receipt, voice/adjust to 'api' module
-- Run As  : MPPMS user on FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Phase 15 - Voice Command ORDS Endpoints
PROMPT ============================================================

BEGIN
  -- voice/stock — GET, fuzzy material search for queries
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'voice/stock',
    p_comments    => 'Voice command: fuzzy material stock query'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'voice/stock',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_collection_feed,
    p_source      => q'[
      SELECT
          m.MATERIAL_ID,
          m.MATERIAL_CODE,
          m.MATERIAL_NAME,
          m.UNIT_OF_MEASURE          AS uom,
          NVL(SUM(s.QTY_ON_HAND),0)  AS qty_on_hand,
          NVL(SUM(s.QTY_AVAILABLE),0) AS qty_available,
          m.SAFETY_STOCK,
          MAX(s.STOCK_STATUS)        AS stock_status,
          MAX(s.WAREHOUSE_CODE)      AS warehouse_code
      FROM MATERIAL_MASTER m
      LEFT JOIN VW_INVENTORY_STOCK s ON s.MATERIAL_ID = m.MATERIAL_ID
      WHERE UPPER(m.MATERIAL_NAME) LIKE '%' || UPPER(:search) || '%'
         OR UPPER(m.MATERIAL_CODE) LIKE '%' || UPPER(:search) || '%'
      GROUP BY m.MATERIAL_ID, m.MATERIAL_CODE, m.MATERIAL_NAME,
               m.UNIT_OF_MEASURE, m.SAFETY_STOCK
      ORDER BY m.MATERIAL_CODE
      FETCH FIRST 5 ROWS ONLY
    ]'
  );

  -- voice/receipt — POST, goods receipt (MIGO 101)
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'voice/receipt',
    p_comments    => 'Voice command: goods receipt (MIGO 101)'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'voice/receipt',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'[
      DECLARE
          v_status  VARCHAR2(20);
          v_message VARCHAR2(1000);
      BEGIN
          PKG_INVENTORY.PROCESS_GOODS_RECEIPT(
              p_po_id        => :po_id,
              p_material_id  => :material_id,
              p_warehouse_id => :warehouse_id,
              p_bin_id       => :bin_id,
              p_received_qty => :quantity,
              p_performed_by => NVL(:performed_by, 'VOICE_CMD'),
              p_remarks      => NVL(:remarks, 'Posted via Voice Command'),
              p_status       => v_status,
              p_message      => v_message
          );
          :status  := v_status;
          :message := v_message;
      END;
    ]'
  );

  -- voice/adjust — POST, stock adjustment (MIGO 551)
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'voice/adjust',
    p_comments    => 'Voice command: stock adjustment (MIGO 551)'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'voice/adjust',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'[
      DECLARE
          v_status  VARCHAR2(20);
          v_message VARCHAR2(1000);
      BEGIN
          PKG_INVENTORY.PROCESS_STOCK_ADJUSTMENT(
              p_material_id     => :material_id,
              p_warehouse_id    => :warehouse_id,
              p_bin_id          => :bin_id,
              p_new_qty_on_hand => :new_quantity,
              p_performed_by    => NVL(:performed_by, 'VOICE_CMD'),
              p_remarks         => NVL(:remarks, 'Adjusted via Voice Command'),
              p_status          => v_status,
              p_message         => v_message
          );
          :status  := v_status;
          :message := v_message;
      END;
    ]'
  );

  COMMIT;
END;
/

PROMPT [OK] Voice Command ORDS endpoints registered under api/voice/*.

-- Verify
SELECT name, pattern, method
FROM   user_ords_services
WHERE  pattern LIKE 'voice/%'
ORDER BY pattern, method;
