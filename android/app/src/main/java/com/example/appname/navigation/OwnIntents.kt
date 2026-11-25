package com.example.appname.navigation

import android.content.Intent
import android.net.Uri
import androidx.core.content.IntentCompat
import com.example.appname.plays.OwnText
import com.example.appname.ui.screens.OwnIncoming

/** What a `text/plain` ACTION_SEND or ACTION_VIEW holds for Add a script (ANDROID-DESIGN §4.23 item 1), or null. */
object OwnIntents {
    fun incoming(intent: Intent?): OwnIncoming? {
        if (intent == null || intent.type?.lowercase(java.util.Locale.ROOT)?.substringBefore(';')?.trim() != "text/plain") return null
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                val words = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
                val file = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                when {
                    file != null && readable(file) -> OwnIncoming.File(file)
                    words != null && words.isNotEmpty() -> OwnIncoming.Words(OwnText.shared(words, intent.getStringExtra(Intent.EXTRA_SUBJECT).orEmpty()))
                    else -> null
                }
            }
            Intent.ACTION_VIEW -> intent.data?.takeIf(::readable)?.let { OwnIncoming.File(it) }
            else -> null
        }
    }

    /** Another app's file comes by a provider's address: a `file:` path handed in could name this app's own files. */
    private fun readable(uri: Uri): Boolean = uri.scheme == "content"
}
