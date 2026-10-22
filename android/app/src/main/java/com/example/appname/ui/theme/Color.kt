// Design tokens, generated from design-tokens.json by tools/design_tokens.mjs. Do not edit by hand:
// change design-tokens.json at the repository root and run `node tools/design_tokens.mjs`.
package com.example.appname.ui.theme

import androidx.compose.ui.graphics.Color

// --- BRAND tokens (UI chrome only, never content meaning) ---
val BrandPrimaryLight = Color(0xFF3F5E78)
val BrandPrimaryDark = Color(0xFFA7BFD6)
val BrandOnPrimaryLight = Color(0xFFFFFFFF)
val BrandOnPrimaryDark = Color(0xFF0F1720)
val BrandBackgroundLight = Color(0xFFFFFFFF)
val BrandBackgroundDark = Color(0xFF141619)
val BrandSurfaceLight = Color(0xFFF5F6F8)
val BrandSurfaceDark = Color(0xFF1D2024)
val BrandSurfaceAltLight = Color(0xFFEBEDF0)
val BrandSurfaceAltDark = Color(0xFF272B30)
val BrandTextLight = Color(0xFF1A1C1F)
val BrandTextDark = Color(0xFFECEEF1)
val BrandTextMutedLight = Color(0xFF5B6270)
val BrandTextMutedDark = Color(0xFFA2A9B4)
val BrandBorderLight = Color(0xFFD3D7DE)
val BrandBorderDark = Color(0xFF3A3F47)

// --- SEMANTIC tokens (content only, never chrome) ---
// Read them through AppSemantics (Theme.kt), never through colorScheme, so
// Material You dynamic color can never change what they mean.
data class SemanticColors(
    val success: Color,
    val warning: Color,
    val error: Color,
    val errorSurface: Color,
)

val LightSemanticColors = SemanticColors(
    success = Color(0xFF1E7A4F),
    warning = Color(0xFF8A5A00),
    error = Color(0xFFB42318),
    errorSurface = Color(0xFFFDECEA),
)

val DarkSemanticColors = SemanticColors(
    success = Color(0xFF5CC593),
    warning = Color(0xFFE8B04B),
    error = Color(0xFFFF8A80),
    errorSurface = Color(0xFF3A1D1B),
)

object Spacing {
    const val S1 = 4 // dp
    const val S2 = 8 // dp
    const val S3 = 12 // dp
    const val S4 = 16 // dp
    const val S6 = 24 // dp
    const val S8 = 32 // dp
}

object Radius {
    const val Control = 8 // dp
    const val Card = 12 // dp
}
