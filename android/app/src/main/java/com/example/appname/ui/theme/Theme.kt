package com.example.appname.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext

/**
 * App theme — brand-first by default; dynamic color (Material You)
 * opt-in only.
 *
 * Tonal elevation tokens (surface / surfaceContainer / surfaceContainerLow
 * etc.) live in MaterialTheme.colorScheme — use those for chrome
 * elevation. Content surfaces stay at `surface` flat per the binding
 * design rule "tonal elevation = navigation chrome only".
 *
 * Pass `dynamicColor = true` from Settings when the user enables
 * "Use system colors" — overrides `primary` only on Android 12+;
 * the [AppSemantics] tokens never change.
 *
 * The colors come from Color.kt, which tools/design_tokens.mjs writes
 * from design-tokens.json. Change the look there, not here.
 */
@Composable
fun AppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit,
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val ctx = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
        }
        darkTheme -> BrandDarkColors
        else -> BrandLightColors
    }

    CompositionLocalProvider(
        LocalSemanticColors provides if (darkTheme) DarkSemanticColors else LightSemanticColors,
    ) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = AppTypography,
            content = content,
        )
    }
}

private val LocalSemanticColors = staticCompositionLocalOf { LightSemanticColors }

/** Semantic colors for content meaning (`AppSemantics.colors.error`), light or dark. */
object AppSemantics {
    val colors: SemanticColors
        @Composable @ReadOnlyComposable get() = LocalSemanticColors.current
}

private val BrandLightColors = lightColorScheme(
    primary = BrandPrimaryLight,
    onPrimary = BrandOnPrimaryLight,
    background = BrandBackgroundLight,
    onBackground = BrandTextLight,
    surface = BrandBackgroundLight,
    onSurface = BrandTextLight,
    surfaceVariant = BrandSurfaceLight,
    onSurfaceVariant = BrandTextMutedLight,
    surfaceContainer = BrandSurfaceLight,
    surfaceContainerHigh = BrandSurfaceAltLight,
    outline = BrandBorderLight,
    outlineVariant = BrandBorderLight,
)

private val BrandDarkColors = darkColorScheme(
    primary = BrandPrimaryDark,
    onPrimary = BrandOnPrimaryDark,
    background = BrandBackgroundDark,
    onBackground = BrandTextDark,
    surface = BrandBackgroundDark,
    onSurface = BrandTextDark,
    surfaceVariant = BrandSurfaceDark,
    onSurfaceVariant = BrandTextMutedDark,
    surfaceContainer = BrandSurfaceDark,
    surfaceContainerHigh = BrandSurfaceAltDark,
    outline = BrandBorderDark,
    outlineVariant = BrandBorderDark,
)
