# Store Manager Pro — Entity Relationship Diagrams

**Source of truth:** `canonical_schema.sql` (55 tables). These diagrams are grouped for readability; SQL foreign keys and integrity triggers remain authoritative.

## 1. Tenant, store, identity and devices

```mermaid
erDiagram
  TENANTS ||--o{ STORES : owns
  TENANTS ||--o{ USERS : owns
  TENANTS ||--o{ ROLES : defines
  TENANTS ||--o{ FISCAL_YEARS : defines
  TENANTS ||--o{ APP_LICENSES : licenses
  STORES ||--o{ WAREHOUSES : contains
  STORES ||--o{ REGISTERED_DEVICES : pairs
  USERS ||--o{ USER_SESSIONS : opens
  USERS ||--o{ USER_ROLES : assigned
  ROLES ||--o{ USER_ROLES : grants
  ROLES ||--o{ ROLE_PERMISSIONS : includes
  PERMISSIONS ||--o{ ROLE_PERMISSIONS : defines
  TENANTS ||--o{ AUDIT_LOGS : records
  TENANTS ||--o{ IDEMPOTENCY_RECORDS : scopes
  REGISTERED_DEVICES ||--o{ IDEMPOTENCY_RECORDS : submits
  REGISTERED_DEVICES ||--o{ INVENTORY_QUOTAS : receives
```

## 2. Catalog, variants, units and prices

```mermaid
erDiagram
  TENANTS ||--o{ CATEGORIES : owns
  CATEGORIES ||--o{ PRODUCTS : classifies
  UNITS_OF_MEASURE ||--o{ PRODUCTS : base_unit
  UNITS_OF_MEASURE ||--o{ UNIT_CONVERSIONS : from_unit
  UNITS_OF_MEASURE ||--o{ UNIT_CONVERSIONS : to_unit
  PRODUCTS ||--o{ PRODUCT_VARIANTS : has
  PRODUCTS ||--o{ STOCK_ITEMS : represented_by
  PRODUCT_VARIANTS ||--o{ STOCK_ITEMS : creates
  TENANTS ||--o{ PRICE_LISTS : owns
  CURRENCIES ||--o{ PRICE_LISTS : denominates
  PRICE_LISTS ||--o{ PRICE_LIST_ITEMS : contains
  PRODUCTS ||--o{ PRICE_LIST_ITEMS : priced_as
  PRODUCT_VARIANTS ||--o{ PRICE_LIST_ITEMS : variant_price
```

## 3. Inventory and offline quotas

```mermaid
erDiagram
  WAREHOUSES ||--o{ INVENTORY_BALANCES : holds
  STOCK_ITEMS ||--o{ INVENTORY_BALANCES : balance
  WAREHOUSES ||--o{ INVENTORY_MOVEMENTS : movement_location
  STOCK_ITEMS ||--o{ INVENTORY_MOVEMENTS : movement_item
  WAREHOUSES ||--o{ INVENTORY_ADJUSTMENTS : adjusted_at
  INVENTORY_ADJUSTMENTS ||--o{ INVENTORY_ADJUSTMENT_LINES : lines
  STOCK_ITEMS ||--o{ INVENTORY_ADJUSTMENT_LINES : counted_item
  WAREHOUSES ||--o{ INVENTORY_QUOTAS : quota_location
  STOCK_ITEMS ||--o{ INVENTORY_QUOTAS : quota_item
  INVENTORY_QUOTAS ||--o{ SALE_ITEM_QUOTA_DEDUCTIONS : consumed_by
  SALE_ITEMS ||--o{ SALE_ITEM_QUOTA_DEDUCTIONS : covered_by
```

## 4. Sales, purchases and returns

```mermaid
erDiagram
  STORES ||--o{ SALES : records
  WAREHOUSES ||--o{ SALES : fulfills
  CUSTOMERS ||--o{ SALES : buys
  REGISTERED_DEVICES ||--o{ SALES : originates
  SALES ||--o{ SALE_ITEMS : contains
  STOCK_ITEMS ||--o{ SALE_ITEMS : sold_as
  SALES ||--o{ SALE_RETURNS : returned_by
  SALE_RETURNS ||--o{ SALE_RETURN_ITEMS : lines
  SALE_ITEMS ||--o{ SALE_RETURN_ITEMS : source_line
  STORES ||--o{ PURCHASES : orders
  SUPPLIERS ||--o{ PURCHASES : supplies
  PURCHASES ||--o{ PURCHASE_ITEMS : contains
  STOCK_ITEMS ||--o{ PURCHASE_ITEMS : ordered_as
  PURCHASES ||--o{ PURCHASE_RECEIPTS : received_by
  PURCHASE_RECEIPTS ||--o{ PURCHASE_RECEIPT_ITEMS : lines
  PURCHASE_ITEMS ||--o{ PURCHASE_RECEIPT_ITEMS : source_line
  PURCHASES ||--o{ PURCHASE_RETURNS : returned_to_supplier
  PURCHASE_RETURNS ||--o{ PURCHASE_RETURN_ITEMS : lines
  PURCHASE_ITEMS ||--o{ PURCHASE_RETURN_ITEMS : source_line
```

## 5. Payments, ledger and cash

```mermaid
erDiagram
  CUSTOMERS ||--o{ PARTY_LEDGER_ENTRIES : customer_ledger
  SUPPLIERS ||--o{ PARTY_LEDGER_ENTRIES : supplier_ledger
  PAYMENTS ||--o{ PAYMENT_ALLOCATIONS : allocates
  SALES ||--o{ PAYMENT_ALLOCATIONS : customer_invoice
  PURCHASES ||--o{ PAYMENT_ALLOCATIONS : supplier_invoice
  PAYMENTS ||--o| PAYMENTS : reverses
  STORES ||--o{ CASH_REGISTERS : owns
  CASH_REGISTERS ||--o{ CASH_SHIFTS : opens
  USERS ||--o{ CASH_SHIFTS : operates
  CASH_SHIFTS ||--o{ CASH_MOVEMENTS : records
  CASH_SHIFTS ||--o{ PAYMENTS : receives_cash
  CASH_SHIFTS ||--o{ EXPENSES : pays
  EXPENSE_CATEGORIES ||--o{ EXPENSES : classifies
```

**Notes:** `party_ledger_entries.party_id` is polymorphic; its Customer/Supplier existence and tenant scope are enforced by triggers. `PAYMENTS` self-reference represents a full reversal link; v1 permits full reversal, not partial reversal. `inventory_balances` is a maintained balance projection fed by immutable `inventory_movements` and quota reservations.
