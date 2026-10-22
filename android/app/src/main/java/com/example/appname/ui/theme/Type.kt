// Design tokens, generated from design-tokens.json by tools/design_tokens.mjs. Do not edit by hand:
// change design-tokens.json at the repository root and run `node tools/design_tokens.mjs`.
package com.example.appname.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// The system face. A custom face goes in res/font/ and replaces this line by
// hand only if the chosen look truly needs one; keep fonts out of the splash path.
private val BrandFontFamily = FontFamily.Default

/** The six-level ramp: refuse a seventh level; refactor instead. */
val AppTypography = Typography(
    displaySmall = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Bold, fontSize = 28.sp), // L1 pageTitle
    headlineSmall = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Bold, fontSize = 20.sp), // L2 sectionHeader
    titleMedium = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 16.sp), // L3 bodyStrong
    bodyMedium = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Normal, fontSize = 16.sp), // L4 body
    labelMedium = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Normal, fontSize = 13.sp), // L5 caption
    bodySmall = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.Normal, fontSize = 14.sp, fontFeatureSettings = "tnum"), // L6 tabular
)
