// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Kamerayla kayan yazı (plaka, tabela, dükkân adı) altyazı sayılmaz; yerinde duran altyazı hiç çıkarılmaz (GitHub #1259).
 * Ortak deneme dosyası fixtures/scene-motion.json (core/Tests/CouchSubsCoreTests/Fixtures kopyası; Mac
 * SceneMotionTests.swift ve Windows SceneMotionTests.cs aynı dosyayı okur).
 */
class SceneMotionTest {
    private fun box(values: JSONArray) =
        TextBox(values.getDouble(0), values.getDouble(1), values.getDouble(2), values.getDouble(3))

    private fun objects(array: JSONArray) = (0 until array.length()).map { array.getJSONObject(it) }

    @Test fun sharedVectors() {
        val cases = objects(JSONObject(Fixtures.text("scene-motion.json")).getJSONArray("cases"))
        assertTrue(cases.isNotEmpty())
        for (vector in cases) {
            val name = vector.getString("name")
            val motion = SceneMotion()
            val area = box(vector.getJSONArray("area"))
            for (frame in objects(vector.getJSONArray("frames"))) {
                val time = frame.getLong("time")
                val lines = objects(frame.getJSONArray("lines")).map { line ->
                    TextLine(line.getString("text"), line.optJSONArray("box")?.let(::box))
                }
                val expected = frame.getJSONArray("kept").let { array -> (0 until array.length()).map { array.getString(it) } }
                val kept = motion.filter(Reading(lines), area, time)
                assertEquals("$name @$time", expected, kept.lines.map { it.text })
                assertEquals("$name @$time", lines.size - expected.size, motion.removed.size)
            }
        }
    }

    @Test fun resetForgetsSeenText() {
        val motion = SceneMotion()
        val area = TextBox(0.0, 0.0, 1.0, 1.0)
        motion.filter(Reading(listOf(TextLine("Charters", TextBox(0.1, 0.5, 0.2, 0.55)))), area, 0)
        motion.reset()
        val kept = motion.filter(Reading(listOf(TextLine("Charters", TextBox(0.4, 0.5, 0.5, 0.55)))), area, 100)
        assertEquals(listOf("Charters"), kept.lines.map { it.text })
    }
}
