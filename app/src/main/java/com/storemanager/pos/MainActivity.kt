package com.storemanager.pos

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Scaffold
import androidx.compose.ui.Modifier
import com.storemanager.core.designsystem.components.StoreBootstrapScreen
import com.storemanager.core.designsystem.theme.StoreManagerTheme
import com.storemanager.core.domain.model.PlatformType
import com.storemanager.core.domain.usecase.GetInitialStoreContextUseCase
import com.storemanager.core.domain.usecase.GetSystemEnvironmentUseCase

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val getEnvironment = GetSystemEnvironmentUseCase()
        val getStoreContext = GetInitialStoreContextUseCase()

        val environment = getEnvironment(PlatformType.ANDROID)
        val storeContext = getStoreContext()

        setContent {
            StoreManagerTheme(darkTheme = false) {
                Scaffold(
                    modifier = Modifier
                        .fillMaxSize()
                        .statusBarsPadding()
                        .navigationBarsPadding()
                ) { _ ->
                    StoreBootstrapScreen(
                        environment = environment,
                        storeContext = storeContext
                    )
                }
            }
        }
    }
}
