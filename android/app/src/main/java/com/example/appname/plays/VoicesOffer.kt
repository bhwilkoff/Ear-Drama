package com.example.appname.plays

import android.content.Context
import androidx.core.content.edit
import com.example.appname.kokoro.KokoroModelStore
import com.example.appname.kokoro.KokoroModule

/**
 * The Better voices step's record (PLAYS-DESIGN §2.8 rule 13, Decision 090; ANDROID-DESIGN §4.6b): one number on the device,
 * never synced. 0 never offered, 1 offered at launch, 2 done (offered at first use, or a download begun).
 */
class VoicesOffer(private val store: Store) {
    interface Store {
        fun read(): Int
        fun write(stage: Int)
    }

    val stage: Int get() = store.read()

    /** At launch: true (and the record moves to 1) only the first time, and only when the download is offered now. */
    fun atLaunch(eligible: Boolean): Boolean {
        if (!eligible || store.read() != NEVER) return false
        store.write(AT_LAUNCH)
        return true
    }

    /** The launch with its DEBUG doors: [force] shows it and [skip] keeps it away, neither reading nor writing the record. */
    fun atLaunch(eligible: Boolean, force: Boolean, skip: Boolean): Boolean = when {
        force -> true
        skip -> false
        else -> atLaunch(eligible)
    }

    /** The first reader, cast or recorder opened: true once, after a skip or a launch that could not offer it. */
    fun atFirstUse(eligible: Boolean): Boolean {
        if (!eligible || store.read() >= DONE) return false
        store.write(DONE)
        return true
    }

    /** A download began (from the step or from Library), or the voices are already here: never offered again. */
    fun downloadBegan() {
        if (store.read() < DONE) store.write(DONE)
    }

    companion object {
        const val KEY = "ed.voicesStep"
        const val NEVER = 0
        const val AT_LAUNCH = 1
        const val DONE = 2

        /** Offered now: the voices could run here, are not here, and nothing of them is downloading. */
        fun eligible(supported: Boolean, store: KokoroModelStore.State, module: KokoroModule.State): Boolean =
            supported &&
                !(store is KokoroModelStore.State.Ready && module is KokoroModule.State.Installed) &&
                !begunOnly(store, module)

        /** Any sign a download began or finished: the record moves to done. */
        fun begun(store: KokoroModelStore.State, module: KokoroModule.State): Boolean =
            store is KokoroModelStore.State.Ready || begunOnly(store, module)

        private fun begunOnly(store: KokoroModelStore.State, module: KokoroModule.State): Boolean =
            store is KokoroModelStore.State.Downloading ||
                module is KokoroModule.State.Pending || module is KokoroModule.State.Downloading ||
                module is KokoroModule.State.Installing || module is KokoroModule.State.NeedsConfirmation

        /** Under the download's size plus 20%, Download is disabled and the free space is said. */
        fun lowSpace(freeBytes: Long, size: Long): Boolean = size > 0 && freeBytes < size + size / 5

        /** Open Settings is offered when no installed English voice reports quality 400 or more. */
        fun wantsSystemVoices(device: List<CastVoice>): Boolean =
            device.isNotEmpty() && device.none { it.quality >= CastVoice.HIGH_QUALITY }
    }
}

/** The record in this device's preferences. */
class PrefsVoicesOfferStore(context: Context) : VoicesOffer.Store {
    private val prefs = context.applicationContext.getSharedPreferences(VoicesOffer.KEY, Context.MODE_PRIVATE)
    override fun read(): Int = prefs.getInt(VoicesOffer.KEY, VoicesOffer.NEVER)
    override fun write(stage: Int) = prefs.edit { putInt(VoicesOffer.KEY, stage) }
}
