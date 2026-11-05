package com.storemanager.core.designsystem.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val DarkStoreColorScheme = darkColorScheme(
    primary = StoreColors.Amber400,
    onPrimary = StoreColors.Slate950,
    primaryContainer = StoreColors.Slate800,
    onPrimaryContainer = StoreColors.Amber400,
    secondary = StoreColors.Sky500,
    onSecondary = Color.White,
    background = StoreColors.Slate950,
    onBackground = StoreColors.Slate100,
    surface = StoreColors.Slate900,
    onSurface = StoreColors.Slate100,
    surfaceVariant = StoreColors.Slate800,
    onSurfaceVariant = StoreColors.Slate400,
    outline = StoreColors.Slate700
)

val LightStoreColorScheme = lightColorScheme(
    primary = StoreColors.Slate900,
    onPrimary = Color.White,
    primaryContainer = StoreColors.Slate100,
    onPrimaryContainer = StoreColors.Slate900,
    secondary = StoreColors.Amber500,
    onSecondary = StoreColors.Slate950,
    background = StoreColors.Slate50,
    onBackground = StoreColors.Slate900,
    surface = Color.White,
    onSurface = StoreColors.Slate900,
    surfaceVariant = StoreColors.Slate100,
    onSurfaceVariant = StoreColors.Slate600,
    outline = StoreColors.Slate200
)

@Composable
fun StoreManagerTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkStoreColorScheme else LightStoreColorScheme

    MaterialTheme(
        colorScheme = colorScheme,
        typography = StoreTypography,
        content = content
    )
}
