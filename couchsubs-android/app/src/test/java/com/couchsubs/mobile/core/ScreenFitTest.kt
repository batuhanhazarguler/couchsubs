// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * "Ekranı çevir" yerleşimi ([ScreenFit]): kutu simgeye taşmaz, eş öğeler aynı boyda, sütun/şerit hizası. Ortak deneme
 * dosyası fixtures/screen-fit.json (Mac ScreenFitTests.swift ve Windows ScreenFitTests.cs aynı vakalar).
 */
class ScreenFitTest {
    private val fixture = JSONObject(Fixtures.text("screen-fit.json"))

    private fun doubles(array: JSONArray) = (0 until array.length()).map { array.getDouble(it) }

    @Test
    fun sharedVectors() {
        val width = fixture.getInt("width")
        val height = fixture.getInt("height")
        val tolerance = fixture.getDouble("tolerance")
        val background = fixture.getString("background")
        val ink = fixture.getString("ink")
        val ground = background.substring(1).toInt(16)
        val inkColor = ink.substring(1).toInt(16)
        val cases = fixture.getJSONArray("cases")
        for (c in 0 until cases.length()) {
            val vector = cases.getJSONObject(c)
            val rgb = IntArray(width * height) { ground }
            val rects = vector.getJSONArray("rects")
            for (r in 0 until rects.length()) {
                val v = doubles(rects.getJSONArray(r))
                for (y in (v[1] * height).roundToInt() until (v[3] * height).roundToInt())
                    for (x in (v[0] * width).roundToInt() until (v[2] * width).roundToInt()) rgb[y * width + x] = inkColor
            }
            val luma = ByteArray(rgb.size) { i ->
                val p = rgb[i]
                ((299 * ((p shr 16) and 255) + 587 * ((p shr 8) and 255) + 114 * (p and 255)) / 1000).toByte()
            }
            val frame = GrayFrame(luma, width, height)
            val raw = vector.getJSONArray("items")
            val items = (0 until raw.length()).map { k ->
                val entry = raw.getJSONObject(k)
                val b = doubles(entry.getJSONArray("box"))
                ScreenTranslation.Item(entry.getString("name"), entry.getString("name"), TextBox(b[0], b[1], b[2], b[3]),
                    entry.getDouble("line"), surface = TextSurface(background, ink, true), look = TextLook(true, false, "left", true))
            }
            val fitted = ScreenFit.fitted(items, frame) { x, y -> rgb[y * width + x] }
            val expect = vector.getJSONArray("expect")
            assertEquals(expect.length(), fitted.size)
            for (k in 0 until expect.length()) {
                val want = expect.getJSONObject(k)
                val have = fitted[k]
                val name = "${vector.getString("id")} ${raw.getJSONObject(k).getString("name")}"
                assertEquals(name, want.getString("align"), have.look!!.align)
                assertEquals(name, want.getDouble("line"), have.lineHeight, tolerance)
                close("$name kutu", doubles(want.getJSONArray("box")), have.box)
                assertNotNull("$name alan yok", have.room)
                close("$name alan", doubles(want.getJSONArray("room")), have.room!!)
            }
        }
    }

    private fun close(name: String, want: List<Double>, have: TextBox) {
        val h = listOf(have.left, have.top, have.right, have.bottom)
        for (i in 0 until 4) assertTrue("$name: $h ≠ $want", abs(want[i] - h[i]) <= fixture.getDouble("tolerance"))
    }
}
