package com.example.appname.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.appname.data.Artwork
import com.example.appname.data.Credit
import com.example.appname.data.WindowFill
import com.example.appname.data.windowFill
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing

/** What an [ActionRow] tells its buttons about the room they have. */
data class RowFit(val folded: Boolean, val tight: Boolean)

/**
 * A page's one button row (WEB-DESIGN §6.4d, ANDROID-DESIGN R11d): a Row, never a FlowRow, so a
 * button never drops to a second line apart from its neighbors. Under [foldBelow] the secondary
 * buttons fold to their icons; under 360 dp the primary label shortens too.
 */
@Composable
fun ActionRow(
    modifier: Modifier = Modifier,
    foldBelow: Dp = 480.dp,
    content: @Composable RowScope.(RowFit) -> Unit,
) {
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val fit = RowFit(folded = maxWidth < foldBelow, tight = maxWidth < 360.dp)
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) { content(fit) }
    }
}

/** A secondary button whose label gives way to its icon on a narrow row; [description] is always its accessible name. */
@Composable
fun FoldButton(
    icon: ImageVector,
    label: String,
    folded: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    description: String = label,
) {
    if (folded) {
        OutlinedIconButton(onClick, modifier.size(48.dp).tvFocusMark(), enabled = enabled, border = ButtonDefaults.outlinedButtonBorder(enabled)) {
            Icon(icon, contentDescription = description)
        }
    } else {
        OutlinedButton(
            onClick,
            modifier.tvFocusMark().semantics { contentDescription = description },
            enabled = enabled,
            contentPadding = ButtonDefaults.ButtonWithIconContentPadding,
        ) {
            Icon(icon, contentDescription = null)
            Text(label, Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
        }
    }
}

/** The credit a license asks for, linked to the file page, for each picture the window shows. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PictureCredit(arts: List<Artwork?>, slot: Dp, modifier: Modifier = Modifier) {
    val owed = arts.filterNotNull()
        .filter { it.credit != null && windowFill(it, slot.value) !is WindowFill.Block }
        .distinctBy { it.evidence ?: it.credit }
    if (owed.isEmpty()) return
    FlowRow(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        Text("Picture: ", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        owed.forEachIndexed { i, a ->
            if (i > 0) Text(" · ", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            ArtCredit(a.credit ?: "", a.evidence)
        }
    }
}

/** On the air: each person of the cast in a round 72 dp window over the name and the character; a tap opens the person. */
@Composable
fun OnTheAir(air: List<Credit>, genre: String?, onOpenPerson: (String) -> Unit, modifier: Modifier = Modifier) {
    if (air.isEmpty()) return
    Column(modifier) {
        SectionHeader("On the air")
        LazyRow(
            contentPadding = PaddingValues(horizontal = Spacing.S4.dp),
            horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
        ) {
            items(air, key = { "air:" + it.personId.ifEmpty { it.name } }) { c ->
                Column(
                    Modifier
                        .width(88.dp)
                        .tvFocusMark()
                        .clip(MaterialTheme.shapes.medium)
                        .clickable(onClickLabel = "Open ${c.name}") { onOpenPerson(c.personId) }
                        .padding(vertical = Spacing.S1.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp),
                ) {
                    PictureWindow(c.art, c.name, genre, Modifier.size(72.dp).clip(CircleShape))
                    Text(
                        c.name,
                        style = MaterialTheme.typography.labelMedium,
                        textAlign = TextAlign.Center,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    c.character?.let {
                        Text(
                            "as $it",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }
    }
}

/** The credits grouped by role, cast first, each role in the order the catalog lists it. */
fun creditGroups(credits: List<Credit>): List<Pair<String, List<Credit>>> =
    credits.groupBy { it.role ?: "cast" }.toList().sortedByDescending { it.first == "cast" }

/** "Cast and credits" folded: the count on the header, the full grouped list when opened. */
@Composable
fun CastAndCredits(credits: List<Credit>, onOpenPerson: (String) -> Unit, modifier: Modifier = Modifier) {
    if (credits.isEmpty()) return
    var open by rememberSaveable { mutableStateOf(false) }
    Column(modifier) {
        Row(
            Modifier
                .fillMaxWidth()
                .tvFocusMark()
                .clickable(role = Role.Button, onClickLabel = if (open) "Fold" else "Unfold") { open = !open }
                .padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Cast and credits", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
            Text(
                credits.size.toString(),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(end = Spacing.S2.dp),
            )
            Icon(if (open) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, contentDescription = null)
        }
        if (open) {
            creditGroups(credits).forEach { (role, group) ->
                Text(
                    role.replaceFirstChar { it.uppercase() },
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp),
                )
                group.forEach { c ->
                    Text(
                        if (c.character != null) "${c.name} as ${c.character}" else c.name,
                        style = MaterialTheme.typography.bodyMedium,
                        color = OnAir.colors.link,
                        modifier = Modifier
                            .fillMaxWidth()
                            .tvFocusMark()
                            .clickable(onClickLabel = "Open ${c.name}") { onOpenPerson(c.personId) }
                            .padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                    )
                }
            }
        }
    }
}
