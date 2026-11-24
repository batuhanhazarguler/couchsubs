// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.random.Random

/**
 * Ekran yazısı çevirisinin oturum boyunca kararlı görünüşü ([ScreenStyleLock]). Ortak deneme dosyası
 * fixtures/screen-style-lock.json (Mac ScreenStyleLockTests.swift ve Windows ScreenStyleLockTests.cs aynı vakalar).
 */
class ScreenStyleLockTest {
    private fun item(entry: JSONObject): ScreenTranslation.Item {
        val source = entry.getString("source")
        val icons = entry.getInt("icons")
        return ScreenTranslation.Item(
            source = source, translation = "TR $source", box = TextBox(0.1, 0.1, 0.3, 0.14), lineHeight = entry.getDouble("line"),
            icons = if (icons > 0) (0 until icons).map { IconPlacement(it, "data:image/png;base64,") } else null,
            surface = TextSurface(entry.getString("bg"), entry.getString("fg")),
            look = if (entry.optBoolean("look", true)) {
                TextLook(entry.getBoolean("bold"), entry.getBoolean("condensed"), "left", entry.getBoolean("upper"))
            } else null,
            bubble = entry.optBoolean("bubble", false),
            rows = entry.getInt("rows"),
        )
    }

    @Test
    fun sharedStyleLockVectors() {
        val cases = JSONObject(Fixtures.text("screen-style-lock.json")).getJSONArray("cases")
        for (c in 0 until cases.length()) {
            val vector = cases.getJSONObject(c)
            val name = vector.getString("name")
            val lock = ScreenStyleLock()
            val steps = vector.getJSONArray("steps")
            for (s in 0 until steps.length()) {
                val step = steps.getJSONObject(s)
                val raw = step.getJSONArray("items")
                val got = lock.steady((0 until raw.length()).map { item(raw.getJSONObject(it)) }, step.getLong("now"))
                val expect = step.getJSONArray("expect")
                assertEquals("$name #$s", expect.length(), got.size)
                for (k in got.indices) {
                    val want = expect.getJSONObject(k)
                    val label = "$name #$s.$k"
                    assertEquals(label, want.getDouble("line"), got[k].lineHeight, 1e-9)
                    assertEquals(label, want.getString("fg"), got[k].surface?.foreground)
                    assertEquals(label, want.getString("bg"), got[k].surface?.background)
                    got[k].look?.let {
                        assertEquals(label, want.getBoolean("bold"), it.bold)
                        assertEquals(label, want.getBoolean("condensed"), it.condensed)
                    }
                }
            }
        }
    }

    /** Kısa konuşma satırı ("Ne?", "Lucia: Evet.") dar aile almaz; menü etiketi ve çok satırlı görev metni dar kalır (#1255). */
    @Test
    fun dialogueNeverCondensed() {
        val lock = ScreenStyleLock()
        val items = listOf("Ne?", "Yoldan çık.", "Lucia: Evet, hadi gidelim.", "HARİTA", "Ayarlar", "Gizli belgeleri bul.").mapIndexed { i, text ->
            ScreenTranslation.Item(
                source = "EN $i", translation = text, box = TextBox(0.4, 0.8 - i * 0.05, 0.6, 0.83 - i * 0.05), lineHeight = 0.03,
                surface = TextSurface("#101010", "#FFFFFF"), look = TextLook(true, true, "center", text == text.uppercase()),
                rows = if (i == 5) 2 else 1,
            )
        }
        val condensed = lock.steady(items, 0).map { it.look!!.condensed }
        assertEquals(listOf(false, false, false, true, true, true), condensed)
        assertEquals(true, ScreenFit.isDialogue("Ne?"))
        assertEquals(true, ScreenFit.isDialogue("“Gel buraya!”"))
        assertEquals(false, ScreenFit.isDialogue("ÇIK!"))
        assertEquals(false, ScreenFit.isDialogue("Haritayı aç"))
        assertEquals(false, ScreenFit.isDialogue("Gizli belgeleri bul.", rows = 2))
    }

    /** Ölçüt: ±%10 titreyen menüde aynı öğenin boyu/stili kareler arasında hiç değişmez. */
    @Test
    fun jitteringMenuNeverChangesLook() {
        val lock = ScreenStyleLock()
        val random = Random(7)
        val first = mutableMapOf<String, List<Any>>()
        for (frame in 0 until 120) {
            val rows = listOf("MAP", "BRIEF", "PROGRESS", "SETTINGS").map { name ->
                ScreenTranslation.Item(
                    source = name, translation = name, box = TextBox(0.1, 0.1, 0.2, 0.13),
                    lineHeight = 0.03 * (0.9 + 0.2 * random.nextDouble()),
                    surface = TextSurface("#%02X1010".format(random.nextInt(0, 31)), "#FFFFFF"),
                    look = TextLook(random.nextBoolean(), false, "left", true),
                )
            }
            for (item in lock.steady(rows, frame * 500L)) {
                val look = listOf(item.lineHeight, item.look!!.bold, item.surface!!.background, item.surface!!.foreground)
                val seen = first[item.source]
                if (seen != null) assertEquals(item.source, seen, look) else first[item.source] = look
            }
        }
    }
}
