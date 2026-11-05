CREATE TRIGGER trg_audit_logs_no_update
BEFORE UPDATE ON audit_logs
BEGIN
    SELECT RAISE(ABORT, 'AUDIT_LOGS_ARE_IMMUTABLE');
END;

CREATE TRIGGER trg_audit_logs_no_delete
BEFORE DELETE ON audit_logs
BEGIN
    SELECT RAISE(ABORT, 'AUDIT_LOGS_ARE_IMMUTABLE');
END;

CREATE TRIGGER trg_sales_prevent_delete_completed
BEFORE DELETE ON sales
WHEN OLD.status != 'DRAFT'
BEGIN
    SELECT RAISE(ABORT, 'CANNOT_DELETE_APPROVED_OR_COMPLETED_SALE');
END;

CREATE TRIGGER trg_purchases_prevent_delete_completed
BEFORE DELETE ON purchases
WHEN OLD.status != 'DRAFT'
BEGIN
    SELECT RAISE(ABORT, 'CANNOT_DELETE_APPROVED_OR_COMPLETED_PURCHASE');
END;

CREATE TRIGGER trg_inventory_movements_prevent_delete
BEFORE DELETE ON inventory_movements
BEGIN
    SELECT RAISE(ABORT, 'CANNOT_DELETE_HISTORICAL_INVENTORY_MOVEMENTS');
END;

CREATE TRIGGER trg_protect_seed_uom_delete
BEFORE DELETE ON units_of_measure
WHEN OLD.id = 'UOM_PIECE'
BEGIN
    SELECT RAISE(ABORT, 'SYSTEM_UNIT_OF_MEASURE_CANNOT_BE_DELETED');
END;

CREATE TRIGGER trg_uom_prevent_dimension_update_if_used
BEFORE UPDATE OF dimension ON units_of_measure
WHEN EXISTS (SELECT 1 FROM products WHERE base_unit_id = OLD.id) 
  OR EXISTS (SELECT 1 FROM unit_conversions WHERE from_unit_id = OLD.id OR to_unit_id = OLD.id)
BEGIN
    SELECT RAISE(ABORT, 'CANNOT_MODIFY_DIMENSION_OF_IN_USE_UNIT_OF_MEASURE');
END;

CREATE TRIGGER trg_check_unit_conversion_dimension_insert
BEFORE INSERT ON unit_conversions
BEGIN
    SELECT CASE
        WHEN (SELECT dimension FROM units_of_measure WHERE id = NEW.from_unit_id) !=
             (SELECT dimension FROM units_of_measure WHERE id = NEW.to_unit_id)
        THEN RAISE(ABORT, 'CROSS_DIMENSION_CONVERSION_FORBIDDEN')
        WHEN NEW.from_unit_id = NEW.to_unit_id
        THEN RAISE(ABORT, 'SELF_UNIT_CONVERSION_FORBIDDEN')
        WHEN EXISTS (
            SELECT 1 FROM unit_conversions 
            WHERE from_unit_id = NEW.to_unit_id AND to_unit_id = NEW.from_unit_id
              AND (factor_numerator * NEW.factor_numerator != factor_denominator * NEW.factor_denominator)
        )
        THEN RAISE(ABORT, 'CONTRADICTORY_REVERSE_CONVERSION_FORBIDDEN')
    END;
END;

CREATE TRIGGER trg_check_unit_conversion_dimension_update
BEFORE UPDATE OF from_unit_id, to_unit_id, factor_numerator, factor_denominator ON unit_conversions
BEGIN
    SELECT CASE
        WHEN (SELECT dimension FROM units_of_measure WHERE id = NEW.from_unit_id) !=
             (SELECT dimension FROM units_of_measure WHERE id = NEW.to_unit_id)
        THEN RAISE(ABORT, 'CROSS_DIMENSION_CONVERSION_FORBIDDEN')
        WHEN NEW.from_unit_id = NEW.to_unit_id
        THEN RAISE(ABORT, 'SELF_UNIT_CONVERSION_FORBIDDEN')
        WHEN EXISTS (
            SELECT 1 FROM unit_conversions 
            WHERE from_unit_id = NEW.to_unit_id AND to_unit_id = NEW.from_unit_id
              AND id != OLD.id
              AND (factor_numerator * NEW.factor_numerator != factor_denominator * NEW.factor_denominator)
        )
        THEN RAISE(ABORT, 'CONTRADICTORY_REVERSE_CONVERSION_FORBIDDEN')
    END;
END;

CREATE TRIGGER trg_stock_item_variant_consistency_insert
BEFORE INSERT ON stock_items
WHEN NEW.variant_id IS NOT NULL
BEGIN
    SELECT CASE
        WHEN (SELECT product_id FROM product_variants WHERE id = NEW.variant_id) != NEW.product_id
        THEN RAISE(ABORT, 'VARIANT_DOES_NOT_BELONG_TO_SPECIFIED_PRODUCT')
    END;
END;

CREATE TRIGGER trg_stock_item_variant_consistency_update
BEFORE UPDATE OF product_id, variant_id ON stock_items
WHEN NEW.variant_id IS NOT NULL
BEGIN
    SELECT CASE
        WHEN (SELECT product_id FROM product_variants WHERE id = NEW.variant_id) != NEW.product_id
        THEN RAISE(ABORT, 'VARIANT_DOES_NOT_BELONG_TO_SPECIFIED_PRODUCT')
    END;
END;

CREATE TRIGGER trg_payment_allocations_no_update
BEFORE UPDATE ON payment_allocations
BEGIN
    SELECT RAISE(ABORT, 'PAYMENT_ALLOCATIONS_ARE_IMMUTABLE_USE_REVERSAL_RECORD');
END;

CREATE TRIGGER trg_payment_allocations_no_delete
BEFORE DELETE ON payment_allocations
BEGIN
    SELECT RAISE(ABORT, 'PAYMENT_ALLOCATIONS_ARE_IMMUTABLE_USE_REVERSAL_RECORD');
END;

CREATE TRIGGER trg_product_create_simple_stock_item AFTER INSERT ON products WHEN NEW.has_variants=0 BEGIN
 INSERT INTO stock_items(id,product_id,variant_id) VALUES(lower(hex(randomblob(16))),NEW.id,NULL);
END;

CREATE TRIGGER trg_variant_create_stock_item AFTER INSERT ON product_variants BEGIN
 SELECT CASE WHEN (SELECT has_variants FROM products WHERE id=NEW.product_id)!=1 THEN RAISE(ABORT,'PRODUCT_NOT_CONFIGURED_FOR_VARIANTS') END;
 INSERT INTO stock_items(id,product_id,variant_id) VALUES(lower(hex(randomblob(16))),NEW.product_id,NEW.id);
END;

CREATE TRIGGER trg_product_variant_mode_immutable BEFORE UPDATE OF has_variants ON products WHEN EXISTS(SELECT 1 FROM stock_items WHERE product_id=OLD.id) BEGIN SELECT RAISE(ABORT,'PRODUCT_VARIANT_MODE_LOCKED_AFTER_STOCK_CREATION'); END;

CREATE TRIGGER trg_products_barcode_cross_insert BEFORE INSERT ON products WHEN NEW.barcode IS NOT NULL AND NEW.barcode<>'' BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM product_variants WHERE barcode=NEW.barcode) THEN RAISE(ABORT,'BARCODE_ALREADY_IN_USE') END;
END;

CREATE TRIGGER trg_products_barcode_cross_update BEFORE UPDATE OF barcode ON products WHEN NEW.barcode IS NOT NULL AND NEW.barcode<>'' BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM product_variants WHERE barcode=NEW.barcode) THEN RAISE(ABORT,'BARCODE_ALREADY_IN_USE') END;
END;

CREATE TRIGGER trg_variants_barcode_cross_insert BEFORE INSERT ON product_variants WHEN NEW.barcode IS NOT NULL AND NEW.barcode<>'' BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM products WHERE barcode=NEW.barcode) THEN RAISE(ABORT,'BARCODE_ALREADY_IN_USE') END;
END;

CREATE TRIGGER trg_variants_barcode_cross_update BEFORE UPDATE OF barcode ON product_variants WHEN NEW.barcode IS NOT NULL AND NEW.barcode<>'' BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM products WHERE barcode=NEW.barcode) THEN RAISE(ABORT,'BARCODE_ALREADY_IN_USE') END;
END;

CREATE TRIGGER trg_price_item_variant_product BEFORE INSERT ON price_list_items WHEN NEW.variant_id IS NOT NULL BEGIN
 SELECT CASE WHEN (SELECT product_id FROM product_variants WHERE id=NEW.variant_id) IS NOT NEW.product_id THEN RAISE(ABORT,'PRICE_VARIANT_PRODUCT_MISMATCH') END;
END;

CREATE TRIGGER trg_price_item_variant_product_update BEFORE UPDATE OF product_id,variant_id ON price_list_items WHEN NEW.variant_id IS NOT NULL BEGIN
 SELECT CASE WHEN (SELECT product_id FROM product_variants WHERE id=NEW.variant_id) IS NOT NEW.product_id THEN RAISE(ABORT,'PRICE_VARIANT_PRODUCT_MISMATCH') END;
END;

CREATE TRIGGER trg_warehouse_scope_insert BEFORE INSERT ON warehouses BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM stores WHERE id=NEW.store_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'WAREHOUSE_TENANT_STORE_MISMATCH') END;
END;

CREATE TRIGGER trg_warehouse_scope_update BEFORE UPDATE OF tenant_id,store_id ON warehouses BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM stores WHERE id=NEW.store_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'WAREHOUSE_TENANT_STORE_MISMATCH') END;
END;

CREATE TRIGGER trg_device_scope_insert BEFORE INSERT ON registered_devices BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM stores WHERE id=NEW.store_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'DEVICE_TENANT_STORE_MISMATCH') END;
END;

CREATE TRIGGER trg_device_scope_update BEFORE UPDATE OF tenant_id,store_id ON registered_devices BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM stores WHERE id=NEW.store_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'DEVICE_TENANT_STORE_MISMATCH') END;
END;

CREATE TRIGGER trg_product_category_scope BEFORE INSERT ON products WHEN NEW.category_id IS NOT NULL BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM categories WHERE id=NEW.category_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'PRODUCT_CATEGORY_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_customer_group_scope BEFORE INSERT ON customers WHEN NEW.group_id IS NOT NULL BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM customer_groups WHERE id=NEW.group_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'CUSTOMER_GROUP_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_cash_register_scope BEFORE INSERT ON cash_registers BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM stores WHERE id=NEW.store_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'CASH_REGISTER_TENANT_STORE_MISMATCH') END;
END;

CREATE TRIGGER trg_user_role_tenant_scope BEFORE INSERT ON user_roles BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM users WHERE id=NEW.user_id) IS NOT (SELECT tenant_id FROM roles WHERE id=NEW.role_id) THEN RAISE(ABORT,'USER_ROLE_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_purchase_scope_insert BEFORE INSERT ON purchases BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM suppliers WHERE id=NEW.supplier_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'PURCHASE_SUPPLIER_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT tenant_id FROM stores WHERE id=NEW.store_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'PURCHASE_STORE_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_purchase_scope_update BEFORE UPDATE OF tenant_id,store_id,supplier_id ON purchases BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM suppliers WHERE id=NEW.supplier_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'PURCHASE_SUPPLIER_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT tenant_id FROM stores WHERE id=NEW.store_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'PURCHASE_STORE_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_sale_scope_insert BEFORE INSERT ON sales BEGIN
 SELECT CASE WHEN (SELECT store_id FROM warehouses WHERE id=NEW.warehouse_id) IS NOT NEW.store_id THEN RAISE(ABORT,'SALE_WAREHOUSE_STORE_MISMATCH') END;
 SELECT CASE WHEN (SELECT tenant_id FROM warehouses WHERE id=NEW.warehouse_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'SALE_WAREHOUSE_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT tenant_id FROM stores WHERE id=NEW.store_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'SALE_STORE_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT tenant_id FROM registered_devices WHERE id=NEW.device_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'SALE_DEVICE_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT store_id FROM registered_devices WHERE id=NEW.device_id) IS NOT NEW.store_id THEN RAISE(ABORT,'SALE_DEVICE_STORE_MISMATCH') END;
 SELECT CASE WHEN NEW.customer_id IS NOT NULL AND (SELECT tenant_id FROM customers WHERE id=NEW.customer_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'SALE_CUSTOMER_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_sale_scope_update BEFORE UPDATE OF tenant_id,store_id,warehouse_id,device_id,customer_id ON sales BEGIN
 SELECT CASE WHEN (SELECT store_id FROM warehouses WHERE id=NEW.warehouse_id) IS NOT NEW.store_id THEN RAISE(ABORT,'SALE_WAREHOUSE_STORE_MISMATCH') END;
 SELECT CASE WHEN (SELECT tenant_id FROM warehouses WHERE id=NEW.warehouse_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'SALE_WAREHOUSE_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT tenant_id FROM stores WHERE id=NEW.store_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'SALE_STORE_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT tenant_id FROM registered_devices WHERE id=NEW.device_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'SALE_DEVICE_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT store_id FROM registered_devices WHERE id=NEW.device_id) IS NOT NEW.store_id THEN RAISE(ABORT,'SALE_DEVICE_STORE_MISMATCH') END;
 SELECT CASE WHEN NEW.customer_id IS NOT NULL AND (SELECT tenant_id FROM customers WHERE id=NEW.customer_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'SALE_CUSTOMER_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_sale_item_scope BEFORE INSERT ON sale_items BEGIN
 SELECT CASE WHEN (SELECT p.tenant_id FROM stock_items si JOIN products p ON p.id=si.product_id WHERE si.id=NEW.stock_item_id) IS NOT (SELECT tenant_id FROM sales WHERE id=NEW.sale_id) THEN RAISE(ABORT,'SALE_ITEM_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_purchase_item_scope BEFORE INSERT ON purchase_items BEGIN
 SELECT CASE WHEN (SELECT p.tenant_id FROM stock_items si JOIN products p ON p.id=si.product_id WHERE si.id=NEW.stock_item_id) IS NOT (SELECT tenant_id FROM purchases WHERE id=NEW.purchase_id) THEN RAISE(ABORT,'PURCHASE_ITEM_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_fiscal_year_range_insert BEFORE INSERT ON fiscal_years BEGIN SELECT CASE WHEN NEW.start_date>NEW.end_date THEN RAISE(ABORT,'INVALID_FISCAL_YEAR_RANGE') END; END;

CREATE TRIGGER trg_fiscal_year_range_update BEFORE UPDATE OF start_date,end_date ON fiscal_years BEGIN SELECT CASE WHEN NEW.start_date>NEW.end_date THEN RAISE(ABORT,'INVALID_FISCAL_YEAR_RANGE') END; END;

CREATE TRIGGER trg_document_sequence_year BEFORE INSERT ON document_sequences BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM fiscal_years f JOIN stores s ON s.tenant_id=f.tenant_id WHERE f.tenant_id=NEW.tenant_id AND s.id=NEW.store_id AND f.year=NEW.fiscal_year AND f.is_closed=0) THEN RAISE(ABORT,'DOCUMENT_SEQUENCE_REQUIRES_OPEN_FISCAL_YEAR') END;
END;

CREATE TRIGGER trg_document_sequence_step BEFORE UPDATE OF last_sequence_number ON document_sequences BEGIN
 SELECT CASE WHEN NEW.last_sequence_number!=OLD.last_sequence_number+1 THEN RAISE(ABORT,'DOCUMENT_SEQUENCE_MUST_INCREMENT_BY_ONE') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM fiscal_years WHERE tenant_id=NEW.tenant_id AND year=NEW.fiscal_year AND is_closed=1) THEN RAISE(ABORT,'FISCAL_YEAR_CLOSED') END;
END;

CREATE TRIGGER trg_inventory_movement_guard BEFORE INSERT ON inventory_movements BEGIN
 SELECT CASE WHEN NEW.quantity_ticks<=0 THEN RAISE(ABORT,'MOVEMENT_QUANTITY_MUST_BE_POSITIVE') END;
 SELECT CASE WHEN NEW.unit_cost_ticks<0 OR NEW.total_cost_centimes<0 THEN RAISE(ABORT,'MOVEMENT_COST_NEGATIVE') END;
 SELECT CASE WHEN (SELECT tenant_id FROM warehouses WHERE id=NEW.warehouse_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'MOVEMENT_WAREHOUSE_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT p.tenant_id FROM stock_items si JOIN products p ON p.id=si.product_id WHERE si.id=NEW.stock_item_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'MOVEMENT_STOCK_TENANT_MISMATCH') END;
 SELECT CASE WHEN NEW.movement_type IN ('SALE_SHIPMENT','PURCHASE_RETURN','ADJUSTMENT_OUT','TRANSFER_OUT') AND COALESCE((SELECT on_hand_ticks-reserved_ticks FROM inventory_balances WHERE warehouse_id=NEW.warehouse_id AND stock_item_id=NEW.stock_item_id),0)<NEW.quantity_ticks THEN RAISE(ABORT,'INSUFFICIENT_AVAILABLE_STOCK') END;
END;

CREATE TRIGGER trg_inventory_movement_apply AFTER INSERT ON inventory_movements BEGIN
 INSERT OR IGNORE INTO inventory_balances(warehouse_id,stock_item_id,on_hand_ticks,reserved_ticks,current_moving_avg_cost)
 VALUES(NEW.warehouse_id,NEW.stock_item_id,0,0,NEW.unit_cost_ticks);
 UPDATE inventory_balances SET
  current_moving_avg_cost=CASE WHEN NEW.movement_type IN ('PURCHASE_RECEIPT','SALE_RETURN','ADJUSTMENT_IN','TRANSFER_IN') THEN
   CASE WHEN on_hand_ticks+NEW.quantity_ticks=0 THEN NEW.unit_cost_ticks ELSE CAST(((on_hand_ticks*current_moving_avg_cost)+(NEW.quantity_ticks*NEW.unit_cost_ticks))/(on_hand_ticks+NEW.quantity_ticks) AS INTEGER) END
   ELSE current_moving_avg_cost END,
  on_hand_ticks=on_hand_ticks+CASE WHEN NEW.movement_type IN ('PURCHASE_RECEIPT','SALE_RETURN','ADJUSTMENT_IN','TRANSFER_IN') THEN NEW.quantity_ticks ELSE -NEW.quantity_ticks END
 WHERE warehouse_id=NEW.warehouse_id AND stock_item_id=NEW.stock_item_id;
END;

CREATE TRIGGER trg_inventory_movement_no_update BEFORE UPDATE ON inventory_movements BEGIN SELECT RAISE(ABORT,'INVENTORY_MOVEMENTS_ARE_IMMUTABLE'); END;

CREATE TRIGGER trg_inventory_movement_no_delete BEFORE DELETE ON inventory_movements BEGIN SELECT RAISE(ABORT,'INVENTORY_MOVEMENTS_ARE_IMMUTABLE'); END;

CREATE TRIGGER trg_quota_issue_guard BEFORE INSERT ON inventory_quotas BEGIN
 SELECT CASE WHEN NEW.status!='ACTIVE' THEN RAISE(ABORT,'NEW_QUOTA_MUST_START_ACTIVE') END;
 SELECT CASE WHEN (SELECT pairing_status FROM registered_devices WHERE id=NEW.device_id)!='ACTIVE' THEN RAISE(ABORT,'QUOTA_DEVICE_NOT_ACTIVE') END;
 SELECT CASE WHEN (SELECT tenant_id FROM registered_devices WHERE id=NEW.device_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'QUOTA_DEVICE_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT tenant_id FROM warehouses WHERE id=NEW.warehouse_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'QUOTA_WAREHOUSE_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT p.tenant_id FROM stock_items si JOIN products p ON p.id=si.product_id WHERE si.id=NEW.stock_item_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'QUOTA_STOCK_TENANT_MISMATCH') END;
 SELECT CASE WHEN COALESCE((SELECT on_hand_ticks-reserved_ticks FROM inventory_balances WHERE warehouse_id=NEW.warehouse_id AND stock_item_id=NEW.stock_item_id),0)<NEW.quota_quantity_ticks THEN RAISE(ABORT,'INSUFFICIENT_STOCK_TO_ISSUE_QUOTA') END;
END;

CREATE TRIGGER trg_quota_issue_reserve AFTER INSERT ON inventory_quotas BEGIN
 UPDATE inventory_balances SET reserved_ticks=reserved_ticks+NEW.quota_quantity_ticks
 WHERE warehouse_id=NEW.warehouse_id AND stock_item_id=NEW.stock_item_id;
END;

CREATE TRIGGER trg_quota_deduction_guard BEFORE INSERT ON sale_item_quota_deductions BEGIN
 SELECT CASE WHEN (SELECT stock_item_id FROM inventory_quotas WHERE id=NEW.quota_id) IS NOT (SELECT stock_item_id FROM sale_items WHERE id=NEW.sale_item_id) THEN RAISE(ABORT,'QUOTA_STOCK_ITEM_MISMATCH') END;
 SELECT CASE WHEN (SELECT device_id FROM inventory_quotas WHERE id=NEW.quota_id) IS NOT (SELECT device_id FROM sales WHERE id=(SELECT sale_id FROM sale_items WHERE id=NEW.sale_item_id)) THEN RAISE(ABORT,'QUOTA_DEVICE_MISMATCH') END;
 SELECT CASE WHEN (SELECT warehouse_id FROM inventory_quotas WHERE id=NEW.quota_id) IS NOT (SELECT warehouse_id FROM sales WHERE id=(SELECT sale_id FROM sale_items WHERE id=NEW.sale_item_id)) THEN RAISE(ABORT,'QUOTA_WAREHOUSE_MISMATCH') END;
 SELECT CASE WHEN (SELECT tenant_id FROM inventory_quotas WHERE id=NEW.quota_id) IS NOT (SELECT tenant_id FROM sales WHERE id=(SELECT sale_id FROM sale_items WHERE id=NEW.sale_item_id)) THEN RAISE(ABORT,'QUOTA_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT status FROM inventory_quotas WHERE id=NEW.quota_id)!='ACTIVE' OR (SELECT valid_until FROM inventory_quotas WHERE id=NEW.quota_id)<strftime('%Y-%m-%dT%H:%M:%fZ','now') THEN RAISE(ABORT,'QUOTA_INACTIVE_OR_EXPIRED') END;
 SELECT CASE WHEN (SELECT consumed_quantity_ticks+NEW.deducted_quantity_ticks FROM inventory_quotas WHERE id=NEW.quota_id)>(SELECT quota_quantity_ticks FROM inventory_quotas WHERE id=NEW.quota_id) THEN RAISE(ABORT,'QUOTA_EXCEEDED') END;
 SELECT CASE WHEN NEW.deducted_quantity_ticks+COALESCE((SELECT SUM(deducted_quantity_ticks) FROM sale_item_quota_deductions WHERE sale_item_id=NEW.sale_item_id),0)>(SELECT quantity_ticks FROM sale_items WHERE id=NEW.sale_item_id) THEN RAISE(ABORT,'QUOTA_DEDUCTION_EXCEEDS_SALE_LINE') END;
END;

CREATE TRIGGER trg_quota_deduction_apply AFTER INSERT ON sale_item_quota_deductions BEGIN
 UPDATE inventory_quotas SET consumed_quantity_ticks=consumed_quantity_ticks+NEW.deducted_quantity_ticks WHERE id=NEW.quota_id;
 UPDATE inventory_balances SET reserved_ticks=reserved_ticks-NEW.deducted_quantity_ticks WHERE warehouse_id=(SELECT warehouse_id FROM inventory_quotas WHERE id=NEW.quota_id) AND stock_item_id=(SELECT stock_item_id FROM inventory_quotas WHERE id=NEW.quota_id);
END;

CREATE TRIGGER trg_quota_deduction_immutable_update BEFORE UPDATE ON sale_item_quota_deductions BEGIN SELECT RAISE(ABORT,'QUOTA_DEDUCTIONS_ARE_IMMUTABLE'); END;

CREATE TRIGGER trg_quota_deduction_delete_guard BEFORE DELETE ON sale_item_quota_deductions WHEN (SELECT status FROM sales WHERE id=(SELECT sale_id FROM sale_items WHERE id=OLD.sale_item_id))!='DRAFT' BEGIN SELECT RAISE(ABORT,'COMPLETED_QUOTA_DEDUCTIONS_ARE_IMMUTABLE'); END;

CREATE TRIGGER trg_quota_deduction_delete_restore AFTER DELETE ON sale_item_quota_deductions BEGIN
 UPDATE inventory_quotas SET consumed_quantity_ticks=consumed_quantity_ticks-OLD.deducted_quantity_ticks WHERE id=OLD.quota_id;
 UPDATE inventory_balances SET reserved_ticks=reserved_ticks+OLD.deducted_quantity_ticks WHERE warehouse_id=(SELECT warehouse_id FROM inventory_quotas WHERE id=OLD.quota_id) AND stock_item_id=(SELECT stock_item_id FROM inventory_quotas WHERE id=OLD.quota_id);
END;

CREATE TRIGGER trg_quota_status_release BEFORE UPDATE OF status ON inventory_quotas WHEN OLD.status IN ('ACTIVE','LOST_DEVICE_EXPOSURE') AND NEW.status IN ('RECONCILED','EXPIRED','VOIDED_BY_ADMIN') BEGIN
 UPDATE inventory_balances SET reserved_ticks=reserved_ticks-(OLD.quota_quantity_ticks-OLD.consumed_quantity_ticks) WHERE warehouse_id=OLD.warehouse_id AND stock_item_id=OLD.stock_item_id;
END;

CREATE TRIGGER trg_quota_no_delete BEFORE DELETE ON inventory_quotas BEGIN SELECT RAISE(ABORT,'INVENTORY_QUOTAS_ARE_IMMUTABLE'); END;

CREATE TRIGGER trg_sales_insert_draft_only BEFORE INSERT ON sales WHEN NEW.status!='DRAFT' BEGIN SELECT RAISE(ABORT,'SALES_MUST_START_AS_DRAFT'); END;

CREATE TRIGGER trg_sale_completion_guard BEFORE UPDATE OF status ON sales WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' BEGIN
 SELECT CASE WHEN NEW.device_seq_num IS NULL OR NEW.device_seq_num<=(SELECT last_seq_num FROM registered_devices WHERE id=NEW.device_id) THEN RAISE(ABORT,'DEVICE_SEQUENCE_NOT_MONOTONIC') END;
 SELECT CASE WHEN NEW.device_signature IS NULL OR NEW.device_signature='' OR NEW.request_hash IS NULL OR NEW.request_hash='' OR NEW.local_operation_uuid IS NULL OR NEW.local_operation_uuid='' THEN RAISE(ABORT,'COMPLETED_SALE_REQUIRES_SIGNED_OPERATION_FIELDS') END;
 SELECT CASE WHEN (SELECT pairing_status FROM registered_devices WHERE id=NEW.device_id)!='ACTIVE' THEN RAISE(ABORT,'DEVICE_NOT_ACTIVE') END;
 SELECT CASE WHEN (SELECT COUNT(*) FROM sale_items WHERE sale_id=NEW.id)=0 THEN RAISE(ABORT,'SALE_REQUIRES_ITEMS') END;
 SELECT CASE WHEN (SELECT COALESCE(SUM(line_total_centimes),0) FROM sale_items WHERE sale_id=NEW.id)!=NEW.total_amount_centimes THEN RAISE(ABORT,'SALE_TOTAL_DOES_NOT_MATCH_LINES') END;
 SELECT CASE WHEN NEW.offline_receipt_number IS NOT NULL AND EXISTS(SELECT 1 FROM sale_items si WHERE si.sale_id=NEW.id AND COALESCE((SELECT SUM(deducted_quantity_ticks) FROM sale_item_quota_deductions qd WHERE qd.sale_item_id=si.id),0)!=si.quantity_ticks) THEN RAISE(ABORT,'OFFLINE_SALE_LINE_NOT_FULLY_COVERED_BY_QUOTA') END;
END;

CREATE TRIGGER trg_sale_completion_post AFTER UPDATE OF status ON sales WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' BEGIN
 UPDATE registered_devices SET last_seq_num=NEW.device_seq_num,last_seen_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=NEW.device_id;
 INSERT INTO inventory_movements(id,tenant_id,warehouse_id,stock_item_id,movement_type,source_event_id,reference_line_id,quantity_ticks,unit_cost_ticks,total_cost_centimes)
 SELECT 'SALE_'||si.id,NEW.tenant_id,NEW.warehouse_id,si.stock_item_id,'SALE_SHIPMENT','SALE:'||NEW.id||':'||si.id,si.id,si.quantity_ticks,
  COALESCE(NULLIF(si.cost_at_sale_ticks,0),(SELECT current_moving_avg_cost FROM inventory_balances WHERE warehouse_id=NEW.warehouse_id AND stock_item_id=si.stock_item_id),0),
  CAST(si.quantity_ticks*COALESCE(NULLIF(si.cost_at_sale_ticks,0),(SELECT current_moving_avg_cost FROM inventory_balances WHERE warehouse_id=NEW.warehouse_id AND stock_item_id=si.stock_item_id),0)/1000000 AS INTEGER)
 FROM sale_items si WHERE si.sale_id=NEW.id;
END;

CREATE TRIGGER trg_sale_item_cost_snapshot AFTER INSERT ON sale_items WHEN NEW.cost_at_sale_ticks=0 BEGIN
 UPDATE sale_items SET cost_at_sale_ticks=COALESCE((SELECT current_moving_avg_cost FROM inventory_balances WHERE warehouse_id=(SELECT warehouse_id FROM sales WHERE id=NEW.sale_id) AND stock_item_id=NEW.stock_item_id),0) WHERE id=NEW.id;
END;

CREATE TRIGGER trg_payment_insert_draft_only BEFORE INSERT ON payments WHEN NEW.status!='DRAFT' BEGIN SELECT RAISE(ABORT,'PAYMENT_MUST_START_AS_DRAFT'); END;

CREATE TRIGGER trg_payment_party_guard BEFORE INSERT ON payments BEGIN
 SELECT CASE WHEN NEW.party_type='CUSTOMER' AND NOT EXISTS(SELECT 1 FROM customers WHERE id=NEW.party_id AND tenant_id=NEW.tenant_id) THEN RAISE(ABORT,'PAYMENT_CUSTOMER_NOT_FOUND') END;
 SELECT CASE WHEN NEW.party_type='SUPPLIER' AND NOT EXISTS(SELECT 1 FROM suppliers WHERE id=NEW.party_id AND tenant_id=NEW.tenant_id) THEN RAISE(ABORT,'PAYMENT_SUPPLIER_NOT_FOUND') END;
 SELECT CASE WHEN NEW.is_reversal=0 AND NEW.reversal_of_id IS NOT NULL THEN RAISE(ABORT,'NORMAL_PAYMENT_CANNOT_REFERENCE_REVERSAL') END;
 SELECT CASE WHEN NEW.is_reversal=1 AND (NEW.reversal_of_id IS NULL OR NOT EXISTS(SELECT 1 FROM payments p WHERE p.id=NEW.reversal_of_id AND p.status='POSTED' AND p.is_reversal=0 AND p.tenant_id=NEW.tenant_id AND p.store_id=NEW.store_id AND p.party_type=NEW.party_type AND p.party_id=NEW.party_id AND p.amount=NEW.amount AND p.amount=(SELECT COALESCE(SUM(pa.allocated_amount),0) FROM payment_allocations pa WHERE pa.payment_id=p.id))) THEN RAISE(ABORT,'REVERSAL_MUST_MATCH_POSTED_FULLY_ALLOCATED_ORIGINAL') END;
 SELECT CASE WHEN NEW.payment_method='CASH' AND NEW.shift_id IS NULL THEN RAISE(ABORT,'CASH_PAYMENT_REQUIRES_SHIFT') END;
 SELECT CASE WHEN NEW.shift_id IS NOT NULL AND (SELECT status FROM cash_shifts WHERE id=NEW.shift_id)!='OPEN' THEN RAISE(ABORT,'PAYMENT_SHIFT_NOT_OPEN') END;
 SELECT CASE WHEN NEW.shift_id IS NOT NULL AND (SELECT cr.store_id FROM cash_shifts cs JOIN cash_registers cr ON cr.id=cs.cash_register_id WHERE cs.id=NEW.shift_id) IS NOT NEW.store_id THEN RAISE(ABORT,'PAYMENT_SHIFT_STORE_MISMATCH') END;
END;

CREATE TRIGGER trg_payment_core_immutable BEFORE UPDATE OF tenant_id,store_id,party_type,party_id,payment_method,shift_id,amount,payment_date,notes,is_reversal,reversal_of_id ON payments BEGIN SELECT RAISE(ABORT,'PAYMENT_CORE_FIELDS_IMMUTABLE'); END;

CREATE TRIGGER trg_payment_status_transition BEFORE UPDATE OF status ON payments BEGIN
 SELECT CASE WHEN OLD.status!='DRAFT' OR NEW.status NOT IN ('POSTED','CANCELLED') THEN RAISE(ABORT,'INVALID_PAYMENT_STATUS_TRANSITION') END;
 SELECT CASE WHEN NEW.status='POSTED' AND COALESCE((SELECT SUM(allocated_amount) FROM payment_allocations WHERE payment_id=OLD.id),0)>NEW.amount THEN RAISE(ABORT,'PAYMENT_ALLOCATIONS_EXCEED_PAYMENT') END;
 SELECT CASE WHEN NEW.status='POSTED' AND OLD.is_reversal=1 AND COALESCE((SELECT SUM(allocated_amount) FROM payment_allocations WHERE payment_id=OLD.id),0)!=OLD.amount THEN RAISE(ABORT,'REVERSAL_ALLOCATIONS_MUST_EQUAL_PAYMENT') END;
 SELECT CASE WHEN NEW.status='POSTED' AND OLD.is_reversal=1 AND (SELECT COUNT(*) FROM payment_allocations WHERE payment_id=OLD.id)!=(SELECT COUNT(*) FROM payment_allocations WHERE payment_id=OLD.reversal_of_id) THEN RAISE(ABORT,'REVERSAL_ALLOCATION_SET_INCOMPLETE') END;
 SELECT CASE WHEN NEW.status='POSTED' AND OLD.is_reversal=0 AND EXISTS(SELECT 1 FROM payment_allocations pa JOIN sales s ON s.id=pa.sale_id WHERE pa.payment_id=OLD.id AND pa.allocated_amount>s.remaining_debt) THEN RAISE(ABORT,'PAYMENT_EXCEEDS_CURRENT_SALE_DEBT') END;
 SELECT CASE WHEN NEW.status='POSTED' AND OLD.is_reversal=0 AND EXISTS(SELECT 1 FROM payment_allocations pa JOIN purchases pu ON pu.id=pa.purchase_id WHERE pa.payment_id=OLD.id AND pa.allocated_amount>pu.remaining_debt) THEN RAISE(ABORT,'PAYMENT_EXCEEDS_CURRENT_PURCHASE_DEBT') END;
END;

CREATE TRIGGER trg_payment_no_delete BEFORE DELETE ON payments BEGIN SELECT RAISE(ABORT,'PAYMENT_HISTORY_RETAINED'); END;

CREATE TRIGGER trg_payment_allocation_guard BEFORE INSERT ON payment_allocations BEGIN
 SELECT CASE WHEN (SELECT status FROM payments WHERE id=NEW.payment_id)!='DRAFT' THEN RAISE(ABORT,'ALLOCATIONS_REQUIRE_DRAFT_PAYMENT') END;
 SELECT CASE WHEN NEW.allocated_amount<=0 THEN RAISE(ABORT,'ALLOCATION_MUST_BE_POSITIVE') END;
 SELECT CASE WHEN COALESCE((SELECT SUM(allocated_amount) FROM payment_allocations WHERE payment_id=NEW.payment_id),0)+NEW.allocated_amount>(SELECT amount FROM payments WHERE id=NEW.payment_id) THEN RAISE(ABORT,'ALLOCATION_EXCEEDS_PAYMENT') END;
 SELECT CASE WHEN NEW.sale_id IS NOT NULL AND (SELECT party_type FROM payments WHERE id=NEW.payment_id)!='CUSTOMER' THEN RAISE(ABORT,'SALE_REQUIRES_CUSTOMER_PAYMENT') END;
 SELECT CASE WHEN NEW.sale_id IS NOT NULL AND (SELECT party_id FROM payments WHERE id=NEW.payment_id) IS NOT (SELECT customer_id FROM sales WHERE id=NEW.sale_id) THEN RAISE(ABORT,'SALE_CUSTOMER_MISMATCH') END;
 SELECT CASE WHEN NEW.sale_id IS NOT NULL AND ((SELECT tenant_id FROM payments WHERE id=NEW.payment_id) IS NOT (SELECT tenant_id FROM sales WHERE id=NEW.sale_id) OR (SELECT store_id FROM payments WHERE id=NEW.payment_id) IS NOT (SELECT store_id FROM sales WHERE id=NEW.sale_id)) THEN RAISE(ABORT,'SALE_PAYMENT_SCOPE_MISMATCH') END;
 SELECT CASE WHEN NEW.purchase_id IS NOT NULL AND (SELECT party_type FROM payments WHERE id=NEW.payment_id)!='SUPPLIER' THEN RAISE(ABORT,'PURCHASE_REQUIRES_SUPPLIER_PAYMENT') END;
 SELECT CASE WHEN NEW.purchase_id IS NOT NULL AND (SELECT party_id FROM payments WHERE id=NEW.payment_id) IS NOT (SELECT supplier_id FROM purchases WHERE id=NEW.purchase_id) THEN RAISE(ABORT,'PURCHASE_SUPPLIER_MISMATCH') END;
 SELECT CASE WHEN NEW.purchase_id IS NOT NULL AND ((SELECT tenant_id FROM payments WHERE id=NEW.payment_id) IS NOT (SELECT tenant_id FROM purchases WHERE id=NEW.purchase_id) OR (SELECT store_id FROM payments WHERE id=NEW.payment_id) IS NOT (SELECT store_id FROM purchases WHERE id=NEW.purchase_id)) THEN RAISE(ABORT,'PURCHASE_PAYMENT_SCOPE_MISMATCH') END;
 SELECT CASE WHEN (SELECT is_reversal FROM payments WHERE id=NEW.payment_id)=1 AND NEW.sale_id IS NOT NULL AND NEW.allocated_amount IS NOT COALESCE((SELECT allocated_amount FROM payment_allocations WHERE payment_id=(SELECT reversal_of_id FROM payments WHERE id=NEW.payment_id) AND sale_id=NEW.sale_id),-1) THEN RAISE(ABORT,'REVERSAL_SALE_ALLOCATION_MISMATCH') END;
 SELECT CASE WHEN (SELECT is_reversal FROM payments WHERE id=NEW.payment_id)=1 AND NEW.purchase_id IS NOT NULL AND NEW.allocated_amount IS NOT COALESCE((SELECT allocated_amount FROM payment_allocations WHERE payment_id=(SELECT reversal_of_id FROM payments WHERE id=NEW.payment_id) AND purchase_id=NEW.purchase_id),-1) THEN RAISE(ABORT,'REVERSAL_PURCHASE_ALLOCATION_MISMATCH') END;
END;

CREATE TRIGGER trg_payment_apply_sale_allocations AFTER UPDATE OF status ON payments WHEN OLD.status='DRAFT' AND NEW.status='POSTED' BEGIN
 UPDATE sales SET paid_amount=paid_amount+(SELECT CASE WHEN NEW.is_reversal=1 THEN -SUM(pa.allocated_amount) ELSE SUM(pa.allocated_amount) END FROM payment_allocations pa WHERE pa.payment_id=NEW.id AND pa.sale_id=sales.id),
  remaining_debt=remaining_debt+(SELECT CASE WHEN NEW.is_reversal=1 THEN SUM(pa.allocated_amount) ELSE -SUM(pa.allocated_amount) END FROM payment_allocations pa WHERE pa.payment_id=NEW.id AND pa.sale_id=sales.id)
 WHERE id IN (SELECT sale_id FROM payment_allocations WHERE payment_id=NEW.id AND sale_id IS NOT NULL);
END;

CREATE TRIGGER trg_payment_apply_purchase_allocations AFTER UPDATE OF status ON payments WHEN OLD.status='DRAFT' AND NEW.status='POSTED' BEGIN
 UPDATE purchases SET paid_amount=paid_amount+(SELECT CASE WHEN NEW.is_reversal=1 THEN -SUM(pa.allocated_amount) ELSE SUM(pa.allocated_amount) END FROM payment_allocations pa WHERE pa.payment_id=NEW.id AND pa.purchase_id=purchases.id),
  remaining_debt=remaining_debt+(SELECT CASE WHEN NEW.is_reversal=1 THEN SUM(pa.allocated_amount) ELSE -SUM(pa.allocated_amount) END FROM payment_allocations pa WHERE pa.payment_id=NEW.id AND pa.purchase_id=purchases.id)
 WHERE id IN (SELECT purchase_id FROM payment_allocations WHERE payment_id=NEW.id AND purchase_id IS NOT NULL);
END;

CREATE TRIGGER trg_cash_shift_opening AFTER INSERT ON cash_shifts BEGIN UPDATE cash_shifts SET expected_cash_centimes=NEW.opening_float_centimes WHERE id=NEW.id; END;

CREATE TRIGGER trg_cash_movement_guard BEFORE INSERT ON cash_movements BEGIN
 SELECT CASE WHEN (SELECT status FROM cash_shifts WHERE id=NEW.shift_id)!='OPEN' THEN RAISE(ABORT,'CASH_SHIFT_NOT_OPEN') END;
END;

CREATE TRIGGER trg_cash_movement_apply AFTER INSERT ON cash_movements BEGIN
 UPDATE cash_shifts SET expected_cash_centimes=expected_cash_centimes+CASE WHEN NEW.movement_type IN ('FLOAT_ADD','MANUAL_IN','SALE_COLLECTION','CUSTOMER_DEBT_COLLECTION','SUPPLIER_REFUND') THEN NEW.amount_centimes ELSE -NEW.amount_centimes END WHERE id=NEW.shift_id;
END;

CREATE TRIGGER trg_cash_movement_no_update BEFORE UPDATE ON cash_movements BEGIN SELECT RAISE(ABORT,'CASH_MOVEMENTS_ARE_IMMUTABLE'); END;

CREATE TRIGGER trg_cash_movement_no_delete BEFORE DELETE ON cash_movements BEGIN SELECT RAISE(ABORT,'CASH_MOVEMENTS_ARE_IMMUTABLE'); END;

CREATE TRIGGER trg_payment_cash_post AFTER UPDATE OF status ON payments WHEN OLD.status='DRAFT' AND NEW.status='POSTED' AND NEW.payment_method='CASH' BEGIN
 INSERT INTO cash_movements(id,shift_id,movement_type,amount_centimes,reason,source_event_id)
 VALUES('PAY_'||NEW.id,NEW.shift_id,CASE WHEN NEW.party_type='CUSTOMER' AND NEW.is_reversal=0 THEN 'CUSTOMER_DEBT_COLLECTION' WHEN NEW.party_type='SUPPLIER' AND NEW.is_reversal=0 THEN 'SUPPLIER_PAYMENT' WHEN NEW.party_type='CUSTOMER' AND NEW.is_reversal=1 THEN 'CUSTOMER_REFUND' ELSE 'SUPPLIER_REFUND' END,NEW.amount,'Payment '||NEW.id,'PAYMENT:'||NEW.id);
END;

CREATE TRIGGER trg_expense_shift_guard BEFORE INSERT ON expenses WHEN NEW.shift_id IS NOT NULL BEGIN
 SELECT CASE WHEN (SELECT status FROM cash_shifts WHERE id=NEW.shift_id)!='OPEN' THEN RAISE(ABORT,'EXPENSE_SHIFT_NOT_OPEN') END;
 SELECT CASE WHEN (SELECT cr.store_id FROM cash_shifts cs JOIN cash_registers cr ON cr.id=cs.cash_register_id WHERE cs.id=NEW.shift_id) IS NOT NEW.store_id THEN RAISE(ABORT,'EXPENSE_SHIFT_STORE_MISMATCH') END;
 SELECT CASE WHEN (SELECT tenant_id FROM expense_categories WHERE id=NEW.category_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'EXPENSE_CATEGORY_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_expense_cash_post AFTER INSERT ON expenses WHEN NEW.shift_id IS NOT NULL BEGIN
 INSERT INTO cash_movements(id,shift_id,movement_type,amount_centimes,reason,source_event_id) VALUES('EXP_'||NEW.id,NEW.shift_id,'PETTY_EXPENSE',NEW.amount_centimes,NEW.description,'EXPENSE:'||NEW.id);
END;

CREATE TRIGGER trg_cash_shift_close_guard BEFORE UPDATE OF status ON cash_shifts WHEN OLD.status='OPEN' AND NEW.status='CLOSED' BEGIN
 SELECT CASE WHEN NEW.closed_at IS NULL OR NEW.actual_cash_centimes IS NULL THEN RAISE(ABORT,'SHIFT_CLOSE_REQUIRES_ACTUAL_CASH_AND_TIME') END;
 SELECT CASE WHEN NEW.difference_centimes IS NOT (NEW.actual_cash_centimes-OLD.expected_cash_centimes) THEN RAISE(ABORT,'SHIFT_DIFFERENCE_MISMATCH') END;
END;

CREATE TRIGGER trg_cash_shift_no_reopen BEFORE UPDATE OF status ON cash_shifts WHEN OLD.status='CLOSED' AND NEW.status!='CLOSED' BEGIN SELECT RAISE(ABORT,'CLOSED_SHIFT_CANNOT_REOPEN'); END;

CREATE TRIGGER trg_receipt_header_scope BEFORE INSERT ON purchase_receipts BEGIN
 SELECT CASE WHEN NEW.status!='DRAFT' THEN RAISE(ABORT,'RECEIPT_MUST_START_AS_DRAFT') END;
 SELECT CASE WHEN (SELECT tenant_id FROM purchases WHERE id=NEW.purchase_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'RECEIPT_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT store_id FROM warehouses WHERE id=NEW.warehouse_id) IS NOT (SELECT store_id FROM purchases WHERE id=NEW.purchase_id) THEN RAISE(ABORT,'RECEIPT_WAREHOUSE_STORE_MISMATCH') END;
END;

CREATE TRIGGER trg_receipt_item_exact_match BEFORE INSERT ON purchase_receipt_items BEGIN
 SELECT CASE WHEN (SELECT status FROM purchase_receipts WHERE id=NEW.receipt_id)!='DRAFT' THEN RAISE(ABORT,'RECEIPT_LINES_REQUIRE_DRAFT') END;
 SELECT CASE WHEN (SELECT purchase_id FROM purchase_items WHERE id=NEW.purchase_item_id) IS NOT (SELECT purchase_id FROM purchase_receipts WHERE id=NEW.receipt_id) THEN RAISE(ABORT,'RECEIPT_PURCHASE_MISMATCH') END;
 SELECT CASE WHEN (SELECT stock_item_id FROM purchase_items WHERE id=NEW.purchase_item_id) IS NOT NEW.stock_item_id THEN RAISE(ABORT,'RECEIPT_STOCK_ITEM_MISMATCH') END;
 SELECT CASE WHEN (SELECT quantity_received_ticks+NEW.quantity_received_ticks FROM purchase_items WHERE id=NEW.purchase_item_id)>(SELECT quantity_ordered_ticks FROM purchase_items WHERE id=NEW.purchase_item_id) THEN RAISE(ABORT,'RECEIPT_OVER_ORDER') END;
END;

CREATE TRIGGER trg_receipt_item_counter_add AFTER INSERT ON purchase_receipt_items BEGIN
 UPDATE purchase_items SET quantity_received_ticks=quantity_received_ticks+NEW.quantity_received_ticks WHERE id=NEW.purchase_item_id;
END;

CREATE TRIGGER trg_receipt_item_no_update BEFORE UPDATE ON purchase_receipt_items BEGIN SELECT RAISE(ABORT,'RECEIPT_LINES_ARE_IMMUTABLE_REPLACE_DRAFT_LINE'); END;

CREATE TRIGGER trg_receipt_item_delete_draft BEFORE DELETE ON purchase_receipt_items BEGIN
 SELECT CASE WHEN (SELECT status FROM purchase_receipts WHERE id=OLD.receipt_id)!='DRAFT' THEN RAISE(ABORT,'NON_DRAFT_RECEIPT_LINES_IMMUTABLE') END;
 UPDATE purchase_items SET quantity_received_ticks=quantity_received_ticks-OLD.quantity_received_ticks WHERE id=OLD.purchase_item_id;
END;

CREATE TRIGGER trg_receipt_complete_guard BEFORE UPDATE OF status ON purchase_receipts WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM purchase_receipt_items WHERE receipt_id=OLD.id) THEN RAISE(ABORT,'EMPTY_RECEIPT_CANNOT_COMPLETE') END;
END;

CREATE TRIGGER trg_receipt_complete_post AFTER UPDATE OF status ON purchase_receipts WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' BEGIN
 INSERT INTO inventory_movements(id,tenant_id,warehouse_id,stock_item_id,movement_type,source_event_id,reference_line_id,quantity_ticks,unit_cost_ticks,total_cost_centimes)
 SELECT 'GRN_'||pri.id,NEW.tenant_id,NEW.warehouse_id,pri.stock_item_id,'PURCHASE_RECEIPT','RECEIPT:'||pri.id,pri.id,pri.quantity_received_ticks,pri.unit_cost_ticks,CAST(pri.quantity_received_ticks*pri.unit_cost_ticks/1000000 AS INTEGER)
 FROM purchase_receipt_items pri WHERE pri.receipt_id=NEW.id;
 UPDATE purchases SET fulfillment_status=CASE WHEN NOT EXISTS(SELECT 1 FROM purchase_items WHERE purchase_id=NEW.purchase_id AND quantity_received_ticks<quantity_ordered_ticks) THEN 'FULLY_RECEIVED' ELSE 'PARTIALLY_RECEIVED' END,
  status=CASE WHEN NOT EXISTS(SELECT 1 FROM purchase_items WHERE purchase_id=NEW.purchase_id AND quantity_received_ticks<quantity_ordered_ticks) THEN 'RECEIVED' ELSE 'ORDERED' END
 WHERE id=NEW.purchase_id;
END;

CREATE TRIGGER trg_receipt_cancel_restore AFTER UPDATE OF status ON purchase_receipts WHEN OLD.status='DRAFT' AND NEW.status='CANCELLED' BEGIN
 UPDATE purchase_items SET quantity_received_ticks=quantity_received_ticks-(SELECT COALESCE(SUM(quantity_received_ticks),0) FROM purchase_receipt_items WHERE receipt_id=OLD.id)
 WHERE id IN (SELECT purchase_item_id FROM purchase_receipt_items WHERE receipt_id=OLD.id);
END;

CREATE TRIGGER trg_receipt_header_no_update BEFORE UPDATE ON purchase_receipts WHEN OLD.status!='DRAFT' BEGIN SELECT RAISE(ABORT,'NON_DRAFT_RECEIPT_IMMUTABLE'); END;

CREATE TRIGGER trg_receipt_header_fields_locked BEFORE UPDATE OF tenant_id,purchase_id,warehouse_id,receipt_number,received_at ON purchase_receipts BEGIN SELECT RAISE(ABORT,'RECEIPT_HEADER_FIELDS_IMMUTABLE'); END;

CREATE TRIGGER trg_receipt_header_no_delete BEFORE DELETE ON purchase_receipts WHEN OLD.status!='DRAFT' BEGIN SELECT RAISE(ABORT,'NON_DRAFT_RECEIPT_IMMUTABLE'); END;

CREATE TRIGGER trg_purchase_return_scope BEFORE INSERT ON purchase_returns BEGIN
 SELECT CASE WHEN NEW.status!='DRAFT' THEN RAISE(ABORT,'PURCHASE_RETURN_MUST_START_AS_DRAFT') END;
 SELECT CASE WHEN (SELECT tenant_id FROM purchases WHERE id=NEW.purchase_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'PURCHASE_RETURN_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT supplier_id FROM purchases WHERE id=NEW.purchase_id) IS NOT NEW.supplier_id THEN RAISE(ABORT,'PURCHASE_RETURN_SUPPLIER_MISMATCH') END;
 SELECT CASE WHEN (SELECT store_id FROM warehouses WHERE id=NEW.warehouse_id) IS NOT (SELECT store_id FROM purchases WHERE id=NEW.purchase_id) THEN RAISE(ABORT,'PURCHASE_RETURN_WAREHOUSE_STORE_MISMATCH') END;
END;

CREATE TRIGGER trg_purchase_return_item_exact_match BEFORE INSERT ON purchase_return_items BEGIN
 SELECT CASE WHEN (SELECT status FROM purchase_returns WHERE id=NEW.purchase_return_id)!='DRAFT' THEN RAISE(ABORT,'PURCHASE_RETURN_LINES_REQUIRE_DRAFT') END;
 SELECT CASE WHEN (SELECT purchase_id FROM purchase_items WHERE id=NEW.purchase_item_id) IS NOT (SELECT purchase_id FROM purchase_returns WHERE id=NEW.purchase_return_id) THEN RAISE(ABORT,'PURCHASE_RETURN_ORDER_MISMATCH') END;
 SELECT CASE WHEN (SELECT stock_item_id FROM purchase_items WHERE id=NEW.purchase_item_id) IS NOT NEW.stock_item_id THEN RAISE(ABORT,'PURCHASE_RETURN_STOCK_ITEM_MISMATCH') END;
 SELECT CASE WHEN (SELECT quantity_returned_ticks+NEW.returned_quantity_ticks FROM purchase_items WHERE id=NEW.purchase_item_id)>(SELECT quantity_received_ticks FROM purchase_items WHERE id=NEW.purchase_item_id) THEN RAISE(ABORT,'PURCHASE_RETURN_OVER_RECEIVED') END;
 SELECT CASE WHEN COALESCE((SELECT on_hand_ticks-reserved_ticks FROM inventory_balances WHERE warehouse_id=(SELECT warehouse_id FROM purchase_returns WHERE id=NEW.purchase_return_id) AND stock_item_id=NEW.stock_item_id),0)<NEW.returned_quantity_ticks THEN RAISE(ABORT,'PURCHASE_RETURN_STOCK_UNAVAILABLE') END;
 SELECT CASE WHEN NEW.line_total_centimes+COALESCE((SELECT SUM(line_total_centimes) FROM purchase_return_items WHERE purchase_return_id=NEW.purchase_return_id),0)>(SELECT total_credit_centimes FROM purchase_returns WHERE id=NEW.purchase_return_id) THEN RAISE(ABORT,'PURCHASE_RETURN_HEADER_VALUE_EXCEEDED') END;
END;

CREATE TRIGGER trg_purchase_return_item_counter_add AFTER INSERT ON purchase_return_items BEGIN
 UPDATE purchase_items SET quantity_returned_ticks=quantity_returned_ticks+NEW.returned_quantity_ticks WHERE id=NEW.purchase_item_id;
END;

CREATE TRIGGER trg_purchase_return_item_no_update BEFORE UPDATE ON purchase_return_items BEGIN SELECT RAISE(ABORT,'PURCHASE_RETURN_LINES_ARE_IMMUTABLE_REPLACE_DRAFT_LINE'); END;

CREATE TRIGGER trg_purchase_return_item_delete_draft BEFORE DELETE ON purchase_return_items BEGIN
 SELECT CASE WHEN (SELECT status FROM purchase_returns WHERE id=OLD.purchase_return_id)!='DRAFT' THEN RAISE(ABORT,'NON_DRAFT_PURCHASE_RETURN_LINES_IMMUTABLE') END;
 UPDATE purchase_items SET quantity_returned_ticks=quantity_returned_ticks-OLD.returned_quantity_ticks WHERE id=OLD.purchase_item_id;
END;

CREATE TRIGGER trg_purchase_return_complete_guard BEFORE UPDATE OF status ON purchase_returns WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM purchase_return_items WHERE purchase_return_id=OLD.id) THEN RAISE(ABORT,'EMPTY_PURCHASE_RETURN_CANNOT_COMPLETE') END;
 SELECT CASE WHEN (SELECT COALESCE(SUM(line_total_centimes),0) FROM purchase_return_items WHERE purchase_return_id=OLD.id)!=NEW.total_credit_centimes THEN RAISE(ABORT,'PURCHASE_RETURN_TOTAL_MISMATCH') END;
END;

CREATE TRIGGER trg_purchase_return_complete_post AFTER UPDATE OF status ON purchase_returns WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' BEGIN
 INSERT INTO inventory_movements(id,tenant_id,warehouse_id,stock_item_id,movement_type,source_event_id,reference_line_id,quantity_ticks,unit_cost_ticks,total_cost_centimes)
 SELECT 'PRT_'||pri.id,NEW.tenant_id,NEW.warehouse_id,pri.stock_item_id,'PURCHASE_RETURN','PURCHASE_RETURN:'||pri.id,pri.id,pri.returned_quantity_ticks,pri.unit_cost_ticks,pri.line_total_centimes
 FROM purchase_return_items pri WHERE pri.purchase_return_id=NEW.id;
END;

CREATE TRIGGER trg_purchase_return_cancel_restore AFTER UPDATE OF status ON purchase_returns WHEN OLD.status='DRAFT' AND NEW.status='CANCELLED' BEGIN
 UPDATE purchase_items SET quantity_returned_ticks=quantity_returned_ticks-(SELECT COALESCE(SUM(returned_quantity_ticks),0) FROM purchase_return_items WHERE purchase_return_id=OLD.id)
 WHERE id IN (SELECT purchase_item_id FROM purchase_return_items WHERE purchase_return_id=OLD.id);
END;

CREATE TRIGGER trg_purchase_return_item_no_update_after BEFORE UPDATE ON purchase_return_items WHEN (SELECT status FROM purchase_returns WHERE id=OLD.purchase_return_id)!='DRAFT' BEGIN SELECT RAISE(ABORT,'NON_DRAFT_PURCHASE_RETURN_LINES_IMMUTABLE'); END;

CREATE TRIGGER trg_purchase_return_header_no_update BEFORE UPDATE ON purchase_returns WHEN OLD.status!='DRAFT' BEGIN SELECT RAISE(ABORT,'NON_DRAFT_PURCHASE_RETURN_IMMUTABLE'); END;

CREATE TRIGGER trg_purchase_return_header_fields_locked BEFORE UPDATE OF tenant_id,purchase_id,supplier_id,warehouse_id,return_number,total_credit_centimes,created_at ON purchase_returns BEGIN SELECT RAISE(ABORT,'PURCHASE_RETURN_HEADER_FIELDS_IMMUTABLE'); END;

CREATE TRIGGER trg_purchase_return_header_no_delete BEFORE DELETE ON purchase_returns WHEN OLD.status!='DRAFT' BEGIN SELECT RAISE(ABORT,'NON_DRAFT_PURCHASE_RETURN_IMMUTABLE'); END;

CREATE TRIGGER trg_sale_return_scope BEFORE INSERT ON sale_returns BEGIN
 SELECT CASE WHEN NEW.status!='DRAFT' THEN RAISE(ABORT,'SALE_RETURN_MUST_START_AS_DRAFT') END;
 SELECT CASE WHEN (SELECT tenant_id FROM sales WHERE id=NEW.original_sale_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'SALE_RETURN_TENANT_MISMATCH') END;
 SELECT CASE WHEN (SELECT store_id FROM sales WHERE id=NEW.original_sale_id) IS NOT NEW.store_id THEN RAISE(ABORT,'SALE_RETURN_STORE_MISMATCH') END;
 SELECT CASE WHEN (SELECT warehouse_id FROM sales WHERE id=NEW.original_sale_id) IS NOT NEW.warehouse_id THEN RAISE(ABORT,'SALE_RETURN_WAREHOUSE_MISMATCH') END;
 SELECT CASE WHEN (SELECT customer_id FROM sales WHERE id=NEW.original_sale_id) IS NOT NEW.customer_id THEN RAISE(ABORT,'SALE_RETURN_CUSTOMER_MISMATCH') END;
 SELECT CASE WHEN NEW.refund_status='REFUNDED_CASH' AND (NEW.shift_id IS NULL OR (SELECT status FROM cash_shifts WHERE id=NEW.shift_id)!='OPEN') THEN RAISE(ABORT,'CASH_REFUND_REQUIRES_OPEN_SHIFT') END;
 SELECT CASE WHEN NEW.refund_status='REFUNDED_CASH' AND (SELECT cr.store_id FROM cash_shifts cs JOIN cash_registers cr ON cr.id=cs.cash_register_id WHERE cs.id=NEW.shift_id) IS NOT NEW.store_id THEN RAISE(ABORT,'CASH_REFUND_SHIFT_STORE_MISMATCH') END;
 SELECT CASE WHEN NEW.total_refund_centimes>(SELECT total_amount_centimes-COALESCE((SELECT SUM(total_refund_centimes) FROM sale_returns WHERE original_sale_id=NEW.original_sale_id AND status='COMPLETED'),0) FROM sales WHERE id=NEW.original_sale_id) THEN RAISE(ABORT,'SALE_RETURN_REFUND_OVER_TOTAL') END;
END;

CREATE TRIGGER trg_sale_return_item_exact_match BEFORE INSERT ON sale_return_items BEGIN
 SELECT CASE WHEN (SELECT status FROM sale_returns WHERE id=NEW.return_id)!='DRAFT' THEN RAISE(ABORT,'SALE_RETURN_LINES_REQUIRE_DRAFT') END;
 SELECT CASE WHEN (SELECT sale_id FROM sale_items WHERE id=NEW.original_sale_item_id) IS NOT (SELECT original_sale_id FROM sale_returns WHERE id=NEW.return_id) THEN RAISE(ABORT,'SALE_RETURN_SOURCE_MISMATCH') END;
 SELECT CASE WHEN (SELECT stock_item_id FROM sale_items WHERE id=NEW.original_sale_item_id) IS NOT NEW.stock_item_id THEN RAISE(ABORT,'SALE_RETURN_STOCK_ITEM_MISMATCH') END;
 SELECT CASE WHEN (SELECT returned_quantity_ticks+NEW.returned_quantity_ticks FROM sale_items WHERE id=NEW.original_sale_item_id)>(SELECT quantity_ticks FROM sale_items WHERE id=NEW.original_sale_item_id) THEN RAISE(ABORT,'SALE_RETURN_OVER_SOLD') END;
 SELECT CASE WHEN NEW.line_total_centimes+COALESCE((SELECT SUM(line_total_centimes) FROM sale_return_items WHERE original_sale_item_id=NEW.original_sale_item_id),0)>(SELECT line_total_centimes FROM sale_items WHERE id=NEW.original_sale_item_id) THEN RAISE(ABORT,'SALE_RETURN_LINE_VALUE_EXCEEDED') END;
 SELECT CASE WHEN NEW.line_total_centimes+COALESCE((SELECT SUM(line_total_centimes) FROM sale_return_items WHERE return_id=NEW.return_id),0)>(SELECT total_refund_centimes FROM sale_returns WHERE id=NEW.return_id) THEN RAISE(ABORT,'SALE_RETURN_HEADER_VALUE_EXCEEDED') END;
END;

CREATE TRIGGER trg_sale_return_item_counter_add AFTER INSERT ON sale_return_items BEGIN
 UPDATE sale_items SET returned_quantity_ticks=returned_quantity_ticks+NEW.returned_quantity_ticks WHERE id=NEW.original_sale_item_id;
END;

CREATE TRIGGER trg_sale_return_item_no_update BEFORE UPDATE ON sale_return_items BEGIN SELECT RAISE(ABORT,'SALE_RETURN_LINES_ARE_IMMUTABLE_REPLACE_DRAFT_LINE'); END;

CREATE TRIGGER trg_sale_return_item_delete_draft BEFORE DELETE ON sale_return_items BEGIN
 SELECT CASE WHEN (SELECT status FROM sale_returns WHERE id=OLD.return_id)!='DRAFT' THEN RAISE(ABORT,'NON_DRAFT_SALE_RETURN_LINES_IMMUTABLE') END;
 UPDATE sale_items SET returned_quantity_ticks=returned_quantity_ticks-OLD.returned_quantity_ticks WHERE id=OLD.original_sale_item_id;
END;

CREATE TRIGGER trg_sale_return_complete_guard BEFORE UPDATE OF status ON sale_returns WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM sale_return_items WHERE return_id=OLD.id) THEN RAISE(ABORT,'EMPTY_SALE_RETURN_CANNOT_COMPLETE') END;
 SELECT CASE WHEN (SELECT COALESCE(SUM(line_total_centimes),0) FROM sale_return_items WHERE return_id=OLD.id)!=NEW.total_refund_centimes THEN RAISE(ABORT,'SALE_RETURN_TOTAL_MISMATCH') END;
 SELECT CASE WHEN NEW.refund_status='REFUNDED_CASH' AND (NEW.shift_id IS NULL OR (SELECT status FROM cash_shifts WHERE id=NEW.shift_id)!='OPEN') THEN RAISE(ABORT,'CASH_REFUND_REQUIRES_OPEN_SHIFT') END;
END;

CREATE TRIGGER trg_sale_return_complete_post AFTER UPDATE OF status ON sale_returns WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' BEGIN
 INSERT INTO inventory_movements(id,tenant_id,warehouse_id,stock_item_id,movement_type,source_event_id,reference_line_id,quantity_ticks,unit_cost_ticks,total_cost_centimes)
 SELECT 'SRT_'||sri.id,sr.tenant_id,sr.warehouse_id,sri.stock_item_id,'SALE_RETURN','SALE_RETURN:'||sri.id,sri.id,sri.returned_quantity_ticks,si.cost_at_sale_ticks,CAST(sri.returned_quantity_ticks*si.cost_at_sale_ticks/1000000 AS INTEGER)
 FROM sale_return_items sri JOIN sale_items si ON si.id=sri.original_sale_item_id JOIN sale_returns sr ON sr.id=sri.return_id WHERE sri.return_id=NEW.id;
END;

CREATE TRIGGER trg_sale_return_cash_post AFTER UPDATE OF status ON sale_returns WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' AND NEW.refund_status='REFUNDED_CASH' BEGIN
 INSERT INTO cash_movements(id,shift_id,movement_type,amount_centimes,reason,source_event_id) VALUES('SRF_'||NEW.id,NEW.shift_id,'CUSTOMER_REFUND',NEW.total_refund_centimes,'Sale return '||NEW.return_number,'SALE_RETURN:'||NEW.id);
END;

CREATE TRIGGER trg_sale_return_account_ledger AFTER UPDATE OF status ON sale_returns WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' AND NEW.refund_status='CREDITED_TO_ACCOUNT' AND NEW.customer_id IS NOT NULL BEGIN
 INSERT INTO party_ledger_entries(id,tenant_id,party_type,party_id,source_document_type,source_document_id,debit_centimes,credit_centimes,running_balance_centimes,notes)
 SELECT 'LED_SRET_'||NEW.id,NEW.tenant_id,'CUSTOMER',NEW.customer_id,'SALE_RETURN',NEW.id,0,NEW.total_refund_centimes,current_balance_centimes-NEW.total_refund_centimes,'Sale return '||NEW.return_number FROM customers WHERE id=NEW.customer_id;
END;

CREATE TRIGGER trg_sale_return_cancel_restore AFTER UPDATE OF status ON sale_returns WHEN OLD.status='DRAFT' AND NEW.status='CANCELLED' BEGIN
 UPDATE sale_items SET returned_quantity_ticks=returned_quantity_ticks-(SELECT COALESCE(SUM(returned_quantity_ticks),0) FROM sale_return_items WHERE return_id=OLD.id)
 WHERE id IN (SELECT original_sale_item_id FROM sale_return_items WHERE return_id=OLD.id);
END;

CREATE TRIGGER trg_sale_return_item_no_update_after BEFORE UPDATE ON sale_return_items WHEN (SELECT status FROM sale_returns WHERE id=OLD.return_id)!='DRAFT' BEGIN SELECT RAISE(ABORT,'NON_DRAFT_SALE_RETURN_LINES_IMMUTABLE'); END;

CREATE TRIGGER trg_sale_return_header_no_update BEFORE UPDATE ON sale_returns WHEN OLD.status!='DRAFT' BEGIN SELECT RAISE(ABORT,'NON_DRAFT_SALE_RETURN_IMMUTABLE'); END;

CREATE TRIGGER trg_sale_return_header_fields_locked BEFORE UPDATE OF tenant_id,store_id,warehouse_id,original_sale_id,return_number,customer_id,shift_id,total_refund_centimes,refund_status,created_at ON sale_returns BEGIN SELECT RAISE(ABORT,'SALE_RETURN_HEADER_FIELDS_IMMUTABLE'); END;

CREATE TRIGGER trg_sale_return_header_no_delete BEFORE DELETE ON sale_returns WHEN OLD.status!='DRAFT' BEGIN SELECT RAISE(ABORT,'NON_DRAFT_SALE_RETURN_IMMUTABLE'); END;

CREATE TRIGGER trg_ledger_party_guard BEFORE INSERT ON party_ledger_entries BEGIN
 SELECT CASE WHEN NEW.party_type='CUSTOMER' AND NOT EXISTS(SELECT 1 FROM customers WHERE id=NEW.party_id AND tenant_id=NEW.tenant_id) THEN RAISE(ABORT,'LEDGER_CUSTOMER_NOT_FOUND') END;
 SELECT CASE WHEN NEW.party_type='SUPPLIER' AND NOT EXISTS(SELECT 1 FROM suppliers WHERE id=NEW.party_id AND tenant_id=NEW.tenant_id) THEN RAISE(ABORT,'LEDGER_SUPPLIER_NOT_FOUND') END;
 SELECT CASE WHEN NEW.debit_centimes=0 AND NEW.credit_centimes=0 THEN RAISE(ABORT,'LEDGER_AMOUNT_REQUIRED') END;
 SELECT CASE WHEN NEW.debit_centimes>0 AND NEW.credit_centimes>0 THEN RAISE(ABORT,'LEDGER_DEBIT_AND_CREDIT_MUTUALLY_EXCLUSIVE') END;
 SELECT CASE WHEN NEW.party_type='CUSTOMER' AND NEW.running_balance_centimes!=(SELECT current_balance_centimes+NEW.debit_centimes-NEW.credit_centimes FROM customers WHERE id=NEW.party_id) THEN RAISE(ABORT,'CUSTOMER_RUNNING_BALANCE_MISMATCH') END;
 SELECT CASE WHEN NEW.party_type='SUPPLIER' AND NEW.running_balance_centimes!=(SELECT current_balance_centimes+NEW.credit_centimes-NEW.debit_centimes FROM suppliers WHERE id=NEW.party_id) THEN RAISE(ABORT,'SUPPLIER_RUNNING_BALANCE_MISMATCH') END;
END;

CREATE TRIGGER trg_ledger_apply_customer AFTER INSERT ON party_ledger_entries WHEN NEW.party_type='CUSTOMER' BEGIN UPDATE customers SET current_balance_centimes=current_balance_centimes+NEW.debit_centimes-NEW.credit_centimes WHERE id=NEW.party_id; END;

CREATE TRIGGER trg_ledger_apply_supplier AFTER INSERT ON party_ledger_entries WHEN NEW.party_type='SUPPLIER' BEGIN UPDATE suppliers SET current_balance_centimes=current_balance_centimes+NEW.credit_centimes-NEW.debit_centimes WHERE id=NEW.party_id; END;

CREATE TRIGGER trg_ledger_no_update BEFORE UPDATE ON party_ledger_entries BEGIN SELECT RAISE(ABORT,'PARTY_LEDGER_IS_IMMUTABLE'); END;

CREATE TRIGGER trg_ledger_no_delete BEFORE DELETE ON party_ledger_entries BEGIN SELECT RAISE(ABORT,'PARTY_LEDGER_IS_IMMUTABLE'); END;

CREATE TRIGGER trg_sale_ledger_post AFTER UPDATE OF status ON sales WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' AND NEW.customer_id IS NOT NULL BEGIN
 INSERT INTO party_ledger_entries(id,tenant_id,party_type,party_id,source_document_type,source_document_id,debit_centimes,credit_centimes,running_balance_centimes,notes)
 SELECT 'LED_SALE_'||NEW.id,NEW.tenant_id,'CUSTOMER',NEW.customer_id,'SALE',NEW.id,NEW.total_amount_centimes,0,current_balance_centimes+NEW.total_amount_centimes,'Sale '||NEW.id FROM customers WHERE id=NEW.customer_id;
END;

CREATE TRIGGER trg_purchase_ledger_post AFTER UPDATE OF status ON purchases WHEN OLD.status='DRAFT' AND NEW.status='ORDERED' BEGIN
 INSERT INTO party_ledger_entries(id,tenant_id,party_type,party_id,source_document_type,source_document_id,debit_centimes,credit_centimes,running_balance_centimes,notes)
 SELECT 'LED_PUR_'||NEW.id,NEW.tenant_id,'SUPPLIER',NEW.supplier_id,'PURCHASE',NEW.id,0,NEW.total_amount_centimes,current_balance_centimes+NEW.total_amount_centimes,'Purchase '||NEW.order_number FROM suppliers WHERE id=NEW.supplier_id;
END;

CREATE TRIGGER trg_payment_ledger_post AFTER UPDATE OF status ON payments WHEN OLD.status='DRAFT' AND NEW.status='POSTED' BEGIN
 INSERT INTO party_ledger_entries(id,tenant_id,party_type,party_id,source_document_type,source_document_id,debit_centimes,credit_centimes,running_balance_centimes,notes)
 SELECT 'LED_PAY_'||NEW.id,NEW.tenant_id,'CUSTOMER',NEW.party_id,'PAYMENT',NEW.id,CASE WHEN NEW.is_reversal=1 THEN NEW.amount ELSE 0 END,CASE WHEN NEW.is_reversal=0 THEN NEW.amount ELSE 0 END,current_balance_centimes+CASE WHEN NEW.is_reversal=1 THEN NEW.amount ELSE -NEW.amount END,'Payment '||NEW.id FROM customers WHERE NEW.party_type='CUSTOMER' AND id=NEW.party_id;
 INSERT INTO party_ledger_entries(id,tenant_id,party_type,party_id,source_document_type,source_document_id,debit_centimes,credit_centimes,running_balance_centimes,notes)
 SELECT 'LED_PAY_'||NEW.id,NEW.tenant_id,'SUPPLIER',NEW.party_id,'PAYMENT',NEW.id,CASE WHEN NEW.is_reversal=0 THEN NEW.amount ELSE 0 END,CASE WHEN NEW.is_reversal=1 THEN NEW.amount ELSE 0 END,current_balance_centimes+CASE WHEN NEW.is_reversal=1 THEN NEW.amount ELSE -NEW.amount END,'Payment '||NEW.id FROM suppliers WHERE NEW.party_type='SUPPLIER' AND id=NEW.party_id;
END;

CREATE TRIGGER trg_purchase_return_ledger_post AFTER UPDATE OF status ON purchase_returns WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' BEGIN
 INSERT INTO party_ledger_entries(id,tenant_id,party_type,party_id,source_document_type,source_document_id,debit_centimes,credit_centimes,running_balance_centimes,notes)
 SELECT 'LED_PRET_'||NEW.id,NEW.tenant_id,'SUPPLIER',NEW.supplier_id,'PURCHASE_RETURN',NEW.id,NEW.total_credit_centimes,0,current_balance_centimes-NEW.total_credit_centimes,'Purchase return '||NEW.return_number FROM suppliers WHERE id=NEW.supplier_id;
END;

CREATE TRIGGER trg_idempotency_device_scope BEFORE INSERT ON idempotency_records BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM registered_devices WHERE id=NEW.device_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'IDEMPOTENCY_DEVICE_TENANT_MISMATCH') END;
 SELECT CASE WHEN NEW.request_hash IS NULL OR NEW.request_hash='' THEN RAISE(ABORT,'IDEMPOTENCY_REQUEST_HASH_REQUIRED') END;
END;

CREATE TRIGGER trg_idempotency_finalize_guard BEFORE UPDATE ON idempotency_records BEGIN
 SELECT CASE WHEN NEW.tenant_id IS NOT OLD.tenant_id OR NEW.device_id IS NOT OLD.device_id OR NEW.client_request_id IS NOT OLD.client_request_id OR NEW.endpoint IS NOT OLD.endpoint OR NEW.request_hash IS NOT OLD.request_hash OR NEW.created_at IS NOT OLD.created_at THEN RAISE(ABORT,'IDEMPOTENCY_KEY_FIELDS_IMMUTABLE') END;
 SELECT CASE WHEN OLD.status!='PROCESSING' OR NEW.status='PROCESSING' THEN RAISE(ABORT,'IDEMPOTENCY_FINALIZED_ONCE') END;
END;

CREATE TRIGGER trg_completed_purchase_no_delete BEFORE DELETE ON purchases WHEN OLD.status!='DRAFT' BEGIN SELECT RAISE(ABORT,'NON_DRAFT_PURCHASE_IMMUTABLE'); END;

CREATE TRIGGER trg_completed_receipt_no_delete BEFORE DELETE ON purchase_receipts WHEN OLD.status='COMPLETED' BEGIN SELECT RAISE(ABORT,'COMPLETED_RECEIPT_IMMUTABLE'); END;

CREATE TRIGGER trg_completed_receipt_no_update BEFORE UPDATE ON purchase_receipts WHEN OLD.status='COMPLETED' BEGIN SELECT RAISE(ABORT,'COMPLETED_RECEIPT_IMMUTABLE'); END;

CREATE TRIGGER trg_adjustment_posted_no_delete BEFORE DELETE ON inventory_adjustments WHEN OLD.status='POSTED' BEGIN SELECT RAISE(ABORT,'POSTED_ADJUSTMENT_IMMUTABLE'); END;

CREATE TRIGGER trg_adjustment_line_insert_draft BEFORE INSERT ON inventory_adjustment_lines WHEN (SELECT status FROM inventory_adjustments WHERE id=NEW.adjustment_id)!='DRAFT' BEGIN SELECT RAISE(ABORT,'ADJUSTMENT_LINES_ONLY_IN_DRAFT'); END;

CREATE TRIGGER trg_adjustment_line_update_draft BEFORE UPDATE ON inventory_adjustment_lines WHEN (SELECT status FROM inventory_adjustments WHERE id=OLD.adjustment_id)!='DRAFT' BEGIN SELECT RAISE(ABORT,'ADJUSTMENT_LINES_ONLY_IN_DRAFT'); END;

CREATE TRIGGER trg_adjustment_line_delete_draft BEFORE DELETE ON inventory_adjustment_lines WHEN (SELECT status FROM inventory_adjustments WHERE id=OLD.adjustment_id)!='DRAFT' BEGIN SELECT RAISE(ABORT,'ADJUSTMENT_LINES_ONLY_IN_DRAFT'); END;

CREATE TRIGGER trg_audit_user_scope BEFORE INSERT ON audit_logs WHEN NEW.user_id IS NOT NULL BEGIN SELECT CASE WHEN (SELECT tenant_id FROM users WHERE id=NEW.user_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'AUDIT_USER_TENANT_MISMATCH') END; END;

CREATE TRIGGER trg_completed_sale_no_core_update BEFORE UPDATE OF tenant_id,store_id,warehouse_id,customer_id,device_id,invoice_number,offline_receipt_number,local_operation_uuid,device_seq_num,device_signature,request_hash,batch_id,subtotal_centimes,discount_centimes,tax_centimes,total_amount_centimes,status ON sales WHEN OLD.status='COMPLETED' BEGIN SELECT RAISE(ABORT,'COMPLETED_SALE_CORE_IMMUTABLE'); END;

CREATE TRIGGER trg_ordered_purchase_no_core_update BEFORE UPDATE OF tenant_id,supplier_id,store_id,order_number,total_amount_centimes ON purchases WHEN OLD.status!='DRAFT' BEGIN SELECT RAISE(ABORT,'ORDERED_PURCHASE_CORE_IMMUTABLE'); END;

CREATE TRIGGER trg_purchase_item_update_draft BEFORE UPDATE ON purchase_items WHEN (SELECT status FROM purchases WHERE id=OLD.purchase_id)!='DRAFT' AND NEW.quantity_received_ticks=OLD.quantity_received_ticks AND NEW.quantity_returned_ticks=OLD.quantity_returned_ticks BEGIN SELECT RAISE(ABORT,'ORDERED_PURCHASE_ITEMS_IMMUTABLE'); END;

CREATE TRIGGER trg_purchase_item_delete_draft BEFORE DELETE ON purchase_items WHEN (SELECT status FROM purchases WHERE id=OLD.purchase_id)!='DRAFT' BEGIN SELECT RAISE(ABORT,'ORDERED_PURCHASE_ITEMS_IMMUTABLE'); END;

CREATE TRIGGER trg_purchase_received_counter_consistency BEFORE UPDATE OF quantity_received_ticks ON purchase_items BEGIN
 SELECT CASE WHEN NEW.quantity_received_ticks != COALESCE((SELECT SUM(pri.quantity_received_ticks) FROM purchase_receipt_items pri JOIN purchase_receipts pr ON pr.id=pri.receipt_id WHERE pri.purchase_item_id=OLD.id AND pr.status IN ('DRAFT','COMPLETED')),0) THEN RAISE(ABORT,'RECEIVED_COUNTER_MUST_MATCH_RECEIPT_LINES') END;
END;

CREATE TRIGGER trg_purchase_returned_counter_consistency BEFORE UPDATE OF quantity_returned_ticks ON purchase_items BEGIN
 SELECT CASE WHEN NEW.quantity_returned_ticks != COALESCE((SELECT SUM(pri.returned_quantity_ticks) FROM purchase_return_items pri JOIN purchase_returns pr ON pr.id=pri.purchase_return_id WHERE pri.purchase_item_id=OLD.id AND pr.status IN ('DRAFT','COMPLETED')),0) THEN RAISE(ABORT,'PURCHASE_RETURN_COUNTER_MUST_MATCH_RETURN_LINES') END;
END;

CREATE TRIGGER trg_sale_returned_counter_consistency BEFORE UPDATE OF returned_quantity_ticks ON sale_items BEGIN
 SELECT CASE WHEN NEW.returned_quantity_ticks != COALESCE((SELECT SUM(sri.returned_quantity_ticks) FROM sale_return_items sri JOIN sale_returns sr ON sr.id=sri.return_id WHERE sri.original_sale_item_id=OLD.id AND sr.status IN ('DRAFT','COMPLETED')),0) THEN RAISE(ABORT,'SALE_RETURN_COUNTER_MUST_MATCH_RETURN_LINES') END;
END;

CREATE TRIGGER trg_sale_item_insert_draft BEFORE INSERT ON sale_items WHEN (SELECT status FROM sales WHERE id=NEW.sale_id)!='DRAFT' BEGIN SELECT RAISE(ABORT,'SALE_ITEMS_ONLY_IN_DRAFT'); END;

CREATE TRIGGER trg_sale_item_update_draft BEFORE UPDATE ON sale_items WHEN (SELECT status FROM sales WHERE id=OLD.sale_id)!='DRAFT' BEGIN
 SELECT CASE WHEN NEW.sale_id IS NOT OLD.sale_id OR NEW.stock_item_id IS NOT OLD.stock_item_id OR NEW.quantity_ticks IS NOT OLD.quantity_ticks OR NEW.unit_price_ticks IS NOT OLD.unit_price_ticks OR NEW.discount_bps IS NOT OLD.discount_bps OR NEW.tax_bps IS NOT OLD.tax_bps OR NEW.line_total_centimes IS NOT OLD.line_total_centimes OR NEW.cost_at_sale_ticks IS NOT OLD.cost_at_sale_ticks THEN RAISE(ABORT,'POSTED_SALE_ITEMS_IMMUTABLE') END;
 SELECT CASE WHEN NEW.returned_quantity_ticks != COALESCE((SELECT SUM(sri.returned_quantity_ticks) FROM sale_return_items sri JOIN sale_returns sr ON sr.id=sri.return_id WHERE sri.original_sale_item_id=OLD.id AND sr.status IN ('DRAFT','COMPLETED')),0) THEN RAISE(ABORT,'SALE_RETURN_COUNTER_MUST_MATCH_RETURN_LINES') END;
END;

CREATE TRIGGER trg_sale_item_delete_draft BEFORE DELETE ON sale_items WHEN (SELECT status FROM sales WHERE id=OLD.sale_id)!='DRAFT' BEGIN SELECT RAISE(ABORT,'POSTED_SALE_ITEMS_IMMUTABLE'); END;

CREATE TRIGGER trg_purchase_item_insert_draft BEFORE INSERT ON purchase_items WHEN (SELECT status FROM purchases WHERE id=NEW.purchase_id)!='DRAFT' BEGIN SELECT RAISE(ABORT,'PURCHASE_ITEMS_ONLY_IN_DRAFT'); END;

CREATE TRIGGER trg_purchase_item_core_update_guard BEFORE UPDATE ON purchase_items WHEN (SELECT status FROM purchases WHERE id=OLD.purchase_id)!='DRAFT' BEGIN
 SELECT CASE WHEN NEW.purchase_id IS NOT OLD.purchase_id OR NEW.stock_item_id IS NOT OLD.stock_item_id OR NEW.quantity_ordered_ticks IS NOT OLD.quantity_ordered_ticks OR NEW.unit_cost_ticks IS NOT OLD.unit_cost_ticks OR NEW.line_total_centimes IS NOT OLD.line_total_centimes THEN RAISE(ABORT,'ORDERED_PURCHASE_ITEMS_CORE_IMMUTABLE') END;
 SELECT CASE WHEN NEW.quantity_received_ticks != COALESCE((SELECT SUM(pri.quantity_received_ticks) FROM purchase_receipt_items pri JOIN purchase_receipts pr ON pr.id=pri.receipt_id WHERE pri.purchase_item_id=OLD.id AND pr.status IN ('DRAFT','COMPLETED')),0) THEN RAISE(ABORT,'RECEIVED_COUNTER_MUST_MATCH_RECEIPT_LINES') END;
 SELECT CASE WHEN NEW.quantity_returned_ticks != COALESCE((SELECT SUM(pri.returned_quantity_ticks) FROM purchase_return_items pri JOIN purchase_returns pr ON pr.id=pri.purchase_return_id WHERE pri.purchase_item_id=OLD.id AND pr.status IN ('DRAFT','COMPLETED')),0) THEN RAISE(ABORT,'PURCHASE_RETURN_COUNTER_MUST_MATCH_RETURN_LINES') END;
END;

CREATE TRIGGER trg_adjustment_header_start_draft BEFORE INSERT ON inventory_adjustments WHEN NEW.status!='DRAFT' BEGIN SELECT RAISE(ABORT,'ADJUSTMENT_MUST_START_AS_DRAFT'); END;

CREATE TRIGGER trg_adjustment_scope_insert BEFORE INSERT ON inventory_adjustments BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM warehouses WHERE id=NEW.warehouse_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'ADJUSTMENT_WAREHOUSE_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_adjustment_line_guard BEFORE INSERT ON inventory_adjustment_lines BEGIN
 SELECT CASE WHEN (SELECT status FROM inventory_adjustments WHERE id=NEW.adjustment_id)!='DRAFT' THEN RAISE(ABORT,'ADJUSTMENT_LINES_ONLY_IN_DRAFT') END;
 SELECT CASE WHEN NEW.system_quantity_ticks<0 OR NEW.actual_quantity_ticks<0 OR NEW.unit_cost_ticks<0 THEN RAISE(ABORT,'ADJUSTMENT_QUANTITIES_AND_COST_MUST_BE_NONNEGATIVE') END;
 SELECT CASE WHEN NEW.difference_ticks != NEW.actual_quantity_ticks-NEW.system_quantity_ticks THEN RAISE(ABORT,'ADJUSTMENT_DIFFERENCE_MISMATCH') END;
 SELECT CASE WHEN NEW.system_quantity_ticks != COALESCE((SELECT on_hand_ticks FROM inventory_balances WHERE warehouse_id=(SELECT warehouse_id FROM inventory_adjustments WHERE id=NEW.adjustment_id) AND stock_item_id=NEW.stock_item_id),0) THEN RAISE(ABORT,'ADJUSTMENT_SYSTEM_QUANTITY_STALE') END;
 SELECT CASE WHEN NEW.actual_quantity_ticks < COALESCE((SELECT reserved_ticks FROM inventory_balances WHERE warehouse_id=(SELECT warehouse_id FROM inventory_adjustments WHERE id=NEW.adjustment_id) AND stock_item_id=NEW.stock_item_id),0) THEN RAISE(ABORT,'ADJUSTMENT_CANNOT_REDUCE_BELOW_RESERVED') END;
 SELECT CASE WHEN (SELECT tenant_id FROM products p JOIN stock_items si ON si.product_id=p.id WHERE si.id=NEW.stock_item_id) IS NOT (SELECT tenant_id FROM inventory_adjustments WHERE id=NEW.adjustment_id) THEN RAISE(ABORT,'ADJUSTMENT_STOCK_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_adjustment_complete_guard BEFORE UPDATE OF status ON inventory_adjustments WHEN OLD.status='DRAFT' AND NEW.status='POSTED' BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM inventory_adjustment_lines WHERE adjustment_id=OLD.id) THEN RAISE(ABORT,'EMPTY_ADJUSTMENT_CANNOT_POST') END;
END;

CREATE TRIGGER trg_adjustment_complete_post AFTER UPDATE OF status ON inventory_adjustments WHEN OLD.status='DRAFT' AND NEW.status='POSTED' BEGIN
 INSERT INTO inventory_movements(id,tenant_id,warehouse_id,stock_item_id,movement_type,source_event_id,reference_line_id,quantity_ticks,unit_cost_ticks,total_cost_centimes)
 SELECT 'ADJ_IN_'||id,NEW.tenant_id,NEW.warehouse_id,stock_item_id,'ADJUSTMENT_IN','ADJUSTMENT:'||id,id,difference_ticks,unit_cost_ticks,CAST(difference_ticks*unit_cost_ticks/1000000 AS INTEGER)
 FROM inventory_adjustment_lines WHERE adjustment_id=NEW.id AND difference_ticks>0;
 INSERT INTO inventory_movements(id,tenant_id,warehouse_id,stock_item_id,movement_type,source_event_id,reference_line_id,quantity_ticks,unit_cost_ticks,total_cost_centimes)
 SELECT 'ADJ_OUT_'||id,NEW.tenant_id,NEW.warehouse_id,stock_item_id,'ADJUSTMENT_OUT','ADJUSTMENT:'||id,id,0-difference_ticks,unit_cost_ticks,CAST((0-difference_ticks)*unit_cost_ticks/1000000 AS INTEGER)
 FROM inventory_adjustment_lines WHERE adjustment_id=NEW.id AND difference_ticks<0;
END;

CREATE TRIGGER trg_adjustment_header_no_update BEFORE UPDATE ON inventory_adjustments WHEN OLD.status!='DRAFT' BEGIN SELECT RAISE(ABORT,'NON_DRAFT_ADJUSTMENT_IMMUTABLE'); END;

CREATE TRIGGER trg_adjustment_header_fields_locked BEFORE UPDATE OF tenant_id,warehouse_id,adjustment_number,reason,created_at ON inventory_adjustments BEGIN SELECT RAISE(ABORT,'ADJUSTMENT_HEADER_FIELDS_IMMUTABLE'); END;

CREATE TRIGGER trg_adjustment_header_no_delete BEFORE DELETE ON inventory_adjustments WHEN OLD.status!='DRAFT' BEGIN SELECT RAISE(ABORT,'NON_DRAFT_ADJUSTMENT_IMMUTABLE'); END;

CREATE TRIGGER trg_price_list_item_tenant_insert BEFORE INSERT ON price_list_items BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM price_lists WHERE id=NEW.price_list_id) IS NOT (SELECT tenant_id FROM products WHERE id=NEW.product_id) THEN RAISE(ABORT,'PRICE_LIST_PRODUCT_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_price_list_item_tenant_update BEFORE UPDATE OF price_list_id,product_id ON price_list_items BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM price_lists WHERE id=NEW.price_list_id) IS NOT (SELECT tenant_id FROM products WHERE id=NEW.product_id) THEN RAISE(ABORT,'PRICE_LIST_PRODUCT_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_product_category_scope_update BEFORE UPDATE OF tenant_id,category_id ON products WHEN NEW.category_id IS NOT NULL BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM categories WHERE id=NEW.category_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'PRODUCT_CATEGORY_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_customer_group_scope_update BEFORE UPDATE OF tenant_id,group_id ON customers WHEN NEW.group_id IS NOT NULL BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM customer_groups WHERE id=NEW.group_id) IS NOT NEW.tenant_id THEN RAISE(ABORT,'CUSTOMER_GROUP_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_purchase_receipt_status_transition BEFORE UPDATE OF status ON purchase_receipts BEGIN
 SELECT CASE WHEN OLD.status!='DRAFT' OR NEW.status NOT IN ('COMPLETED','CANCELLED') THEN RAISE(ABORT,'INVALID_RECEIPT_STATUS_TRANSITION') END;
END;

CREATE TRIGGER trg_purchase_return_status_transition BEFORE UPDATE OF status ON purchase_returns BEGIN
 SELECT CASE WHEN OLD.status!='DRAFT' OR NEW.status NOT IN ('COMPLETED','CANCELLED') THEN RAISE(ABORT,'INVALID_PURCHASE_RETURN_STATUS_TRANSITION') END;
END;

CREATE TRIGGER trg_sale_return_status_transition BEFORE UPDATE OF status ON sale_returns BEGIN
 SELECT CASE WHEN OLD.status!='DRAFT' OR NEW.status NOT IN ('COMPLETED','CANCELLED') THEN RAISE(ABORT,'INVALID_SALE_RETURN_STATUS_TRANSITION') END;
END;

CREATE TRIGGER trg_sale_financial_totals_guard BEFORE UPDATE OF status ON sales WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' BEGIN
 SELECT CASE WHEN NEW.subtotal_centimes-NEW.discount_centimes+NEW.tax_centimes!=NEW.total_amount_centimes THEN RAISE(ABORT,'SALE_HEADER_TOTAL_MISMATCH') END;
END;

CREATE TRIGGER trg_purchase_order_totals_guard BEFORE UPDATE OF status ON purchases WHEN OLD.status='DRAFT' AND NEW.status='ORDERED' BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM purchase_items WHERE purchase_id=OLD.id) THEN RAISE(ABORT,'PURCHASE_REQUIRES_ITEMS') END;
 SELECT CASE WHEN (SELECT COALESCE(SUM(line_total_centimes),0) FROM purchase_items WHERE purchase_id=OLD.id)!=NEW.total_amount_centimes THEN RAISE(ABORT,'PURCHASE_HEADER_TOTAL_MISMATCH') END;
END;

CREATE TRIGGER trg_purchase_return_value_guard BEFORE UPDATE OF status ON purchase_returns WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' BEGIN
 SELECT CASE WHEN NEW.total_credit_centimes+COALESCE((SELECT SUM(total_credit_centimes) FROM purchase_returns WHERE purchase_id=NEW.purchase_id AND status='COMPLETED'),0)>(SELECT total_amount_centimes FROM purchases WHERE id=NEW.purchase_id) THEN RAISE(ABORT,'PURCHASE_RETURN_VALUE_EXCEEDS_PURCHASE_TOTAL') END;
END;

CREATE TRIGGER trg_sale_return_value_guard BEFORE UPDATE OF status ON sale_returns WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' BEGIN
 SELECT CASE WHEN NEW.total_refund_centimes+COALESCE((SELECT SUM(total_refund_centimes) FROM sale_returns WHERE original_sale_id=NEW.original_sale_id AND status='COMPLETED'),0)>(SELECT total_amount_centimes FROM sales WHERE id=NEW.original_sale_id) THEN RAISE(ABORT,'SALE_RETURN_VALUE_EXCEEDS_SALE_TOTAL') END;
 SELECT CASE WHEN NEW.refund_status='CREDITED_TO_ACCOUNT' AND NEW.customer_id IS NULL THEN RAISE(ABORT,'ACCOUNT_CREDIT_REFUND_REQUIRES_CUSTOMER') END;
 SELECT CASE WHEN NEW.refund_status='REFUNDED_CASH' AND (SELECT cr.store_id FROM cash_shifts cs JOIN cash_registers cr ON cr.id=cs.cash_register_id WHERE cs.id=NEW.shift_id) IS NOT NEW.store_id THEN RAISE(ABORT,'SALE_RETURN_CASH_SHIFT_STORE_MISMATCH') END;
END;

CREATE TRIGGER trg_sale_return_item_value_active BEFORE INSERT ON sale_return_items BEGIN
 SELECT CASE WHEN NEW.line_total_centimes+COALESCE((SELECT SUM(sri.line_total_centimes) FROM sale_return_items sri JOIN sale_returns sr ON sr.id=sri.return_id WHERE sri.original_sale_item_id=NEW.original_sale_item_id AND sr.status IN ('DRAFT','COMPLETED')),0)>(SELECT line_total_centimes FROM sale_items WHERE id=NEW.original_sale_item_id) THEN RAISE(ABORT,'ACTIVE_SALE_RETURN_VALUE_EXCEEDS_SOURCE_LINE') END;
END;

CREATE TRIGGER trg_cash_shift_insert_open_only BEFORE INSERT ON cash_shifts WHEN NEW.status!='OPEN' BEGIN SELECT RAISE(ABORT,'CASH_SHIFT_MUST_START_OPEN'); END;

CREATE TRIGGER trg_cash_shift_scope_insert BEFORE INSERT ON cash_shifts BEGIN
 SELECT CASE WHEN (SELECT tenant_id FROM users WHERE id=NEW.user_id) IS NOT (SELECT tenant_id FROM cash_registers WHERE id=NEW.cash_register_id) THEN RAISE(ABORT,'CASH_SHIFT_USER_REGISTER_TENANT_MISMATCH') END;
END;

CREATE TRIGGER trg_cash_shift_closed_immutable BEFORE UPDATE ON cash_shifts WHEN OLD.status='CLOSED' BEGIN SELECT RAISE(ABORT,'CLOSED_CASH_SHIFT_IMMUTABLE'); END;

CREATE TRIGGER trg_expense_immutable_update BEFORE UPDATE ON expenses BEGIN SELECT RAISE(ABORT,'EXPENSE_RECORDS_ARE_IMMUTABLE_USE_REVERSAL'); END;

CREATE TRIGGER trg_expense_immutable_delete BEFORE DELETE ON expenses BEGIN SELECT RAISE(ABORT,'EXPENSE_RECORDS_ARE_IMMUTABLE'); END;

CREATE TRIGGER trg_allocation_update_draft_guard BEFORE UPDATE ON payment_allocations WHEN (SELECT status FROM payments WHERE id=OLD.payment_id)!='DRAFT' BEGIN SELECT RAISE(ABORT,'POSTED_PAYMENT_ALLOCATIONS_IMMUTABLE'); END;

CREATE TRIGGER trg_allocation_delete_draft_guard BEFORE DELETE ON payment_allocations WHEN (SELECT status FROM payments WHERE id=OLD.payment_id)!='DRAFT' BEGIN SELECT RAISE(ABORT,'POSTED_PAYMENT_ALLOCATIONS_IMMUTABLE'); END;

CREATE TRIGGER trg_ledger_source_document_guard BEFORE INSERT ON party_ledger_entries BEGIN
 SELECT CASE WHEN NEW.source_document_type='SALE' AND NOT EXISTS(SELECT 1 FROM sales s WHERE s.id=NEW.source_document_id AND s.status='COMPLETED' AND s.tenant_id=NEW.tenant_id AND s.customer_id=NEW.party_id AND NEW.party_type='CUSTOMER') THEN RAISE(ABORT,'LEDGER_SALE_SOURCE_MISMATCH') END;
 SELECT CASE WHEN NEW.source_document_type='PURCHASE' AND NOT EXISTS(SELECT 1 FROM purchases p WHERE p.id=NEW.source_document_id AND p.status IN ('ORDERED','RECEIVED') AND p.tenant_id=NEW.tenant_id AND p.supplier_id=NEW.party_id AND NEW.party_type='SUPPLIER') THEN RAISE(ABORT,'LEDGER_PURCHASE_SOURCE_MISMATCH') END;
 SELECT CASE WHEN NEW.source_document_type='PAYMENT' AND NOT EXISTS(SELECT 1 FROM payments p WHERE p.id=NEW.source_document_id AND p.status='POSTED' AND p.tenant_id=NEW.tenant_id AND p.party_id=NEW.party_id AND p.party_type=NEW.party_type) THEN RAISE(ABORT,'LEDGER_PAYMENT_SOURCE_MISMATCH') END;
 SELECT CASE WHEN NEW.source_document_type='SALE_RETURN' AND NOT EXISTS(SELECT 1 FROM sale_returns r WHERE r.id=NEW.source_document_id AND r.status='COMPLETED' AND r.tenant_id=NEW.tenant_id AND r.customer_id=NEW.party_id AND NEW.party_type='CUSTOMER') THEN RAISE(ABORT,'LEDGER_SALE_RETURN_SOURCE_MISMATCH') END;
 SELECT CASE WHEN NEW.source_document_type='PURCHASE_RETURN' AND NOT EXISTS(SELECT 1 FROM purchase_returns r WHERE r.id=NEW.source_document_id AND r.status='COMPLETED' AND r.tenant_id=NEW.tenant_id AND r.supplier_id=NEW.party_id AND NEW.party_type='SUPPLIER') THEN RAISE(ABORT,'LEDGER_PURCHASE_RETURN_SOURCE_MISMATCH') END;
END;

CREATE TRIGGER trg_adjustment_post_snapshot_guard BEFORE UPDATE OF status ON inventory_adjustments WHEN OLD.status='DRAFT' AND NEW.status='POSTED' BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM inventory_adjustment_lines l WHERE l.adjustment_id=OLD.id AND l.system_quantity_ticks!=COALESCE((SELECT on_hand_ticks FROM inventory_balances b WHERE b.warehouse_id=OLD.warehouse_id AND b.stock_item_id=l.stock_item_id),0)) THEN RAISE(ABORT,'ADJUSTMENT_STOCK_CHANGED_AFTER_COUNT') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM inventory_adjustment_lines l WHERE l.adjustment_id=OLD.id AND l.actual_quantity_ticks<COALESCE((SELECT reserved_ticks FROM inventory_balances b WHERE b.warehouse_id=OLD.warehouse_id AND b.stock_item_id=l.stock_item_id),0)) THEN RAISE(ABORT,'ADJUSTMENT_ACTUAL_BELOW_RESERVED') END;
END;

CREATE TRIGGER trg_movement_total_cost_guard BEFORE INSERT ON inventory_movements BEGIN
 SELECT CASE WHEN NEW.total_cost_centimes!=CAST(NEW.quantity_ticks*NEW.unit_cost_ticks/1000000 AS INTEGER) THEN RAISE(ABORT,'MOVEMENT_TOTAL_COST_MISMATCH') END;
END;

CREATE TRIGGER trg_purchase_item_cost_guard BEFORE INSERT ON purchase_items BEGIN
 SELECT CASE WHEN NEW.line_total_centimes!=CAST(NEW.quantity_ordered_ticks*NEW.unit_cost_ticks/1000000 AS INTEGER) THEN RAISE(ABORT,'PURCHASE_LINE_TOTAL_MISMATCH') END;
END;

CREATE TRIGGER trg_purchase_item_cost_update_guard BEFORE UPDATE OF quantity_ordered_ticks,unit_cost_ticks,line_total_centimes ON purchase_items BEGIN
 SELECT CASE WHEN NEW.line_total_centimes!=CAST(NEW.quantity_ordered_ticks*NEW.unit_cost_ticks/1000000 AS INTEGER) THEN RAISE(ABORT,'PURCHASE_LINE_TOTAL_MISMATCH') END;
END;

CREATE TRIGGER trg_purchase_return_item_cost_guard BEFORE INSERT ON purchase_return_items BEGIN
 SELECT CASE WHEN NEW.line_total_centimes!=CAST(NEW.returned_quantity_ticks*NEW.unit_cost_ticks/1000000 AS INTEGER) THEN RAISE(ABORT,'PURCHASE_RETURN_LINE_TOTAL_MISMATCH') END;
END;

CREATE TRIGGER trg_sale_return_item_cost_guard BEFORE INSERT ON sale_return_items BEGIN
 SELECT CASE WHEN NEW.line_total_centimes!=CAST(NEW.returned_quantity_ticks*NEW.refund_unit_price_ticks/1000000 AS INTEGER) THEN RAISE(ABORT,'SALE_RETURN_LINE_TOTAL_MISMATCH') END;
END;

CREATE TRIGGER trg_cancel_draft_sale_release_quota BEFORE UPDATE OF status ON sales WHEN OLD.status='DRAFT' AND NEW.status='CANCELLED' BEGIN
 DELETE FROM sale_item_quota_deductions WHERE sale_item_id IN (SELECT id FROM sale_items WHERE sale_id=OLD.id);
END;

CREATE TRIGGER trg_purchase_status_transition_guard BEFORE UPDATE OF status ON purchases BEGIN
 SELECT CASE WHEN OLD.status='DRAFT' AND NEW.status NOT IN ('ORDERED','CANCELLED') THEN RAISE(ABORT,'INVALID_PURCHASE_STATUS_TRANSITION') END;
 SELECT CASE WHEN OLD.status IN ('ORDERED','RECEIVED') AND NEW.status!=OLD.status AND NEW.status!='RECEIVED' THEN RAISE(ABORT,'ORDERED_PURCHASE_CANNOT_BE_CANCELLED_OR_REOPENED') END;
END;

CREATE TRIGGER trg_quota_fields_immutable BEFORE UPDATE OF tenant_id,device_id,warehouse_id,stock_item_id,quota_quantity_ticks,valid_until,signed_token,created_at ON inventory_quotas BEGIN SELECT RAISE(ABORT,'QUOTA_IDENTITY_AND_SIGNED_PAYLOAD_IMMUTABLE'); END;

CREATE TRIGGER trg_quota_consumed_counter_guard BEFORE UPDATE OF consumed_quantity_ticks ON inventory_quotas BEGIN
 SELECT CASE WHEN NEW.consumed_quantity_ticks!=COALESCE((SELECT SUM(deducted_quantity_ticks) FROM sale_item_quota_deductions WHERE quota_id=OLD.id),0) THEN RAISE(ABORT,'QUOTA_CONSUMED_COUNTER_MUST_MATCH_DEDUCTIONS') END;
END;

CREATE TRIGGER trg_quota_status_transition_guard BEFORE UPDATE OF status ON inventory_quotas BEGIN
 SELECT CASE WHEN OLD.status NOT IN ('ACTIVE','LOST_DEVICE_EXPOSURE') OR NEW.status NOT IN ('RECONCILED','EXPIRED','VOIDED_BY_ADMIN','LOST_DEVICE_EXPOSURE') OR NEW.status=OLD.status THEN RAISE(ABORT,'INVALID_QUOTA_STATUS_TRANSITION') END;
END;

CREATE TRIGGER trg_device_sequence_guard BEFORE UPDATE OF last_seq_num ON registered_devices WHEN NEW.last_seq_num!=OLD.last_seq_num BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM sales s WHERE s.device_id=OLD.id AND s.device_seq_num=NEW.last_seq_num AND s.status='COMPLETED') THEN RAISE(ABORT,'DEVICE_SEQUENCE_MUST_MATCH_COMPLETED_SALE') END;
END;

CREATE TRIGGER trg_device_public_key_immutable BEFORE UPDATE OF public_key,tenant_id,store_id ON registered_devices BEGIN SELECT RAISE(ABORT,'DEVICE_IDENTITY_AND_PUBLIC_KEY_IMMUTABLE'); END;

CREATE TRIGGER trg_idempotency_no_delete BEFORE DELETE ON idempotency_records BEGIN
 SELECT CASE WHEN OLD.status='PROCESSING' OR OLD.created_at>=strftime('%Y-%m-%dT%H:%M:%fZ','now','-30 days') THEN RAISE(ABORT,'IDEMPOTENCY_RECORD_WITHIN_RETENTION_WINDOW') END;
END;

CREATE TRIGGER trg_sale_invoice_required_guard BEFORE UPDATE OF status ON sales WHEN OLD.status='DRAFT' AND NEW.status='COMPLETED' BEGIN
 SELECT CASE WHEN NEW.invoice_number IS NULL OR NEW.invoice_number='' THEN RAISE(ABORT,'COMPLETED_SALE_REQUIRES_HOST_INVOICE_NUMBER') END;
END;

