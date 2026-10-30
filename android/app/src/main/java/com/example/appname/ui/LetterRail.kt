package com.example.appname.ui

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

private val Slot = 20.dp

/**
 * Browse's A to Z fast-scroll rail: the letters down the trailing edge; a touch or a drag along
 * them jumps to that letter's first show, with the selection haptic per letter. TalkBack gets one
 * custom action per letter instead of a strip of twenty-seven tiny targets.
 */
@Composable
fun LetterRail(letters: List<String>, onJump: (String) -> Unit, modifier: Modifier = Modifier) {
    val haptics = rememberHaptics()
    val slotPx = with(LocalDensity.current) { Slot.toPx() }
    var last by remember { mutableStateOf<String?>(null) }
    fun pick(y: Float) {
        val letter = letters.getOrNull((y / slotPx).toInt().coerceIn(0, letters.lastIndex)) ?: return
        if (letter != last) {
            last = letter
            haptics(Haptic.Selection)
            onJump(letter)
        }
    }
    Box(modifier.padding(end = 2.dp)) {
        Column(
            Modifier
                .width(Slot)
                .pointerInput(letters) { detectTapGestures { pick(it.y) } }
                .pointerInput(letters) {
                    detectVerticalDragGestures(
                        onDragStart = { pick(it.y) },
                        onDragEnd = { last = null },
                        onDragCancel = { last = null },
                    ) { change, _ -> pick(change.position.y) }
                }
                .clearAndSetSemantics {
                    contentDescription = "Jump to a letter"
                    customActions = letters.map { l ->
                        CustomAccessibilityAction(if (l == "#") "Numbers and symbols" else "Letter $l") { onJump(l); true }
                    }
                },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            letters.forEach { l ->
                Box(Modifier.size(Slot), contentAlignment = Alignment.Center) {
                    Text(
                        l,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}
