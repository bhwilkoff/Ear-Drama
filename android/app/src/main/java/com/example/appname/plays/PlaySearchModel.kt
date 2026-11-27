package com.example.appname.plays

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * The play search's state (B31 §3.3, ANDROID-DESIGN §4.5), drawn by `PlaySearchSections`; the rules are [FindCore]'s. Title and
 * author hits, characters, and the lines found in the scripts the line shards name, read a batch at a time within about 1.6 MB a
 * press ([LINE_BUDGET], the web's).
 *
 * [run] is called once per query from the page that shows the sections, keyed on the query: a section that composes never
 * starts it again (the Apple search spun forever when each section's own task restarted it).
 */
class PlaySearchModel(private val feed: PlayLibraryFeed) {
    enum class Phase { Idle, Loading, Done }

    data class State(
        val query: String = "",
        val phase: Phase = Phase.Idle,
        val titled: List<PlayRow> = emptyList(),
        val characters: List<FindCore.CharacterHit> = emptyList(),
        val hits: List<FindCore.LineHit> = emptyList(),
        val reading: Boolean = false,
        val from: Int = 0,
        val total: Int = 0,
    ) {
        val shown: List<FindCore.LineHit> get() = FindCore.shownHits(hits)
        val left: Int get() = total - from
        val foundAny: Boolean get() = titled.isNotEmpty() || characters.isNotEmpty() || shown.isNotEmpty()
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state

    private var ordered: List<FindCore.Ordered> = emptyList()
    private var prefix: Set<String> = emptySet()

    suspend fun run(q: String, rows: List<PlayRow>) {
        _state.value = State(query = q, phase = Phase.Loading)
        ordered = emptyList()
        prefix = emptySet()
        feed.forgetShards()
        val titled = FindCore.titleHits(rows, q)
        _state.value = _state.value.copy(titled = titled)
        val (names, lined, said) = coroutineScope {
            val n = async { orNull { feed.characterNames() } }
            val l = async { orNull { FindCore.lineCandidates(q) { feed.shard("lines", it) } } }
            val ln = l.await()
            // A library built before the line shards: the plays that say every word (search/said).
            val s = if (ln == null) async { orNull { FindCore.saidPlays(q) { feed.shard("said", it) } } } else null
            Triple(n.await(), ln, s?.await())
        }
        var cands = lined?.cands.orEmpty()
        if (lined == null) cands = (said?.let { if (it.exact.isEmpty()) it.all else it.exact } ?: emptyList()).map { FindCore.Candidate(it, null) }
        prefix = lined?.prefix.orEmpty()
        ordered = FindCore.orderCandidates(cands, rows, q)
        _state.value = _state.value.copy(
            characters = FindCore.characterHits(rows, names, q), phase = Phase.Done, total = ordered.size,
        )
        if (ordered.isNotEmpty()) more()
    }

    /** Reads the next batch of scripts once, not keeping them, and keeps their best lines. */
    suspend fun more() {
        val now = _state.value
        if (now.reading || now.from >= ordered.size) return
        _state.value = now.copy(reading = true)
        val q = now.query
        val to = FindCore.nextBatch(ordered, now.from, LINE_BUDGET)
        val batch = ordered.subList(now.from, to)
        val kept = prefix
        val got = try {
            coroutineScope {
                batch.map { c ->
                    async(Dispatchers.Default) {
                        val script = orNull { feed.scriptOnce(c.row) } ?: return@async null
                        FindCore.lineHit(script, c.row, q, c.lines, kept)
                    }
                }.awaitAll().filterNotNull()
            }
        } catch (e: CancellationException) {
            _state.value = _state.value.copy(reading = false)
            throw e
        }
        val cur = _state.value
        if (cur.query != q) return
        _state.value = cur.copy(reading = false, from = to, hits = cur.hits + got)
    }

    private suspend fun <T> orNull(block: suspend () -> T?): T? = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        null
    }

    companion object {
        /** About how many bytes of scripts one press of More lines reads (the web's LINE_BUDGET). */
        const val LINE_BUDGET = 1_600_000
    }
}
