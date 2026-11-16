package com.focuskey.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** Same accent colors as the iOS app (system blue accent, green, red, orange). */
object FocusColors {
    val Blue = Color(0xFF007AFF)
    val BlueDark = Color(0xFF0A84FF)
    val Green = Color(0xFF34C759)
    val Red = Color(0xFFFF3B30)
    val Orange = Color(0xFFFF9500)
}

private val LightColors = lightColorScheme(
    primary = FocusColors.Blue,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD6E8FF),
    onPrimaryContainer = Color(0xFF00214A),
    secondary = FocusColors.Blue,
    background = Color(0xFFF2F2F7),
    surface = Color.White,
    surfaceVariant = Color(0xFFF2F2F7),
    error = FocusColors.Red,
)

private val DarkColors = darkColorScheme(
    primary = FocusColors.BlueDark,
    onPrimary = Color.White,
    primaryContainer = Color(0xFF003A80),
    onPrimaryContainer = Color(0xFFD6E8FF),
    secondary = FocusColors.BlueDark,
    background = Color.Black,
    surface = Color(0xFF1C1C1E),
    surfaceVariant = Color(0xFF2C2C2E),
    error = Color(0xFFFF453A),
)

@Composable
fun FocusKeyTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content
    )
}
