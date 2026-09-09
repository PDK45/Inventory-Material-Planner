-- ============================================================
-- MPPMS :: 30_enable_ords_endpoints.sql
-- Purpose : Enable ORDS REST API Services for MPPMS Portal UI
-- Run As  : MPPMS user connected to FREEPDB1
-- ============================================================
SET ECHO ON
SET FEEDBACK ON
SET DEFINE OFF

PROMPT ============================================================
PROMPT  MPPMS :: Creating ORDS REST Endpoints
PROMPT ============================================================

-- Step 1: Enable ORDS Schema
BEGIN
    ORDS.enable_schema(
        p_enabled             => TRUE,
        p_schema              => 'MPPMS',
        p_url_mapping_type    => 'BASE_PATH',
        p_url_mapping_pattern => 'mppms',
        p_auto_rest_auth      => FALSE
    );
    COMMIT;
END;
/
PROMPT [OK] Schema MPPMS is REST-enabled.

-- Step 2: Delete old module if exists to prevent duplicate errors
BEGIN
    ORDS.remove_module(p_module_name => 'api');
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        NULL;
END;
/

-- Step 3: Define REST Module
BEGIN
  ORDS.define_module(
    p_module_name    => 'api',
    p_base_path      => 'api/',
    p_items_per_page => 0,
    p_status         => 'PUBLISHED',
    p_comments       => 'MPPMS Core REST API Module'
  );

  -- 1. KPI Stats
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'dashboard/stats',
    p_comments    => 'Get core KPI metrics'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'dashboard/stats',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT PKG_DASHBOARD.GET_OPEN_PR_COUNT() AS open_prs,
                             PKG_DASHBOARD.GET_OPEN_PO_COUNT() AS open_pos,
                             PKG_DASHBOARD.GET_SHORTAGE_COUNT() AS shortages,
                             PKG_DASHBOARD.GET_ACTIVE_PLAN_COUNT() AS active_plans,
                             PKG_DASHBOARD.GET_MONTHLY_PO_VALUE() AS monthly_spend
                      FROM DUAL',
    p_comments    => 'Return dashboard stats'
  );

  -- 2. Stock Balance Monitor
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'inventory/stock',
    p_comments    => 'Get inventory stock monitor list'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'inventory/stock',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT * FROM VW_INVENTORY_STOCK ORDER BY WAREHOUSE_CODE, MATERIAL_CODE',
    p_comments    => 'Return stock balances'
  );

  -- 3. PRs list
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'procurement/prs',
    p_comments    => 'Get all PRs'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'procurement/prs',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT * FROM VW_PR_DASHBOARD ORDER BY CREATED_DATE DESC',
    p_comments    => 'Return purchase requisitions'
  );

  -- 4. POs list
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'procurement/pos',
    p_comments    => 'Get all POs'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'procurement/pos',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT * FROM VW_PO_HEADER ORDER BY ORDER_DATE DESC',
    p_comments    => 'Return purchase orders'
  );

  -- 5. LOV Materials
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'lov/materials',
    p_comments    => 'Get materials list'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'lov/materials',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT MATERIAL_ID, MATERIAL_CODE, MATERIAL_NAME, UNIT_OF_MEASURE FROM MATERIAL_MASTER WHERE STATUS = ''ACTIVE'' ORDER BY MATERIAL_CODE',
    p_comments    => 'Materials list'
  );

  -- 6. LOV Warehouses
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'lov/warehouses',
    p_comments    => 'Get warehouses list'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'lov/warehouses',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT WAREHOUSE_ID, WAREHOUSE_CODE, WAREHOUSE_NAME FROM WAREHOUSE_MASTER WHERE STATUS = ''ACTIVE'' ORDER BY WAREHOUSE_CODE',
    p_comments    => 'Warehouses list'
  );

  -- 7. LOV Bins
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'lov/bins',
    p_comments    => 'Get storage bins list'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'lov/bins',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT BIN_ID, BIN_CODE, WAREHOUSE_ID FROM STORAGE_BIN ORDER BY BIN_CODE',
    p_comments    => 'Storage bins list'
  );

  -- 8. LOV Plans
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'lov/plans',
    p_comments    => 'Get active plans'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'lov/plans',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT PLAN_ID, PLAN_NAME, STATUS FROM PRODUCTION_PLAN WHERE STATUS IN (''APPROVED'',''IN_PROGRESS'') ORDER BY PLAN_ID',
    p_comments    => 'Active plans'
  );

  -- 9. Run MRP
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'mrp/calculate',
    p_comments    => 'Run MRP engine calculation'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'mrp/calculate',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => 'DECLARE
                        v_status VARCHAR2(20);
                        v_message VARCHAR2(1000);
                      BEGIN
                        PKG_MRP_ENGINE.CALCULATE_MRP(
                          p_plan_id => :plan_id,
                          p_status  => v_status,
                          p_message => v_message
                        );
                        apex_json.open_object;
                        apex_json.write(''status'', v_status);
                        apex_json.write(''message'', v_message);
                        apex_json.close_object;
                      END;',
    p_comments    => 'Calculate MRP'
  );

  -- 10. Generate PR from MRP
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'procurement/generate_pr',
    p_comments    => 'Generate PR from MRP plan shortages'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'procurement/generate_pr',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => 'DECLARE
                        v_status VARCHAR2(20);
                        v_message VARCHAR2(1000);
                        v_pr_count NUMBER;
                      BEGIN
                        PKG_PROCUREMENT.GENERATE_PR_FROM_MRP(
                          p_plan_id  => :plan_id,
                          p_user     => NVL(:user, ''REST_API''),
                          p_status   => v_status,
                          p_message  => v_message,
                          p_pr_count => v_pr_count
                        );
                        apex_json.open_object;
                        apex_json.write(''status'', v_status);
                        apex_json.write(''message'', v_message);
                        apex_json.write(''pr_count'', v_pr_count);
                        apex_json.close_object;
                      END;',
    p_comments    => 'Generate PR from MRP'
  );

  -- 11. Approve PR
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'procurement/approve_pr',
    p_comments    => 'Approve a purchase requisition'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'procurement/approve_pr',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => 'DECLARE
                        v_status VARCHAR2(20);
                        v_message VARCHAR2(1000);
                      BEGIN
                        PKG_PROCUREMENT.APPROVE_PR(
                          p_pr_id    => :pr_id,
                          p_approver => NVL(:user, ''REST_API''),
                          p_status   => v_status,
                          p_message  => v_message
                        );
                        apex_json.open_object;
                        apex_json.write(''status'', v_status);
                        apex_json.write(''message'', v_message);
                        apex_json.close_object;
                      END;',
    p_comments    => 'Approve PR'
  );

  -- 12. Recommend Supplier
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'procurement/recommend_supplier',
    p_comments    => 'Get recommended supplier'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'procurement/recommend_supplier',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT PKG_PROCUREMENT.RECOMMEND_SUPPLIER(:material_id) AS supplier_id,
                             (SELECT supplier_name FROM SUPPLIER_MASTER WHERE supplier_id = PKG_PROCUREMENT.RECOMMEND_SUPPLIER(:material_id)) AS supplier_name
                      FROM DUAL',
    p_comments    => 'Recommend supplier'
  );

  -- 13. Generate PO from PR
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'procurement/generate_po',
    p_comments    => 'Generate PO from approved PR'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'procurement/generate_po',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => 'DECLARE
                        v_po_id NUMBER;
                        v_po_num VARCHAR2(50);
                        v_status VARCHAR2(20);
                        v_message VARCHAR2(1000);
                      BEGIN
                        PKG_PROCUREMENT.GENERATE_PO_FROM_PR(
                          p_pr_id      => :pr_id,
                          p_supplier_id=> :supplier_id,
                          p_created_by => NVL(:user, ''REST_API''),
                          p_po_id      => v_po_id,
                          p_po_number  => v_po_num,
                          p_status     => v_status,
                          p_message    => v_message
                        );
                        apex_json.open_object;
                        apex_json.write(''status'', v_status);
                        apex_json.write(''message'', v_message);
                        apex_json.write(''po_id'', v_po_id);
                        apex_json.write(''po_number'', v_po_num);
                        apex_json.close_object;
                      END;',
    p_comments    => 'Generate PO from PR'
  );

  -- 14. Goods Movement (MIGO)
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'inventory/migo',
    p_comments    => 'Process MIGO goods movement'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'inventory/migo',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => 'DECLARE
                        v_status VARCHAR2(20);
                        v_message VARCHAR2(1000);
                      BEGIN
                        IF :movement_code = ''101'' THEN
                          PKG_INVENTORY.PROCESS_GOODS_RECEIPT(
                            p_po_id        => :po_id,
                            p_material_id  => :material_id,
                            p_warehouse_id => :warehouse_id,
                            p_bin_id       => :bin_id,
                            p_received_qty => :quantity,
                            p_performed_by => NVL(:user, ''REST_API''),
                            p_remarks      => :remarks,
                            p_status       => v_status,
                            p_message      => v_message
                          );
                        ELSIF :movement_code = ''261'' THEN
                          PKG_INVENTORY.PROCESS_GOODS_ISSUE(
                            p_plan_id      => :plan_id,
                            p_material_id  => :material_id,
                            p_warehouse_id => :warehouse_id,
                            p_bin_id       => :bin_id,
                            p_issue_qty    => :quantity,
                            p_performed_by => NVL(:user, ''REST_API''),
                            p_remarks      => :remarks,
                            p_status       => v_status,
                            p_message      => v_message
                          );
                        ELSIF :movement_code = ''311'' THEN
                          PKG_INVENTORY.PROCESS_STOCK_TRANSFER(
                            p_material_id  => :material_id,
                            p_src_wh_id    => :warehouse_id,
                            p_src_bin_id   => :bin_id,
                            p_dest_wh_id   => :dest_warehouse_id,
                            p_dest_bin_id  => :dest_bin_id,
                            p_transfer_qty => :quantity,
                            p_performed_by => NVL(:user, ''REST_API''),
                            p_remarks      => :remarks,
                            p_status       => v_status,
                            p_message      => v_message
                          );
                        ELSIF :movement_code = ''551'' THEN
                          PKG_INVENTORY.PROCESS_STOCK_ADJUSTMENT(
                            p_material_id  => :material_id,
                            p_warehouse_id => :warehouse_id,
                            p_bin_id       => :bin_id,
                            p_new_qty_on_hand => :quantity,
                            p_performed_by => NVL(:user, ''REST_API''),
                            p_remarks      => :remarks,
                            p_status       => v_status,
                            p_message      => v_message
                          );
                        ELSE
                          v_status  := ''ERROR'';
                          v_message := ''Invalid movement code: '' || :movement_code;
                        END IF;

                        apex_json.open_object;
                        apex_json.write(''status'', v_status);
                        apex_json.write(''message'', v_message);
                        apex_json.close_object;
                      END;',
    p_comments    => 'Process MIGO Goods Movement'
  );

  -- 15. BOM Breakdown
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'bom/breakdown',
    p_comments    => 'Run BOM breakdown for a product'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'bom/breakdown',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT * FROM TABLE(PKG_BOM_BREAKDOWN.BREAKDOWN_BOM(:product_id, NVL(:quantity, 1)))',
    p_comments    => 'BOM breakdown list'
  );

  -- 16. LOV Products
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'lov/products',
    p_comments    => 'Get products list'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'lov/products',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT PRODUCT_ID, PRODUCT_CODE, PRODUCT_NAME FROM PRODUCT_MASTER WHERE STATUS = ''ACTIVE'' ORDER BY PRODUCT_CODE',
    p_comments    => 'Products list'
  );

  -- 17. LOV POs
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'lov/pos',
    p_comments    => 'Get open purchase orders'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'lov/pos',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT PO_ID, PO_NUMBER, TOTAL_VALUE, ORDER_STATUS FROM PURCHASE_ORDER WHERE ORDER_STATUS IN (''ISSUED'',''ACKNOWLEDGED'',''PARTIALLY_RECEIVED'') ORDER BY PO_NUMBER',
    p_comments    => 'Open POs list'
  );

  -- 18. AI Forecast RUN
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'forecast/run',
    p_comments    => 'Run AI demand forecast'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'forecast/run',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => 'BEGIN
                        PKG_AI_FORECAST.RUN_FORECAST(p_product_id => :product_id);
                        PKG_AI_FORECAST.SYNC_TO_DEMAND_FORECAST(p_product_id => :product_id);
                        apex_json.open_object;
                        apex_json.write(''status'', ''SUCCESS'');
                        apex_json.write(''message'', ''AI demand forecast recalculated and synchronized successfully.'');
                        apex_json.close_object;
                      END;',
    p_comments    => 'Run AI Forecast'
  );

  -- 19. AI Forecast Data
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'forecast/data',
    p_comments    => 'Get forecast data for product'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'forecast/data',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT TO_CHAR(FORECAST_PERIOD, ''Mon-YYYY'') AS PERIOD, FORECAST_QTY, LOWER_CONFIDENCE_QTY, UPPER_CONFIDENCE_QTY FROM VW_AI_FORECAST_VS_ACTUAL WHERE PRODUCT_ID = :product_id ORDER BY FORECAST_PERIOD',
    p_comments    => 'AI forecast data'
  );

  -- 20. Goods Bills List (Zamil Data)
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'procurement/goods_bills',
    p_comments    => 'Get all goods bills'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'procurement/goods_bills',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT rgb.BILL_ID, rgb.BILL_NUMBER, rgb.PO_ID, po.PO_NUMBER, rgb.DELIVERY_NOTE, rgb.RECEIVED_DATE, rgb.RECEIVED_BY, rgb.STATUS, rgb.REMARKS FROM RECEIVER_GOODS_BILL rgb LEFT JOIN PURCHASE_ORDER po ON po.PO_ID = rgb.PO_ID ORDER BY rgb.RECEIVED_DATE DESC',
    p_comments    => 'Return goods bills'
  );

  -- 21. Goods Bill Details
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'procurement/goods_bill_details',
    p_comments    => 'Get goods bill items'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'procurement/goods_bill_details',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT rgbi.BILL_ITEM_ID, rgbi.BILL_ID, rgbi.MATERIAL_ID, mm.MATERIAL_CODE, mm.MATERIAL_NAME, rgbi.QUANTITY_RECEIVED, rgbi.WAREHOUSE_ID, wm.WAREHOUSE_CODE, rgbi.BIN_ID, sb.BIN_CODE, rgbi.REMARKS FROM RECEIVER_GOODS_BILL_ITEMS rgbi JOIN MATERIAL_MASTER mm ON mm.MATERIAL_ID = rgbi.MATERIAL_ID JOIN WAREHOUSE_MASTER wm ON wm.WAREHOUSE_ID = rgbi.WAREHOUSE_ID JOIN STORAGE_BIN sb ON sb.BIN_ID = rgbi.BIN_ID WHERE rgbi.BILL_ID = :bill_id',
    p_comments    => 'Return goods bill items'
  );

  -- 22. Create Goods Bill
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'procurement/create_goods_bill',
    p_comments    => 'Create a draft goods receipt bill'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'procurement/create_goods_bill',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => 'DECLARE
                        v_bill_id NUMBER;
                        v_bill_number VARCHAR2(30);
                      BEGIN
                        PKG_RECEIVER_GOODS_BILL.CREATE_BILL(
                          p_po_id         => :po_id,
                          p_delivery_note => :delivery_note,
                          p_received_by   => NVL(:user, ''REST_API''),
                          p_remarks       => :remarks,
                          p_bill_id       => v_bill_id,
                          p_bill_number   => v_bill_number
                        );
                        apex_json.open_object;
                        apex_json.write(''status'', ''SUCCESS'');
                        apex_json.write(''bill_id'', v_bill_id);
                        apex_json.write(''bill_number'', v_bill_number);
                        apex_json.close_object;
                      END;',
    p_comments    => 'Create draft goods bill'
  );

  -- 23. Add Goods Bill Item
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'procurement/add_goods_bill_item',
    p_comments    => 'Add item to draft goods bill'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'procurement/add_goods_bill_item',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => 'BEGIN
                        PKG_RECEIVER_GOODS_BILL.ADD_BILL_ITEM(
                          p_bill_id      => :bill_id,
                          p_material_id  => :material_id,
                          p_qty_received => :quantity,
                          p_warehouse_id => :warehouse_id,
                          p_bin_id       => :bin_id,
                          p_remarks      => :remarks
                        );
                        apex_json.open_object;
                        apex_json.write(''status'', ''SUCCESS'');
                        apex_json.close_object;
                      END;',
    p_comments    => 'Add item to goods bill'
  );

  -- 24. Post Goods Bill
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'procurement/post_goods_bill',
    p_comments    => 'Post and commit draft goods bill'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'procurement/post_goods_bill',
    p_method      => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => 'DECLARE
                        v_status VARCHAR2(20);
                        v_message VARCHAR2(1000);
                      BEGIN
                        PKG_RECEIVER_GOODS_BILL.POST_BILL(
                          p_bill_id => :bill_id,
                          p_status  => v_status,
                          p_message => v_message
                        );
                        apex_json.open_object;
                        apex_json.write(''status'', v_status);
                        apex_json.write(''message'', v_message);
                        apex_json.close_object;
                      END;',
    p_comments    => 'Post goods bill'
  );

  -- 25. PO Items List
  ORDS.define_template(
    p_module_name => 'api',
    p_pattern     => 'procurement/po_items',
    p_comments    => 'Get items for a purchase order'
  );
  ORDS.define_handler(
    p_module_name => 'api',
    p_pattern     => 'procurement/po_items',
    p_method      => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT poi.PO_ITEM_ID, poi.PO_ID, poi.MATERIAL_ID, mm.MATERIAL_CODE, mm.MATERIAL_NAME, poi.ORDERED_QTY, poi.RECEIVED_QTY FROM PURCHASE_ORDER_ITEMS poi JOIN MATERIAL_MASTER mm ON mm.MATERIAL_ID = poi.MATERIAL_ID WHERE poi.PO_ID = :po_id',
    p_comments    => 'Return purchase order items'
  );

  COMMIT;
END;
/
PROMPT [SUCCESS] ORDS REST Modules and Endpoints configured successfully.
