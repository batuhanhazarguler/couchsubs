// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ürün/ambalaj/etiket yazısı (bira kutusu, süt kartonu) ekran yazısı ve altyazı sayılmaz; menü, istem, görev, bildirim ve
 * telefon yazısı kalır (Sinan Bey beta.101). Ortak deneme dosyası fixtures/package-text.json (core/Tests/CouchSubsCoreTests/
 * Fixtures kopyası; Mac PackageTextTests.swift ve Windows PackageTextTests.cs aynı dosyayı okur).
 */
class PackageTextTest {
    private fun box(values: JSONArray) =
        TextBox(values.getDouble(0), values.getDouble(1), values.getDouble(2), values.getDouble(3))

    private fun objects(array: JSONArray) = (0 until array.length()).map { array.getJSONObject(it) }

    private fun ints(array: JSONArray) = IntArray(array.length()) { array.getInt(it) }

    private val root by lazy { JSONObject(Fixtures.text("package-text.json")) }

    private fun look(vector: JSONObject): PackageText.Look? =
        if (vector.isNull("look")) null
        else vector.getJSONObject("look").let { PackageText.Look(it.getBoolean("textured"), it.getBoolean("uiInk")) }

    @Test fun brandShape() {
        for (shape in objects(root.getJSONArray("shapes"))) {
            val text = shape.getString("text")
            assertEquals(text, shape.getBoolean("brand"), PackageText.isBrandShape(text))
        }
    }

    @Test fun productNamesAreKept() {
        for (product in objects(root.getJSONArray("products"))) {
            val text = product.getString("text")
            assertEquals(text, product.getBoolean("keep"), ScreenTranslation.keepsNames(text))
        }
    }

    @Test fun sharedCases() {
        val cases = objects(root.getJSONArray("cases"))
        assertTrue(cases.isNotEmpty())
        for (vector in cases) {
            val name = vector.getString("name")
            val lines = objects(vector.getJSONArray("lines")).map { line ->
                TextLine(line.getString("text"), box(line.getJSONArray("box")),
                    words = line.optJSONArray("words")?.let { words ->
                        objects(words).map { TextWord(it.getString("text"), box(it.getJSONArray("box"))) }
                    })
            }
            val seen = look(vector)
            val expected = (0 until vector.getJSONArray("kept").length()).map { vector.getJSONArray("kept").getString(it) }
            val (kept, removed) = PackageText.filter(Reading(lines), box(vector.getJSONArray("area"))) { _, _ -> seen }
            assertEquals(name, expected, kept.lines.map { it.text })
            assertEquals(name, lines.size - expected.size, removed.size)
        }
    }

    @Test fun lookFromPixels() {
        for (vector in objects(root.getJSONArray("pixels"))) {
            val name = vector.getString("name")
            val size = vector.getJSONArray("size")
            val w = size.getInt(0)
            val h = size.getInt(1)
            val target = box(vector.getJSONArray("box"))
            val others = (0 until vector.getJSONArray("others").length()).map { box(vector.getJSONArray("others").getJSONArray(it)) }
            val boxes = listOf(target) + others
            val ground = vector.getJSONObject("ground")
            val kind = ground.getString("kind")
            val a = ints(ground.getJSONArray("a"))
            val b = ints(ground.getJSONArray("b"))
            val period = ground.getInt("period")
            val ink = ints(vector.getJSONArray("ink"))
            fun pack(c: IntArray) = (c[0] shl 16) or (c[1] shl 8) or c[2]
            val rgb = { x: Int, y: Int ->
                val hit = boxes.any { k ->
                    val top = k.top * h
                    val height = (k.bottom - k.top) * h
                    x >= Math.floor(k.left * w).toInt() && x < Math.ceil(k.right * w).toInt() &&
                        y >= Math.floor(top).toInt() && y < Math.ceil(k.bottom * h).toInt() &&
                        y >= top + 0.15 * height && y < top + 0.85 * height && (x / 2) % 2 == 0
                }
                when {
                    hit -> pack(ink)
                    kind == "checker" -> pack(if ((x / period + y / period) % 2 == 0) a else b)
                    kind == "gradient" -> pack(IntArray(3) { a[it] + (b[it] - a[it]) * x / (w - 1) })
                    else -> pack(a)
                }
            }
            val expected = look(vector)
            assertEquals(name, expected, PackageText.measure(target, others, w, h, rgb))
        }
    }
}
