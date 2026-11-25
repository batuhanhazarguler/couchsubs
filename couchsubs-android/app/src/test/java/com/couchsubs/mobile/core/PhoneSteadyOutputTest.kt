// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * GTA 6 telefonunun çevirisi kararlı (X, 22 Kas: "sağ tarafta kutu çıkarıyorsun ama her saniye şekli de hareketi de
 * değişiyor"): aynı ekran gürültülü okunsa da (bir harf, birkaç piksel, telefon bir an kaybolup geri gelse de) çizilen
 * Türkçe birebir aynı kalır; aynı mesaj bir kez yazılır, yeniden çevrilmez; yeni mesajda yalnız o balon eklenir. Mac/iPhone
 * (PhoneSteadyOutputTests.swift) ve Windows (PhoneSteadyOutputTests.cs) aynı durumları sınar. Metinler uydurmadır.
 */
class PhoneSteadyOutputTest {
    private class Reader {
        @Volatile var lines: List<TextLine> = emptyList()
        fun read(): Reading = Reading(lines)
    }

    /** Her çağrıda başka Türkçe veren motor (yapay zekâ gibi): aynı mesaj yeniden çevrilirse ekrandaki yazı değişir. */
    private class Translator : TextTranslator {
        override val translatesTogether: Boolean get() = true
        val calls = java.util.Collections.synchronizedList(mutableListOf<String>())
        override fun translate(text: String): String {
            calls.add(text)
            return "Çeviri ${calls.size}: $text"
        }
    }

    private class Server : RegionSender {
        val sent = java.util.Collections.synchronizedList(mutableListOf<List<ScreenTranslation.Item>>())
        override fun sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?) = sendRegion(id, text, box, lineHeight, null, null)
        override fun sendRegion(
            id: String, text: String, box: TextBox?, lineHeight: Double?, icons: List<IconPlacement>?, blocks: List<ScreenTranslation.Item>?,
        ) {
            sent.add(blocks ?: emptyList())
        }
        override fun clearRegions() {}
    }

    private val work = java.util.concurrent.Executors.newSingleThreadExecutor { Thread(it).apply { isDaemon = true } }
    @Volatile private var clock = 0L

    private fun wait(done: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 5000
        while (!done()) {
            check(System.currentTimeMillis() < deadline) { "zaman aşımı" }
            Thread.sleep(1)
        }
    }

    private fun watcher(reader: Reader, translator: Translator, server: Server) =
        RegionWatcher({ reader.read() }, translator, server, clock = { clock }, readPhone = { reader.read() })

    private fun RegionWatcher.offer() = offer(emptyList(), {
        RegionWatcher.Crop(Unit, ByteArray(RegionSignature.WIDTH * RegionSignature.HEIGHT))
    }) { work.execute(it) }

    private fun RegionWatcher.turn(image: PhoneImage, pose: GamePhoneGeometry.Pose) {
        observePhone(PhoneCapture(image, pose))
        offer()
        wait { !isBusy }
    }

    companion object {
        private const val FIRST = "Are you coming to the barbecue tonight?"
        private const val SECOND = "Bring the folding chairs from the garage."
        private const val THIRD = "Sure, I will be there around eight."

        private fun box(top: Double, left: Double, shift: Double = 0.0) =
            TextBox(left + shift, top + shift, left + 0.50 + shift, top + 0.06 + shift)

        private fun chat(first: String = FIRST, second: String = SECOND, shift: Double = 0.0) =
            listOf(TextLine(first, box(0.30, 0.05, shift)), TextLine(second, box(0.50, 0.45, shift)))

        private fun picture(items: List<ScreenTranslation.Item>) = items.map { "${it.panel}|${it.translation}|${it.lineHeight}" }

        private fun item(source: String, translation: String, top: Double = 0.3, line: Double = 0.02,
                         role: ScreenPhoneCard.Role? = ScreenPhoneCard.Role.INCOMING) =
            ScreenTranslation.Item(source, translation, TextBox(0.6, top, 0.8, top + 0.05), line,
                phone = role?.let { ScreenPhoneCard.Placement(it, TextBox(0.1, top, 0.9, top + 0.05)) })
    }

    @Test
    fun noisyReadingsKeepTheSidePanelIdentical() {
        val reader = Reader()
        val translator = Translator()
        val server = Server()
        val watcher = watcher(reader, translator, server)
        val pose = GamePhoneGeometry.locate(TestPhoneImage.phone())!!
        // Sallanan telefonun kareleri: yazının pikselleri her karede biraz başka yerde, telefon her turda yeniden okunur.
        val frames = (0 until 6).map { TestPhoneImage.phone(patch = intArrayOf(168 + 10 * it, 94, 8, 12)) }
        reader.lines = chat()
        watcher.turn(frames[0], pose)
        val shown = server.sent.last()
        val card = shown.first { it.panel == ScreenPhoneCard.PanelPart.CARD }
        assertEquals(2, shown.count { it.panel == ScreenPhoneCard.PanelPart.THEIRS || it.panel == ScreenPhoneCard.PanelPart.MINE })

        // Gürültülü okumalar: bir harf oynuyor, rakamlı sözcük atılıyor, soru işareti kaçıyor, kutular birkaç piksel kayıyor,
        // bir okumada ilk mesaj iki kez geliyor, bir okumada da telefon bir an kayboluyor.
        val noisy = listOf(
            chat("Are you cominq to the barbecue tonight?", shift = 0.004),
            chat(FIRST, "Bring the fo1ding chairs from the garage.", shift = -0.004),
            listOf(TextLine(FIRST, box(0.30, 0.05)), TextLine(FIRST, box(0.37, 0.05)), TextLine(SECOND, box(0.50, 0.45))),
            listOf(TextLine(FIRST, box(0.30, 0.05)), TextLine(FIRST, box(0.40, 0.05)), TextLine(SECOND, box(0.50, 0.45))),
            chat("Are you coming to the barbecue tonight", shift = 0.003),
        )
        for ((index, lines) in noisy.withIndex()) {
            clock += 450
            reader.lines = lines
            watcher.turn(frames[(index + 1) % frames.size], pose)
            if (index == 2) {
                // Telefon bir an kayboldu (izleyici kapattı) ve geri geldi.
                watcher.closePhone()
                clock += 450
                watcher.turn(frames[index % frames.size], pose)
            }
        }
        val pictures = server.sent.filter { it.isNotEmpty() }
        for (sent in pictures) {
            assertEquals("aynı ekranda çizilen Türkçe birebir aynı", picture(shown), picture(sent))
            assertEquals("kartın yeri ve boyu aynı", card.box, sent.first { it.panel == ScreenPhoneCard.PanelPart.CARD }.box)
        }
        assertEquals("her mesaj bir kez çevrilir: ${translator.calls}", 2, translator.calls.size)
    }

    @Test
    fun newMessageAddsOnlyItsBubble() {
        val reader = Reader()
        val translator = Translator()
        val server = Server()
        val watcher = watcher(reader, translator, server)
        val pose = GamePhoneGeometry.locate(TestPhoneImage.phone())!!
        reader.lines = chat()
        watcher.turn(TestPhoneImage.phone(), pose)
        val message = { item: ScreenTranslation.Item ->
            item.panel == ScreenPhoneCard.PanelPart.THEIRS || item.panel == ScreenPhoneCard.PanelPart.MINE
        }
        val before = server.sent.last().filter(message)

        // Sohbet yukarı kaydı, yeni mesaj altta.
        reader.lines = chat(shift = -0.08) + TextLine(THIRD, box(0.62, 0.05))
        clock = 450
        watcher.turn(TestPhoneImage.phone(patch = intArrayOf(170, 150, 20, 12)), pose)
        val after = server.sent.last().filter(message)
        assertEquals(3, after.size)
        assertEquals("eski balonlar aynı", before.map { it.translation }, after.take(2).map { it.translation })
        assertEquals("gruptaki bütün balonlar aynı boyda", 1, after.map { it.lineHeight }.toSet().size)
        assertEquals("yazı boyu değişmez", before[0].lineHeight, after[0].lineHeight, 0.0)
        assertEquals(listOf(FIRST, SECOND, THIRD), translator.calls.toList())
    }

    @Test
    fun bubblesOnTopShareOneTextSize() {
        val reader = Reader()
        val translator = Translator()
        val server = Server()
        val watcher = watcher(reader, translator, server).apply { phonePanel = { PhonePanelOptions(enabled = false) } }
        val pose = GamePhoneGeometry.locate(TestPhoneImage.phone())!!
        val lines = chat().toMutableList()
        lines[1] = lines[1].copy(box = TextBox(0.45, 0.50, 0.95, 0.575))
        reader.lines = lines.toList()
        watcher.turn(TestPhoneImage.phone(), pose)
        val first = server.sent.last()
        assertEquals(2, first.size)
        assertEquals("iki balon aynı yazı boyunda", 1, first.map { it.lineHeight }.toSet().size)

        // Aynı ekran biraz farklı satır yüksekliğiyle okunur: yazı boyu değişmez.
        lines[0] = lines[0].copy(box = TextBox(0.05, 0.30, 0.55, 0.368))
        reader.lines = lines.toList()
        clock = 450
        watcher.turn(TestPhoneImage.phone(patch = intArrayOf(170, 94, 10, 12)), pose)
        assertEquals(first.map { it.lineHeight }, server.sent.last().map { it.lineHeight })
    }

    @Test
    fun sameMessageIsWrittenOnce() {
        val items = listOf(item(FIRST, "A"), item("Are you cominq to the barbecue tonight?", "B", 0.4), item(SECOND, "C", 0.5))
        assertEquals(listOf("A", "C"), PhoneSteady.withoutRepeats(items).map { it.translation })
        assertEquals(3, PhoneSteady.withoutRepeats(listOf(item("Ok", "Tamam"), item(SECOND, "C", 0.4), item("Ok", "Tamam", 0.5))).size)
        assertEquals(1, PhoneSteady.withoutRepeats(listOf(item("Ok", "Tamam"), item("Ok", "Tamam", 0.4))).size)
        val far = listOf(item(FIRST, "A"), item(SECOND, "C", 0.4), item(FIRST, "A", 0.5))
        assertEquals(listOf("A", "C"), PhoneSteady.withoutRepeats(far).map { it.translation })
        assertEquals(2, PhoneSteady.withoutRepeats(listOf(item("Ok", "x", role = null), item("Ok", "x", role = null))).size)
    }

    @Test
    fun shownTranslationIsKeptForTheSameMessage() {
        val previous = listOf(item(FIRST, "Bu akşam mangala geliyor musun?"))
        val fresh = listOf(item("Are you cominq to the barbecue tonight?", "Bu gece mangala gelir misin?"),
            item(SECOND, "Katlanır sandalyeleri getir.", 0.5))
        val kept = PhoneSteady.keptTranslations(fresh, previous)
        assertEquals(listOf("Bu akşam mangala geliyor musun?", "Katlanır sandalyeleri getir."), kept.map { it.translation })
        assertEquals(FIRST, kept[0].source)
        assertEquals(listOf("6'da"), PhoneSteady.keptTranslations(listOf(item("Meet me at the station at 6", "6'da")),
            listOf(item("Meet me at the station at 5", "5'te"))).map { it.translation })
        assertEquals("Sandalyeleri getir.", PhoneSteady.shownTranslation("Bring the chairs from the garage.",
            TextBox(0.1, 0.5, 0.9, 0.55), listOf(item(SECOND, "Sandalyeleri getir.", 0.5))))
        assertNull(PhoneSteady.shownTranslation("Bring the chairs from the garage.", TextBox(0.1, 0.2, 0.9, 0.25),
            listOf(item(SECOND, "Sandalyeleri getir.", 0.5))))
        assertTrue(PhoneSteady.sameReading(FIRST, "Are you coming to the barbecue tonight"))
        assertFalse(PhoneSteady.sameReading("Ok?", "Ok."))
    }

    @Test
    fun messageBubblesShareTheLockedLine() {
        val items = listOf(item("Rose", "Rose", line = 0.03, role = ScreenPhoneCard.Role.HEADER), item(FIRST, "A", line = 0.018),
            item(SECOND, "B", line = 0.023), item("x", "x", line = 0.05, role = null))
        assertEquals(listOf(0.03, 0.02, 0.02, 0.05), PhoneSteady.uniformLine(items, 0.02).map { it.lineHeight })
    }

    @Test
    fun cardDoesNotShrinkWhileThePhoneStays() {
        fun card(bottom: Double, left: Double = 0.7) = ScreenTranslation.Item("", ScreenPhoneCard.BACKDROP_TEXT,
            TextBox(left, 0.2, left + 0.2, bottom), 0.02, panel = ScreenPhoneCard.PanelPart.CARD)
        assertEquals(0.8, PhoneSteady.steadyCard(listOf(card(0.7)), listOf(card(0.8)))[0].box.bottom, 0.0)
        assertEquals(0.9, PhoneSteady.steadyCard(listOf(card(0.9)), listOf(card(0.8)))[0].box.bottom, 0.0)
        assertEquals(0.7, PhoneSteady.steadyCard(listOf(card(0.7, 0.6)), listOf(card(0.8)))[0].box.bottom, 0.0)
    }

    @Test
    fun repeatedTextIsCollapsed() {
        assertEquals("Grab some ice on the way.", GamePhoneText.withoutRepeat("Grab some ice on the way. Grab some ice on the way."))
        assertEquals("Yolda buz al.", GamePhoneText.withoutRepeat("Yolda buz al. Yolda buz al."))
        assertEquals("no no", GamePhoneText.withoutRepeat("no no"))
        assertEquals("Call me at 5. Call me at 6.", GamePhoneText.withoutRepeat("Call me at 5. Call me at 6."))
        val lines = listOf(TextLine("Grab some ice on the way", TextBox(0.05, 0.3, 0.55, 0.34)),
            TextLine("Grab some ice on the way", TextBox(0.05, 0.34, 0.55, 0.38)),
            TextLine("and some plates", TextBox(0.05, 0.38, 0.55, 0.42)))
        assertEquals(listOf("Grab some ice on the way", "and some plates"), GamePhoneText.withoutRepeatedLines(lines).map { it.text })
    }

    @Test
    fun panelRemembersItsTextSizeAndFollowsAMoveWithTheSameSize() {
        val still = GamePhoneGeometry.Pose(0.5, 0.19, 0.5, 0.87)
        val steady = PhonePanelSteady()
        steady.steadyPose(still, 0)
        assertEquals(0.02, steady.steadyLine(0.02, 0)!!, 0.0)
        steady.reset()
        val back = steady.steadyPose(GamePhoneGeometry.Pose(0.505, 0.2, 0.505, 0.885), 450)
        assertFalse(back.resized)
        assertEquals(0.02, steady.steadyLine(0.024, 450)!!, 0.0)
        val moved = GamePhoneGeometry.Pose(0.30, 0.21, 0.31, 0.91)
        steady.steadyPose(moved, 900)
        val placed = steady.steadyPose(moved, 1950)
        assertFalse(placed.resized)
        assertEquals(0.885 - 0.2, placed.pose.bottomY - placed.pose.topY, 1e-9)
        assertEquals((moved.bounds.left + moved.bounds.right) / 2, (placed.pose.bounds.left + placed.pose.bounds.right) / 2, 1e-9)
        steady.forget()
        assertTrue(steady.steadyPose(still, 2400).resized)
    }

    @Test
    fun memoryKeepsTranslationsAndForgetsTheOldest() {
        val memory = PhoneMemory()
        memory.remember(FIRST, "Bu akşam mangala geliyor musun?")
        assertEquals("Bu akşam mangala geliyor musun?", memory.translation("Are you cominq to the barbecue tonight?"))
        for (i in 0 until PhoneMemory.CAPACITY) memory.remember("Message number $i about the party", "$i")
        assertFalse(memory.knows(FIRST))
        assertEquals(PhoneMemory.CAPACITY, memory.known.size)
        memory.clear()
        assertTrue(memory.known.isEmpty())
    }
}
