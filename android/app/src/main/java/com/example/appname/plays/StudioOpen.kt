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
        val pick = StudioCore.productionFor(store.all(), { store.share(it) != null }, script, part)
        if (StudioCore.asksAccount(pick, store.all(), plays.signedIn())) {
            plays.accountAsk.value = SECOND_PRODUCTION
            return null
        }
        return when (pick) {
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

    /** Record this: the play's empty production while it lasts, else a new one; null when a second production needs an account. */
    suspend fun recordThis(plays: PlaysLibrary, script: PlayScript): String? {
        val store = plays.store
        StudioCore.reusable(store.all(), { store.share(it) != null }, script.id)?.let { return it }
        if (Production.secondNeedsAccount(store.all(), plays.signedIn())) {
            plays.accountAsk.value = SECOND_PRODUCTION
            return null
        }
        return plays.create(script).id
    }

    /** A scene card's door: this scene's production, made on the first tap; null when a second production needs an account or the scene cannot be cut. */
    suspend fun recordScene(plays: PlaysLibrary, script: PlayScript, range: ProductionRange, heading: String?): String? {
        val store = plays.store
        if (script.rangeSpan(range) == null) return null
        StudioCore.sceneProduction(store.all(), { store.share(it) != null }, script.id, range)?.let { return it }
        if (Production.secondNeedsAccount(store.all(), plays.signedIn())) {
            plays.accountAsk.value = SECOND_PRODUCTION
            return null
        }
        return plays.create(script, range, heading).id
    }

    const val SECOND_PRODUCTION = "A second production needs an account."
}
