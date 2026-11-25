package com.example.appname.ui

/**
 * Whether a bottom bar's labels fit as whole words. A tab's label gets its share of the width less its own padding; when the
 * widest word would not stand on one line the bar shows icons alone (Material's pattern at large text) and each icon carries its
 * name for TalkBack, so no label ever breaks in the middle of a word (R4-2c, PLAYS-DESIGN §13).
 */
internal object TabLabels {
    /** The room around a label inside its item, in pixels at density 1: the item's own padding on each side. */
    const val PADDING_DP = 16f

    fun fit(widestWordPx: Int, screenWidthPx: Float, items: Int, density: Float): Boolean =
        items > 0 && widestWordPx <= screenWidthPx / items - PADDING_DP * density
}
