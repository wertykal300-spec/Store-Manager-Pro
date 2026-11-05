package com.storemanager.core.data

import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AndroidDatabaseIsolationTest {

    @Test
    fun testAndroid_cannotOpenMasterDatabase_throwsUnsupportedOperationException() {
        val factory = DatabaseDriverFactory()
        try {
            factory.createDriver()
            fail("Android must NOT be permitted to create or open master operational database")
        } catch (e: UnsupportedOperationException) {
            assertTrue(
                "Exception message must clarify LAN HTTPS architecture and prohibition of direct SQLite access",
                e.message?.contains("LAN HTTPS") == true && e.message?.contains("Android does not open or write") == true
            )
        }
    }
}
