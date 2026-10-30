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

// --- ON-GENRE: text on a genre mark used as a fill; the page text for an unnamed key ---
val OnGenreDramaLight = Color(0xFFFFFFFF)
val OnGenreDramaDark = Color(0xFF0F0F11)
val OnGenreMysteryLight = Color(0xFFFFFFFF)
val OnGenreMysteryDark = Color(0xFF0F0F11)
val OnGenreScifiLight = Color(0xFFFFFFFF)
val OnGenreScifiDark = Color(0xFF0F0F11)
val OnGenreWesternLight = Color(0xFFFFFFFF)
val OnGenreWesternDark = Color(0xFF0F0F11)
val OnGenreComedyLight = Color(0xFFFFFFFF)
val OnGenreComedyDark = Color(0xFF0F0F11)
val OnGenreNewsLight = Color(0xFFFFFFFF)
val OnGenreNewsDark = Color(0xFF0F0F11)
val OnGenreDocumentaryLight = Color(0xFFFFFFFF)
val OnGenreDocumentaryDark = Color(0xFF0F0F11)
val OnGenreSerialLight = Color(0xFFFFFFFF)
val OnGenreSerialDark = Color(0xFF0F0F11)
fun onGenreColor(key: String?, dark: Boolean): Color = when (key) {
    "drama" -> if (dark) OnGenreDramaDark else OnGenreDramaLight
    "mystery" -> if (dark) OnGenreMysteryDark else OnGenreMysteryLight
    "scifi" -> if (dark) OnGenreScifiDark else OnGenreScifiLight
    "western" -> if (dark) OnGenreWesternDark else OnGenreWesternLight
    "comedy" -> if (dark) OnGenreComedyDark else OnGenreComedyLight
    "news" -> if (dark) OnGenreNewsDark else OnGenreNewsLight
    "documentary" -> if (dark) OnGenreDocumentaryDark else OnGenreDocumentaryLight
    "serial" -> if (dark) OnGenreSerialDark else OnGenreSerialLight
    else -> if (dark) BrandTextDark else BrandTextLight
}

// --- BOARDS (D2c-1): the block a tile or head stands on; surfaceAlt for a show with no genre ---
val BoardDramaLight = Color(0xFF86426F)
val BoardDramaDark = Color(0xFF5F2A4D)
val BoardMysteryLight = Color(0xFF375C9B)
val BoardMysteryDark = Color(0xFF223F6F)
val BoardScifiLight = Color(0xFF006A79)
val BoardScifiDark = Color(0xFF004854)
val BoardWesternLight = Color(0xFF8B492A)
val BoardWesternDark = Color(0xFF623018)
val BoardComedyLight = Color(0xFF795700)
val BoardComedyDark = Color(0xFF543B00)
val BoardNewsLight = Color(0xFF615D53)
val BoardNewsDark = Color(0xFF424038)
val BoardDocumentaryLight = Color(0xFF296E38)
val BoardDocumentaryDark = Color(0xFF154C22)
val BoardSerialLight = Color(0xFF684D92)
val BoardSerialDark = Color(0xFF473368)
fun boardColor(key: String?, dark: Boolean): Color = when (key) {
    "drama" -> if (dark) BoardDramaDark else BoardDramaLight
    "mystery" -> if (dark) BoardMysteryDark else BoardMysteryLight
    "scifi" -> if (dark) BoardScifiDark else BoardScifiLight
    "western" -> if (dark) BoardWesternDark else BoardWesternLight
    "comedy" -> if (dark) BoardComedyDark else BoardComedyLight
    "news" -> if (dark) BoardNewsDark else BoardNewsLight
    "documentary" -> if (dark) BoardDocumentaryDark else BoardDocumentaryLight
    "serial" -> if (dark) BoardSerialDark else BoardSerialLight
    else -> if (dark) BrandSurfaceAltDark else BrandSurfaceAltLight
}

// --- ON-BOARD: the one color everything on a board takes; the page text on the neutral board ---
val OnBoardDramaLight = Color(0xFFFFFFFF)
val OnBoardDramaDark = Color(0xFFF2F2F4)
val OnBoardMysteryLight = Color(0xFFFFFFFF)
val OnBoardMysteryDark = Color(0xFFF2F2F4)
val OnBoardScifiLight = Color(0xFFFFFFFF)
val OnBoardScifiDark = Color(0xFFF2F2F4)
val OnBoardWesternLight = Color(0xFFFFFFFF)
val OnBoardWesternDark = Color(0xFFF2F2F4)
val OnBoardComedyLight = Color(0xFFFFFFFF)
val OnBoardComedyDark = Color(0xFFF2F2F4)
val OnBoardNewsLight = Color(0xFFFFFFFF)
val OnBoardNewsDark = Color(0xFFF2F2F4)
val OnBoardDocumentaryLight = Color(0xFFFFFFFF)
val OnBoardDocumentaryDark = Color(0xFFF2F2F4)
val OnBoardSerialLight = Color(0xFFFFFFFF)
val OnBoardSerialDark = Color(0xFFF2F2F4)
fun onBoardColor(key: String?, dark: Boolean): Color = when (key) {
    "drama" -> if (dark) OnBoardDramaDark else OnBoardDramaLight
    "mystery" -> if (dark) OnBoardMysteryDark else OnBoardMysteryLight
    "scifi" -> if (dark) OnBoardScifiDark else OnBoardScifiLight
    "western" -> if (dark) OnBoardWesternDark else OnBoardWesternLight
    "comedy" -> if (dark) OnBoardComedyDark else OnBoardComedyLight
    "news" -> if (dark) OnBoardNewsDark else OnBoardNewsLight
    "documentary" -> if (dark) OnBoardDocumentaryDark else OnBoardDocumentaryLight
    "serial" -> if (dark) OnBoardSerialDark else OnBoardSerialLight
    else -> if (dark) BrandTextDark else BrandTextLight
}

// --- PRINT MOUNT (D2c-3): the ground a contained picture sits on; the hairline edge around every window ---
val PrintGroundLight = Color(0xFFEDEDED)
val PrintGroundDark = Color(0xFF2A2A2E)
val PrintEdgeLight = Color(0x2E131316)
val PrintEdgeDark = Color(0x29F2F2F4)

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
