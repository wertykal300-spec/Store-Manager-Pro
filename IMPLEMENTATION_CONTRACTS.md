# Store Manager Pro — Implementation Contracts (Windows Host / Android POS)

This document defines application-layer behavior required by the SQL baseline. SQL triggers enforce database invariants, but cryptography, HTTPS, platform keystores, file-system operations and UI behavior are not implemented by SQLite.

## 1. Authority and write model

- Windows Host owns the central SQLite database and is the only writer to that database.
- Android POS communicates through the Ktor LAN API over HTTPS; it must never open the Windows database file or use SMB/CIFS sharing.
- Android may persist a local offline work queue and signed sale operations. That local queue is not a second writer to the central database.
- Windows local UI uses the same application services / repository boundary as LAN requests, not a separate SQL path that bypasses invariants.

## 2. Connection and transaction policy

- Enable `PRAGMA foreign_keys=ON` on every connection.
- Use WAL mode on the Windows host, a bounded `busy_timeout`, and `BEGIN IMMEDIATE` for write transactions.
- Keep all SQL write operations for one business event inside one transaction.
- Never report success to the client until commit succeeds.
- On any trigger/constraint/service failure, rollback the whole operation and return a stable domain error code.
- Do not share the SQLite file over a network filesystem.

## 3. Sale completion contract

1. Authenticate user and registered device.
2. Verify the Ed25519 signature before opening the database transaction.
3. Recompute SHA-256 over the canonical request bytes and compare it with `request_hash`.
4. Resolve the idempotency key `(tenant_id, device_id, client_request_id)`; same hash returns the stored completed response, different hash is rejected.
5. Begin `IMMEDIATE` transaction; insert/retain idempotency state and a DRAFT sale.
6. Allocate the official invoice number by incrementing the correct open fiscal-year sequence exactly once and format `invoice_number` inside the same transaction.
7. Insert sale lines and, for offline sales, quota deductions covering each line quantity.
8. Complete the sale. SQL rechecks totals, device status, sequence monotonicity, quota coverage and inventory availability; completion posts immutable stock movements and party ledger entry.
9. Post any customer payment as a DRAFT payment with its allocations, then transition it to POSTED inside the same transaction. Cash payment triggers the cash ledger; bank/card payments do not alter drawer cash.
10. Finalize the idempotency response and commit.

For walk-in sales (`customer_id IS NULL`), do not create an invalid CUSTOMER allocation. The v1 application must use the cash-sale settlement path and link the receipt to an open shift; this integration path must be proven in the POS acceptance tests before enabling walk-in cash sales. The current SQL acceptance suite covers customer-linked sales and cash payments; it does not claim a tested walk-in cash flow.

## 4. Signed operation bytes

Do not sign a display string with ambiguous separators. Use a versioned canonical binary/UTF-8 representation with length-prefixed fields. The SHA-256 `request_hash` must cover at least:

- schema/protocol version;
- tenant, store, warehouse and device identifiers;
- device sequence number and local operation UUID;
- customer identifier or explicit walk-in marker;
- every line in deterministic order: stock item, quantity ticks, unit price ticks, discount, tax and line total;
- subtotal, discount, tax, total and operation timestamp.

The Ed25519 signing payload must include the protocol version, tenant ID, device ID, sequence number, local operation UUID, `request_hash` and timestamp. The host recomputes the hash and verifies the Ed25519 signature with the registered public key. SQL checks non-empty signature/hash metadata, active device and monotonic sequence; **SQLite does not cryptographically verify Ed25519**.

The Python Ed25519 test in `verify_canonical_schema.py` is a primitive smoke test only. A Kotlin/Ktor integration test must verify the actual serialization, Android private-key operation and Windows public-key verification.

## 5. Offline quota lifecycle

- Host issues a signed quota only after checking the available quantity and reserving it in `inventory_balances.reserved_ticks`.
- A quota is bound to tenant, registered device, warehouse, StockItem, exact quantity and validity.
- Android signs each sale operation; on sync, host validates device identity and sequence, verifies signature/hash, then applies quota deductions.
- Deduction must match sale item, device, warehouse and tenant, remain within both quota and sale-line quantity, and update consumed/reserved counters in the same transaction.
- Deleting/cancelling a DRAFT sale restores its quota deductions. Completed sale deductions are immutable.
- Expired quotas must be moved to EXPIRED by a host maintenance job; the trigger releases unused reservations. Lost devices move to LOST_DEVICE_EXPOSURE and keep unused reservation unavailable until expiry or an audited administrative reconciliation.

## 6. Purchase, receipt, return and adjustment lifecycle

- Purchase: DRAFT → ORDERED. Header total must equal purchase-line totals; posting creates the supplier ledger entry.
- Receipt: DRAFT → COMPLETED or CANCELLED. Add lines while DRAFT; validate purchase and StockItem match; counters update from source lines. Only completion creates receipt movements. Cancellation restores received counters and creates no movement.
- Purchase return: DRAFT → COMPLETED or CANCELLED. Lines must match source purchase item and StockItem, not exceed received quantity or available stock. Completion creates the outbound movement and supplier ledger entry.
- Sale return: DRAFT → COMPLETED or CANCELLED. Lines must match the original sale line and StockItem, not exceed sold quantity/value. Completion posts stock and cash/receivable refund effects.
- Inventory adjustment: DRAFT → POSTED or CANCELLED. The physical count snapshot must still match current on-hand at posting, actual quantity cannot fall below reserved, and POSTED creates immutable adjustment movements.

## 7. Payment and reversal lifecycle

- Insert payments as DRAFT; insert/edit allocations only before posting.
- POSTED is the only state that changes invoice balances, party ledger and cash drawer.
- Allocation must be positive, party-type compatible, party-identical, same tenant/store and within current invoice debt.
- v1 supports **full reversals only**: reversal payment must match a POSTED, fully allocated original; its allocation set and values must exactly mirror the original. Partial reversals are not implemented in this baseline.
- Post the reversal payment and its allocations inside one transaction. Original payment/allocation rows remain immutable.

## 8. Cash and shifts

- Opening a shift records opening float; only one OPEN shift per register.
- Each cash movement is append-only and has a unique source event ID.
- Cash payments and shift-linked expenses post a movement automatically. Closed shifts reject new movements and are immutable after close.
- Close transaction stores actual cash, close timestamp and the calculated difference against expected cash.

## 9. Idempotency and maintenance

- Create and finalize idempotency state in the same write transaction as the business event.
- Store request hash and final response. Same key + same hash returns previous response; same key + different hash rejects.
- Retain terminal idempotency records for at least 30 days. Host maintenance may purge only terminal records older than 30 days; PROCESSING records cannot be purged.
- Host maintenance also marks expired quotas and records backup verification results.

## 10. First-run bootstrap, licensing and backup

- Seed contains no default user or placeholder ACTIVE license.
- First-run wizard collects owner credentials, generates per-user random salt and password hash using the chosen password KDF parameters, creates the administrator and grants system role in one transaction.
- License record is inserted only after application-level Ed25519 signature verification. Expiry blocks new business transactions but never blocks history viewing/export/printing.
- Use SQLite backup API or a verified WAL-aware backup procedure; do not copy only the main `.db` file while WAL is active. Verify SHA-256 and restore into a disposable database as an acceptance test.

## 11. Required platform tests not covered by the SQL suite

- Windows: Ktor host startup/shutdown, HTTPS certificate provisioning/pinning, Windows firewall/network profile, concurrent LAN writes, WAL checkpointing, lock timeout/retry, backup/restore and recovery after power loss.
- Android: Keystore Ed25519 key generation/use, local offline queue durability, ordered replay, revoked/lost device behavior, app process death and clock changes.
- Shared: SQLDelight code generation from this DDL, transaction boundaries, Arabic/RTL receipts and thermal/A4 print output.
