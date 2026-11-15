package com.example.appname.plays

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import kotlinx.coroutines.launch
import org.junit.Test

/**
 * A first take needs no account; a second production does; a production with no take stays out of sight
 * (Decision 079, PLAYS-DESIGN §2.3 rules 3 and 3a; the web's js/plays.test.js and js/plays-share.test.js).
 */
class FirstTakeTest {
    private val script = fixtureScript()
    private fun empty(id: String, created: Double = 1.0) = Production.create(script, id).copy(created = created)
    private fun taken(id: String) = empty(id).add(take("t-$id", "L0003", PartID.role("MOLLY"), 4_800))

    @Test fun `signed out, a second production asks for an account, an empty one does not count`() {
        assertFalse("the first production needs none", Production.secondNeedsAccount(emptyList(), signedIn = false))
        assertFalse("a production with no take does not count", Production.secondNeedsAccount(listOf(empty("a")), signedIn = false))
        assertTrue("one with a take makes the next a second", Production.secondNeedsAccount(listOf(empty("a"), taken("b")), signedIn = false))
        assertFalse("signed in, nothing is asked", Production.secondNeedsAccount(listOf(taken("b")), signedIn = true))
    }

    @Test fun `only beginning a new production asks`() {
        val held = listOf(taken("b"))
        assertTrue(StudioCore.asksAccount(StudioCore.Pick.Make, held, signedIn = false))
        assertFalse("continuing the part", StudioCore.asksAccount(StudioCore.Pick.Resume("b"), held, signedIn = false))
        assertFalse("taking an open part", StudioCore.asksAccount(StudioCore.Pick.Take("b"), held, signedIn = false))
        assertFalse(StudioCore.asksAccount(StudioCore.Pick.Make, emptyList(), signedIn = false))
        assertFalse(StudioCore.asksAccount(StudioCore.Pick.Make, held, signedIn = true))
    }

    @Test fun `record this reuses an empty production of the play while it lasts`() {
        val other = fixtureScript().copy(id = "gut-9")
        val productions = listOf(empty("old", 1.0), empty("new", 5.0), taken("full"), Production.create(other, "elsewhere"), empty("shared", 9.0))
        assertEquals("new", StudioCore.reusable(productions, { it == "shared" }, script.id))
        assertNull(StudioCore.reusable(listOf(taken("full")), { false }, script.id))
    }

    @Test fun `an empty, unshared production is abandoned, a shared or taken one is not`() {
        val productions = listOf(empty("a"), taken("b"), empty("c"))
        assertEquals(listOf("a"), Production.abandoned(productions, isShared = { it == "c" }))
        assertEquals(emptyList<String>(), Production.abandoned(productions, isShared = { true }))
    }

    @Test fun `yours lists a production once it holds a take, a shared one always`() {
        val store = ProductionStore(temporaryRoot())
        store.save(empty("empty", 1.0))
        store.save(taken("taken").copy(created = 2.0))
        store.save(empty("shared", 3.0))
        store.setShare("shared", ShareLink("pid-shared"))
        assertEquals(listOf("shared", "taken"), PlaysShare.libraryRows(store, null).map { it.local!!.id })
    }

    @Test fun `loading the store deletes the empty productions an earlier visit left`() {
        val root = temporaryRoot()
        val first = ProductionStore(root)
        val abandoned = first.create(script)
        val kept = first.create(script).add(take("t1", "L0003", PartID.role("MOLLY"), 4_800)).also(first::save)
        val shared = first.create(script)
        first.setShare(shared.id, ShareLink("pid"))
        assertTrue(File(root, abandoned.id).isDirectory)
        val next = ProductionStore(root)
        assertEquals(setOf(kept.id, shared.id), next.all().map { it.id }.toSet())
        assertFalse("its folder goes, as Delete production does", File(root, abandoned.id).exists())
    }

    @Test fun `a production made in this visit stays until the studio closes without a take`() {
        val store = ProductionStore(temporaryRoot())
        val made = store.create(script)
        store.load()
        assertEquals("the studio may still be open on it", made.id, store.production(made.id)?.id)
        store.hold(made.id)
        store.dropIfEmpty(made.id)
        assertEquals("a screen showing it keeps it", made.id, store.production(made.id)?.id)
        store.release(made.id)
        store.dropIfEmpty(made.id)
        assertNull(store.production(made.id))
        assertFalse(store.folder(made.id).exists())
        val full = store.create(script).add(take("t1", "L0003", PartID.role("MOLLY"), 4_800)).also(store::save)
        store.dropIfEmpty(full.id)
        assertEquals(full.id, store.production(full.id)?.id)
    }

    @Test fun `a take written after the old two second window survives with its production`() = kotlinx.coroutines.test.runTest {
        val store = ProductionStore(temporaryRoot())
        val made = store.create(script)
        val leaving = launch { store.dropWhenSettled(made.id) }
        var written = false
        val writing = Thread {
            store.takeWrite(made.id) {
                Thread.sleep(2_500)
                store.save(store.production(made.id)!!.add(take("late", "L0003", PartID.role("MOLLY"), 4_800)))
                written = true
            }
        }
        writing.start()
        while (!store.hasPendingTake(made.id)) Thread.sleep(5)
        store.dropIfEmpty(made.id)
        assertEquals("a pending write is never dropped under", made.id, store.production(made.id)?.id)
        writing.join()
        leaving.join()
        assertTrue(written)
        assertEquals(1, store.production(made.id)?.takes?.size)
    }

    @Test fun `an empty production with no pending writes is removed on leave`() = kotlinx.coroutines.test.runTest {
        val store = ProductionStore(temporaryRoot())
        val made = store.create(script)
        store.dropWhenSettled(made.id)
        assertNull(store.production(made.id))
    }

    @Test fun `a held production is never pruned on leave`() = kotlinx.coroutines.test.runTest {
        val store = ProductionStore(temporaryRoot())
        val made = store.create(script)
        store.hold(made.id)
        store.dropWhenSettled(made.id)
        assertEquals(made.id, store.production(made.id)?.id)
    }
}
