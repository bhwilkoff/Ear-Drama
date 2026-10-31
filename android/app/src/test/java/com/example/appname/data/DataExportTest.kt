package com.example.appname.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Export (Human-Shaped principle 11): the JSON holds history, follows, queue and takes under the web's keys; the CSV quotes what needs it. */
class DataExportTest {
    private val sample = DataExport(
        exportedAtMs = 1_793_361_600_000,
        history = listOf(
            DataExport.History("a|1", "One, with a comma", "The \"Quoted\" Show", "1949-02-03", 1_793_300_000_000, 600.0, 1800.0),
            DataExport.History("a|2", null, null, null, null, null, null),
        ),
        following = listOf(DataExport.Follow("a", "A Show")),
        queue = listOf(DataExport.Queued("a|3", "Three", "A Show", null)),
        takes = listOf(DataExport.Production("p1", "Play", 1_793_000_000_000, listOf(
            DataExport.Take("t1", "l1", "role:A", 1_793_000_100_000, 2.5, true),
        ))),
    )

    @Test fun `the json carries everything under the web's keys`() {
        val root = Json.parseToJsonElement(sample.json()).jsonObject
        assertEquals("Ear Drama", root["app"]!!.jsonPrimitive.content)
        val first = root["history"]!!.jsonArray[0].jsonObject
        assertEquals("a|1", first["episode"]!!.jsonPrimitive.content)
        assertEquals(600.0, first["positionSeconds"]!!.jsonPrimitive.double, 0.0)
        assertEquals("a", root["following"]!!.jsonArray[0].jsonObject["series"]!!.jsonPrimitive.content)
        assertEquals("1", root["queue"]!!.jsonArray[0].jsonObject["position"]!!.jsonPrimitive.content)
        val production = root["takes"]!!.jsonArray[0].jsonObject
        assertEquals("p1", production["production"]!!.jsonPrimitive.content)
        assertTrue(production["takes"]!!.jsonArray[0].jsonObject["chosen"]!!.jsonPrimitive.boolean)
    }

    @Test fun `the csv quotes commas and quotes and leaves gaps empty`() {
        val lines = sample.historyCsv().split("\r\n")
        assertEquals(DataExport.HISTORY_COLUMNS.joinToString(","), lines[0])
        assertTrue(lines[1], lines[1].startsWith("a|1,\"One, with a comma\",\"The \"\"Quoted\"\" Show\",1949-02-03,"))
        assertTrue(lines[1].endsWith(",600,1800"))
        assertEquals("a|2,,,,,,", lines[2])
        assertEquals(4, lines.size)
    }

    @Test fun `nothing held exports an empty file, not an error`() {
        val empty = DataExport(0, emptyList(), emptyList(), emptyList(), emptyList())
        assertEquals(0, Json.parseToJsonElement(empty.json()).jsonObject["history"]!!.jsonArray.size)
        assertEquals(DataExport.HISTORY_COLUMNS.joinToString(",") + "\r\n", empty.historyCsv())
    }

    @Test fun `a reference date converts to the unix instant`() {
        assertEquals(978_307_200_000, DataExport.fromReferenceDate(0.0))
    }
}
