package com.storemanager.core.data

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume
import org.junit.Before
import org.junit.Test
import java.io.File
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class StoreDatabaseIntegrationTest {

    private lateinit var tempDbFile: File
    private lateinit var factory: DatabaseDriverFactory
    private lateinit var driver: SqlDriver
    private lateinit var db: StoreDatabase

    @Before
    fun setUp() {
        tempDbFile = File.createTempFile("test_store_master_", ".db")
        if (tempDbFile.exists()) tempDbFile.delete()
        factory = DatabaseDriverFactory(tempDbFile)
        driver = factory.createDriver()
        db = StoreDatabase(driver)
    }

    @After
    fun tearDown() {
        try { driver.close() } catch (_: Throwable) {}
        if (tempDbFile.exists()) tempDbFile.delete()
        File("${tempDbFile.absolutePath}-wal").takeIf { it.exists() }?.delete()
        File("${tempDbFile.absolutePath}-shm").takeIf { it.exists() }?.delete()
        File("${tempDbFile.parentFile.absolutePath}/${tempDbFile.name}.init.lock").takeIf { it.exists() }?.delete()
    }

    @Test
    fun test01_createDatabaseFromScratch_has55Tables() {
        val cursor = driver.executeQuery<Long>(
            null,
            "SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
            {
                it.next()
                QueryResult.Value(it.getLong(0) ?: 0L)
            },
            0
        )
        val tableCount = cursor.value
        assertEquals("Expected exactly 55 tables created by SQLDelight", 55L, tableCount)
    }

    @Test
    fun test02_hasAll107ExplicitIndexes() {
        val cursor = driver.executeQuery<Long>(
            null,
            "SELECT count(*) FROM sqlite_master WHERE type='index' AND sql IS NOT NULL;",
            {
                it.next()
                QueryResult.Value(it.getLong(0) ?: 0L)
            },
            0
        )
        val indexCount = cursor.value
        assertEquals("Expected exactly 107 explicit indexes created by SQLDelight", 107L, indexCount)
    }

    @Test
    fun test03_hasAll186CanonicalTriggers() {
        val cursor = driver.executeQuery<Long>(
            null,
            "SELECT count(*) FROM sqlite_master WHERE type='trigger';",
            {
                it.next()
                QueryResult.Value(it.getLong(0) ?: 0L)
            },
            0
        )
        val triggerCount = cursor.value
        assertEquals("Expected exactly 186 canonical triggers created", 186L, triggerCount)
    }

    @Test
    fun test04_pragmaForeignKeyCheck_returnsZeroErrors() {
        val cursor = driver.executeQuery<Long>(
            null,
            "PRAGMA foreign_key_check;",
            {
                var errorCount = 0L
                while (it.next().value) {
                    errorCount++
                }
                QueryResult.Value(errorCount)
            },
            0
        )
        assertEquals("PRAGMA foreign_key_check must return 0 errors", 0L, cursor.value)
    }

    @Test
    fun test05_pragmaIntegrityCheck_returnsOk() {
        val cursor = driver.executeQuery<String?>(
            null,
            "PRAGMA integrity_check;",
            {
                it.next()
                QueryResult.Value(it.getString(0))
            },
            0
        )
        assertEquals("PRAGMA integrity_check must return 'ok'", "ok", cursor.value)
    }

    @Test
    fun test06_userVersionIsSetToOne() {
        val cursor = driver.executeQuery<Long>(
            null,
            "PRAGMA user_version;",
            {
                it.next()
                QueryResult.Value(it.getLong(0) ?: 0L)
            },
            0
        )
        assertEquals("PRAGMA user_version must be 1 for fresh baseline v1.0", 1L, cursor.value)
    }

    @Test
    fun test07_checkConstraint_rejectsReservedExceedingOnHand() {
        try {
            driver.execute(
                null,
                """
                INSERT INTO inventory_balances (warehouse_id, stock_item_id, on_hand_ticks, reserved_ticks, current_moving_avg_cost)
                VALUES ('WH_TEST', 'SI_TEST', 100, 200, 50);
                """.trimIndent(),
                0
            )
            fail("Expected CHECK constraint violation when reserved_ticks > on_hand_ticks")
        } catch (e: Exception) {
            assertTrue("Expected integrity error", e.message?.contains("CHECK") == true || e.message?.contains("constraint") == true)
        }
    }

    @Test
    fun test08_seedBaselineAndQueriesExecution() {
        // Seed tenant
        db.storeDatabaseQueries.insertTenant("TENANT_TEST", "Test Enterprise", 1)
        val tenant = db.storeDatabaseQueries.selectTenantById("TENANT_TEST").executeAsOneOrNull()
        assertNotNull(tenant)
        assertEquals("Test Enterprise", tenant?.name)

        // Seed store
        db.storeDatabaseQueries.insertStore("STORE_TEST", "TENANT_TEST", "Branch 1", "B01")
        val stores = db.storeDatabaseQueries.selectAllStores().executeAsList()
        assertTrue(stores.any { it.id == "STORE_TEST" })
    }

    @Test
    fun test09_productNameOnlyMinimalInsert_autoDefaultsUomAndCreatesStockItem() {
        driver.execute(null, "INSERT INTO tenants (id, name) VALUES ('T_PROD_MIN', 'Prod Minimal Tenant');", 0)
        driver.execute(
            null,
            "INSERT INTO units_of_measure (id, dimension, name_ar, name_fr, symbol, is_fractional) VALUES ('UOM_PIECE', 'COUNT', 'قطعة', 'Piece', 'pc', 0);",
            0
        )
        driver.execute(null, "INSERT INTO stores (id, tenant_id, name, code) VALUES ('STR_MIN', 'T_PROD_MIN', 'Store Min', 'SMIN');", 0)
        driver.execute(null, "INSERT INTO warehouses (id, tenant_id, store_id, name, is_default) VALUES ('WH_MIN', 'T_PROD_MIN', 'STR_MIN', 'Default WH', 1);", 0)

        // Insert product with MINIMAL required fields ONLY (id, tenant_id, name) without specifying base_unit_id
        driver.execute(
            null,
            "INSERT INTO products (id, tenant_id, name) VALUES ('P_MIN_01', 'T_PROD_MIN', 'Fresh Artisan Bread');",
            0
        )

        val productUom = driver.executeQuery<String?>(
            null,
            "SELECT base_unit_id FROM products WHERE id = 'P_MIN_01';",
            {
                if (it.next().value) {
                    QueryResult.Value(it.getString(0))
                } else QueryResult.Value(null)
            },
            0
        ).value
        assertEquals("UOM_PIECE", productUom)

        val stockItemCursor = driver.executeQuery<Pair<String, String>?>(
            null,
            "SELECT id, product_id FROM stock_items WHERE product_id = 'P_MIN_01' AND variant_id IS NULL;",
            {
                if (it.next().value) {
                    QueryResult.Value(Pair(it.getString(0)!!, it.getString(1)!!))
                } else QueryResult.Value(null)
            },
            0
        )
        assertNotNull("Trigger must auto-create stock_items record", stockItemCursor.value)
        assertEquals("P_MIN_01", stockItemCursor.value?.second)
        assertTrue("Auto-generated stock item id must be non-blank", stockItemCursor.value?.first?.isNotBlank() == true)
    }

    @Test
    fun test09b_productWithMinimalData_inboundMovementInitializesInventoryBalance() {
        driver.execute(null, "INSERT INTO tenants (id, name) VALUES ('T_PROD_MOV', 'Prod Mov Tenant');", 0)
        driver.execute(
            null,
            "INSERT INTO units_of_measure (id, dimension, name_ar, name_fr, symbol, is_fractional) VALUES ('UOM_PIECE', 'COUNT', 'قطعة', 'Piece', 'pc', 0);",
            0
        )
        driver.execute(null, "INSERT INTO stores (id, tenant_id, name, code) VALUES ('STR_MOV', 'T_PROD_MOV', 'Store Mov', 'SMOV');", 0)
        driver.execute(null, "INSERT INTO warehouses (id, tenant_id, store_id, name, is_default) VALUES ('WH_MOV', 'T_PROD_MOV', 'STR_MOV', 'Warehouse Mov', 1);", 0)

        driver.execute(
            null,
            "INSERT INTO products (id, tenant_id, name) VALUES ('P_MOV_01', 'T_PROD_MOV', 'Organic Olive Oil 1L');",
            0
        )

        val stockItemId = driver.executeQuery<String>(
            null,
            "SELECT id FROM stock_items WHERE product_id = 'P_MOV_01' AND variant_id IS NULL;",
            {
                it.next()
                QueryResult.Value(it.getString(0)!!)
            },
            0
        ).value

        driver.execute(
            null,
            """
            INSERT INTO inventory_movements (
                id, tenant_id, warehouse_id, stock_item_id, movement_type, source_event_id,
                quantity_ticks, unit_cost_ticks, total_cost_centimes
            ) VALUES (
                'MOV_INIT_01', 'T_PROD_MOV', 'WH_MOV', '$stockItemId', 'ADJUSTMENT_IN', 'EVT_INIT_01',
                5000, 200000, 1000
            );
            """.trimIndent(),
            0
        )

        val onHand = driver.executeQuery<Long>(
            null,
            "SELECT on_hand_ticks FROM inventory_balances WHERE warehouse_id = 'WH_MOV' AND stock_item_id = '$stockItemId';",
            {
                it.next()
                QueryResult.Value(it.getLong(0) ?: 0L)
            },
            0
        ).value
        assertEquals("Inventory balance on_hand_ticks must equal 5000 ticks", 5000L, onHand)
    }

    @Test
    fun test10_databaseReopen_preservesDataWithoutRecreatingSchema() {
        db.storeDatabaseQueries.insertTenant("TENANT_PERSIST", "Persistent Enterprise", 1)

        driver.close()

        val reopenFactory = DatabaseDriverFactory(tempDbFile)
        val newDriver = reopenFactory.createDriver()
        val newDb = StoreDatabase(newDriver)

        try {
            val tenant = newDb.storeDatabaseQueries.selectTenantById("TENANT_PERSIST").executeAsOneOrNull()
            assertNotNull("Data must persist across database reopens", tenant)
            assertEquals("Persistent Enterprise", tenant?.name)
        } finally {
            newDriver.close()
        }
    }

    @Test
    fun test11_auditLogsImmutability_rejectsUpdateAndDelete() {
        driver.execute(null, "INSERT INTO tenants (id, name) VALUES ('T_AUDIT', 'Audit Tenant');", 0)
        driver.execute(null, "INSERT INTO audit_logs (id, tenant_id, action, entity_name, entity_id) VALUES ('A_01', 'T_AUDIT', 'INSERT', 'sales', 'S_01');", 0)

        try {
            driver.execute(null, "UPDATE audit_logs SET action = 'MODIFIED' WHERE id = 'A_01';", 0)
            fail("Trigger must reject UPDATE on audit_logs")
        } catch (e: Exception) {
            assertTrue("Expected audit log update rejection", e.message?.contains("AUDIT_LOGS_ARE_IMMUTABLE") == true)
        }

        try {
            driver.execute(null, "DELETE FROM audit_logs WHERE id = 'A_01';", 0)
            fail("Trigger must reject DELETE on audit_logs")
        } catch (e: Exception) {
            assertTrue("Expected audit log delete rejection", e.message?.contains("AUDIT_LOGS_ARE_IMMUTABLE") == true)
        }
    }

    @Test
    fun test12_transactionRollback_cleansUpAtomicallyOnFailure() {
        driver.execute(null, "INSERT INTO tenants (id, name) VALUES ('T_TX', 'Tx Tenant');", 0)

        try {
            db.transaction {
                db.storeDatabaseQueries.insertTenant("T_FAIL_1", "Will Rollback", 1)
                rollback()
            }
        } catch (_: Exception) {
        }

        val tenant = db.storeDatabaseQueries.selectTenantById("T_FAIL_1").executeAsOneOrNull()
        assertEquals("Rolled back record must not exist", null, tenant)
    }

    @Test
    fun test13_singleStorePerTenant_partialUniqueIndex() {
        driver.execute(null, "INSERT INTO tenants (id, name) VALUES ('T_SINGLE', 'Single Store Tenant');", 0)
        driver.execute(null, "INSERT INTO stores (id, tenant_id, name, code) VALUES ('STR_1', 'T_SINGLE', 'First Store', 'S01');", 0)

        try {
            driver.execute(null, "INSERT INTO stores (id, tenant_id, name, code) VALUES ('STR_2', 'T_SINGLE', 'Second Store', 'S02');", 0)
            fail("Expected unique constraint violation for second store under same tenant")
        } catch (e: Exception) {
            assertTrue(
                "Expected single-store constraint violation",
                e.message?.contains("UNIQUE") == true || e.message?.contains("stores.tenant_id") == true
            )
        }
    }

    @Test
    fun test14_oneOpenShiftPerCashRegister_partialUniqueIndex() {
        driver.execute(null, "INSERT INTO tenants (id, name) VALUES ('T_SHIFT', 'Shift Tenant');", 0)
        driver.execute(null, "INSERT INTO stores (id, tenant_id, name, code) VALUES ('STR_SH', 'T_SHIFT', 'Store Shift', 'SSH');", 0)
        driver.execute(null, "INSERT INTO cash_registers (id, tenant_id, store_id, code, name) VALUES ('CR_1', 'T_SHIFT', 'STR_SH', 'REG1', 'POS 1');", 0)
        driver.execute(
            null,
            "INSERT INTO users (id, tenant_id, username, password_hash, salt, full_name, is_active) VALUES ('U_1', 'T_SHIFT', 'cashier1', 'hash', 'salt', 'Cashier', 1);",
            0
        )

        driver.execute(null, "INSERT INTO cash_shifts (id, cash_register_id, user_id, opening_float_centimes, status) VALUES ('SH_1', 'CR_1', 'U_1', 1000, 'OPEN');", 0)

        try {
            driver.execute(null, "INSERT INTO cash_shifts (id, cash_register_id, user_id, opening_float_centimes, status) VALUES ('SH_2', 'CR_1', 'U_1', 2000, 'OPEN');", 0)
            fail("Expected partial unique index violation for second open shift on same cash register")
        } catch (e: Exception) {
            assertTrue(
                "Expected open shift index violation",
                e.message?.contains("UNIQUE") == true || e.message?.contains("idx_one_open_shift_per_register") == true
            )
        }
    }

    // ==========================================
    // 1. SECURE ATOMIC PUBLICATION & WAL VERIFICATION TESTS
    // ==========================================

    @Test
    fun test16_atomicity_triggerFailureLeavesNoPartialDatabase() {
        val failDbFile = File.createTempFile("test_fail_atomicity_", ".db")
        if (failDbFile.exists()) failDbFile.delete()

        val failFactory = DatabaseDriverFactory(failDbFile).apply {
            simulateTriggerFailure = true
        }

        try {
            failFactory.createDriver()
            fail("Expected DatabaseInitializationException when trigger installation fails")
        } catch (e: DatabaseInitializationException) {
            assertTrue("Exception message must indicate initialization failure", e.message?.contains("failed") == true)
        } finally {
            assertFalse(
                "Target database file must NOT exist if initialization failed mid-operation",
                failDbFile.exists()
            )
        }
    }

    @Test
    fun test17_atomicity_recoveryAfterFailureCreatesCleanDatabase() {
        val recoverDbFile = File.createTempFile("test_recover_atomicity_", ".db")
        if (recoverDbFile.exists()) recoverDbFile.delete()

        val failFactory = DatabaseDriverFactory(recoverDbFile).apply {
            simulateTriggerFailure = true
        }
        try {
            failFactory.createDriver()
            fail("Expected failure")
        } catch (_: DatabaseInitializationException) {
        }
        assertFalse("File must not exist after failure", recoverDbFile.exists())

        val recoverFactory = DatabaseDriverFactory(recoverDbFile).apply {
            simulateTriggerFailure = false
        }
        val cleanDriver = recoverFactory.createDriver()
        try {
            assertTrue("Target database file must now exist after successful initialization", recoverDbFile.exists())
            val tableCount = cleanDriver.executeQuery<Long>(
                null,
                "SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
                { it.next(); QueryResult.Value(it.getLong(0) ?: 0L) },
                0
            ).value
            assertEquals("Expected exactly 55 tables", 55L, tableCount)

            val triggerCount = cleanDriver.executeQuery<Long>(
                null,
                "SELECT count(*) FROM sqlite_master WHERE type='trigger';",
                { it.next(); QueryResult.Value(it.getLong(0) ?: 0L) },
                0
            ).value
            assertEquals("Expected exactly 186 triggers", 186L, triggerCount)
        } finally {
            cleanDriver.close()
            if (recoverDbFile.exists()) recoverDbFile.delete()
        }
    }

    @Test
    fun test18_existingDb_reopeningDoesNotDuplicateTriggersOrRecreateSchema() {
        driver.close()

        val reopenFactory = DatabaseDriverFactory(tempDbFile)
        val reopenedDriver = reopenFactory.createDriver()
        try {
            val triggerCount = reopenedDriver.executeQuery<Long>(
                null,
                "SELECT count(*) FROM sqlite_master WHERE type='trigger';",
                { it.next(); QueryResult.Value(it.getLong(0) ?: 0L) },
                0
            ).value
            assertEquals("Reopening database must not duplicate triggers (must remain exactly 186)", 186L, triggerCount)

            val tableCount = reopenedDriver.executeQuery<Long>(
                null,
                "SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
                { it.next(); QueryResult.Value(it.getLong(0) ?: 0L) },
                0
            ).value
            assertEquals("Reopening database must retain exactly 55 tables", 55L, tableCount)
        } finally {
            reopenedDriver.close()
        }
    }

    @Test
    fun test19_existingDb_rejectsInvalidUserVersion() {
        driver.execute(null, "PRAGMA user_version = 99;", 0)
        driver.close()

        val checkFactory = DatabaseDriverFactory(tempDbFile)
        try {
            checkFactory.createDriver()
            fail("Expected DatabaseValidationException when user_version is invalid")
        } catch (e: DatabaseValidationException) {
            assertTrue("Error must mention user_version", e.message?.contains("user_version") == true)
        }

        assertTrue("Corrupt/invalid database file must NOT be deleted upon rejection", tempDbFile.exists())
    }

    @Test
    fun test20_existingDb_rejectsIncompleteSchemaAndPreservesUserDataOnDisk() {
        // Seed customer data
        db.storeDatabaseQueries.insertTenant("TENANT_DO_NOT_DELETE", "Valuable Customer Data", 1)

        // Drop one trigger to simulate incomplete schema
        driver.execute(null, "DROP TRIGGER trg_products_barcode_cross_insert;", 0)
        driver.close()

        val checkFactory = DatabaseDriverFactory(tempDbFile)
        try {
            checkFactory.createDriver()
            fail("Expected DatabaseValidationException when trigger count is incomplete")
        } catch (e: DatabaseValidationException) {
            assertTrue("Error must mention triggers", e.message?.contains("triggers") == true)
        }

        // Section 5.A: Independent raw read verification that customer data and exact original value are preserved
        assertTrue("Database file must NOT be deleted when schema validation fails", tempDbFile.exists())
        val rawReadDriver = JdbcSqliteDriver("jdbc:sqlite:${tempDbFile.absolutePath}")
        try {
            val preservedName = rawReadDriver.executeQuery<String?>(
                null,
                "SELECT name FROM tenants WHERE id = 'TENANT_DO_NOT_DELETE';",
                {
                    if (it.next().value) QueryResult.Value(it.getString(0))
                    else QueryResult.Value(null)
                },
                0
            ).value
            assertEquals(
                "Original customer data value must remain completely intact and uncorrupted",
                "Valuable Customer Data",
                preservedName
            )
        } finally {
            rawReadDriver.close()
        }
    }

    @Test
    fun test26_concurrentInitialization_exclusiveLockPreventsRace() {
        val concurrentFile = File.createTempFile("test_concurrent_init_", ".db")
        if (concurrentFile.exists()) concurrentFile.delete()

        val executor = Executors.newFixedThreadPool(2)
        try {
            val task1 = Callable {
                val f1 = DatabaseDriverFactory(concurrentFile)
                val d1 = f1.createDriver()
                d1
            }
            val task2 = Callable {
                val f2 = DatabaseDriverFactory(concurrentFile)
                val d2 = f2.createDriver()
                d2
            }

            val futures = executor.invokeAll(listOf(task1, task2))
            val d1 = futures[0].get(15, TimeUnit.SECONDS)
            val d2 = futures[1].get(15, TimeUnit.SECONDS)

            assertNotNull("First driver must be initialized", d1)
            assertNotNull("Second driver must be initialized", d2)

            val tables1 = d1.executeQuery<Long>(null, "SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';", { it.next(); QueryResult.Value(it.getLong(0) ?: 0L) }, 0).value
            val tables2 = d2.executeQuery<Long>(null, "SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';", { it.next(); QueryResult.Value(it.getLong(0) ?: 0L) }, 0).value
            assertEquals(55L, tables1)
            assertEquals(55L, tables2)

            d1.close()
            d2.close()
        } finally {
            executor.shutdownNow()
            if (concurrentFile.exists()) concurrentFile.delete()
            File("${concurrentFile.parentFile.absolutePath}/${concurrentFile.name}.init.lock").takeIf { it.exists() }?.delete()
        }
    }

    @Test
    fun test27_atomicMove_neverReplacesExistingTargetDatabase() {
        val collisionDbFile = File.createTempFile("test_collision_", ".db")
        if (collisionDbFile.exists()) collisionDbFile.delete()

        val collisionFactory = DatabaseDriverFactory(collisionDbFile).apply {
            simulateTargetCollisionDuringMove = true
        }

        try {
            collisionFactory.createDriver()
            fail("Expected DatabaseInitializationException when target collision is detected during publication")
        } catch (e: DatabaseInitializationException) {
            assertTrue(
                "Must reject replacing existing database",
                e.message?.contains("already exists") == true || e.message?.contains("prohibited") == true
            )
        }

        // Verify original file and marker were NOT overwritten or replaced
        assertTrue("Target file must exist with marker preserved", collisionDbFile.exists())
        assertEquals(
            "Target file content must remain exactly the marker and not be overwritten",
            "PRE_EXISTING_TARGET_FILE_MARKER",
            collisionDbFile.readText()
        )
        collisionDbFile.delete()
        File("${collisionDbFile.parentFile.absolutePath}/${collisionDbFile.name}.init.lock").takeIf { it.exists() }?.delete()
    }

    @Test
    fun test28_walCheckpointFailure_abortsPublicationAndCleansStaging() {
        val checkpointFailFile = File.createTempFile("test_checkpoint_fail_", ".db")
        if (checkpointFailFile.exists()) checkpointFailFile.delete()

        val factory = DatabaseDriverFactory(checkpointFailFile).apply {
            simulateCheckpointFailure = true
        }

        try {
            factory.createDriver()
            fail("Expected DatabaseInitializationException when checkpoint fails")
        } catch (e: DatabaseInitializationException) {
            assertTrue("Must mention checkpoint failure", e.message?.contains("checkpoint") == true)
        } finally {
            assertFalse(
                "Target database file must not be published if checkpoint verification fails",
                checkpointFailFile.exists()
            )
            File("${checkpointFailFile.parentFile.absolutePath}/${checkpointFailFile.name}.init.lock").takeIf { it.exists() }?.delete()
        }
    }

    // ==========================================
    // 2. CONNECTION PRAGMAS (FULL SYNCHRONOUS & FOREIGN KEYS)
    // ==========================================

    @Test
    fun test21_connectionPragmas_actualValuesEnforced() {
        val foreignKeys = driver.executeQuery<Long>(
            null, "PRAGMA foreign_keys;",
            { it.next(); QueryResult.Value(it.getLong(0) ?: 0L) }, 0
        ).value
        assertEquals("PRAGMA foreign_keys must be 1 (ON)", 1L, foreignKeys)

        val busyTimeout = driver.executeQuery<Long>(
            null, "PRAGMA busy_timeout;",
            { it.next(); QueryResult.Value(it.getLong(0) ?: 0L) }, 0
        ).value
        assertEquals("PRAGMA busy_timeout must be 10000 ms", 10000L, busyTimeout)

        val journalMode = driver.executeQuery<String?>(
            null, "PRAGMA journal_mode;",
            { it.next(); QueryResult.Value(it.getString(0)?.lowercase()) }, 0
        ).value
        assertEquals("PRAGMA journal_mode must be 'wal'", "wal", journalMode)

        val synchronous = driver.executeQuery<Long>(
            null, "PRAGMA synchronous;",
            { it.next(); QueryResult.Value(it.getLong(0) ?: 0L) }, 0
        ).value
        assertEquals("PRAGMA synchronous must be 2 (FULL for strict financial and inventory durability)", 2L, synchronous)
    }

    @Test
    fun test22_foreignKeyEnforcement_rejectsOrphanReference() {
        try {
            driver.execute(
                null,
                "INSERT INTO stores (id, tenant_id, name, code) VALUES ('STR_ORPHAN', 'NON_EXISTENT_TENANT_XYZ', 'Orphan Store', 'ORP');",
                0
            )
            fail("SQLite must reject insert with non-existent foreign key reference")
        } catch (e: Exception) {
            assertTrue(
                "Expected foreign key constraint violation",
                e.message?.contains("FOREIGN KEY") == true || e.message?.contains("constraint") == true
            )
        }
    }

    @Test
    fun test23_connectionPragmas_allFourReappliedOnReopenedConnection() {
        driver.close()

        val reopenFactory = DatabaseDriverFactory(tempDbFile)
        val newDriver = reopenFactory.createDriver()
        try {
            val fk = newDriver.executeQuery<Long>(null, "PRAGMA foreign_keys;", { it.next(); QueryResult.Value(it.getLong(0) ?: 0L) }, 0).value
            assertEquals("PRAGMA foreign_keys must remain 1 (ON) on new connection", 1L, fk)

            val timeout = newDriver.executeQuery<Long>(null, "PRAGMA busy_timeout;", { it.next(); QueryResult.Value(it.getLong(0) ?: 0L) }, 0).value
            assertEquals("PRAGMA busy_timeout must remain 10000 ms on new connection", 10000L, timeout)

            val jm = newDriver.executeQuery<String?>(null, "PRAGMA journal_mode;", { it.next(); QueryResult.Value(it.getString(0)?.lowercase()) }, 0).value
            assertEquals("PRAGMA journal_mode must remain 'wal' on reopened database", "wal", jm)

            val sync = newDriver.executeQuery<Long>(null, "PRAGMA synchronous;", { it.next(); QueryResult.Value(it.getLong(0) ?: 0L) }, 0).value
            assertEquals("PRAGMA synchronous must remain 2 (FULL) on new connection", 2L, sync)
        } finally {
            newDriver.close()
        }
    }

    // ==========================================
    // 3. COMPARATIVE BENCHMARK: NORMAL vs FULL
    // ==========================================

    @Test
    fun test29_comparativeBenchmark_normalVsFullDurability() {
        // Execute identical set of operations on NORMAL and FULL
        val normalDbFile = File.createTempFile("bench_normal_", ".db")
        val fullDbFile = File.createTempFile("bench_full_", ".db")
        normalDbFile.delete()
        fullDbFile.delete()

        val normalFactory = DatabaseDriverFactory(normalDbFile)
        val normalDriver = normalFactory.createDriver()
        normalDriver.execute(null, "PRAGMA synchronous = NORMAL;", 0)

        val fullFactory = DatabaseDriverFactory(fullDbFile)
        val fullDriver = fullFactory.createDriver()
        fullDriver.execute(null, "PRAGMA synchronous = FULL;", 0)

        try {
            val operationsCount = 50

            val timeNormalMs = runBenchmarkBatch(normalDriver, operationsCount)
            val timeFullMs = runBenchmarkBatch(fullDriver, operationsCount)

            println("=== BENCHMARK RESULTS ($operationsCount retail transactions) ===")
            println("synchronous = NORMAL: $timeNormalMs ms")
            println("synchronous = FULL:   $timeFullMs ms")
            val diffMs = timeFullMs - timeNormalMs
            val ratio = if (timeNormalMs > 0) String.format("%.2f", timeFullMs.toDouble() / timeNormalMs.toDouble()) else "N/A"
            println("Difference: +$diffMs ms (Ratio FULL/NORMAL: ${ratio}x)")
            println("===============================================================")

            assertTrue("Both benchmarks must complete positively", timeNormalMs >= 0 && timeFullMs >= 0)
        } finally {
            normalDriver.close()
            fullDriver.close()
            normalDbFile.delete()
            fullDbFile.delete()
        }
    }

    private fun runBenchmarkBatch(targetDriver: SqlDriver, count: Int): Long {
        // Seed tenant, store, register, user, base unit
        val prefix = "B_${System.nanoTime()}_"
        targetDriver.execute(null, "INSERT INTO tenants (id, name) VALUES ('${prefix}T', 'Bench Tenant');", 0)
        targetDriver.execute(null, "INSERT INTO units_of_measure (id, dimension, name_ar, name_fr, symbol, is_fractional) VALUES ('${prefix}UOM', 'COUNT', 'قطعة', 'Piece', 'pc', 0);", 0)
        targetDriver.execute(null, "INSERT INTO stores (id, tenant_id, name, code) VALUES ('${prefix}STR', '${prefix}T', 'Bench Store', 'BS');", 0)
        targetDriver.execute(null, "INSERT INTO warehouses (id, tenant_id, store_id, name, is_default) VALUES ('${prefix}WH', '${prefix}T', '${prefix}STR', 'Default WH', 1);", 0)

        val start = System.nanoTime()
        for (i in 1..count) {
            val prodId = "${prefix}P_$i"
            targetDriver.execute(null, "INSERT INTO products (id, tenant_id, name, base_unit_id) VALUES ('$prodId', '${prefix}T', 'Bench Prod $i', '${prefix}UOM');", 0)
            val stockItemId = targetDriver.executeQuery<String>(
                null,
                "SELECT id FROM stock_items WHERE product_id = '$prodId';",
                { it.next(); QueryResult.Value(it.getString(0)!!) },
                0
            ).value

            targetDriver.execute(
                null,
                """
                INSERT INTO inventory_movements (
                    id, tenant_id, warehouse_id, stock_item_id, movement_type, source_event_id,
                    quantity_ticks, unit_cost_ticks, total_cost_centimes
                ) VALUES (
                    '${prefix}MOV_$i', '${prefix}T', '${prefix}WH', '$stockItemId', 'ADJUSTMENT_IN', '${prefix}EVT_$i',
                    10000, 100000, 1000
                );
                """.trimIndent(),
                0
            )
        }
        val end = System.nanoTime()
        return TimeUnit.NANOSECONDS.toMillis(end - start)
    }

    // ==========================================
    // 4. SQLITE RUNTIME VERSION & ED25519
    // ==========================================

    @Test
    fun test24_sqliteRuntimeVersion_loggedAndVerified() {
        val sqliteVersion = DatabaseDriverFactory.getSqliteVersion(driver)
        println("=== DESKTOP SQLITE RUNTIME VERSION: $sqliteVersion ===")
        assertTrue("SQLite runtime version must be non-empty", sqliteVersion.isNotBlank())
    }

    @Test
    fun test25_ed25519SignatureVerification_nativeJdkCrypto() {
        val isEd25519Available = try {
            KeyPairGenerator.getInstance("Ed25519")
            true
        } catch (_: java.security.NoSuchAlgorithmException) {
            false
        }

        Assume.assumeTrue(
            "Ed25519 JCA algorithm is not available in the active JDK 11 runtime (requires JDK 15+ or BouncyCastle provider); skipping without claiming false pass",
            isEd25519Available
        )

        val kpg = KeyPairGenerator.getInstance("Ed25519")
        val keyPair = kpg.generateKeyPair()

        val payload = "STORE_POS_OP:TENANT_01:DEVICE_01:SEQ_42:TOTAL_15000".toByteArray(Charsets.UTF_8)

        val signer = Signature.getInstance("Ed25519")
        signer.initSign(keyPair.private)
        signer.update(payload)
        val signature = signer.sign()
        assertTrue("Generated signature must not be empty", signature.isNotEmpty())

        val verifier = Signature.getInstance("Ed25519")
        verifier.initVerify(keyPair.public)
        verifier.update(payload)
        assertTrue("Valid Ed25519 signature must pass verification", verifier.verify(signature))

        val tamperedPayload = payload.clone()
        tamperedPayload[tamperedPayload.size - 1] = (tamperedPayload[tamperedPayload.size - 1] + 1).toByte()
        val tamperVerifier = Signature.getInstance("Ed25519")
        tamperVerifier.initVerify(keyPair.public)
        tamperVerifier.update(tamperedPayload)
        assertFalse("Tampered payload must be rejected by Ed25519 verification", tamperVerifier.verify(signature))
    }

    @Test
    fun test15_runFullReferenceVerificationMatrix_onActualDatabaseFile() {
        val script = listOf(
            File("verify_canonical_schema.py"),
            File("../../verify_canonical_schema.py"),
            File(System.getProperty("user.dir"), "verify_canonical_schema.py"),
            File(System.getProperty("user.dir"), "../../verify_canonical_schema.py")
        ).firstOrNull { it.exists() }

        var pythonAvailable = false
        try {
            val checkProcess = ProcessBuilder("python3", "--version").start()
            pythonAvailable = (checkProcess.waitFor() == 0)
        } catch (_: Exception) {
            pythonAvailable = false
        }

        Assume.assumeTrue(
            "python3 is not available in this environment; skipping external script verification without claiming false pass",
            pythonAvailable && script != null
        )

        val process = ProcessBuilder(
            "python3",
            script!!.absolutePath,
            tempDbFile.absolutePath
        ).redirectErrorStream(true).start()

        val output = process.inputStream.bufferedReader().use { it.readText() }
        val exitCode = process.waitFor()

        println("Python Verification Suite Output on SQLDelight DB:\n$output")
        assertEquals("Python script execution returned non-zero exit code:\n$output", 0, exitCode)
        assertTrue(
            "Output must confirm zero failures and reflect actual runs (58 PASS / 0 FAIL / 1 NOT RUN or 59 PASS)",
            output.contains("0 FAIL") && (output.contains("58 PASS") || output.contains("59 PASS"))
        )
    }
}
