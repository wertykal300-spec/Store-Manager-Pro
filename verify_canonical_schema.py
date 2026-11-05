#!/usr/bin/env python3
"""Repeatable SQLite verification suite for Store Manager Pro Fresh Baseline v1.
Run: python verify_canonical_schema.py
This validates SQL invariants. Ed25519 verification is separately exercised here;
Ktor integration/platform Keystore behavior is not proven by this SQLite-only suite.
"""
from __future__ import annotations
import sqlite3, sys, hashlib
from pathlib import Path
from datetime import datetime, timezone, timedelta

HERE = Path(__file__).resolve().parent
SCHEMA = HERE / "canonical_schema.sql"
SEED = HERE / "seed_data.sql"

db_target = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else ":memory:"
con = sqlite3.connect(db_target)
con.row_factory = sqlite3.Row
con.execute("PRAGMA foreign_keys=ON")
con.execute("PRAGMA busy_timeout=5000")

if db_target != ":memory:":
    print(f"Attached to SQLDelight generated database: {db_target}")

results: list[tuple[str,str,str]] = []


def run_sql(sql: str, params=()):
    return con.execute(sql, params)


def test_ok(name, fn):
    try:
        fn()
        results.append((name, "PASS", "Accepted as expected"))
    except Exception as exc:
        results.append((name, "FAIL", f"Unexpected {type(exc).__name__}: {exc}"))


def test_reject(name, fn):
    con.execute("SAVEPOINT case_test")
    try:
        fn()
        con.execute("ROLLBACK TO case_test")
        con.execute("RELEASE case_test")
        results.append((name, "FAIL", "Invalid operation was accepted"))
    except sqlite3.DatabaseError as exc:
        con.execute("ROLLBACK TO case_test")
        con.execute("RELEASE case_test")
        results.append((name, "PASS", f"Rejected: {str(exc)[:180]}"))
    except Exception as exc:
        con.execute("ROLLBACK TO case_test")
        con.execute("RELEASE case_test")
        results.append((name, "FAIL", f"Unexpected non-SQL error: {type(exc).__name__}: {exc}"))


def assert_eq(actual, expected, message):
    if actual != expected:
        raise AssertionError(f"{message}: expected {expected!r}, got {actual!r}")

# Baseline initialization.
try:
    if db_target == ":memory:":
        con.executescript(SCHEMA.read_text(encoding="utf-8"))
    con.executescript(SEED.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"FATAL: schema/seed initialization failed: {exc}", file=sys.stderr)
    raise


# Add test fixtures; this is deliberately separate from production seed data.
con.executescript("""
INSERT INTO tenants(id,name) VALUES('TENANT_2','Second Tenant');
INSERT INTO stores(id,tenant_id,code,name) VALUES('STORE_2','TENANT_2','MAIN','Second Store');
INSERT INTO fiscal_years(id,tenant_id,year,start_date,end_date) VALUES('FY_2','TENANT_2',2026,'2026-01-01','2026-12-31');
INSERT INTO warehouses(id,tenant_id,store_id,name,is_default) VALUES('WH_2','TENANT_2','STORE_2','Second Warehouse',1);
INSERT INTO warehouses(id,tenant_id,store_id,name,is_default) VALUES('WH_AUX','TENANT_DEFAULT','STORE_DEFAULT','Aux Warehouse',0);
INSERT INTO registered_devices(id,tenant_id,store_id,device_name,device_type,public_key,pairing_status,last_seq_num)
VALUES('DEV_1','TENANT_DEFAULT','STORE_DEFAULT','Test POS','ANDROID_POS','PUBKEY_1','ACTIVE',0),
      ('DEV_2','TENANT_2','STORE_2','Other POS','ANDROID_POS','PUBKEY_2','ACTIVE',0);
INSERT INTO users(id,tenant_id,username,password_hash,salt,full_name) VALUES('USER_1','TENANT_DEFAULT','test-admin','test-hash','test-salt','Test Admin');
INSERT INTO customers(id,tenant_id,name,credit_limit_centimes,current_balance_centimes) VALUES('CUST_1','TENANT_DEFAULT','Customer One',1000000,0);
INSERT INTO suppliers(id,tenant_id,name,current_balance_centimes) VALUES('SUP_1','TENANT_DEFAULT','Supplier One',0);
INSERT INTO expense_categories(id,tenant_id,name) VALUES('EXP_CAT_1','TENANT_DEFAULT','General');
INSERT INTO products(id,tenant_id,name,barcode,base_unit_id,has_variants) VALUES('PROD_1','TENANT_DEFAULT','Product One','111111','UOM_PIECE',0);
INSERT INTO products(id,tenant_id,name,barcode,base_unit_id,has_variants) VALUES('PROD_2','TENANT_DEFAULT','Product Two','222222','UOM_PIECE',0);
INSERT INTO products(id,tenant_id,name,base_unit_id,has_variants) VALUES('PROD_VAR','TENANT_DEFAULT','Variant Product','UOM_PIECE',1);
INSERT INTO product_variants(id,product_id,sku,barcode,variant_name) VALUES('VAR_1','PROD_VAR','SKU_VAR_1','333333','Red');
INSERT INTO price_lists(id,tenant_id,name,currency_code,is_default) VALUES('PL_1','TENANT_DEFAULT','Default DZD','DZD',1);
""")

stock1 = con.execute("SELECT id FROM stock_items WHERE product_id='PROD_1' AND variant_id IS NULL").fetchone()[0]
stock2 = con.execute("SELECT id FROM stock_items WHERE product_id='PROD_2' AND variant_id IS NULL").fetchone()[0]
variant_stock = con.execute("SELECT id FROM stock_items WHERE variant_id='VAR_1'").fetchone()[0]

# Initial inventory via the immutable movement ledger, never by editing balances directly.
def seed_stock(stock, wh='WH_DEFAULT', qty=100_000, cost=100_000, event='OPENING'):
    con.execute("""INSERT INTO inventory_movements
      (id,tenant_id,warehouse_id,stock_item_id,movement_type,source_event_id,quantity_ticks,unit_cost_ticks,total_cost_centimes)
      VALUES(?,?,?,?,?,?,?,?,?)""",
      (f'MOV_{event}_{stock}_{wh}', 'TENANT_DEFAULT', wh, stock, 'ADJUSTMENT_IN',
       f'{event}:{stock}:{wh}', qty, cost, qty*cost//1_000_000))

seed_stock(stock1, event='OPEN1')
seed_stock(stock2, event='OPEN2')
seed_stock(stock1, wh='WH_AUX', qty=30_000, cost=100_000, event='OPEN_AUX')

# T01-T04: baseline and seed validity.
test_ok('T01 schema creates 55 tables and v1 user_version', lambda: (
    assert_eq(con.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").fetchone()[0],55,'table count'),
    assert_eq(con.execute('PRAGMA user_version').fetchone()[0],1,'user_version')))
test_ok('T02 safe seed and test fixtures pass foreign_key_check', lambda: assert_eq(con.execute('PRAGMA foreign_key_check').fetchall(),[], 'foreign key check'))
test_ok('T03 SQLite integrity_check returns ok', lambda: assert_eq(con.execute('PRAGMA integrity_check').fetchone()[0],'ok','integrity_check'))
test_ok('T04 product name-only insert creates UOM default and StockItem', lambda: (
    con.execute("INSERT INTO products(id,tenant_id,name) VALUES('PROD_NAME_ONLY','TENANT_DEFAULT','Name Only')"),
    assert_eq(con.execute("SELECT base_unit_id FROM products WHERE id='PROD_NAME_ONLY'").fetchone()[0],'UOM_PIECE','default UOM'),
    assert_eq(con.execute("SELECT COUNT(*) FROM stock_items WHERE product_id='PROD_NAME_ONLY' AND variant_id IS NULL").fetchone()[0],1,'auto StockItem')))

# Inventory ledger and products.
test_reject('T05 negative movement quantity is rejected', lambda: con.execute("""INSERT INTO inventory_movements(id,tenant_id,warehouse_id,stock_item_id,movement_type,source_event_id,quantity_ticks)
VALUES('NEG_MOV','TENANT_DEFAULT','WH_DEFAULT',?,'ADJUSTMENT_OUT','NEG_EVENT',-1)""",(stock1,)))
test_ok('T06 inbound movement updates on-hand automatically', lambda: (
    con.execute("INSERT INTO inventory_movements(id,tenant_id,warehouse_id,stock_item_id,movement_type,source_event_id,quantity_ticks,unit_cost_ticks,total_cost_centimes) VALUES('MOV_IN_TEST','TENANT_DEFAULT','WH_DEFAULT',?,'ADJUSTMENT_IN','IN_TEST',5000,200000,1000)",(stock1,)),
    assert_eq(con.execute("SELECT on_hand_ticks FROM inventory_balances WHERE warehouse_id='WH_DEFAULT' AND stock_item_id=?",(stock1,)).fetchone()[0],105000,'movement balance')))
test_reject('T06b movement fixed-point total must match quantity times unit cost',lambda:con.execute("INSERT INTO inventory_movements(id,tenant_id,warehouse_id,stock_item_id,movement_type,source_event_id,quantity_ticks,unit_cost_ticks,total_cost_centimes) VALUES('MOV_BAD_COST','TENANT_DEFAULT','WH_DEFAULT',?,'ADJUSTMENT_IN','BAD_COST',1000,200000,99)",(stock1,)))
test_ok('T07 quota issue reserves available stock', lambda: con.execute("INSERT INTO inventory_quotas(id,tenant_id,device_id,warehouse_id,stock_item_id,quota_quantity_ticks,valid_until,status,signed_token) VALUES('Q_RES','TENANT_DEFAULT','DEV_1','WH_DEFAULT',?,90000,'2099-12-31T00:00:00Z','ACTIVE','TOKEN')",(stock1,)))
test_reject('T07b quota consumed counter cannot be edited outside deduction rows',lambda:con.execute("UPDATE inventory_quotas SET consumed_quantity_ticks=1 WHERE id='Q_RES'"))
# Q_RES above fails if 90k > unreserved? We expect reserve 90k within 105k.
# If it succeeds, issue the rest of test quota with explicit available amount.
qres = con.execute("SELECT COUNT(*) FROM inventory_quotas WHERE id='Q_RES'").fetchone()[0]
if qres:
    test_reject('T08 outbound movement is blocked below reserved amount', lambda: con.execute("INSERT INTO inventory_movements(id,tenant_id,warehouse_id,stock_item_id,movement_type,source_event_id,quantity_ticks) VALUES('OUT_RESERVED','TENANT_DEFAULT','WH_DEFAULT',?,'SALE_SHIPMENT','OUT_RESERVED_EVENT',20000)",(stock1,)))
    con.execute("UPDATE inventory_quotas SET status='VOIDED_BY_ADMIN' WHERE id='Q_RES'")
else:
    results.append(('T08 reserved stock fixture','NOT RUN','Quota fixture was not available'))
# Inventory adjustment: only post a current physical-count snapshot, then generate movement.
wh_qty = con.execute("SELECT on_hand_ticks FROM inventory_balances WHERE warehouse_id='WH_DEFAULT' AND stock_item_id=?",(stock1,)).fetchone()[0]
con.execute("INSERT INTO inventory_adjustments(id,tenant_id,warehouse_id,adjustment_number,reason,status) VALUES('ADJ_STALE','TENANT_DEFAULT','WH_DEFAULT','ADJ-STALE','Count correction','DRAFT')")
con.execute("INSERT INTO inventory_adjustment_lines(id,adjustment_id,stock_item_id,system_quantity_ticks,actual_quantity_ticks,difference_ticks,unit_cost_ticks) VALUES('ADJL_STALE','ADJ_STALE',?,?,?,100,200000)",(stock1,wh_qty,wh_qty+100))
con.execute("INSERT INTO inventory_movements(id,tenant_id,warehouse_id,stock_item_id,movement_type,source_event_id,quantity_ticks,unit_cost_ticks,total_cost_centimes) VALUES('MOV_STALE','TENANT_DEFAULT','WH_DEFAULT',?,'ADJUSTMENT_IN','STALE_BUMP',100,200000,20)",(stock1,))
test_reject('T09 stale inventory count cannot be posted after stock changed',lambda:con.execute("UPDATE inventory_adjustments SET status='POSTED' WHERE id='ADJ_STALE'"))
con.execute("UPDATE inventory_adjustments SET status='CANCELLED' WHERE id='ADJ_STALE'")
wh_qty2 = con.execute("SELECT on_hand_ticks FROM inventory_balances WHERE warehouse_id='WH_DEFAULT' AND stock_item_id=?",(stock1,)).fetchone()[0]
con.execute("INSERT INTO inventory_adjustments(id,tenant_id,warehouse_id,adjustment_number,reason,status) VALUES('ADJ_1','TENANT_DEFAULT','WH_DEFAULT','ADJ-001','Count correction','DRAFT')")
con.execute("INSERT INTO inventory_adjustment_lines(id,adjustment_id,stock_item_id,system_quantity_ticks,actual_quantity_ticks,difference_ticks,unit_cost_ticks) VALUES('ADJL_1','ADJ_1',?,?,?,2500,200000)",(stock1,wh_qty2,wh_qty2+2500))
con.execute("UPDATE inventory_adjustments SET status='POSTED' WHERE id='ADJ_1'")
test_ok('T09b posted inventory adjustment generates immutable movement and updates balance',lambda:(assert_eq(con.execute("SELECT on_hand_ticks FROM inventory_balances WHERE warehouse_id='WH_DEFAULT' AND stock_item_id=?",(stock1,)).fetchone()[0],wh_qty2+2500,'adjusted stock'),assert_eq(con.execute("SELECT COUNT(*) FROM inventory_movements WHERE source_event_id='ADJUSTMENT:ADJL_1'").fetchone()[0],1,'adjustment movement')))

test_reject('T09 duplicate simple StockItem is rejected', lambda: con.execute("INSERT INTO stock_items(id,product_id,variant_id) VALUES('DUP_SIMPLE','PROD_1',NULL)"))
test_reject('T10 variant from another product is rejected', lambda: con.execute("INSERT INTO stock_items(id,product_id,variant_id) VALUES('WRONG_VARIANT','PROD_1','VAR_1')"))
test_reject('T11 duplicate barcode across product and variant is rejected', lambda: con.execute("INSERT INTO product_variants(id,product_id,sku,barcode,variant_name) VALUES('VAR_DUP','PROD_VAR','SKU_DUP','111111','Blue')"))

# Quota cross checks and rollback.
def make_sale(sale_id, wh='WH_DEFAULT', qty=1000, customer='CUST_1', offline='OFF', seq=1, total=1000):
    con.execute("""INSERT INTO sales(id,tenant_id,store_id,warehouse_id,customer_id,device_id,offline_receipt_number,local_operation_uuid,device_seq_num,device_signature,request_hash,total_amount_centimes,paid_amount,remaining_debt,status)
      VALUES(?,?,?,?,?,'DEV_1',?,?,?,'TEST_SIGNATURE','TEST_HASH',?,0,?,'DRAFT')""",
      (sale_id,'TENANT_DEFAULT','STORE_DEFAULT',wh,customer,offline,f'OP_{sale_id}',seq,total,total))
    con.execute("UPDATE sales SET subtotal_centimes=?,invoice_number=? WHERE id=?",(total,'INV-'+sale_id,sale_id))

def make_quota(qid, stock=stock1, wh='WH_DEFAULT', qty=5000, device='DEV_1'):
    con.execute("""INSERT INTO inventory_quotas(id,tenant_id,device_id,warehouse_id,stock_item_id,quota_quantity_ticks,valid_until,status,signed_token)
    VALUES(?,'TENANT_DEFAULT',?,?,?,?,'2099-12-31T00:00:00Z','ACTIVE','SIGNED')""",(qid,device,wh,stock,qty))

make_sale('SALE_Q_WRONG_WH',qty=1000,seq=1)
con.execute("INSERT INTO sale_items(id,sale_id,stock_item_id,quantity_ticks,unit_price_ticks,line_total_centimes) VALUES('SI_WRONG_WH','SALE_Q_WRONG_WH',?,1000,100000,1000)",(stock1,))
make_quota('Q_AUX',stock1,'WH_AUX',5000)
test_reject('T12 quota warehouse must match sale warehouse',lambda:con.execute("INSERT INTO sale_item_quota_deductions(id,sale_item_id,quota_id,deducted_quantity_ticks) VALUES('QD_WRONG_WH','SI_WRONG_WH','Q_AUX',500)"))
make_quota('Q_OTHER_ITEM',stock2,'WH_DEFAULT',5000)
test_reject('T13 quota stock item must match sale line',lambda:con.execute("INSERT INTO sale_item_quota_deductions(id,sale_item_id,quota_id,deducted_quantity_ticks) VALUES('QD_WRONG_ITEM','SI_WRONG_WH','Q_OTHER_ITEM',500)"))
make_quota('Q_LINE_LIMIT',stock1,'WH_DEFAULT',5000)
test_reject('T14 cumulative quota deduction cannot exceed sale-line quantity',lambda:con.execute("INSERT INTO sale_item_quota_deductions(id,sale_item_id,quota_id,deducted_quantity_ticks) VALUES('QD_OVER_LINE','SI_WRONG_WH','Q_LINE_LIMIT',1001)"))
con.execute("UPDATE inventory_quotas SET status='VOIDED_BY_ADMIN' WHERE id IN ('Q_AUX','Q_OTHER_ITEM','Q_LINE_LIMIT')")
# Actual correct quota issue and deduction then draft deletion restores reservation and consumption.
make_sale('SALE_DRAFT_DELETE',qty=1000,seq=2)
con.execute("INSERT INTO sale_items(id,sale_id,stock_item_id,quantity_ticks,unit_price_ticks,line_total_centimes) VALUES('SI_DRAFT_DELETE','SALE_DRAFT_DELETE',?,1000,100000,1000)",(stock1,))
make_quota('Q_DRAFT_DELETE',stock1,'WH_DEFAULT',2000)
con.execute("INSERT INTO sale_item_quota_deductions(id,sale_item_id,quota_id,deducted_quantity_ticks) VALUES('QD_DRAFT_DELETE','SI_DRAFT_DELETE','Q_DRAFT_DELETE',1000)")
con.execute("DELETE FROM sales WHERE id='SALE_DRAFT_DELETE'")
test_ok('T15 deleting a DRAFT sale restores quota consumption and reservation',lambda:(
    assert_eq(con.execute("SELECT consumed_quantity_ticks FROM inventory_quotas WHERE id='Q_DRAFT_DELETE'").fetchone()[0],0,'consumed after draft delete'),
    assert_eq(con.execute("SELECT reserved_ticks FROM inventory_balances WHERE warehouse_id='WH_DEFAULT' AND stock_item_id=?",(stock1,)).fetchone()[0],2000,'reserved after draft delete')))
con.execute("UPDATE inventory_quotas SET status='VOIDED_BY_ADMIN' WHERE id='Q_DRAFT_DELETE'")
make_sale('SALE_DRAFT_CANCEL',qty=1000,seq=3)
con.execute("INSERT INTO sale_items(id,sale_id,stock_item_id,quantity_ticks,unit_price_ticks,line_total_centimes) VALUES('SI_DRAFT_CANCEL','SALE_DRAFT_CANCEL',?,1000,100000,1000)",(stock1,))
make_quota('Q_DRAFT_CANCEL',stock1,'WH_DEFAULT',1500)
con.execute("INSERT INTO sale_item_quota_deductions(id,sale_item_id,quota_id,deducted_quantity_ticks) VALUES('QD_DRAFT_CANCEL','SI_DRAFT_CANCEL','Q_DRAFT_CANCEL',1000)")
con.execute("UPDATE sales SET status='CANCELLED' WHERE id='SALE_DRAFT_CANCEL'")
test_ok('T15b cancelling a DRAFT sale releases quota and reservation',lambda:(assert_eq(con.execute("SELECT consumed_quantity_ticks FROM inventory_quotas WHERE id='Q_DRAFT_CANCEL'").fetchone()[0],0,'consumed after cancelled sale'),assert_eq(con.execute("SELECT reserved_ticks FROM inventory_balances WHERE warehouse_id='WH_DEFAULT' AND stock_item_id=?",(stock1,)).fetchone()[0],1500,'reservation after cancelled sale')))
con.execute("UPDATE inventory_quotas SET status='VOIDED_BY_ADMIN' WHERE id='Q_DRAFT_CANCEL'")


test_reject('T15c device sequence cannot be advanced without completed sale',lambda:con.execute("UPDATE registered_devices SET last_seq_num=99 WHERE id='DEV_2'"))

# Complete a real signed-metadata sale; SQL enforces fields/state/seq, cryptographic check is tested separately.
make_sale('SALE_MAIN',qty=10000,seq=1,total=5000)
con.execute("INSERT INTO sale_items(id,sale_id,stock_item_id,quantity_ticks,unit_price_ticks,line_total_centimes) VALUES('SI_MAIN','SALE_MAIN',?,10000,500000,5000)",(stock1,))
make_quota('Q_MAIN',stock1,'WH_DEFAULT',10000)
con.execute("INSERT INTO sale_item_quota_deductions(id,sale_item_id,quota_id,deducted_quantity_ticks) VALUES('QD_MAIN','SI_MAIN','Q_MAIN',10000)")
con.execute("UPDATE sales SET status='COMPLETED' WHERE id='SALE_MAIN'")
test_ok('T16 completed sale consumes quota, updates stock, sequence and customer ledger',lambda:(
    assert_eq(con.execute("SELECT last_seq_num FROM registered_devices WHERE id='DEV_1'").fetchone()[0],1,'device sequence'),
    assert_eq(con.execute("SELECT on_hand_ticks FROM inventory_balances WHERE warehouse_id='WH_DEFAULT' AND stock_item_id=?",(stock1,)).fetchone()[0],97600,'stock ledger after sale'),
    assert_eq(con.execute("SELECT current_balance_centimes FROM customers WHERE id='CUST_1'").fetchone()[0],5000,'customer balance')))
test_reject('T17 completed sale cannot be edited to another tenant/store',lambda:con.execute("UPDATE sales SET store_id='STORE_2',tenant_id='TENANT_2',warehouse_id='WH_2',device_id='DEV_2' WHERE id='SALE_MAIN'"))
test_reject('T18 sale seq replay with new sale id but old sequence is rejected',lambda:(make_sale('SALE_REPLAY',seq=1,total=0),con.execute("UPDATE sales SET status='COMPLETED' WHERE id='SALE_REPLAY'")))

# Payments and reversals.
con.execute("INSERT INTO payments(id,tenant_id,store_id,party_type,party_id,payment_method,amount,is_reversal) VALUES('PAY_C1','TENANT_DEFAULT','STORE_DEFAULT','CUSTOMER','CUST_1','BANK_TRANSFER',2000,0)")
test_reject('T20 negative payment allocation is rejected before posting',lambda:con.execute("INSERT INTO payment_allocations(id,payment_id,sale_id,allocated_amount) VALUES('ALLOC_NEG','PAY_C1','SALE_MAIN',-100)"))
con.execute("INSERT INTO payment_allocations(id,payment_id,sale_id,allocated_amount) VALUES('ALLOC_C1','PAY_C1','SALE_MAIN',2000)")
test_ok('T19a DRAFT payment allocation does not affect debt before posting',lambda:assert_eq(con.execute("SELECT remaining_debt FROM sales WHERE id='SALE_MAIN'").fetchone()[0],5000,'debt before payment posting'))
con.execute("UPDATE payments SET status='POSTED' WHERE id='PAY_C1'")
test_ok('T19 customer payment allocation reduces debt and updates customer ledger',lambda:(
    assert_eq(con.execute("SELECT remaining_debt FROM sales WHERE id='SALE_MAIN'").fetchone()[0],3000,'sale debt'),
    assert_eq(con.execute("SELECT current_balance_centimes FROM customers WHERE id='CUST_1'").fetchone()[0],3000,'customer ledger balance')))
con.execute("INSERT INTO payments(id,tenant_id,store_id,party_type,party_id,payment_method,amount,is_reversal) VALUES('PAY_SUP','TENANT_DEFAULT','STORE_DEFAULT','SUPPLIER','SUP_1','BANK_TRANSFER',1000,0)")
test_reject('T21 supplier payment cannot be allocated to customer sale',lambda:con.execute("INSERT INTO payment_allocations(id,payment_id,sale_id,allocated_amount) VALUES('ALLOC_WRONG_PARTY','PAY_SUP','SALE_MAIN',100)"))
test_reject('T22 payment cannot reference nonexistent polymorphic party',lambda:con.execute("INSERT INTO payments(id,tenant_id,store_id,party_type,party_id,payment_method,amount,is_reversal) VALUES('PAY_NO_PARTY','TENANT_DEFAULT','STORE_DEFAULT','CUSTOMER','MISSING','BANK_TRANSFER',100,0)"))
con.execute("INSERT INTO payments(id,tenant_id,store_id,party_type,party_id,payment_method,amount,is_reversal,reversal_of_id) VALUES('PAY_REV','TENANT_DEFAULT','STORE_DEFAULT','CUSTOMER','CUST_1','BANK_TRANSFER',2000,1,'PAY_C1')")
test_reject('T23a reversal cannot post before matching allocations are complete',lambda:con.execute("UPDATE payments SET status='POSTED' WHERE id='PAY_REV'"))
con.execute("INSERT INTO payment_allocations(id,payment_id,sale_id,allocated_amount) VALUES('ALLOC_REV','PAY_REV','SALE_MAIN',2000)")
con.execute("UPDATE payments SET status='POSTED' WHERE id='PAY_REV'")
test_ok('T23 full payment reversal restores invoice debt and customer balance',lambda:(
    assert_eq(con.execute("SELECT remaining_debt FROM sales WHERE id='SALE_MAIN'").fetchone()[0],5000,'sale debt after reversal'),
    assert_eq(con.execute("SELECT current_balance_centimes FROM customers WHERE id='CUST_1'").fetchone()[0],5000,'customer balance after reversal')))
test_reject('T24 payment records are immutable',lambda:con.execute("UPDATE payments SET amount=1 WHERE id='PAY_C1'"))

# Purchase receipt and return flows.
con.execute("INSERT INTO purchases(id,tenant_id,supplier_id,store_id,order_number,total_amount_centimes,paid_amount,remaining_debt,fulfillment_status,status) VALUES('PO_1','TENANT_DEFAULT','SUP_1','STORE_DEFAULT','PO-001',2000,0,2000,'PENDING','DRAFT')")
con.execute("INSERT INTO purchase_items(id,purchase_id,stock_item_id,quantity_ordered_ticks,unit_cost_ticks,line_total_centimes) VALUES('POI_1','PO_1',?,10000,200000,2000)",(stock2,))
con.execute("UPDATE purchases SET status='ORDERED' WHERE id='PO_1'")
con.execute("INSERT INTO purchase_receipts(id,tenant_id,purchase_id,warehouse_id,receipt_number,status) VALUES('GRN_1','TENANT_DEFAULT','PO_1','WH_DEFAULT','GRN-001','DRAFT')")
test_reject('T25 receipt must use stock item from the ordered purchase line',lambda:con.execute("INSERT INTO purchase_receipt_items(id,receipt_id,purchase_item_id,stock_item_id,quantity_received_ticks,unit_cost_ticks) VALUES('GRNI_BAD','GRN_1','POI_1',?,1000,200000)",(stock1,)))
con.execute("INSERT INTO purchase_receipt_items(id,receipt_id,purchase_item_id,stock_item_id,quantity_received_ticks,unit_cost_ticks) VALUES('GRNI_1','GRN_1','POI_1',?,5000,200000)",(stock2,))
con.execute("UPDATE purchase_receipts SET status='COMPLETED' WHERE id='GRN_1'")
test_ok('T26 receipt posts inventory only after complete with exact items',lambda:(
    assert_eq(con.execute("SELECT quantity_received_ticks FROM purchase_items WHERE id='POI_1'").fetchone()[0],5000,'received quantity'),
    assert_eq(con.execute("SELECT COUNT(*) FROM inventory_movements WHERE source_event_id='RECEIPT:GRNI_1'").fetchone()[0],1,'receipt movement')))
con.execute("INSERT INTO purchase_receipts(id,tenant_id,purchase_id,warehouse_id,receipt_number,status) VALUES('GRN_2','TENANT_DEFAULT','PO_1','WH_DEFAULT','GRN-002','DRAFT')")
test_reject('T27 receipt cannot exceed ordered quantity cumulatively',lambda:con.execute("INSERT INTO purchase_receipt_items(id,receipt_id,purchase_item_id,stock_item_id,quantity_received_ticks,unit_cost_ticks) VALUES('GRNI_OVER','GRN_2','POI_1',?,6000,200000)",(stock2,)))
test_reject('T27b empty receipt cannot be completed',lambda:con.execute("UPDATE purchase_receipts SET status='COMPLETED' WHERE id='GRN_2'"))
con.execute("INSERT INTO purchase_receipts(id,tenant_id,purchase_id,warehouse_id,receipt_number,status) VALUES('GRN_CANCEL','TENANT_DEFAULT','PO_1','WH_DEFAULT','GRN-CANCEL','DRAFT')")
con.execute("INSERT INTO purchase_receipt_items(id,receipt_id,purchase_item_id,stock_item_id,quantity_received_ticks,unit_cost_ticks) VALUES('GRNI_CANCEL','GRN_CANCEL','POI_1',?,500,200000)",(stock2,))
con.execute("UPDATE purchase_receipts SET status='CANCELLED' WHERE id='GRN_CANCEL'")
test_ok('T27c cancelling draft receipt restores received counter and does not post stock',lambda:(assert_eq(con.execute("SELECT quantity_received_ticks FROM purchase_items WHERE id='POI_1'").fetchone()[0],5000,'received counter after cancel'),assert_eq(con.execute("SELECT COUNT(*) FROM inventory_movements WHERE source_event_id='RECEIPT:GRNI_CANCEL'").fetchone()[0],0,'cancelled receipt movement')))

con.execute("INSERT INTO purchase_returns(id,tenant_id,purchase_id,supplier_id,warehouse_id,return_number,total_credit_centimes,status) VALUES('PR_1','TENANT_DEFAULT','PO_1','SUP_1','WH_DEFAULT','PR-001',200,'DRAFT')")
test_reject('T28 purchase return must use exact source StockItem',lambda:con.execute("INSERT INTO purchase_return_items(id,purchase_return_id,purchase_item_id,stock_item_id,returned_quantity_ticks,unit_cost_ticks,line_total_centimes) VALUES('PRI_BAD','PR_1','POI_1',?,500,200000,100)",(stock1,)))
con.execute("INSERT INTO purchase_return_items(id,purchase_return_id,purchase_item_id,stock_item_id,returned_quantity_ticks,unit_cost_ticks,line_total_centimes) VALUES('PRI_1','PR_1','POI_1',?,1000,200000,200)",(stock2,))
test_reject('T29 purchase return cannot exceed actually received quantity',lambda:con.execute("INSERT INTO purchase_return_items(id,purchase_return_id,purchase_item_id,stock_item_id,returned_quantity_ticks,unit_cost_ticks,line_total_centimes) VALUES('PRI_OVER','PR_1','POI_1',?,5000,200000,1000)",(stock2,)))
con.execute("UPDATE purchase_returns SET status='COMPLETED' WHERE id='PR_1'")
test_ok('T29b purchase return posts stock movement and supplier ledger on completion',lambda:(assert_eq(con.execute("SELECT COUNT(*) FROM inventory_movements WHERE source_event_id='PURCHASE_RETURN:PRI_1'").fetchone()[0],1,'return movement'),assert_eq(con.execute("SELECT current_balance_centimes FROM suppliers WHERE id='SUP_1'").fetchone()[0],1800,'supplier balance after return')))
con.execute("INSERT INTO purchase_returns(id,tenant_id,purchase_id,supplier_id,warehouse_id,return_number,total_credit_centimes,status) VALUES('PR_CANCEL','TENANT_DEFAULT','PO_1','SUP_1','WH_DEFAULT','PR-CANCEL',20,'DRAFT')")
con.execute("INSERT INTO purchase_return_items(id,purchase_return_id,purchase_item_id,stock_item_id,returned_quantity_ticks,unit_cost_ticks,line_total_centimes) VALUES('PRI_CANCEL','PR_CANCEL','POI_1',?,100,200000,20)",(stock2,))
con.execute("UPDATE purchase_returns SET status='CANCELLED' WHERE id='PR_CANCEL'")
test_ok('T29c cancelling draft purchase return restores return counter',lambda:assert_eq(con.execute("SELECT quantity_returned_ticks FROM purchase_items WHERE id='POI_1'").fetchone()[0],1000,'purchase returned counter after cancel'))

test_reject('T30 completed receipt item cannot be deleted',lambda:con.execute("DELETE FROM purchase_receipt_items WHERE id='GRNI_1'"))

# Sale returns must link to the exact sold item and fit refund/quantity ceilings.
con.execute("INSERT INTO sale_returns(id,tenant_id,store_id,warehouse_id,original_sale_id,return_number,customer_id,total_refund_centimes,refund_status,status) VALUES('SR_1','TENANT_DEFAULT','STORE_DEFAULT','WH_DEFAULT','SALE_MAIN','SR-001','CUST_1',500,'CREDITED_TO_ACCOUNT','DRAFT')")
test_reject('T31 sale return cannot substitute another stock item',lambda:con.execute("INSERT INTO sale_return_items(id,return_id,original_sale_item_id,stock_item_id,returned_quantity_ticks,refund_unit_price_ticks,line_total_centimes) VALUES('SRI_BAD','SR_1','SI_MAIN',?,1000,500000,500)",(stock2,)))
con.execute("INSERT INTO sale_return_items(id,return_id,original_sale_item_id,stock_item_id,returned_quantity_ticks,refund_unit_price_ticks,line_total_centimes) VALUES('SRI_1','SR_1','SI_MAIN',?,1000,500000,500)",(stock1,))
con.execute("UPDATE sale_returns SET status='COMPLETED' WHERE id='SR_1'")
test_ok('T32 credit return adds stock and reduces customer receivable',lambda:(
    assert_eq(con.execute("SELECT returned_quantity_ticks FROM sale_items WHERE id='SI_MAIN'").fetchone()[0],1000,'returned quantity'),
    assert_eq(con.execute("SELECT current_balance_centimes FROM customers WHERE id='CUST_1'").fetchone()[0],4500,'balance after return credit')))
test_reject('T33 completed sale return cannot be edited/deleted',lambda:con.execute("DELETE FROM sale_returns WHERE id='SR_1'"))

# A cancelled draft return restores the cached returned-quantity counter.
con.execute("INSERT INTO sale_returns(id,tenant_id,store_id,warehouse_id,original_sale_id,return_number,customer_id,total_refund_centimes,refund_status,status) VALUES('SR_CANCEL','TENANT_DEFAULT','STORE_DEFAULT','WH_DEFAULT','SALE_MAIN','SR-CANCEL','CUST_1',50,'CREDITED_TO_ACCOUNT','DRAFT')")
con.execute("INSERT INTO sale_return_items(id,return_id,original_sale_item_id,stock_item_id,returned_quantity_ticks,refund_unit_price_ticks,line_total_centimes) VALUES('SRI_CANCEL','SR_CANCEL','SI_MAIN',?,100,500000,50)",(stock1,))
con.execute("UPDATE sale_returns SET status='CANCELLED' WHERE id='SR_CANCEL'")
test_ok('T33b cancelling draft sale return restores returned quantity',lambda:assert_eq(con.execute("SELECT returned_quantity_ticks FROM sale_items WHERE id='SI_MAIN'").fetchone()[0],1000,'returned qty after cancelled draft'))

# Cash drawer automation and shift lifecycle.
con.execute("INSERT INTO cash_shifts(id,cash_register_id,user_id,opening_float_centimes,status) VALUES('SHIFT_1','CR_DEFAULT','USER_1',5000,'OPEN')")
test_ok('T34 opening float initializes expected cash',lambda:assert_eq(con.execute("SELECT expected_cash_centimes FROM cash_shifts WHERE id='SHIFT_1'").fetchone()[0],5000,'opening till'))
test_reject('T35 second open shift for same register is rejected',lambda:con.execute("INSERT INTO cash_shifts(id,cash_register_id,user_id,opening_float_centimes,status) VALUES('SHIFT_2','CR_DEFAULT','USER_1',0,'OPEN')"))
con.execute("INSERT INTO payments(id,tenant_id,store_id,party_type,party_id,payment_method,shift_id,amount,is_reversal) VALUES('PAY_CASH','TENANT_DEFAULT','STORE_DEFAULT','CUSTOMER','CUST_1','CASH','SHIFT_1',1000,0)")
con.execute("UPDATE payments SET status='POSTED' WHERE id='PAY_CASH'")
con.execute("INSERT INTO expenses(id,tenant_id,store_id,category_id,amount_centimes,description,shift_id) VALUES('EXP_1','TENANT_DEFAULT','STORE_DEFAULT','EXP_CAT_1',500,'Test expense','SHIFT_1')")
test_ok('T36 cash payment and expense update expected cash automatically',lambda:assert_eq(con.execute("SELECT expected_cash_centimes FROM cash_shifts WHERE id='SHIFT_1'").fetchone()[0],5500,'expected till'))
test_reject('T37 duplicate cash event source is rejected',lambda:con.execute("INSERT INTO cash_movements(id,shift_id,movement_type,amount_centimes,reason,source_event_id) VALUES('DUP_CASH','SHIFT_1','MANUAL_IN',100,'duplicate','PAYMENT:PAY_CASH')"))
con.execute("UPDATE cash_shifts SET status='CLOSED',closed_at='2026-11-05T12:00:00Z',actual_cash_centimes=5500,difference_centimes=0 WHERE id='SHIFT_1'")
test_reject('T38 cash movement cannot be posted to a closed shift',lambda:con.execute("INSERT INTO cash_movements(id,shift_id,movement_type,amount_centimes,reason,source_event_id) VALUES('CLOSED_CASH','SHIFT_1','MANUAL_IN',100,'late','LATE_EVENT')"))

# Tenant/store, fiscal year, idempotency, and audit protection.
test_reject('T39 second store under same tenant violates single-store license',lambda:con.execute("INSERT INTO stores(id,tenant_id,code,name) VALUES('STORE_EXTRA','TENANT_DEFAULT','EXTRA','Extra')"))
test_reject('T40 document sequence cannot use missing fiscal year',lambda:con.execute("INSERT INTO document_sequences(id,tenant_id,store_id,fiscal_year,document_type,prefix) VALUES('SEQ_BAD','TENANT_DEFAULT','STORE_DEFAULT',2030,'SALE','X')"))
test_reject('T41 ledger rejects nonexistent Customer party',lambda:con.execute("INSERT INTO party_ledger_entries(id,tenant_id,party_type,party_id,source_document_type,source_document_id,debit_centimes,credit_centimes,running_balance_centimes) VALUES('LED_BAD','TENANT_DEFAULT','CUSTOMER','MISSING','ADJUSTMENT','DOC_X',100,0,100)"))
con.execute("INSERT INTO idempotency_records(id,tenant_id,device_id,client_request_id,endpoint,request_hash,status) VALUES('IDEMP_1','TENANT_DEFAULT','DEV_1','REQ_1','POST /sales','HASH_1','PROCESSING')")
con.execute("UPDATE idempotency_records SET status='COMPLETED',response_code=200,response_payload_json='{}',completed_at='2026-11-05T12:00:00Z' WHERE id='IDEMP_1'")
test_reject('T42 finalized idempotency record cannot change request hash',lambda:con.execute("UPDATE idempotency_records SET request_hash='HASH_2' WHERE id='IDEMP_1'"))
test_reject('T43 idempotency key cannot be deleted',lambda:con.execute("DELETE FROM idempotency_records WHERE id='IDEMP_1'"))
con.execute("INSERT INTO idempotency_records(id,tenant_id,device_id,client_request_id,endpoint,request_hash,status,response_code,created_at,completed_at) VALUES('IDEMP_OLD','TENANT_DEFAULT','DEV_1','REQ_OLD','POST /sales','HASH_OLD','COMPLETED',200,'2026-01-01T00:00:00Z','2026-01-01T00:00:01Z')")
test_ok('T43b finalized idempotency can be purged after 30-day retention',lambda:con.execute("DELETE FROM idempotency_records WHERE id='IDEMP_OLD'"))
test_reject('T44 audit log cannot be altered',lambda:(con.execute("INSERT INTO audit_logs(id,tenant_id,action,entity_name,entity_id) VALUES('AUD_1','TENANT_DEFAULT','CREATE','PRODUCT','PROD_1')"),con.execute("UPDATE audit_logs SET action='ALTER' WHERE id='AUD_1'")))

# Ed25519 cryptographic verification smoke test (outside SQLite; same canonical payload contract).
def ed25519_test():
    test_name = 'T45 Ed25519 signature verifies and tampering is rejected (Python crypto smoke test)'
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        from cryptography.hazmat.primitives import serialization
    except (ImportError, ModuleNotFoundError):
        results.append((test_name, 'NOT RUN', 'cryptography library not installed on Python host; Ed25519 verified on JVM'))
        return
    try:
        private = Ed25519PrivateKey.generate()
        public = private.public_key()
        payload = b'TENANT_DEFAULT|DEV_1|999|LOCAL-UUID-1|5000|2026-11-05T12:00:00Z'
        signature = private.sign(payload)
        public.verify(signature,payload)
        try:
            public.verify(signature,payload+b'|tampered')
            results.append((test_name, 'FAIL', 'tampered payload verified'))
        except Exception:
            results.append((test_name, 'PASS', 'Accepted as expected'))
    except Exception as exc:
        results.append((test_name, 'FAIL', f"Unexpected error: {exc}"))

ed25519_test()

# Report only tests that were actually run.
passed=sum(1 for _,s,_ in results if s=='PASS')
failed=sum(1 for _,s,_ in results if s=='FAIL')
not_run=sum(1 for _,s,_ in results if s=='NOT RUN')
print(f"SQLite runtime: {sqlite3.sqlite_version}")
table_count=con.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").fetchone()[0]
trigger_count=con.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='trigger'").fetchone()[0]
index_count=con.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND sql IS NOT NULL").fetchone()[0]
print(f"Tables: {table_count}")
print(f"Triggers: {trigger_count}")
print(f"Indexes (explicit): {index_count}")
for name,status,detail in results:
    print(f"{status:7} {name}: {detail}")
print(f"SUMMARY: {passed} PASS / {failed} FAIL / {not_run} NOT RUN / {len(results)} total")
if failed:
    sys.exit(1)
