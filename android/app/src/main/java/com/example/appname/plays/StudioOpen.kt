package com.example.appname.plays

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Where the studio records (PLAYS-DESIGN §2.9 rule 1's one seam): the reader's Record continues the part where it records
 * on this device, else takes it where it is open and no other part records, else makes a production and takes the part.
 */
object StudioOpen {
    /** The production the studio records into, or null when the part could not be taken (another part records, the part is not open). */
    suspend fun resolve(plays: PlaysLibrary, script: PlayScript, part: PartID): String? {
        val store = plays.store
        return when (val pick = StudioCore.productionFor(store.all(), { store.share(it) != null }, script, part)) {
            is StudioCore.Pick.Resume -> pick.id
            is StudioCore.Pick.Take -> {
                val production = store.production(pick.id) ?: return null
                val cast = plays.castScript(pick.id) ?: return null
                withContext(Dispatchers.IO) { runCatching { store.save(Relay.take(part, null, production, cast)) } }
                    .getOrNull() ?: return null
                pick.id
            }
            StudioCore.Pick.Make -> {
                val made = plays.create(script)
                withContext(Dispatchers.IO) { runCatching { store.save(Relay.take(part, null, made, script)) } }
                    .getOrNull() ?: return null
                made.id
            }
        }
    }
}
