package com.example.appname.plays

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * A TV's side of pairing (PLAYS-DESIGN §12.10 item 9, ANDROID-DESIGN §4.19): asks the Worker for a code, shows it, and asks
 * again every 2 seconds whether a leader has attached it. A code lasts 10 minutes and is used once: an expired or unknown one
 * is replaced by a new one without a word. Paired, the answer is the room as this device's screen. It records nothing.
 */
class ReadPairing(private val wire: ReadWire, private val scope: CoroutineScope, private val pollMs: Long = POLL_MS) {
    data class State(
        /** The code on screen, as the Worker made it. */
        val code: String? = null,
        /** A refusal worth a line (the Worker could not be reached); an expired code is never one. */
        val refusal: String? = null,
        /** Set once a leader attached this TV: join the room with this. */
        val paired: ReadJoined? = null,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state
    private var job: Job? = null
    private var pair: PairStart? = null

    fun start() {
        if (job != null) return
        job = scope.launch {
            while (_state.value.paired == null) {
                step()
                if (_state.value.paired != null) break
                delay(pollMs)
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    private suspend fun step() {
        val current = pair
        try {
            if (current == null) {
                val fresh = wire.pairStart()
                pair = fresh
                _state.update { it.copy(code = fresh.code, refusal = null) }
            } else {
                val joined = wire.pairPoll(current.code, current.key)
                if (joined != null) _state.update { it.copy(paired = joined, refusal = null) }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: ReadFailure) {
            if (e.code == "pair_expired" || e.code == "no_such_pair") pair = null
            else _state.update { it.copy(refusal = ReadCore.refusal(e.code)) }
        } catch (_: Exception) {
            _state.update { it.copy(refusal = ReadCore.refusal("error")) }
        }
    }

    companion object {
        const val POLL_MS = 2000L

        /** The code large, split 3 + 3 ("ABC 123"). */
        fun split(code: String) = if (code.length == ReadCore.CODE_LENGTH) code.take(3) + " " + code.drop(3) else code
    }
}
