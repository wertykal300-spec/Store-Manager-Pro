PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;
INSERT INTO tenants(id,name,is_active) VALUES ('TENANT_DEFAULT','Default Store Tenant',1);
INSERT INTO stores(id,tenant_id,code,name,address,phone,is_active) VALUES ('STORE_DEFAULT','TENANT_DEFAULT','MAIN','Main Store',NULL,NULL,1);
INSERT INTO fiscal_years(id,tenant_id,year,start_date,end_date,is_closed) VALUES ('FY_'||strftime('%Y','now','localtime'),'TENANT_DEFAULT',CAST(strftime('%Y','now','localtime') AS INTEGER),strftime('%Y','now','localtime')||'-01-01',strftime('%Y','now','localtime')||'-12-31',0);
INSERT INTO currencies(code,name,symbol,decimal_places,is_base) VALUES ('DZD','Algerian Dinar','دج',2,1);
INSERT INTO units_of_measure(id,dimension,name_ar,name_fr,symbol,is_fractional) VALUES
 ('UOM_PIECE','COUNT','قطعة','Pièce','pc',0),
 ('UOM_KG','WEIGHT','كيلوغرام','Kilogramme','kg',1),
 ('UOM_GRAM','WEIGHT','غرام','Gramme','g',1),
 ('UOM_METER','LENGTH','متر','Mètre','m',1),
 ('UOM_LITER','VOLUME','لتر','Litre','L',1);
INSERT INTO unit_conversions(id,from_unit_id,to_unit_id,factor_numerator,factor_denominator) VALUES ('CONV_KG_G','UOM_KG','UOM_GRAM',1000,1);
INSERT INTO roles(id,tenant_id,name,description,is_system) VALUES
 ('ROLE_ADMIN','TENANT_DEFAULT','Administrator','Full system administration',1),
 ('ROLE_CASHIER','TENANT_DEFAULT','Cashier','POS and cash operations',1),
 ('ROLE_STOCK_MANAGER','TENANT_DEFAULT','Stock Manager','Inventory and purchasing',1);
INSERT INTO permissions(code,category,description) VALUES
 ('SALE_CREATE','SALES','Create and complete sales'),
 ('INVENTORY_ADJUST','INVENTORY','Adjust inventory'),
 ('PAYMENT_CREATE','FINANCE','Create payments'),
 ('REPORT_VIEW','REPORTS','View reports');
INSERT INTO role_permissions(role_id,permission_code) VALUES
 ('ROLE_ADMIN','SALE_CREATE'),('ROLE_ADMIN','INVENTORY_ADJUST'),('ROLE_ADMIN','PAYMENT_CREATE'),('ROLE_ADMIN','REPORT_VIEW'),
 ('ROLE_CASHIER','SALE_CREATE'),('ROLE_CASHIER','PAYMENT_CREATE'),('ROLE_STOCK_MANAGER','INVENTORY_ADJUST');
INSERT INTO warehouses(id,tenant_id,store_id,name,is_default,is_active) VALUES ('WH_DEFAULT','TENANT_DEFAULT','STORE_DEFAULT','Main Warehouse',1,1);
INSERT INTO cash_registers(id,tenant_id,store_id,name,code,is_active) VALUES ('CR_DEFAULT','TENANT_DEFAULT','STORE_DEFAULT','Main Cash Register','POS-01',1);
-- No placeholder ACTIVE license is seeded. Activation creates a verified signed license record.
WITH document_types(document_type) AS (VALUES ('SALE'),('SALE_RETURN'),('PURCHASE'),('PURCHASE_RECEIPT'),('PURCHASE_RETURN'),('PAYMENT'),('ADJUSTMENT'))
INSERT INTO document_sequences(id,tenant_id,store_id,fiscal_year,document_type,last_sequence_number,prefix,suffix,padding)
SELECT 'SEQ_'||document_type||'_'||strftime('%Y','now','localtime'),'TENANT_DEFAULT','STORE_DEFAULT',CAST(strftime('%Y','now','localtime') AS INTEGER),document_type,0,
       CASE document_type WHEN 'SALE' THEN 'S-'||strftime('%Y','now','localtime')||'-' WHEN 'SALE_RETURN' THEN 'SR-'||strftime('%Y','now','localtime')||'-' WHEN 'PURCHASE' THEN 'P-'||strftime('%Y','now','localtime')||'-'
            WHEN 'PURCHASE_RECEIPT' THEN 'GRN-'||strftime('%Y','now','localtime')||'-' WHEN 'PURCHASE_RETURN' THEN 'PR-'||strftime('%Y','now','localtime')||'-' WHEN 'PAYMENT' THEN 'PAY-'||strftime('%Y','now','localtime')||'-' ELSE 'ADJ-'||strftime('%Y','now','localtime')||'-' END,
       NULL,6
FROM document_types;
COMMIT;
