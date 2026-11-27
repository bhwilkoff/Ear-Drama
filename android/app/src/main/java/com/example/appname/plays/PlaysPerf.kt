package com.example.appname.plays

import com.example.appname.BuildConfig

/** Debug-only timestamps for the library's cold load (grep logcat for EDPERF); a release build runs the block and says nothing. */
internal object PlaysPerf {
    private val start = System.nanoTime()

    inline fun <T> time(label: String, detail: () -> String = { "" }, block: () -> T): T {
        if (!BuildConfig.DEBUG) return block()
        val t0 = System.nanoTime()
        val out = block()
        say(label, t0, detail())
        return out
    }

    fun say(label: String, since: Long, detail: String = "") {
        if (!BuildConfig.DEBUG) return
        val now = System.nanoTime()
        println("EDPERF +${(now - start) / 1_000_000}ms $label took ${(now - since) / 1_000_000}ms on ${Thread.currentThread().name} $detail")
    }
}
