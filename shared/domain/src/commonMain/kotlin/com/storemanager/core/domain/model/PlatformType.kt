package com.storemanager.core.domain.model

enum class PlatformType(val displayName: String, val osFamily: String) {
    WINDOWS("Windows Host / Desktop POS", "Desktop (x64)"),
    ANDROID("Android POS Client", "Mobile / Tablet (Android)")
}

data class SystemEnvironment(
    val appName: String = "Store Manager Pro",
    val appVersion: String = "1.0-alpha01",
    val platform: PlatformType,
    val isLanHostCapable: Boolean,
    val localFirstStorage: String = "SQLite (Local-First)",
    val architectureVersion: String = "v1.0 (Phase 1A Baseline)"
)

data class StoreContext(
    val storeId: String = "STORE_MAIN",
    val storeName: String = "Store Manager Pro — Main Store",
    val defaultCurrency: String = "DZD",
    val defaultLanguage: String = "العربية (RTL) / Français (LTR)",
    val multiUserLanEnabled: Boolean = true
)
