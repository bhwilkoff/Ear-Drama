package com.example.appname.plays

import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

/** The device voice as the table read needs it: whether a part is read at all, and reading one line live. */
interface LineSpeaker {
    fun reads(part: PartID): Boolean

    /** Reads [text] in [part]'s cast voice; true when it was read, false when no voice can read it. */
    suspend fun speak(text: String, part: PartID): Boolean

    fun cancel()
}

/**
 * The reader's Hear the cast (PLAYS-DESIGN §2.7, §2.8): from a line to the end of the play, each
 * part in its cast voice, [onLine] following each line as it is read. Text only: it keeps
 * nothing, touches no file and no network, and nothing it reads is stored (§5). A direction or sound line is
 * read only when its part has been given a voice.
 */
class TableRead(
    private val script: PlayScript,
    private val speaker: LineSpeaker,
    private val onLine: (ScriptLine?) -> Unit = {},
) {
    suspend fun play(from: Int = 0) {
        try {
            for (i in from.coerceAtLeast(0) until script.lines.size) {
                coroutineContext.ensureActive()
                val line = script.lines[i]
                if (line.kind != ScriptLine.Kind.Speech && !speaker.reads(line.part)) continue
                if (line.spokenText.isBlank()) continue
                onLine(line)
                speaker.speak(line.spokenText, line.part)
            }
        } finally {
            speaker.cancel()
            onLine(null)
        }
    }
}
