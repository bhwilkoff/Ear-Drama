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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
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
 *
 * ON AIR'S ROLES (DECISIONS 064, ANDROID-DESIGN §6.1a). Material components
 * take `colorScheme.primary` by default, so M3's `primary` slot holds the
 * brand's blue `secondary`: the selected tab, chips, filled buttons, the
 * spinner, and every other control follow it with no override. The brand's
 * red `primary` is only for what is live, read through [OnAir.colors]
 * (`live`, `onLive`) and set by hand on Play, the progress line, the slot on
 * the air, Listen live, and Start recording. It is M3's `tertiary` too, which
 * no default component uses. Dynamic color never changes [OnAir.colors].
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
        LocalOnAirColors provides if (darkTheme) DarkOnAirColors else LightOnAirColors,
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

/** On Air's chrome roles beyond M3's slots: red for what is live, and the link blue. */
data class OnAirColors(
    val live: Color,
    val onLive: Color,
    /** Links and the focus ring; a lighter blue than `secondary` in dark mode. */
    val link: Color,
    val dark: Boolean,
)

private val LightOnAirColors = OnAirColors(BrandPrimaryLight, BrandOnPrimaryLight, BrandLinkLight, dark = false)
private val DarkOnAirColors = OnAirColors(BrandPrimaryDark, BrandOnPrimaryDark, BrandLinkDark, dark = true)
private val LocalOnAirColors = staticCompositionLocalOf { LightOnAirColors }

/** On Air's roles (`OnAir.colors.live`, `OnAir.colors.link`, `OnAir.genre(key)`), light or dark. */
object OnAir {
    val colors: OnAirColors
        @Composable @ReadOnlyComposable get() = LocalOnAirColors.current

    /** The series' genre mark in this mode, or null for a key the palette does not name. */
    @Composable @ReadOnlyComposable
    fun genre(key: String?): Color? = genreColor(key, LocalOnAirColors.current.dark)
}

/** The selected tab's indicator and a selected chip: the blue at a sixth over the ground. */
private fun selectedContainer(blue: Color, ground: Color): Color = blue.copy(alpha = 0.16f).compositeOver(ground)

private val BrandLightColors = lightColorScheme(
    primary = BrandSecondaryLight,
    onPrimary = BrandOnSecondaryLight,
    primaryContainer = selectedContainer(BrandSecondaryLight, BrandBackgroundLight),
    onPrimaryContainer = BrandTextLight,
    secondary = BrandSecondaryLight,
    onSecondary = BrandOnSecondaryLight,
    secondaryContainer = selectedContainer(BrandSecondaryLight, BrandBackgroundLight),
    onSecondaryContainer = BrandSecondaryLight,
    tertiary = BrandPrimaryLight,
    onTertiary = BrandOnPrimaryLight,
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
    primary = BrandSecondaryDark,
    onPrimary = BrandOnSecondaryDark,
    primaryContainer = selectedContainer(BrandSecondaryDark, BrandBackgroundDark),
    onPrimaryContainer = BrandTextDark,
    secondary = BrandSecondaryDark,
    onSecondary = BrandOnSecondaryDark,
    secondaryContainer = selectedContainer(BrandSecondaryDark, BrandBackgroundDark),
    onSecondaryContainer = BrandSecondaryDark,
    tertiary = BrandPrimaryDark,
    onTertiary = BrandOnPrimaryDark,
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

/** A genre key's mark (`color.genre`, content only): null for a key the palette does not name. */
fun genreColor(key: String?, dark: Boolean): Color? = when (key) {
    "drama" -> if (dark) GenreDramaDark else GenreDramaLight
    "mystery" -> if (dark) GenreMysteryDark else GenreMysteryLight
    "scifi" -> if (dark) GenreScifiDark else GenreScifiLight
    "western" -> if (dark) GenreWesternDark else GenreWesternLight
    "comedy" -> if (dark) GenreComedyDark else GenreComedyLight
    "news" -> if (dark) GenreNewsDark else GenreNewsLight
    "documentary" -> if (dark) GenreDocumentaryDark else GenreDocumentaryLight
    "serial" -> if (dark) GenreSerialDark else GenreSerialLight
    else -> null
}
