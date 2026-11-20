package com.example.appname.ui

import android.content.Context
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Canvas as ComposeCanvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.createFontFamilyResolver
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import com.example.appname.data.LabelItem
import com.example.appname.data.LabelSpec
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.BrandBackgroundDark
import com.example.appname.ui.theme.BrandBackgroundLight
import com.example.appname.ui.theme.BrandSurfaceAltDark
import com.example.appname.ui.theme.BrandSurfaceAltLight
import com.example.appname.ui.theme.BrandTextDark
import com.example.appname.ui.theme.BrandTextLight
import com.example.appname.ui.theme.BrandTextMutedDark
import com.example.appname.ui.theme.BrandTextMutedLight
import com.example.appname.ui.theme.DisplayFontFamily
import com.example.appname.ui.theme.PrintGroundDark
import com.example.appname.ui.theme.PrintGroundLight
import com.example.appname.ui.theme.boardColor
import com.example.appname.ui.theme.genreColor
import com.example.appname.ui.theme.onBoardColor
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

// The label drawn (Decision 081, ANDROID-DESIGN "The label is the default art"): LabelSpec decides, this
// paints, with a Compose DrawScope in a window of any side (crisp from a 40 dp tile to the Google TV hero)
// and, through CanvasDrawScope, into an ImageBitmap for the media session's artwork. Colors are the token
// references the spec names, so light and dark follow the theme.

/** A label token reference (board.mystery, brand.text, print.ground) as this mode's color. */
class LabelPalette(val dark: Boolean) {
    fun color(ref: String): Color {
        val (group, name) = ref.split(".", limit = 2).let { it[0] to it.getOrElse(1) { "" } }
        return when (group) {
            "board" -> boardColor(name, dark)
            "onBoard" -> onBoardColor(name, dark)
            "genre" -> genreColor(name, dark) ?: pick(BrandTextMutedLight, BrandTextMutedDark)
            "print" -> pick(PrintGroundLight, PrintGroundDark)
            else -> when (name) {
                "surfaceAlt" -> pick(BrandSurfaceAltLight, BrandSurfaceAltDark)
                "textMuted" -> pick(BrandTextMutedLight, BrandTextMutedDark)
                "background" -> pick(BrandBackgroundLight, BrandBackgroundDark)
                else -> pick(BrandTextLight, BrandTextDark)
            }
        }
    }

    private fun pick(light: Color, dark: Color) = if (this.dark) dark else light
}

private fun point(r: Double, deg: Double, k: Float): Offset {
    val a = deg * PI / 180
    return Offset(((50 + r * cos(a)) * k).toFloat(), ((50 - r * sin(a)) * k).toFloat())
}

private fun DrawScope.ring(color: Color, r: Double, from: Double, to: Double, width: Double, k: Float) {
    val rad = (r * k).toFloat()
    if (LabelSpec.isFull(from, to)) {
        drawCircle(color, rad, Offset(50 * k, 50 * k), style = Stroke((width * k).toFloat()))
    } else {
        drawArc(color, (-from).toFloat(), (from - to).toFloat(), false, Offset(50 * k - rad, 50 * k - rad), Size(2 * rad, 2 * rad),
            style = Stroke((width * k).toFloat()))
    }
}

private fun DrawScope.dot(color: Color, r: Double, deg: Double, radius: Double, k: Float) =
    drawCircle(color, (radius * k).toFloat(), point(r, deg, k))

private fun DrawScope.line(color: Color, a: Offset, b: Offset, width: Double, k: Float, cap: StrokeCap = StrokeCap.Butt) =
    drawLine(color, a, b, (width * k).toFloat(), cap)

/** The spec painted in a square of the scope's smaller side; [overlay] leaves a play's page showing under its rules. */
fun DrawScope.drawLabel(s: LabelSpec, measurer: TextMeasurer, palette: LabelPalette, overlay: Boolean = false) {
    val side = minOf(size.width, size.height)
    val k = side / s.viewBox.toFloat()
    val on = palette.color(s.on)
    fun withAlpha(c: Color, a: Double) = c.copy(alpha = c.alpha * a.toFloat())
    if (!overlay) drawRect(palette.color(s.ground), Offset.Zero, Size(side, side))
    s.cast?.bars?.forEach { b ->
        val h = (b.h * k).toFloat()
        drawRoundRect(on, Offset((b.x * k).toFloat(), (b.y * k).toFloat()), Size((b.w * k).toFloat(), h),
            androidx.compose.ui.geometry.CornerRadius(h / 2))
    }
    s.disc?.let { drawCircle(withAlpha(on, it.opacity), (it.r * k).toFloat(), Offset(50 * k, 50 * k), style = Fill) }
    s.grooves?.let { g -> g.radii.forEach { r -> ring(withAlpha(on, g.opacity), r, 0.0, -360.0, g.width, k) } }
    s.ticks?.let { t -> t.deg.forEach { d -> line(withAlpha(on, t.opacity), point(t.r0, d, k), point(t.r1, d, k), t.width, k) } }
    s.ring?.let { ring(withAlpha(on, it.opacity), it.r, 0.0, -360.0, it.width, k) }
    s.arc?.let { a ->
        ring(on, a.r, a.from, if (LabelSpec.isFull(a.from, a.to)) a.from - 360 else a.to, a.width, k)
        if (a.capFrom == "round") dot(on, a.r, a.from, a.width / 2, k)
        if (a.capTo == "round") dot(on, a.r, a.to, a.width / 2, k)
    }
    s.parts?.let { p ->
        ring(palette.color(p.backing.color), p.r, 0.0, -360.0, p.backing.width, k)
        p.segments.forEach { g -> ring(palette.color(g.color), p.r, g.from, if (LabelSpec.isFull(g.from, g.to)) g.from - 360 else g.to, p.width, k) }
    }
    s.evening?.let { e -> line(on, point(e.r0, e.deg, k), point(e.r1, e.deg, k), e.width, k, StrokeCap.Round) }
    s.label?.let { drawCircle(on, (it.r * k).toFloat(), Offset(50 * k, 50 * k)) }
    for (t in s.text) {
        val ink = palette.color(if (t.fill == "ground") s.ground else s.on)
        val layout = measurer.measure(t.s, labelStyle(t.face, (t.size * k).toFloat(), ink), softWrap = false, maxLines = 1)
        val x = (t.x * k).toFloat() - if (t.anchor == "end") layout.size.width.toFloat() else layout.size.width / 2f
        drawText(layout, topLeft = Offset(x, (t.y * k).toFloat() - layout.firstBaseline))
    }
    s.rim?.let { rim ->
        val px = (rim.size * k).toFloat()
        val track = rim.tracking * px
        val rad = rim.r * k
        val ink = withAlpha(on, rim.opacity)
        val glyphs = rim.text.map { ch -> measurer.measure(ch.toString(), labelStyle("body", px, ink), softWrap = false, maxLines = 1) }
        val advances = glyphs.map { it.size.width + track }
        val total = advances.sum() - track
        var deg = rim.centerDeg + (total / rad) * 180 / PI / 2
        glyphs.forEachIndexed { i, layout ->
            val mid = deg - ((advances[i] - track) / 2 / rad) * 180 / PI
            val p = point(rim.r, mid, k)
            rotate((90 - mid).toFloat(), pivot = p) {
                drawText(layout, topLeft = Offset(p.x - layout.size.width / 2f, p.y - layout.firstBaseline))
            }
            deg -= (advances[i] / rad) * 180 / PI
        }
    }
    s.rules?.let { r ->
        drawRect(palette.color(s.ground), Offset(0f, (r.foot * k).toFloat()), Size(side, side - (r.foot * k).toFloat()))
        for (i in 0 until r.count) {
            val x = r.x0 + i * (r.len + r.gap)
            drawRect(withAlpha(on, r.opacity), Offset((x * k).toFloat(), ((r.y - r.width / 2) * k).toFloat()), Size((r.len * k).toFloat(), (r.width * k).toFloat()))
        }
    }
}

private fun DrawScope.labelStyle(face: String, px: Float, color: Color) = TextStyle(
    fontFamily = if (face == "display") DisplayFontFamily else FontFamily.Default,
    fontWeight = FontWeight.Bold,
    fontSize = px.toSp(),
    color = color,
)

/** The label in a square window: the item's own art where it has no picture. Hidden from accessibility. */
@Composable
fun LabelArt(item: LabelItem, modifier: Modifier = Modifier) {
    val dark = OnAir.colors.dark
    val measurer = rememberTextMeasurer()
    BoxWithConstraints(modifier.aspectRatio(1f).clearAndSetSemantics {}) {
        val spec = remember(item, maxWidth) { LabelSpec.make(item, maxWidth.value.toDouble()) }
        val palette = remember(dark) { LabelPalette(dark) }
        Canvas(Modifier.matchParentSize()) { drawLabel(spec, measurer, palette) }
    }
}

/** The label as a square bitmap [px] on a side, for the media session's artwork; drawn in the dark palette. */
fun labelBitmap(context: Context, item: LabelItem, px: Int = 512, dark: Boolean = true): ImageBitmap {
    val density = Density(1f)
    val measurer = TextMeasurer(createFontFamilyResolver(context), density, LayoutDirection.Ltr)
    val bitmap = ImageBitmap(px, px)
    CanvasDrawScope().draw(density, LayoutDirection.Ltr, ComposeCanvas(bitmap), Size(px.toFloat(), px.toFloat())) {
        drawLabel(LabelSpec.make(item, px.toDouble()), measurer, LabelPalette(dark))
    }
    return bitmap
}
