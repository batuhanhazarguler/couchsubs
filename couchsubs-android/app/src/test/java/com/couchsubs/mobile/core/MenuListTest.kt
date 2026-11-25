// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.util.Collections
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * Duraklatma menüsünün konuşma/yardım geçmişi listesi (Sinan Bey beta.100, 3380-3383). Ortak deneme dosyası
 * fixtures/menu-list.json (core/Tests/CouchSubsCoreTests/Fixtures kopyası; Mac MenuListTests.swift ve Windows
 * MenuListTests.cs aynı dosyayı okur).
 */
class MenuListTest {
    private val root = JSONObject(Fixtures.text("menu-list.json"))

    private fun box(array: JSONArray) = TextBox(array.getDouble(0), array.getDouble(1), array.getDouble(2), array.getDouble(3))

    private fun objects(name: String) = root.getJSONArray(name).let { array -> (0 until array.length()).map { array.getJSONObject(it) } }

    private fun lines(item: JSONObject, key: String = "lines") = item.getJSONArray(key).let { array ->
        (0 until array.length()).map { array.getJSONObject(it) }.map { TextLine(it.getString("text"), box(it.getJSONArray("box"))) }
    }

    /** Liste satırları altyazı seçilmez: alt kutuda "Staff Member: …" gösterilmiyor, gerçek altyazı seçilmeye devam ediyor. */
    @Test
    fun historyListIsNeverASubtitle() {
        val area = TextBox(0.14, 0.62, 0.86, 0.97)
        for (item in objects("lists")) {
            val name = item.getString("name")
            val read = Reading(lines(item))
            assertEquals(name, item.getBoolean("list"), read.isHistoryList)
            val reasons = mutableListOf<String>()
            val block = read.subtitleBlock(area, dropped = { _, reason -> reasons += reason })
            if (item.getBoolean("list")) {
                assertTrue(name, block.lines.isEmpty())
                assertEquals(name, listOf(Reading.LIST_REASON), reasons)
            } else {
                assertFalse(name, Reading.LIST_REASON in reasons)
            }
        }
    }

    @Test
    fun piecesOfOneRowAreJoined() {
        for (item in objects("pieces")) {
            val joined = RegionWatcher.joinedPieces(lines(item), item.getDouble("aspect"))
            val expected = item.getJSONArray("expected").let { a -> (0 until a.length()).map { a.getString(it) } }
            assertEquals(item.getString("name"), expected, joined.map { it.text })
        }
    }

    @Test
    fun rowCutAtTheAreaEdgeIsSkipped() {
        for (item in objects("cuts")) {
            val r = item.getJSONArray("region")
            val region = CropRegion(top = r.getDouble(1), bottom = r.getDouble(3), left = r.getDouble(0), right = r.getDouble(2))
            assertEquals(item.getString("name"), item.getBoolean("cut"),
                RegionWatcher.cutAtAreaEdge(TextLine("Clerk: Need a hand", box(item.getJSONArray("box"))), region))
        }
    }

    /** Konuşan adı ve özel ad çeviriye gitmez ("JASON & LUCIA MAP" → yalnız "MAP" çevrilir). */
    @Test
    fun speakerAndNameHeadsStayUntranslated() {
        for (item in objects("labels")) {
            val text = item.getString("text")
            val head = RegionWatcher.keptHead(text) ?: ""
            assertEquals(text, item.getString("prefix"), head)
            assertEquals(text, item.getString("core"), text.substring(head.length))
        }
    }

    /** Liste kayınca eski kutular kalkar (gösterilen satır başka yerde ya da yerinde başka satır). */
    @Test
    fun scrollingListDropsOldBoxes() {
        for (item in objects("scrolls")) {
            val rendered = item.getJSONArray("rendered").let { a -> (0 until a.length()).map { a.getJSONObject(it) } }.map {
                val b = box(it.getJSONArray("box"))
                ScreenTranslation.Item(source = it.getString("source"), translation = "çeviri", box = b, lineHeight = b.bottom - b.top)
            }
            val current = item.getJSONArray("current").let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
                .map { box(it.getJSONArray("box")) to it.getString("text") }
            assertEquals(item.getString("name"), item.getBoolean("moved"), RegionWatcher.listMoved(rendered, current))
        }
    }

    private val width = 640
    private val height = 360

    private fun label(pixels: ByteArray, column: Int, row: Int, columns: Int = 1) {
        for (y in row * 20 until row * 20 + 20) for (x in column * 20 until (column + columns) * 20) {
            val text = (y - row * 20) % 8 in 3..4 && x % 4 != 0
            pixels[y * width + x] = (if (text) 230 else 25).toByte()
        }
    }

    private fun ScreenTextDetector.step(pixels: ByteArray, now: Long): List<ExtraArea> =
        update(sample(width, height) { x, y -> pixels[y * width + x].toInt() and 0xff }, emptyList(), now)

    /**
     * Liste okunurken menü durumu bitmez: konuşan adlı satır (kaydırırken tek satır okunabilir) menüyü kapatmaz, menü
     * süresi ([ScreenTextDetector.MENU_LIFE_MS]) de dolmaz. Liste ekrandan kalkınca konuşma satırı yine menüyü bitirir (#1240).
     */
    @Test
    fun listKeepsTheMenuAndDialogueEndsItOnlyAfterwards() {
        val random = Random(7)
        val pixels = ByteArray(width * height) { (110 + random.nextInt(6)).toByte() }
        listOf(4 to 12, 8 to 12, 12 to 12, 16 to 12, 20 to 12, 24 to 12, 6 to 4, 26 to 4).forEach { (c, r) -> label(pixels, c, r) }
        label(pixels, 14, 8, columns = 3)
        val detector = ScreenTextDetector()
        for (t in 0L..400L step 100) detector.step(pixels, t)
        assertTrue(detector.menu)
        for (t in 500L..8000L step 100) {
            if (t % 500 == 0L) detector.noteList(t)
            if (t % 700 == 0L) detector.noteDialogue(t)
            detector.step(pixels, t)
            assertTrue("$t ms", detector.menu)
        }
        detector.noteDialogue(9700)
        detector.step(pixels, 9700)
        assertFalse(detector.menu)
    }

    @Test
    fun listLinesHeldDuringTheMenuAreNotSentAfterIt() {
        val sent = mutableListOf<String>()
        val sink = object : SubtitleSender {
            override fun sendSubtitle(text: String, durationMs: Int, box: TextBox?, replaces: Boolean) { sent += text }
            override fun clear() {}
        }
        var menu = true
        var time = 0L
        val sender = MenuHeldSender(sink, { menu }, null) { time }
        assertTrue(sender.poll())
        time = 1000
        sender.sendSubtitle("Clerk: Take it easy.", 15000, null, false)
        sender.forget()
        menu = false
        time = 2000
        sender.poll()
        assertEquals(emptyList<String>(), sent)
    }

    /**
     * Uçtan uca: altyazı alanında geçmiş listesi 15 sn okunur; hiçbir satır altyazı olarak gönderilmez (bekçi de
     * göndermez), konuşan adı menüyü bitirmez ([SubtitlePipeline.onDialogue] çağrılmaz), liste bildirilir.
     */
    @Test
    fun pipelineSendsNothingFromTheList() {
        val list = objects("lists").first { it.getBoolean("list") && it.getJSONArray("lines").length() >= 4 }
        val executor = Executors.newSingleThreadExecutor()
        val sent = Collections.synchronizedList(mutableListOf<String>())
        val translator = object : TextTranslator {
            override fun translate(text: String): String = "TR $text"
        }
        val sender = object : SubtitleSender {
            override fun sendSubtitle(text: String, durationMs: Int, box: TextBox?, replaces: Boolean) { sent.add(text) }
            override fun clear() {}
        }
        var time = 1_000_000L
        var dialogue = 0
        var listed = 0
        val pipeline = SubtitlePipeline(translator, sender, { time }, executor).apply {
            onDialogue = { dialogue++ }
            onList = { listed++ }
        }
        try {
            repeat(150) {
                pipeline.process(Reading(lines(list)), CropRegion().box)
                time += 100
            }
            executor.submit {}.get(5, TimeUnit.SECONDS)
            assertEquals(emptyList<String>(), sent.toList())
            assertEquals(0, dialogue)
            assertTrue(listed > 0)
        } finally {
            executor.shutdownNow()
        }
    }
}
