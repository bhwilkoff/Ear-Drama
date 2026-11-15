package com.example.appname.kokoro

import android.content.Context
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import com.google.android.play.core.splitcompat.SplitCompat
import com.google.android.play.core.splitinstall.SplitInstallException
import com.google.android.play.core.splitinstall.SplitInstallManager
import com.google.android.play.core.splitinstall.SplitInstallManagerFactory
import com.google.android.play.core.splitinstall.SplitInstallRequest
import com.google.android.play.core.splitinstall.SplitInstallSessionState
import com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
import com.google.android.play.core.splitinstall.model.SplitInstallSessionStatus
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * The on-demand `:kokoro` module (ONNX Runtime and the renderer; owner 2026-11-15), installed through Play Feature
 * Delivery when the person taps Download voices, before the model files. [state] is what the picker shows. Delete
 * asks Play to remove it again, so the app returns to its base size.
 */
class KokoroModule(private val context: Context) {
    sealed interface State {
        data object Absent : State
        data object Pending : State
        data class Downloading(val done: Long, val total: Long) : State
        data object Installing : State
        /** Play asks the person first (a large download, or on a metered network): the picker shows Continue. */
        data class NeedsConfirmation(val session: SplitInstallSessionState) : State
        data class Failed(val code: Int) : State
        data object Installed : State
    }

    private val manager: SplitInstallManager by lazy { SplitInstallManagerFactory.create(context) }
    private val _state = MutableStateFlow<State>(State.Absent)
    val state: StateFlow<State> = _state

    /** The module's bytes this install moved, so the picker can count module and voices as one download. */
    @Volatile var bytesThisInstall = 0L
        private set

    init {
        if (installed()) _state.value = State.Installed
    }

    fun installed(): Boolean = KokoroEngines.MODULE in manager.installedModules && KokoroEngines.present()

    /** Before Play reports its own figure: the arm64-v8a split as bundletool measures it (R2-kokoro-feasibility S6a). */
    fun downloadBytes(): Long = when (val s = _state.value) {
        is State.Downloading -> s.total
        State.Installed -> 0L
        else -> KNOWN_BYTES
    }

    fun clearFailure() {
        if (_state.value is State.Failed) _state.value = State.Absent
    }

    /** Installs the module (nothing when it is here). True once the engine can load; cancelling cancels Play's session. */
    suspend fun install(): Boolean {
        if (installed()) { _state.value = State.Installed; return true }
        bytesThisInstall = 0L
        _state.value = State.Pending
        var session = 0
        var listener: SplitInstallStateUpdatedListener? = null
        return try {
            suspendCancellableCoroutine { cont ->
                val l = SplitInstallStateUpdatedListener { s -> if (s.sessionId() == session || session == 0) onUpdate(s, cont) }
                listener = l
                manager.registerListener(l)
                manager.startInstall(SplitInstallRequest.newBuilder().addModule(KokoroEngines.MODULE).build())
                    .addOnSuccessListener { id ->
                        session = id
                        if (id == 0 && installed()) finish(cont, true)
                    }
                    .addOnFailureListener { e ->
                        _state.value = State.Failed((e as? SplitInstallException)?.errorCode ?: -100)
                        finish(cont, false)
                    }
                cont.invokeOnCancellation { if (session != 0) manager.cancelInstall(session) }
            }
        } finally {
            listener?.let { manager.unregisterListener(it) }
            if (_state.value !is State.Installed && _state.value !is State.Failed) _state.value = State.Absent
        }
    }

    private fun onUpdate(s: SplitInstallSessionState, cont: CancellableContinuation<Boolean>) {
        when (s.status()) {
            SplitInstallSessionStatus.PENDING -> _state.value = State.Pending
            SplitInstallSessionStatus.DOWNLOADING -> _state.value = State.Downloading(s.bytesDownloaded(), s.totalBytesToDownload())
            SplitInstallSessionStatus.DOWNLOADED, SplitInstallSessionStatus.INSTALLING -> {
                bytesThisInstall = s.totalBytesToDownload()
                _state.value = State.Installing
            }
            SplitInstallSessionStatus.REQUIRES_USER_CONFIRMATION -> _state.value = State.NeedsConfirmation(s)
            SplitInstallSessionStatus.INSTALLED -> {
                // The module's classes join the running app without a restart.
                SplitCompat.install(context)
                finish(cont, installed())
            }
            SplitInstallSessionStatus.FAILED -> {
                _state.value = State.Failed(s.errorCode())
                finish(cont, false)
            }
            SplitInstallSessionStatus.CANCELED -> finish(cont, false)
            else -> Unit
        }
    }

    private fun finish(cont: CancellableContinuation<Boolean>, ok: Boolean) {
        if (ok) _state.value = State.Installed
        if (cont.isActive) cont.resume(ok)
    }

    /** Play's own confirmation sheet for [s]; its answer arrives as the next state update. */
    fun confirm(s: State.NeedsConfirmation, launcher: ActivityResultLauncher<IntentSenderRequest>) {
        manager.startConfirmationDialogForResult(s.session, launcher)
    }

    /** "Delete downloaded voices": Play removes the module when the app is next in the background. */
    fun uninstall() {
        manager.deferredUninstall(listOf(KokoroEngines.MODULE))
        _state.value = State.Absent
    }

    companion object {
        /** `bundletool get-size total --modules=kokoro` of the release bundle for an arm64-v8a phone (2026-11-15). */
        const val KNOWN_BYTES = 18_650_181L
    }
}
