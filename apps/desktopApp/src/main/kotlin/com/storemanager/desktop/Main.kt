package com.storemanager.desktop

import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowState
import androidx.compose.ui.window.application
import com.storemanager.core.designsystem.components.StoreBootstrapScreen
import com.storemanager.core.designsystem.theme.StoreManagerTheme
import com.storemanager.core.domain.model.PlatformType
import com.storemanager.core.domain.usecase.GetInitialStoreContextUseCase
import com.storemanager.core.domain.usecase.GetSystemEnvironmentUseCase

fun main() = application {
    val getEnvironment = GetSystemEnvironmentUseCase()
    val getStoreContext = GetInitialStoreContextUseCase()

    val environment = getEnvironment(PlatformType.WINDOWS)
    val storeContext = getStoreContext()

    Window(
        onCloseRequest = ::exitApplication,
        title = "Store Manager Pro — Windows Host",
        state = WindowState(width = 1100.dp, height = 750.dp)
    ) {
        StoreManagerTheme(darkTheme = true) {
            StoreBootstrapScreen(
                environment = environment,
                storeContext = storeContext
            )
        }
    }
}
