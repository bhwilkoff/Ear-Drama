package com.example.appname.data

import java.io.File

/**
 * The catalog's files on disk and the moves between them, kept apart from
 * Android so every state a killed process can leave is unit-tested
 * (CatalogFilesTest). A force-stop can land between any two lines of a
 * download, so launch repairs what it finds before anything opens the live
 * file: a complete, valid staging file is promoted; a live file that is empty
 * or will not open is discarded and the "last checked" stamp with it, so the
 * next refresh downloads regardless of the stale window.
 */
class CatalogFiles(
    val dir: File,
    private val minFullBytes: Long,
    private val validate: (String) -> Boolean,
) {
    val live get() = File(dir, "catalog.sqlite")
    val staging get() = File(dir, "catalog.sqlite.staging")
    private val stagingEtag get() = File(dir, "catalog.staging.etag")
    val etag get() = File(dir, "catalog.etag")
    val source get() = File(dir, "catalog.source")
    val lastCheck get() = File(dir, "catalog.lastcheck")

    fun readSource(): String? = source.readTextOrNull()

    /**
     * Launch: repair, then open. [copySeed] copies the bundled seed over the
     * live file and stamps it [seedStamp] (false when the build carries none);
     * [open] returns null for a file this build cannot read. A null result
     * leaves no live file and no "last checked" stamp behind.
     */
    fun <T : Any> openAtLaunch(seedStamp: String, copySeed: () -> Boolean, open: (String) -> T?): T? {
        recoverStaging()
        val stamp = readSource()
        // A new app build carries a newer seed; a cached seed copy from an
        // older build is replaced, a downloaded full catalog is kept.
        if (!liveLooksUsable() || (stamp != "full" && stamp != seedStamp)) copySeed()
        var opened = if (liveLooksUsable()) open(live.path) else null
        if (opened == null) {
            discardLive()
            if (copySeed()) opened = open(live.path)
            if (opened == null) discardLive()
        }
        return opened
    }

    /**
     * A staging file a killed process left behind: promoted when complete and
     * valid, deleted otherwise. True when it became the live catalog.
     */
    fun recoverStaging(): Boolean {
        if (!staging.exists()) {
            stagingEtag.delete()
            return false
        }
        return promoteStaging()
    }

    /**
     * Validates the staging file and renames it over the live one. The
     * source is marked "full" before the rename: a kill between the two
     * leaves the staging file in place, which the next launch promotes.
     */
    fun promoteStaging(): Boolean {
        if (staging.length() < minFullBytes || !validate(staging.path)) {
            discardStaging()
            return false
        }
        val previous = readSource()
        source.writeText("full")
        if (!staging.renameTo(live)) {
            if (previous == null) source.delete() else source.writeText(previous)
            discardStaging()
            return false
        }
        if (stagingEtag.exists()) stagingEtag.renameTo(etag) else etag.delete()
        return true
    }

    fun writeStagingEtag(value: String?) {
        if (value == null) stagingEtag.delete() else stagingEtag.writeText(value)
    }

    fun discardStaging() {
        staging.delete()
        stagingEtag.delete()
    }

    /** Whether the live file is worth opening; SQLite would create an empty file at a missing path. */
    fun liveLooksUsable(): Boolean = live.isFile && live.length() > 0

    /** The live catalog could not be served: drop it and everything that described it. */
    fun discardLive() {
        live.delete()
        File(dir, "catalog.sqlite-journal").delete()
        File(dir, "catalog.sqlite-wal").delete()
        File(dir, "catalog.sqlite-shm").delete()
        etag.delete()
        source.delete()
        lastCheck.delete()
    }

    fun markChecked(now: Long) = lastCheck.writeText(now.toString())

    fun isStale(now: Long, staleAfterMs: Long): Boolean {
        val last = lastCheck.readTextOrNull()?.toLongOrNull() ?: return true
        return now - last >= staleAfterMs
    }

    private fun File.readTextOrNull(): String? = takeIf { it.exists() }?.readText()?.trim()
}
