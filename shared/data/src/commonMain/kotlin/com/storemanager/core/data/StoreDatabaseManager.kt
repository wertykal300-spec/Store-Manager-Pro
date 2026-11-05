package com.storemanager.core.data

import app.cash.sqldelight.db.SqlDriver

class StoreDatabaseManager(
    private val driverFactory: DatabaseDriverFactory
) {
    private var driver: SqlDriver? = null
    private var database: StoreDatabase? = null

    @Synchronized
    fun getDatabase(): StoreDatabase {
        if (database == null) {
            val d = driverFactory.createDriver()
            try {
                database = StoreDatabase(d)
                driver = d
            } catch (t: Throwable) {
                try { d.close() } catch (_: Throwable) {}
                driver = null
                database = null
                throw t
            }
        }
        return database!!
    }

    @Synchronized
    fun getDriver(): SqlDriver {
        if (driver == null) {
            getDatabase()
        }
        return driver!!
    }

    @Synchronized
    fun isOpen(): Boolean = driver != null

    @Synchronized
    fun close() {
        try { driver?.close() } catch (_: Throwable) {}
        driver = null
        database = null
    }
}
