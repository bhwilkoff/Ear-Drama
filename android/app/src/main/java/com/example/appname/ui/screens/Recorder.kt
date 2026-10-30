package com.example.appname.ui.screens

import com.example.appname.ui.wayColors
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FiberManualRecord
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.Replay
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.appname.plays.LinePart
import com.example.appname.plays.PartID
import com.example.appname.plays.PartState
import com.example.appname.plays.PlayScript
import com.example.appname.plays.Production
import com.example.appname.plays.RecordingSession.Mode
import com.example.appname.plays.RecordingSession.Phase
import com.example.appname.plays.Relay
import com.example.appname.plays.ScriptLine
import com.example.appname.plays.Take
import com.example.appname.ui.Holder
import com.example.appname.ui.PartFace
import com.example.appname.ui.holderOf
import com.example.appname.ui.partMark
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.theme.boardColor
import com.example.appname.ui.theme.onBoardColor
import java.util.Locale

// The recorder in direction D (ANDROID-DESIGN §4.9b, PLAYS-DESIGN §2.3-2.4, owner ruling 4): fixed
// slots that never move between modes or states: the top, the strip, the mode control, the scene,
// the dock. It is stateless: RecordingScreen feeds it the session's flows and takes its actions.

/** Everything the recorder draws, read from the session by [RecordingScreen] (or built by a render test). */
internal class RecorderUi(
    val script: PlayScript,
    val part: PartID,
    val production: Production,
    val phase: Phase,
    val mode: Mode,
    val runTakes: List<Take>,
    val running: Boolean,
    val index: Int,
    val levels: List<Float> = emptyList(),
    val seconds: Int = 0,
    val announcing: Boolean = false,
    val rate: Float = 1f,
    val refusal: String? = null,
) {
    val lines: List<ScriptLine> = script.lines(part)
    val current: ScriptLine? = lines.getOrNull(index.coerceIn(0, (lines.size - 1).coerceAtLeast(0)))
    val kept: Int = lines.count { production.usableTake(it.id) != null }
    val busy: Boolean = phase is Phase.RoomTone || phase is Phase.Cue || phase is Phase.Listening
    val listening: Boolean = phase is Phase.Listening
    val cuePlaying: Boolean = phase is Phase.Cue
    val inReview: Boolean = phase is Phase.RunReview || (running && phase is Phase.Failed)
    val missing: Int = Relay.missingLines(part, production, script).size
}

internal class RecorderActions(
    val onClose: () -> Unit = {},
    val onMode: (Mode) -> Unit = {},
    val onSelect: (Int) -> Unit = {},
    val onMove: (Int) -> Unit = {},
    val onRecord: () -> Unit = {},
    val onStop: () -> Unit = {},
    val onCancel: () -> Unit = {},
    val onRunFrom: () -> Unit = {},
    val onPause: () -> Unit = {},
    val onKeep: () -> Unit = {},
    val onAgain: (String) -> Unit = {},
    val onWithCue: (Take) -> Unit = {},
    val onPlayTake: (Take) -> Unit = {},
    val onChoose: (Take) -> Unit = {},
    val onCue: (String) -> Unit = {},
    val onRunUp: () -> Unit = {},
    val onHearRead: () -> Unit = {},
    val onRate: (Float) -> Unit = {},
    val onKeepRun: () -> Unit = {},
    val onDiscardRun: () -> Unit = {},
    val onDone: () -> Unit = {},
    val loadWave: suspend (Take) -> FloatArray? = { null },
)

private val ModeLabels = listOf(Mode.Run to "Run through", Mode.Lines to "Line by line", Mode.Step to "Step")

@Composable
internal fun RecorderView(ui: RecorderUi, act: RecorderActions, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        val wide = maxWidth >= 840.dp
        Column(Modifier.fillMaxSize()) {
            RecorderTop(ui, act)
            LineStrip(ui, Modifier.padding(horizontal = Spacing.S4.dp))
            if (wide) {
                Row(Modifier.weight(1f).fillMaxWidth()) {
                    Rail(Modifier.width(200.dp)) { ScenePartners(ui, stacked = true) }
                    Column(Modifier.weight(1f).padding(horizontal = Spacing.S4.dp)) { Body(ui, act, wide = true) }
                    Rail(Modifier.width(200.dp)) { Aids(ui, act, stacked = true) }
                }
            } else {
                Column(Modifier.weight(1f).padding(horizontal = Spacing.S4.dp)) { Body(ui, act, wide = false) }
            }
        }
    }
}

@Composable
private fun Rail(modifier: Modifier, content: @Composable () -> Unit) {
    Column(modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S3.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) { content() }
}

/** The column under the strip: the mode control, the scene, the dock, in fixed slots. */
@Composable
private fun Body(ui: RecorderUi, act: RecorderActions, wide: Boolean) {
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(Modifier.widthIn(max = 720.dp).fillMaxWidth().weight(1f)) {
            ModeControl(ui, act, Modifier.padding(vertical = Spacing.S2.dp))
            if (!wide) ScenePartners(ui, stacked = false)
            if (ui.mode == Mode.Lines && !ui.inReview && ui.phase !is Phase.RoomTone) {
                LinesScene(ui, act, Modifier.weight(1f).fillMaxWidth())
            } else {
                val scroll = rememberScrollState()
                Column(
                    Modifier.weight(1f).fillMaxWidth().verticalScroll(scroll),
                    verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                ) {
                    Scene(ui, act)
                }
            }
            if (!wide && ui.mode != Mode.Run && !ui.inReview) Aids(ui, act, stacked = false)
            Dock(ui, act)
            DoneRow(ui, act)
        }
    }
}

// ---- top, strip, mode ----

@Composable
private fun RecorderTop(ui: RecorderUi, act: RecorderActions) {
    Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = act.onClose) { Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "Close") }
        Column(Modifier.weight(1f)) {
            Text(ui.part.title.uppercase(), style = MaterialTheme.typography.headlineSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(ui.script.title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(
            "${ui.kept} of ${ui.lines.size}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(end = Spacing.S2.dp),
        )
    }
}

/** One cell per line of the part: kept in the part's hue, the current one outlined (red while it records). */
@Composable
private fun LineStrip(ui: RecorderUi, modifier: Modifier = Modifier) {
    val hue = partMark(ui.script, ui.part) ?: MaterialTheme.colorScheme.onSurfaceVariant
    val rest = MaterialTheme.colorScheme.surfaceContainerHigh
    val ink = OnAir.colors.play
    val red = OnAir.colors.record
    val keptDescription = "${ui.kept} of ${ui.lines.size} lines kept"
    Canvas(modifier.fillMaxWidth().height(14.dp).semantics { contentDescription = keptDescription }) {
        val n = ui.lines.size
        if (n == 0) return@Canvas
        val gap = if (n > 120) 0.5.dp.toPx() else 1.dp.toPx()
        val w = (size.width - gap * (n - 1)) / n
        ui.lines.forEachIndexed { i, line ->
            val x = i * (w + gap)
            val current = i == ui.index
            val kept = ui.production.usableTake(line.id) != null
            val fill = when {
                current && ui.listening -> red
                kept -> hue
                else -> rest
            }
            drawRect(fill, Offset(x, 0f), Size(w, size.height))
            if (current && !ui.listening) {
                val stroke = 1.5.dp.toPx()
                drawRect(ink, Offset(x - stroke / 2, stroke / 2), Size(w + stroke, size.height - stroke), style = Stroke(stroke))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ModeControl(ui: RecorderUi, act: RecorderActions, modifier: Modifier = Modifier) {
    val enabled = !ui.busy && !ui.running
    val primary = MaterialTheme.colorScheme.primary
    val colors = SegmentedButtonDefaults.colors(
        activeContainerColor = primary,
        activeContentColor = MaterialTheme.colorScheme.onPrimary,
        activeBorderColor = primary,
        inactiveContainerColor = Color.Transparent,
        inactiveContentColor = primary,
        inactiveBorderColor = MaterialTheme.colorScheme.outline,
        disabledActiveContainerColor = primary,
        disabledActiveContentColor = MaterialTheme.colorScheme.onPrimary,
        disabledActiveBorderColor = primary,
        disabledInactiveContainerColor = Color.Transparent,
        disabledInactiveContentColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
        disabledInactiveBorderColor = MaterialTheme.colorScheme.outline,
    )
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        ModeLabels.forEachIndexed { i, (mode, label) ->
            SegmentedButton(
                selected = ui.mode == mode,
                onClick = { act.onMode(mode) },
                shape = SegmentedButtonDefaults.itemShape(i, ModeLabels.size),
                enabled = enabled,
                colors = colors,
                icon = {},
                label = { Text(label, style = MaterialTheme.typography.titleMedium, maxLines = 1) },
            )
        }
    }
}

// ---- who is in the scene ----

private fun whoLabel(ui: RecorderUi, part: PartID, lineID: String?): String {
    if (part == ui.part) return "You"
    val state = ui.production.state(part)
    return state.performer?.takeIf { it.isNotBlank() && state.status != PartState.Status.Open }
        ?: if (lineID != null && ui.production.usableTake(lineID) != null) "Recorded" else "Device voice"
}

private fun partsNear(ui: RecorderUi): List<Pair<PartID, String?>> {
    val line = ui.current ?: return emptyList()
    val at = ui.script.lines.indexOfFirst { it.id == line.id }
    val cue = Relay.cueLines(line.id, ui.script, runUp = false).lastOrNull()
    val near = listOfNotNull(ui.script.lines.getOrNull(at - 2), cue, line, ui.script.lines.getOrNull(at + 1))
    return near.map { it.part to it.id }.distinctBy { it.first }.sortedByDescending { it.first == ui.part }
}

/** Faces of the parts near this line, each with who holds it: a row on a phone, "In this scene" on a rail. */
@Composable
private fun ScenePartners(ui: RecorderUi, stacked: Boolean) {
    val near = partsNear(ui)
    if (near.isEmpty()) return
    @Composable fun one(part: PartID, lineID: String?) {
        Row(
            Modifier.semantics(mergeDescendants = true) {},
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
        ) {
            PartFace(ui.script, part, holderOf(ui.production, part), recorded = false, size = if (stacked) 40.dp else 24.dp)
            if (stacked) {
                Column {
                    Text(part.title.uppercase(), style = MaterialTheme.typography.headlineSmall)
                    Text(whoLabel(ui, part, lineID), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                Text(part.title.uppercase(), style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.5.sp), maxLines = 1)
                Text(whoLabel(ui, part, lineID), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            }
        }
    }
    if (stacked) {
        Text("IN THIS SCENE", style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 1.sp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        near.forEach { (p, l) -> one(p, l) }
    } else {
        Row(Modifier.fillMaxWidth().padding(bottom = Spacing.S2.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
            near.take(3).forEach { (p, l) -> one(p, l) }
        }
    }
}

// ---- the scene ----

@Composable
private fun Scene(ui: RecorderUi, act: RecorderActions) {
    when {
        ui.phase is Phase.RoomTone -> Unit
        ui.inReview -> RunReview(ui, act)
        else -> Stage(ui, act)
    }
    ui.refusal?.let { ErrorLine(it) }
    (ui.phase as? Phase.Failed)?.let { ErrorLine(it.message) }
}

/** A line of the play in direction D's quiet form: the speaker, who holds the part, the words. */
@Composable
private fun DimLine(ui: RecorderUi, line: ScriptLine, modifier: Modifier = Modifier) {
    Row(modifier.alpha(0.7f).semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        PartFace(ui.script, line.part, holderOf(ui.production, line.part), recorded = false, size = 24.dp)
        Column {
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                Text(line.part.title.uppercase(), style = LabelCaps, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(whoLabel(ui, line.part, line.id), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(lineText(line, MaterialTheme.colorScheme.onSurfaceVariant), style = MaterialTheme.typography.bodyMedium)
        }
    }
}

private val LabelCaps
    @Composable get() = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 1.sp)

/** The cue: face, part, who, and the line; labeled "Device voice" whenever it is the device that reads it, so a stand-in never passes as a person. */
@Composable
private fun CueCard(ui: RecorderUi, cue: ScriptLine, modifier: Modifier = Modifier) {
    val playing = (ui.phase as? Phase.Cue)?.lineID == cue.id
    val mark = partMark(ui.script, cue.part)
    Surface(
        modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        border = if (playing) BorderStroke(2.dp, mark ?: OnAir.colors.link) else null,
    ) {
        Row(Modifier.padding(Spacing.S3.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
            PartFace(ui.script, cue.part, holderOf(ui.production, cue.part), recorded = false, size = 28.dp)
            Column {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    Text(cue.part.title.uppercase(), style = LabelCaps, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(whoLabel(ui, cue.part, cue.id), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(lineText(cue, MaterialTheme.colorScheme.onSurfaceVariant), style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

/** Step and Run through: the line before, the cue, your line, the line after. */
@Composable
private fun Stage(ui: RecorderUi, act: RecorderActions) {
    val line = ui.current ?: run {
        Text("No lines in this part.", style = MaterialTheme.typography.bodyMedium)
        return
    }
    val at = ui.script.lines.indexOfFirst { it.id == line.id }
    val cue = Relay.cueLines(line.id, ui.script, runUp = false).lastOrNull()
    val anchor = cue?.let { c -> ui.script.lines.indexOfFirst { it.id == c.id } } ?: at
    ui.script.lines.getOrNull(anchor - 1)?.let { DimLine(ui, it) }
    cue?.let { CueCard(ui, it) }
    YourLine(ui, line, act, review = ui.phase is Phase.Review && ui.phase.lineID == line.id)
    ui.script.lines.getOrNull(at + 1)?.let { DimLine(ui, it) }
}

/** The edge the box wears: dashed red while armed, solid red while recording, nothing otherwise (the slot is always kept). */
private fun Modifier.edge(color: Color?, dashed: Boolean): Modifier = drawBehind {
    if (color == null) return@drawBehind
    val w = 2.dp.toPx()
    drawRoundRect(
        color,
        topLeft = Offset(w / 2, w / 2),
        size = Size(size.width - w, size.height - w),
        cornerRadius = CornerRadius(16.dp.toPx()),
        style = Stroke(w, pathEffect = if (dashed) PathEffect.dashPathEffect(floatArrayOf(7.dp.toPx(), 4.dp.toPx())) else null),
    )
}

/**
 * Your line box: your part's board with its one on-board color and large type. Armed (the cue plays)
 * it wears a dashed red edge and a "Next" pill; recording, a solid red edge, the red recording pill
 * and the live level; in a Step review, the take with its play control and length and the take count.
 */
@Composable
private fun YourLine(ui: RecorderUi, line: ScriptLine, act: RecorderActions, review: Boolean, modifier: Modifier = Modifier) {
    val dark = OnAir.colors.dark
    val hue = ui.script.partHue(ui.part)
    val board = boardColor(hue, dark)
    val on = onBoardColor(hue, dark)
    val red = OnAir.colors.record
    val armed = ui.phase is Phase.Cue && ui.phase.lineID != line.id
    val recording = ui.listening && (ui.phase as Phase.Listening).lineID == line.id
    val takes = ui.production.takes(line.id)
    val chosen = ui.production.chosenTake(line.id)
    val speaks = recording || ui.announcing
    Box(modifier.fillMaxWidth().edge(if (recording) red else if (armed) red else null, dashed = armed).padding(5.dp)) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(board)
                .padding(Spacing.S3.dp)
                .semantics(mergeDescendants = true) { if (speaks) liveRegion = LiveRegionMode.Polite },
            verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp),
        ) {
            Row(Modifier.heightIn(min = 28.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("${ui.part.title.uppercase()} · YOU", style = LabelCaps, color = on, modifier = Modifier.weight(1f))
                when {
                    recording -> Pill(red, OnAir.colors.onRecord, "Recording ${clock(ui.seconds)}", dot = OnAir.colors.onRecord)
                    armed -> Pill(MaterialTheme.colorScheme.surface, MaterialTheme.colorScheme.onSurface, "Next", dot = red)
                    review && takes.size > 1 -> TakeCount(takes, chosen, act)
                }
            }
            Text(lineText(line, on.copy(alpha = 0.8f)), style = MaterialTheme.typography.displaySmall, color = on)
            when {
                recording -> LevelMeter(ui.levels, red)
                chosen != null && !armed && (review || ui.mode == Mode.Lines) -> TakeStrip(chosen, act)
            }
            if (chosen?.bleed == true && !recording) BleedWarning(on)
        }
    }
}

@Composable
private fun Pill(container: Color, content: Color, text: String, dot: Color) {
    Surface(shape = CircleShape, color = container, contentColor = content) {
        Row(Modifier.padding(horizontal = Spacing.S2.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(dot))
            Text(text, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold), maxLines = 1)
        }
    }
}

/** The takes of this line as numbered chips; the chosen one is filled, and a tap chooses another. */
@Composable
private fun TakeCount(takes: List<Take>, chosen: Take?, act: RecorderActions) {
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        takes.forEachIndexed { i, take ->
            val on = take.id == chosen?.id
            Box(
                Modifier
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(if (on) MaterialTheme.colorScheme.surface else Color.Transparent)
                    .then(if (on) Modifier else Modifier.drawBehind { drawCircle(Color.White.copy(alpha = 0.85f), style = Stroke(1.5.dp.toPx())) })
                    .clickable(role = Role.RadioButton, onClickLabel = "Use take ${i + 1}") { act.onChoose(take) }
                    .semantics { selected = on; contentDescription = "Take ${i + 1}" },
                contentAlignment = Alignment.Center,
            ) {
                Text("${i + 1}", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold), color = if (on) MaterialTheme.colorScheme.onSurface else Color.White)
            }
        }
    }
}

/** The take: a play control, its waveform, its length. */
@Composable
private fun TakeStrip(take: Take, act: RecorderActions) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
        PlayDisc(onClick = { act.onPlayTake(take) }, description = "Play your take", light = true)
        TakeWave(take, act, Color.White.copy(alpha = 0.85f), Modifier.weight(1f))
        Text(seconds(take), style = MaterialTheme.typography.bodySmall, color = Color.White)
    }
}

@Composable
private fun PlayDisc(onClick: () -> Unit, description: String, light: Boolean = false, enabled: Boolean = true) {
    val line = if (light) Color.White else MaterialTheme.colorScheme.onSurface
    IconButton(onClick = onClick, enabled = enabled, modifier = Modifier.size(44.dp)) {
        Box(Modifier.size(36.dp).clip(CircleShape).drawBehind { drawCircle(line, style = Stroke(1.5.dp.toPx())) }, contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.PlayArrow, contentDescription = description, tint = line)
        }
    }
}

@Composable
private fun TakeWave(take: Take, act: RecorderActions, color: Color, modifier: Modifier = Modifier) {
    val peaks by produceState<FloatArray?>(null, take.id) { value = act.loadWave(take) }
    Canvas(modifier.height(28.dp).clearAndSetSemantics {}) {
        val n = 36
        val gap = 2.dp.toPx()
        val w = (size.width - gap * (n - 1)) / n
        val p = peaks
        for (i in 0 until n) {
            val v = if (p == null || p.isEmpty()) 0f else p[i * p.size / n]
            val h = maxOf(2.dp.toPx(), size.height * v)
            drawRect(color, Offset(i * (w + gap), (size.height - h) / 2), Size(w, h))
        }
    }
}

/** The live level while a line is taken: red bars on white, the newest at the right. */
@Composable
private fun LevelMeter(levels: List<Float>, red: Color) {
    Canvas(Modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(8.dp)).background(Color.White).clearAndSetSemantics {}) {
        val n = 48
        val gap = 2.dp.toPx()
        val w = (size.width - 16.dp.toPx() - gap * (n - 1)) / n
        val shown = levels.takeLast(n)
        shown.forEachIndexed { i, v ->
            val h = maxOf(3.dp.toPx(), (size.height - 12.dp.toPx()) * v)
            drawRect(red, Offset(8.dp.toPx() + i * (w + gap), (size.height - h) / 2), Size(w, h))
        }
    }
}

@Composable
private fun BleedWarning(on: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        Icon(Icons.Outlined.WarningAmber, contentDescription = null, tint = on)
        Text("The device voice is in this take. Re-take it with headphones.", style = MaterialTheme.typography.labelMedium, color = on)
    }
}

// ---- Run review ----

@Composable
private fun RunReview(ui: RecorderUi, act: RecorderActions) {
    Text(
        "This run · ${ui.runTakes.size} ${if (ui.runTakes.size == 1) "take" else "takes"}",
        style = MaterialTheme.typography.headlineSmall,
        modifier = Modifier.padding(vertical = Spacing.S2.dp),
    )
    ui.runTakes.forEach { take ->
        val number = ui.lines.indexOfFirst { it.id == take.lineID } + 1
        val line = ui.lines.getOrNull(number - 1) ?: return@forEach
        Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
            Column(Modifier.padding(Spacing.S3.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Line $number", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (take.bleed) {
                        Icon(Icons.Outlined.WarningAmber, contentDescription = null, tint = AppSemantics.colors.warning)
                        Text("The device voice is in this take.", style = MaterialTheme.typography.labelMedium, color = AppSemantics.colors.warning)
                    }
                }
                Text(lineText(line, MaterialTheme.colorScheme.onSurfaceVariant), style = MaterialTheme.typography.bodyMedium)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    PlayDisc(onClick = { act.onWithCue(take) }, description = "Play line $number with its cue", enabled = !ui.busy)
                    TakeWave(take, act, MaterialTheme.colorScheme.onSurface, Modifier.weight(1f))
                    Text(seconds(take), style = MaterialTheme.typography.bodySmall)
                    AgainButton(onClick = { act.onAgain(take.lineID) }, enabled = !ui.busy, description = "Record line $number again")
                }
            }
        }
    }
}

@Composable
private fun AgainButton(
    onClick: () -> Unit,
    enabled: Boolean,
    description: String = "Again",
    modifier: Modifier = Modifier,
    padding: PaddingValues = ButtonDefaults.ButtonWithIconContentPadding,
) {
    val red = OnAir.colors.record
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.semantics { contentDescription = description },
        border = BorderStroke(1.dp, red.copy(alpha = if (enabled) 1f else 0.4f)),
        colors = ButtonDefaults.outlinedButtonColors(contentColor = red),
        contentPadding = padding,
    ) {
        Icon(Icons.Filled.FiberManualRecord, contentDescription = null, modifier = Modifier.size(12.dp))
        Text("Again", Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
    }
}

/** The dock's three buttons share one row at 360 dp, so each gives its icon a little less room. */
private val DockPadding = PaddingValues(horizontal = 10.dp, vertical = 8.dp)

// ---- Line by line ----

/** Every line of the part in order; the list keeps the open line one row from the top. */
@Composable
private fun LinesScene(ui: RecorderUi, act: RecorderActions, modifier: Modifier) {
    val state = rememberLazyListState()
    LaunchedEffect(ui.index) { state.scrollToItem((ui.index - 1).coerceAtLeast(0)) }
    LazyColumn(modifier, state = state) {
        itemsIndexed(ui.lines, key = { _, line -> line.id }) { i, line -> LineRow(ui, act, i, line) }
        item(key = "refusal") {
            ui.refusal?.let { ErrorLine(it) }
            (ui.phase as? Phase.Failed)?.let { ErrorLine(it.message) }
        }
    }
}

@Composable
private fun LineRow(ui: RecorderUi, act: RecorderActions, i: Int, line: ScriptLine) {
    run {
        val open = i == ui.index
        val number = i + 1
        val takes = ui.production.takes(line.id)
        val chosen = ui.production.chosenTake(line.id)
        val state = if (chosen != null) "Take ${takes.indexOfFirst { it.id == chosen.id } + 1}" else "Not yet"
        if (open) {
            OpenLine(ui, line, act)
        } else {
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .clickable(enabled = !ui.busy, role = Role.Button, onClickLabel = "Open line $number") { act.onSelect(i) }
                    .padding(vertical = Spacing.S2.dp)
                    .semantics(mergeDescendants = true) { contentDescription = "Line $number, $state. ${line.spokenText}" },
                horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp),
            ) {
                Text("$number", Modifier.width(24.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(lineText(line, MaterialTheme.colorScheme.onSurfaceVariant), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                    if (chosen != null) Icon(Icons.Filled.Check, contentDescription = null, Modifier.size(16.dp), tint = OnAir.colors.link)
                    Text(state, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            androidx.compose.material3.HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        }
    }
}

/** The line that is open: its cue above, your line box, then Record (red) and Cue (blue), or Stop while the microphone is open. */
@Composable
private fun OpenLine(ui: RecorderUi, line: ScriptLine, act: RecorderActions) {
    val cue = Relay.cueLines(line.id, ui.script, runUp = false).lastOrNull()
    val recording = ui.listening && (ui.phase as Phase.Listening).lineID == line.id
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp), modifier = Modifier.padding(vertical = Spacing.S2.dp)) {
        cue?.let { CueCard(ui, it) }
        YourLine(ui, line, act, review = false)
        if (recording) {
            Button(
                onClick = act.onStop,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = OnAir.colors.record, contentColor = OnAir.colors.onRecord),
            ) {
                Icon(Icons.Filled.Stop, contentDescription = null)
                Text("Stop", Modifier.padding(start = Spacing.S2.dp))
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                Button(
                    onClick = act.onRecord,
                    enabled = !ui.busy,
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = OnAir.colors.record, contentColor = OnAir.colors.onRecord),
                ) {
                    Icon(Icons.Filled.Mic, contentDescription = null)
                    Text("Record", Modifier.padding(start = Spacing.S2.dp))
                }
                OutlinedButton(onClick = { act.onCue(line.id) }, enabled = !ui.busy, modifier = Modifier.weight(1f), colors = wayColors()) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = null)
                    Text("Cue", Modifier.padding(start = Spacing.S2.dp))
                }
            }
        }
    }
}

// ---- aids and dock ----

/** Run-up, Hear it read, the device voice's speed: a row on a phone, "This line" stacked on a rail. */
@Composable
private fun Aids(ui: RecorderUi, act: RecorderActions, stacked: Boolean) {
    if (ui.mode == Mode.Run && !stacked) return
    val enabled = !ui.busy && !ui.running && !ui.inReview
    var menu by remember { mutableStateOf(false) }
    val speed: @Composable (Modifier) -> Unit = { m ->
        Box(m) {
            OutlinedButton(onClick = { menu = true }, enabled = enabled, modifier = Modifier.fillMaxWidth(), colors = wayColors(), contentPadding = ButtonDefaults.ButtonWithIconContentPadding) {
                Icon(Icons.Filled.Speed, contentDescription = null)
                Text(rateLabel(ui.rate), Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                listOf("Slower" to 0.8f, "Normal" to 1f, "Faster" to 1.2f).forEach { (label, value) ->
                    DropdownMenuItem(
                        text = { Text(label) },
                        leadingIcon = { if (ui.rate == value) Icon(Icons.Filled.Check, contentDescription = null) },
                        onClick = { menu = false; act.onRate(value) },
                    )
                }
            }
        }
    }
    val runUp: @Composable (Modifier) -> Unit = { m ->
        OutlinedButton(onClick = act.onRunUp, enabled = enabled, modifier = m, colors = wayColors(), contentPadding = ButtonDefaults.ButtonWithIconContentPadding) {
            Icon(Icons.Outlined.Replay, contentDescription = null)
            Text("Run-up", Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
        }
    }
    val hear: @Composable (Modifier) -> Unit = { m ->
        OutlinedButton(onClick = act.onHearRead, enabled = enabled, modifier = m, colors = wayColors(), contentPadding = ButtonDefaults.ButtonWithIconContentPadding) {
            Icon(Icons.Filled.Headphones, contentDescription = null)
            Text("Hear it read", Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
        }
    }
    if (stacked) {
        Text("THIS LINE", style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 1.sp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        runUp(Modifier.fillMaxWidth())
        hear(Modifier.fillMaxWidth())
        speed(Modifier.fillMaxWidth())
    } else {
        Row(Modifier.fillMaxWidth().padding(vertical = Spacing.S2.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp, Alignment.CenterHorizontally)) {
            runUp(Modifier)
            hear(Modifier)
            speed(Modifier.width(88.dp))
        }
    }
}

private fun rateLabel(rate: Float) = when {
    rate < 1f -> "0.8×"
    rate > 1f -> "1.2×"
    else -> "1×"
}

@Composable
private fun Dock(ui: RecorderUi, act: RecorderActions) {
    if (ui.mode == Mode.Lines && !ui.inReview) return
    val line = ui.current
    Column(Modifier.fillMaxWidth().heightIn(min = 112.dp).padding(vertical = Spacing.S2.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        when {
            ui.phase is Phase.RoomTone || line == null -> Unit
            ui.inReview -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                OutlinedButton(onClick = act.onDiscardRun, modifier = Modifier.weight(1f), colors = wayColors()) { Text("Discard the run", maxLines = 1) }
                Button(onClick = act.onKeepRun, modifier = Modifier.weight(1f), colors = ink()) {
                    Icon(Icons.Filled.Check, contentDescription = null)
                    Text("Keep ${ui.runTakes.size} ${if (ui.runTakes.size == 1) "take" else "takes"}", Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
                }
            }
            ui.mode == Mode.Lines -> Unit
            ui.mode == Mode.Run && ui.running -> RunTransport(ui, act)
            ui.mode == Mode.Step && ui.phase is Phase.Review && ui.phase.lineID == line.id -> {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    AgainButton(onClick = { act.onAgain(line.id) }, enabled = !ui.busy, modifier = Modifier.weight(1f), padding = DockPadding)
                    OutlinedButton(
                        onClick = { ui.production.chosenTake(line.id)?.let(act.onWithCue) },
                        enabled = !ui.busy,
                        modifier = Modifier.weight(1f),
                        colors = wayColors(),
                        contentPadding = DockPadding,
                    ) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null)
                        Text("With cue", Modifier.padding(start = Spacing.S1.dp), maxLines = 1)
                    }
                    Button(onClick = act.onKeep, enabled = !ui.busy, modifier = Modifier.weight(1f), colors = ink(), contentPadding = DockPadding) {
                        Icon(Icons.Filled.Check, contentDescription = null)
                        Text("Keep", Modifier.padding(start = Spacing.S1.dp), maxLines = 1)
                    }
                }
            }
            else -> Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { act.onMove(-1) }, enabled = ui.index > 0 && !ui.busy) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous line")
                }
                Spacer(Modifier.weight(1f))
                val cueing = ui.cuePlaying
                val label = when {
                    ui.listening -> "Stop"
                    cueing -> "Cancel"
                    ui.mode == Mode.Run -> "From here"
                    else -> "Record"
                }
                RoundControl(
                    label = label,
                    container = OnAir.colors.record,
                    content = OnAir.colors.onRecord,
                    icon = if (ui.listening) Icons.Filled.Stop else if (cueing) Icons.Filled.Close else Icons.Filled.Mic,
                    onClick = {
                        when {
                            ui.listening -> act.onStop()
                            cueing -> act.onCancel()
                            ui.mode == Mode.Run -> act.onRunFrom()
                            else -> act.onRecord()
                        }
                    },
                )
                Spacer(Modifier.weight(1f))
                IconButton(onClick = { act.onMove(1) }, enabled = ui.index + 1 < ui.lines.size && !ui.busy) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next line")
                }
            }
        }
    }
}

/** Run through while it plays: ink Pause (red Stop while the microphone is open; both pause), and how many lines are taken. */
@Composable
private fun RunTransport(ui: RecorderUi, act: RecorderActions) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text("${ui.runTakes.size} taken", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (ui.listening) {
            RoundControl("Stop", OnAir.colors.record, OnAir.colors.onRecord, Icons.Filled.Stop, act.onPause)
        } else {
            RoundControl("Pause", OnAir.colors.play, OnAir.colors.onPlay, Icons.Filled.Pause, act.onPause)
        }
        Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun RoundControl(label: String, container: Color, content: Color, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier
                .size(80.dp)
                .drawBehind { drawCircle(container.copy(alpha = 0.3f), style = Stroke(3.dp.toPx())) }
                .padding(7.dp)
                .clip(CircleShape)
                .background(container)
                .clickable(role = Role.Button, onClickLabel = label, onClick = onClick)
                .semantics { contentDescription = label },
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = content, modifier = Modifier.size(32.dp))
        }
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ink() = ButtonDefaults.buttonColors(containerColor = OnAir.colors.play, contentColor = OnAir.colors.onPlay)

/** "Done with this part" stays where it was: enabled when every line has a take. */
@Composable
private fun DoneRow(ui: RecorderUi, act: RecorderActions) {
    if (ui.phase is Phase.RoomTone) return
    Column(Modifier.fillMaxWidth().padding(bottom = Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        OutlinedButton(
            onClick = act.onDone,
            enabled = !ui.busy && !ui.running && !ui.inReview && !(ui.part.isSpeaking && ui.missing > 0),
            modifier = Modifier.fillMaxWidth(),
        ) { Text("Done with this part") }
        if (ui.part.isSpeaking && ui.missing > 0) {
            Text(
                if (ui.missing == 1) "1 line to go" else "${ui.missing} lines to go",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ---- text ----

/** A script line with its printed directions kept apart from the words said (§3, Decision 059); nothing is rewritten. */
@Composable
internal fun lineText(line: ScriptLine, muted: Color) = buildAnnotatedString {
    if (line.kind == ScriptLine.Kind.Speech) {
        line.parts.orEmpty().forEachIndexed { i, piece ->
            if (i > 0) append(" ")
            if (piece is LinePart.Say) {
                append(piece.text)
            } else {
                pushStyle(SpanStyle(fontStyle = FontStyle.Italic, color = muted))
                append("(${piece.text})")
                pop()
            }
        }
    } else {
        pushStyle(SpanStyle(fontStyle = FontStyle.Italic, color = muted))
        append(line.source.orEmpty())
        pop()
    }
}

private fun clock(seconds: Int) = String.format(Locale.US, "%d:%02d", seconds / 60, seconds % 60)

private fun seconds(take: Take) = String.format(Locale.US, "%.1f s", take.seconds)

/** The shape of a take, [bins] peaks scaled to the loudest, for its waveform. */
internal fun takePeaks(samples: FloatArray, bins: Int = 72): FloatArray {
    if (samples.isEmpty()) return FloatArray(0)
    val out = FloatArray(bins) { b ->
        val from = b * samples.size / bins
        val to = maxOf(from + 1, (b + 1) * samples.size / bins).coerceAtMost(samples.size)
        var peak = 0f
        for (i in from until to) peak = maxOf(peak, kotlin.math.abs(samples[i]))
        peak
    }
    val top = out.max().coerceAtLeast(1e-6f)
    for (i in out.indices) out[i] = out[i] / top
    return out
}
