package com.example.appname.data

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Every state a force-stop can leave the catalog's files in, opened the way
 * a launch opens them (2026-11-14: a kill mid-swap on the Google TV left a
 * 0-byte catalog.sqlite beside a complete staging file, and the stale window
 * kept every later launch from downloading again).
 */
class CatalogFilesTest {
    private lateinit var dir: File
    private lateinit var fixtureDir: File
    private lateinit var files: CatalogFiles

    @Before fun setUp() {
        dir = Files.createTempDirectory("catalog-files").toFile()
        fixtureDir = Files.createTempDirectory("catalog-fixture").toFile()
        files = CatalogFiles(dir, minFullBytes = 1, validate = CatalogDatabase::validate)
    }

    @After fun tearDown() {
        dir.deleteRecursively()
        fixtureDir.deleteRecursively()
    }

    private fun fixture(): File = CatalogFixture.build(fixtureDir)

    private val noSeed = { false }

    private fun openAtLaunch(copySeed: () -> Boolean = noSeed): CatalogDatabase? =
        files.openAtLaunch("seed:1", copySeed, CatalogDatabase::open)

    @Test fun firstLaunchWithoutASeedLeavesNoEmptyFileAndNoCheckStamp() {
        assertNull(openAtLaunch())
        assertFalse("SQLite created an empty live file", files.live.exists())
        assertTrue(files.isStale(now = 0, staleAfterMs = Long.MAX_VALUE))
    }

    @Test fun zeroByteLiveBesideCompleteStagingPromotesTheStaging() {
        files.live.writeBytes(ByteArray(0))
        fixture().copyTo(files.staging)
        files.markChecked(System.currentTimeMillis())
        val db = openAtLaunch()
        assertNotNull(db)
        db?.close()
        assertFalse(files.staging.exists())
        assertEquals("full", files.readSource())
        assertTrue(files.live.length() > 0)
    }

    @Test fun zeroByteLiveWithoutStagingDiscardsTheCheckStamp() {
        files.live.writeBytes(ByteArray(0))
        files.source.writeText("full")
        files.etag.writeText("\"abc\"")
        files.markChecked(System.currentTimeMillis())
        assertNull(openAtLaunch())
        assertFalse(files.live.exists())
        assertFalse(files.etag.exists())
        assertTrue("an unservable catalog must download regardless of the stale window",
            files.isStale(System.currentTimeMillis(), staleAfterMs = Long.MAX_VALUE))
    }

    @Test fun corruptLiveFallsBackToTheSeed() {
        files.live.writeText("not a database at all, just bytes")
        files.source.writeText("full")
        val seed = fixture()
        val db = openAtLaunch(copySeed = {
            seed.copyTo(files.live, overwrite = true)
            files.source.writeText("seed:1")
            true
        })
        assertNotNull(db)
        db?.close()
        assertEquals("seed:1", files.readSource())
    }

    @Test fun truncatedStagingIsDiscardedAndTheLiveCatalogKept() {
        fixture().copyTo(files.live)
        files.source.writeText("full")
        val whole = fixture().readBytes()
        files.staging.writeBytes(whole.copyOf(whole.size / 3))
        val db = openAtLaunch()
        assertNotNull(db)
        db?.close()
        assertFalse(files.staging.exists())
        assertEquals("full", files.readSource())
    }

    @Test fun stagingBelowTheSizeFloorIsNeverPromoted() {
        val strict = CatalogFiles(dir, minFullBytes = Long.MAX_VALUE, validate = CatalogDatabase::validate)
        fixture().copyTo(strict.staging)
        assertFalse(strict.recoverStaging())
        assertFalse(strict.staging.exists())
        assertFalse(strict.live.exists())
    }

    @Test fun promotionCarriesTheStagingEtag() {
        fixture().copyTo(files.staging)
        files.writeStagingEtag("\"v2\"")
        files.etag.writeText("\"v1\"")
        assertTrue(files.promoteStaging())
        assertEquals("\"v2\"", files.etag.readText())
    }

    @Test fun aKillAfterTheSourceStampButBeforeTheRenameStillPromotes() {
        fixture().copyTo(files.live)
        files.source.writeText("full")
        fixture().copyTo(files.staging)
        assertTrue(files.recoverStaging())
        assertFalse(files.staging.exists())
    }
}
