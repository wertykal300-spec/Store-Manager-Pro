package com.storemanager.core.data

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import java.io.File
import java.io.RandomAccessFile
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.Properties
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

actual class DatabaseDriverFactory(
    private val dbFile: File? = null
) {
    internal var simulateTriggerFailure: Boolean = false
    internal var simulateCheckpointFailure: Boolean = false
    internal var simulateTargetCollisionDuringMove: Boolean = false
    internal var customTriggerScript: String? = null

    actual fun createDriver(): SqlDriver {
        val targetFile = dbFile ?: getDefaultDatabaseFile()
        val parentDir = targetFile.parentFile ?: File(".")
        if (!parentDir.exists()) {
            parentDir.mkdirs()
        }

        val canonicalPath = targetFile.canonicalPath
        val jvmLock = inJvmLocks.computeIfAbsent(canonicalPath) { Any() }
        val isNewDatabase: Boolean

        // Thread-safe within JVM + Process-safe across OS processes via FileChannel.lock
        synchronized(jvmLock) {
            val lockFile = File(parentDir, "${targetFile.name}.init.lock")
            RandomAccessFile(lockFile, "rw").use { raf ->
                raf.channel.lock().use {
                    // Check target existence strictly after acquiring exclusive lock
                    if (!targetFile.exists()) {
                        isNewDatabase = true
                        initializeNewDatabaseAtomically(targetFile, parentDir)
                    } else {
                        isNewDatabase = false
                    }
                }
            }
        }

        // Open connection to verified target database
        val properties = createConnectionProperties()
        val url = "jdbc:sqlite:${targetFile.absolutePath}"
        val driver = JdbcSqliteDriver(url, properties)

        // Apply per-connection runtime PRAGMAs
        applyConnectionRuntimePragmas(driver)

        if (!isNewDatabase) {
            // Validate existing database before modifying any persistent database properties
            try {
                validateExistingDatabase(driver)
                // Only after validation succeeds, ensure persistent journal_mode is WAL
                driver.execute(null, "PRAGMA journal_mode = WAL;", 0)
            } catch (e: Throwable) {
                try { driver.close() } catch (_: Throwable) {}
                // Never delete, wipe, or alter existing file on validation rejection
                throw e
            }
        }

        return driver
    }

    private fun createConnectionProperties(): Properties {
        return Properties().apply {
            put("foreign_keys", "true")
            put("busy_timeout", "10000") // 10 seconds busy timeout
            put("synchronous", "FULL")   // Full synchronous durability for financial and inventory safety
        }
    }

    private fun applyConnectionRuntimePragmas(driver: SqlDriver) {
        driver.execute(null, "PRAGMA foreign_keys = ON;", 0)
        driver.execute(null, "PRAGMA busy_timeout = 10000;", 0)
        driver.execute(null, "PRAGMA synchronous = FULL;", 0)
    }

    private fun initializeNewDatabaseAtomically(targetFile: File, parentDir: File) {
        // Staging file is created strictly in the SAME directory as the target database
        val stagingFile = File(
            parentDir,
            "${targetFile.name}.staging.${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}"
        )

        var stagingDriver: SqlDriver? = null
        try {
            val properties = Properties().apply {
                put("foreign_keys", "true")
                put("busy_timeout", "10000")
                put("journal_mode", "WAL")
                put("synchronous", "FULL")
            }
            val stagingUrl = "jdbc:sqlite:${stagingFile.absolutePath}"
            stagingDriver = JdbcSqliteDriver(stagingUrl, properties)

            // Configure staging connection
            stagingDriver.execute(null, "PRAGMA foreign_keys = ON;", 0)
            stagingDriver.execute(null, "PRAGMA busy_timeout = 10000;", 0)
            stagingDriver.execute(null, "PRAGMA journal_mode = WAL;", 0)
            stagingDriver.execute(null, "PRAGMA synchronous = FULL;", 0)

            // 1. Create 55 Tables and 107 explicit unique/functional indexes from SQLDelight schema
            StoreDatabase.Schema.create(stagingDriver)

            // 2. Execute 186 canonical triggers
            if (simulateTriggerFailure) {
                val script = customTriggerScript ?: loadCanonicalTriggerScript()
                val parts = script.split("CREATE TRIGGER").filter { it.trim().isNotBlank() }
                for (i in 0 until (parts.size / 2).coerceAtLeast(1)) {
                    val statement = "CREATE TRIGGER " + parts[i].trim()
                    stagingDriver.execute(null, statement, 0)
                }
                throw IllegalStateException("Simulated mid-trigger failure during database initialization")
            } else {
                val script = customTriggerScript ?: loadCanonicalTriggerScript()
                executeTriggerScript(stagingDriver, script)
            }

            // 3. Validate newly initialized staging schema before setting user_version
            validateCountsAndIntegrity(stagingDriver)

            // 4. Mark database baseline version
            stagingDriver.execute(null, "PRAGMA user_version = $EXPECTED_USER_VERSION;", 0)

            // 5. WAL Checkpoint Verification: read checkpoint results and verify no busy frames remain
            if (simulateCheckpointFailure) {
                throw DatabaseInitializationException("Simulated WAL checkpoint failure during staging verification")
            }
            val checkpointResult = queryCheckpoint(stagingDriver)
            val busy = checkpointResult.first
            val log = checkpointResult.second
            val checkpointed = checkpointResult.third

            if (busy != 0L) {
                throw DatabaseInitializationException("WAL checkpoint blocked: busy flag = $busy")
            }
            if (checkpointed < log) {
                throw DatabaseInitializationException("WAL checkpoint incomplete: checkpointed $checkpointed of $log frames")
            }

            // Close staging driver cleanly before publication
            stagingDriver.close()
            stagingDriver = null

            // 6. Verify sidecar files: no non-empty WAL/SHM files may remain
            val stagingWal = File("${stagingFile.absolutePath}-wal")
            val stagingShm = File("${stagingFile.absolutePath}-shm")
            if (stagingWal.exists()) {
                if (stagingWal.length() > 0L) {
                    throw DatabaseInitializationException("Staging WAL sidecar contains uncheckpointed data (${stagingWal.length()} bytes)")
                }
                stagingWal.delete()
            }
            if (stagingShm.exists()) {
                stagingShm.delete()
            }

            // 7. Secure Atomic Publication:
            // Check collision: Never replace an existing database file under any circumstance
            if (simulateTargetCollisionDuringMove) {
                targetFile.writeText("PRE_EXISTING_TARGET_FILE_MARKER")
            }
            if (targetFile.exists()) {
                throw DatabaseInitializationException(
                    "Publication aborted: target database file already exists at ${targetFile.absolutePath}. Replacing existing databases is strictly prohibited."
                )
            }

            // Move using ATOMIC_MOVE strictly — NO fallback to REPLACE_EXISTING
            try {
                Files.move(
                    stagingFile.toPath(),
                    targetFile.toPath(),
                    StandardCopyOption.ATOMIC_MOVE
                )
            } catch (e: AtomicMoveNotSupportedException) {
                throw DatabaseInitializationException(
                    "Filesystem does not support ATOMIC_MOVE across target path. Staging aborted to protect integrity.",
                    e
                )
            } catch (e: Exception) {
                throw DatabaseInitializationException(
                    "Atomic publication failed: ${e.message}",
                    e
                )
            }
        } catch (e: Throwable) {
            // Safely close staging driver
            try { stagingDriver?.close() } catch (_: Throwable) {}
            // Clean up staging files completely
            cleanFileAndSidecars(stagingFile)
            // Ensure target file does NOT exist in incomplete state
            if (targetFile.exists() && targetFile.length() == 0L) {
                targetFile.delete()
            }
            throw DatabaseInitializationException(
                "Database initialization failed and staging was cleaned up: ${e.message}",
                e
            )
        }
    }

    private fun queryCheckpoint(driver: SqlDriver): Triple<Long, Long, Long> {
        val cursor = driver.executeQuery<Triple<Long, Long, Long>>(
            null,
            "PRAGMA wal_checkpoint(TRUNCATE);",
            {
                it.next()
                val busy = it.getLong(0) ?: 0L
                val log = it.getLong(1) ?: 0L
                val checkpointed = it.getLong(2) ?: 0L
                QueryResult.Value(Triple(busy, log, checkpointed))
            },
            0
        )
        return cursor.value
    }

    private fun loadCanonicalTriggerScript(): String {
        val stream = this::class.java.classLoader.getResourceAsStream("canonical_triggers.sql")
            ?: error("canonical_triggers.sql resource not found in classpath")
        return stream.bufferedReader().use { it.readText() }
    }

    private fun executeTriggerScript(driver: SqlDriver, script: String) {
        val parts = script.split("CREATE TRIGGER")
        for (part in parts) {
            val trimmed = part.trim()
            if (trimmed.isNotBlank()) {
                val statement = "CREATE TRIGGER " + trimmed
                driver.execute(null, statement, 0)
            }
        }
    }

    private fun cleanFileAndSidecars(baseFile: File) {
        if (baseFile.exists()) baseFile.delete()
        File("${baseFile.absolutePath}-wal").takeIf { it.exists() }?.delete()
        File("${baseFile.absolutePath}-shm").takeIf { it.exists() }?.delete()
    }

    fun validateExistingDatabase(driver: SqlDriver) {
        // 1. Verify PRAGMA user_version
        val userVersion = querySingleLong(driver, "PRAGMA user_version;")
        if (userVersion != EXPECTED_USER_VERSION) {
            throw DatabaseValidationException(
                "Invalid database user_version: found $userVersion, expected $EXPECTED_USER_VERSION. Database rejected."
            )
        }

        // 2. Validate tables, indexes, triggers, and SQLite integrity
        validateCountsAndIntegrity(driver)
    }

    private fun validateCountsAndIntegrity(driver: SqlDriver) {
        // Tables count
        val tableCount = querySingleLong(
            driver,
            "SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
        )
        if (tableCount != EXPECTED_TABLE_COUNT) {
            throw DatabaseValidationException(
                "Incomplete database schema: found $tableCount tables, expected $EXPECTED_TABLE_COUNT."
            )
        }

        // Indexes count
        val indexCount = querySingleLong(
            driver,
            "SELECT count(*) FROM sqlite_master WHERE type='index' AND sql IS NOT NULL;"
        )
        if (indexCount != EXPECTED_INDEX_COUNT) {
            throw DatabaseValidationException(
                "Incomplete database schema: found $indexCount explicit indexes, expected $EXPECTED_INDEX_COUNT."
            )
        }

        // Triggers count
        val triggerCount = querySingleLong(
            driver,
            "SELECT count(*) FROM sqlite_master WHERE type='trigger';"
        )
        if (triggerCount != EXPECTED_TRIGGER_COUNT) {
            throw DatabaseValidationException(
                "Incomplete database schema: found $triggerCount triggers, expected $EXPECTED_TRIGGER_COUNT."
            )
        }

        // Integrity check
        val integrityResult = querySingleString(driver, "PRAGMA integrity_check;")
        if (integrityResult != "ok") {
            throw DatabaseValidationException(
                "Database integrity check failed: $integrityResult"
            )
        }

        // Foreign key check
        val fkErrors = countRows(driver, "PRAGMA foreign_key_check;")
        if (fkErrors > 0) {
            throw DatabaseValidationException(
                "Database foreign key check failed with $fkErrors violations."
            )
        }
    }

    private fun querySingleLong(driver: SqlDriver, sql: String): Long {
        val cursor = driver.executeQuery<Long>(
            null,
            sql,
            {
                it.next()
                QueryResult.Value(it.getLong(0) ?: 0L)
            },
            0
        )
        return cursor.value
    }

    private fun querySingleString(driver: SqlDriver, sql: String): String? {
        val cursor = driver.executeQuery<String?>(
            null,
            sql,
            {
                it.next()
                QueryResult.Value(it.getString(0))
            },
            0
        )
        return cursor.value
    }

    private fun countRows(driver: SqlDriver, sql: String): Long {
        val cursor = driver.executeQuery<Long>(
            null,
            sql,
            {
                var count = 0L
                while (it.next().value) {
                    count++
                }
                QueryResult.Value(count)
            },
            0
        )
        return cursor.value
    }

    companion object {
        private val inJvmLocks = ConcurrentHashMap<String, Any>()

        const val EXPECTED_TABLE_COUNT = 55L
        const val EXPECTED_INDEX_COUNT = 107L
        const val EXPECTED_TRIGGER_COUNT = 186L
        const val EXPECTED_USER_VERSION = 1L

        fun getDefaultDatabaseFile(): File {
            val os = System.getProperty("os.name").lowercase()
            val baseDir = when {
                os.contains("win") -> {
                    val appData = System.getenv("LOCALAPPDATA")
                        ?: (System.getProperty("user.home") + "\\AppData\\Local")
                    File(appData, "StoreManagerPro\\data")
                }
                os.contains("mac") -> {
                    File(System.getProperty("user.home"), "Library/Application Support/StoreManagerPro/data")
                }
                else -> { // Linux / Unix
                    val xdgData = System.getenv("XDG_DATA_HOME")
                    if (!xdgData.isNullOrBlank()) {
                        File(xdgData, "storemanagerpro/data")
                    } else {
                        File(System.getProperty("user.home"), ".local/share/storemanagerpro/data")
                    }
                }
            }
            return File(baseDir, "store_manager_master.db")
        }

        fun createInMemoryDriver(): SqlDriver {
            val properties = Properties().apply {
                put("foreign_keys", "true")
                put("busy_timeout", "10000")
                put("synchronous", "FULL")
            }
            val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY, properties)
            driver.execute(null, "PRAGMA foreign_keys = ON;", 0)
            driver.execute(null, "PRAGMA busy_timeout = 10000;", 0)
            driver.execute(null, "PRAGMA synchronous = FULL;", 0)

            StoreDatabase.Schema.create(driver)

            val factory = DatabaseDriverFactory()
            val script = factory.loadCanonicalTriggerScript()
            factory.executeTriggerScript(driver, script)
            driver.execute(null, "PRAGMA user_version = $EXPECTED_USER_VERSION;", 0)

            return driver
        }

        fun getSqliteVersion(driver: SqlDriver): String {
            val cursor = driver.executeQuery<String>(
                null,
                "SELECT sqlite_version();",
                {
                    it.next()
                    QueryResult.Value(it.getString(0) ?: "UNKNOWN")
                },
                0
            )
            return cursor.value
        }
    }
}
