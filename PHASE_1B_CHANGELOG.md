# Store Manager Pro — Phase 1B Changelog
## Targeted Defect Corrections & Engineering Changes

This changelog records the specific changes made to the Phase 1B delivery.

---

### 1. Database Initialization Atomicity & Staging
- **Added `DatabaseExceptions.kt`**:
  - `DatabaseException` (base)
  - `DatabaseInitializationException`
  - `DatabaseValidationException`
- **Updated `DatabaseDriverFactory.desktop.kt`**:
  - Implemented staging-based atomic database creation using isolated staging files (`.staging.<UUID>`).
  - Implemented automatic checkpoint and atomic move (`Files.move(..., ATOMIC_MOVE)`), ensuring no partial database file can ever be created at the target path on failure.
  - Implemented safe staging cleanup and rollback on any initialization failure.
  - Added full schema validation when opening an existing database:
    - `PRAGMA user_version == 1`
    - 55 tables verification
    - 107 explicit indexes verification
    - 186 triggers verification
    - `PRAGMA integrity_check == 'ok'`
    - `PRAGMA foreign_key_check` (0 errors)
  - Guaranteed that invalid/corrupt databases are rejected with clear diagnostic exceptions without deleting or modifying user data.

---

### 2. Connection PRAGMAs Enforcement
- **Enforced connection-level PRAGMAs**:
  - `PRAGMA foreign_keys = ON;`
  - `PRAGMA busy_timeout = 10000;`
  - `PRAGMA journal_mode = WAL;`
  - `PRAGMA synchronous = NORMAL;`
- Applied both via JDBC properties and explicit SQL execution on every connection and reopened connection.
- Documented technical rationale for retaining `synchronous = NORMAL` in WAL mode for POS performance and crash durability.

---

### 3. Test Suite Enhancements & Accuracy
- **Updated `StoreDatabaseIntegrationTest.kt`**:
  - Added `test09_productNameOnlyMinimalInsert_autoDefaultsUomAndCreatesStockItem`: Tests inserting product with only `id`, `tenant_id`, and `name` (no UOM passed), verifying automatic default to `UOM_PIECE` and auto-generation of `stock_items`.
  - Added `test09b_productWithMinimalData_inboundMovementInitializesInventoryBalance`: Tests inventory balance creation and on-hand ticks update from inbound movement.
  - Added `test16_atomicity_triggerFailureLeavesNoPartialDatabase`: Verifies that mid-trigger installation failure rolls back cleanly and leaves no partial database file on disk.
  - Added `test17_atomicity_recoveryAfterFailureCreatesCleanDatabase`: Verifies that clean retry after failure creates complete database with 55 tables, 107 indexes, and 186 triggers.
  - Added `test18_existingDb_reopeningDoesNotDuplicateTriggersOrRecreateSchema`: Verifies idempotent reopen without trigger duplication.
  - Added `test19_existingDb_rejectsInvalidUserVersion`: Verifies rejection of invalid user_version without file deletion.
  - Added `test20_existingDb_rejectsIncompleteSchemaWithoutDeletingData`: Verifies rejection of incomplete schema with user data preservation.
  - Added `test21_connectionPragmas_actualValuesEnforced`: Verifies all 4 PRAGMA values directly from SQLite.
  - Added `test22_foreignKeyEnforcement_rejectsOrphanReference`: Verifies SQLite foreign key rejection.
  - Added `test23_connectionPragmas_reappliedOnReopenedConnection`: Verifies PRAGMA reapplication on connection reopen.
  - Added `test24_sqliteRuntimeVersion_loggedAndVerified`: Verifies and logs Desktop SQLite JDBC version (`3.53.4`).
  - Added `test25_ed25519SignatureVerification_nativeJdkCrypto`: Added native JDK Ed25519 cryptography testing with graceful assumption handling for JDK versions.
  - Updated `test15`: Uses `Assume.assumeTrue` for python availability to prevent false passes when external runtime is absent.

---

### 4. Android POS Client Isolation
- **Added `app/src/test/java/com/storemanager/pos/AndroidIsolationRobolectricTest.kt`**:
  - Proves that `DatabaseDriverFactory.createDriver()` on Android immediately throws `UnsupportedOperationException`.
- **Added `shared/data/src/androidUnitTest/kotlin/com/storemanager/core/data/AndroidDatabaseIsolationTest.kt`**:
  - Multiplatform unit test verifying Android isolation invariant.
- **Updated `app/build.gradle.kts`**:
  - Added `testImplementation(project(":shared:data"))` for isolation verification.

---

### 5. Build System & Wrapper Deliverables
- **Generated Gradle Wrapper**:
  - Added `gradlew` (executable shell script)
  - Added `gradlew.bat` (Windows batch script)
  - Added `gradle/wrapper/gradle-wrapper.jar`
- Verified clean build reproducibility via `--no-build-cache --no-configuration-cache --rerun-tasks` (101 tasks passed).
