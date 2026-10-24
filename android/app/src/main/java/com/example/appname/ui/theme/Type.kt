// Design tokens, generated from design-tokens.json by tools/design_tokens.mjs. Do not edit by hand:
// change design-tokens.json at the repository root and run `node tools/design_tokens.mjs`.
package com.example.appname.ui.theme

import com.example.appname.R
import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// Body text is the system face (Decision 060).
private val BrandFontFamily = FontFamily.Default

// The display levels set the bundled Big Shoulders (res/font, built by tools/build_fonts.py).
val DisplayFontFamily = FontFamily(Font(R.font.big_shoulders_bold, FontWeight.Bold))

/** The six-level ramp: refuse a seventh level; refactor instead. */
val AppTypography = Typography(
    displaySmall = TextStyle(fontFamily = DisplayFontFamily, fontWeight = FontWeight.Bold, fontSize = 28.sp), // L1 pageTitle
    headlineSmall = TextStyle(fontFamily = DisplayFontFamily, fontWeight = FontWeight.Bold, fontSize = 20.sp), // L2 sectionHeader
    titleMedium = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 16.sp), // L3 bodyStrong
    bodyMedium = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Normal, fontSize = 16.sp), // L4 body
    labelMedium = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Normal, fontSize = 13.sp), // L5 caption
    bodySmall = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Normal, fontSize = 14.sp, fontFeatureSettings = "tnum"), // L6 tabular
)
