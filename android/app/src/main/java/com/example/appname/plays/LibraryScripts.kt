package com.example.appname.plays

import kotlinx.coroutines.CancellationException

/** Where a screen's play is: being asked of the library, here, or why it did not come. */
sealed interface ScriptLoad {
    data object Loading : ScriptLoad
    data class Ready(val script: PlayScript) : ScriptLoad
    data class Failed(val line: String) : ScriptLoad
}

/** The twin of apple/Core/Plays/LibraryScripts.swift: a play for a screen that holds only its id (and the revision it was cast from). */
object LibraryScripts {
    /** The play from the published library, else the bundle; a failure carries the words to show. */
    suspend fun resolve(feed: PlayLibraryFeed, id: String, revision: String?): ScriptLoad = try {
        feed.script(id, revision)?.let { ScriptLoad.Ready(it) }
            ?: ScriptLoad.Failed(ReadCore.refusal(if (revision == null) "not_castable" else "revision_mismatch"))
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        ScriptLoad.Failed(PlaysShare.line(e))
    }
}
