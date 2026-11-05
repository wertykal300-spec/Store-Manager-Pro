package com.storemanager.core.data

import app.cash.sqldelight.db.SqlDriver

actual class DatabaseDriverFactory {
    actual fun createDriver(): SqlDriver {
        throw UnsupportedOperationException(
            "Android POS client connects to Windows Host via LAN HTTPS. Android does not open or write to the master operational database directly."
        )
    }
}
