package com.example.appname.data

import java.time.LocalDate
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * One value per calendar day (tonight.json, stations.json change once a day): the first caller of
 * a day loads it, concurrent callers wait for that load, later callers get the kept value. A load
 * that throws or returns null keeps nothing, so the next visit asks again.
 */
class DayCache<T : Any>(private val today: () -> LocalDate = { LocalDate.now() }) {
    private val lock = Mutex()
    private var day: LocalDate? = null
    private var value: T? = null

    suspend fun get(load: suspend () -> T?): T? = lock.withLock {
        val now = today()
        value?.takeIf { day == now }?.let { return it }
        val fresh = load()
        if (fresh != null) {
            day = now
            value = fresh
        }
        fresh
    }
}
