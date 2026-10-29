// Design tokens, generated from design-tokens.json by tools/design_tokens.mjs. Do not edit by hand:
// change design-tokens.json at the repository root and run `node tools/design_tokens.mjs`.
package com.example.appname.ui.theme

import androidx.compose.ui.graphics.Color

// --- BRAND tokens (UI chrome only, never content meaning) ---
val BrandPrimaryLight = Color(0xFF131316)
val BrandPrimaryDark = Color(0xFFF2F2F4)
val BrandOnPrimaryLight = Color(0xFFFFFFFF)
val BrandOnPrimaryDark = Color(0xFF0F0F11)
val BrandBackgroundLight = Color(0xFFFFFFFF)
val BrandBackgroundDark = Color(0xFF0F0F11)
val BrandSurfaceLight = Color(0xFFF4F4F5)
val BrandSurfaceDark = Color(0xFF19191C)
val BrandSurfaceAltLight = Color(0xFFE8E8EB)
val BrandSurfaceAltDark = Color(0xFF232327)
val BrandTextLight = Color(0xFF131316)
val BrandTextDark = Color(0xFFF2F2F4)
val BrandTextMutedLight = Color(0xFF5C5C66)
val BrandTextMutedDark = Color(0xFFC4C4CC)
val BrandBorderLight = Color(0xFFD8D8DD)
val BrandBorderDark = Color(0xFF34343A)
val BrandSecondaryLight = Color(0xFF0B6E99)
val BrandSecondaryDark = Color(0xFF6CC0E0)
val BrandOnSecondaryLight = Color(0xFFFFFFFF)
val BrandOnSecondaryDark = Color(0xFF06141B)
val BrandLinkLight = Color(0xFF0B6E99)
val BrandLinkDark = Color(0xFF6CC0E0)
val BrandRecordLight = Color(0xFFB0152F)
val BrandRecordDark = Color(0xFFE3384B)
val BrandOnRecordLight = Color(0xFFFFFFFF)
val BrandOnRecordDark = Color(0xFF120708)

// --- GENRE tokens (content only, never chrome), keyed by the catalog genre key ---
val GenreDramaLight = Color(0xFF9D547C)
val GenreDramaDark = Color(0xFFF89DC9)
val GenreMysteryLight = Color(0xFF2459A5)
val GenreMysteryDark = Color(0xFF8EBBFF)
val GenreScifiLight = Color(0xFF007C88)
val GenreScifiDark = Color(0xFF44D5D7)
val GenreWesternLight = Color(0xFF864E37)
val GenreWesternDark = Color(0xFFC99580)
val GenreComedyLight = Color(0xFF816B01)
val GenreComedyDark = Color(0xFFD4C27E)
val GenreNewsLight = Color(0xFF504C3E)
val GenreNewsDark = Color(0xFFB4B3B3)
val GenreDocumentaryLight = Color(0xFF2F6100)
val GenreDocumentaryDark = Color(0xFF7CB45A)
val GenreSerialLight = Color(0xFF5A3983)
val GenreSerialDark = Color(0xFFAA87DE)

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
    success = Color(0xFF1D7A4A),
    warning = Color(0xFF8A5300),
    error = Color(0xFFC2410C),
    errorSurface = Color(0xFFFDEEE8),
)

val DarkSemanticColors = SemanticColors(
    success = Color(0xFF5CC593),
    warning = Color(0xFFE8B04B),
    error = Color(0xFFFF9466),
    errorSurface = Color(0xFF3A1F16),
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
