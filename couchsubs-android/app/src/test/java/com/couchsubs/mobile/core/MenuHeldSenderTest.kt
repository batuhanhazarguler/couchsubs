// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Menü sırasında gelen altyazı (Windows MenuPausedSenderTests ve Mac/iPhone MenuHeldSenderTests ile aynı). */
class MenuHeldSenderTest {
    private class Sink : SubtitleSender {
        val sent = mutableListOf<String>()
        var clears = 0
        override fun sendSubtitle(text: String, durationMs: Int, box: TextBox?, replaces: Boolean) { sent += text }
        override fun clear() { clears++ }
    }

    @Test
    fun menuLabelsAreNotSentAfterARealMenu() {
        val sink = Sink()
        var menu = false
        var time = 0L
        val log = mutableListOf<String>()
        val sender = MenuHeldSender(sink, { menu }, { log += it }, { time })
        sender.sendSubtitle("Bir")
        menu = true
        time = 100
        sender.sendSubtitle("RESTORE DEFAULT")
        sender.clear()
        menu = false
        time = 3000
        sender.sendSubtitle("İki")
        assertEquals(listOf("Bir", "İki"), sink.sent)
        assertEquals(1, sink.clears)
        assertTrue(log.any { it.contains("menü sırasında bekletildi") && it.contains("RESTORE DEFAULT") })
    }

    /**
     * #1240: karanlık balık tutma sahnesinde tuş ipucu ve görev yazısı birlikte belirince menü sanılıyordu; o sırada gelen
     * konuşma satırı TV'ye hiç gitmiyordu. Satır bekletilir, menü kapanınca (yeni satır gelmese de) gönderilir.
     */
    @Test
    fun dialogueDuringAFalseMenuReachesTheTv() {
        val sink = Sink()
        var menu = true
        var time = 0L
        val log = mutableListOf<String>()
        val sender = MenuHeldSender(sink, { menu }, { log += it }, { time })
        assertTrue(sender.poll())
        time = 400
        sender.sendSubtitle("Lucia: Balık yine kaçtı.")
        time = 900
        sender.sendSubtitle("Jason: Sabret biraz, gelecek.")
        assertTrue(sink.sent.isEmpty())
        menu = false
        time = 1500
        assertFalse(sender.poll())
        assertEquals(listOf("Jason: Sabret biraz, gelecek."), sink.sent)
        assertTrue(log.any { it.contains("menü kapanınca gönderildi") && it.contains("Jason") })
    }

    @Test
    fun oldHeldLineIsNotSentAfterALongMenu() {
        val sink = Sink()
        var menu = true
        var time = 0L
        val sender = MenuHeldSender(sink, { menu }, clock = { time })
        sender.sendSubtitle("Lucia: Balık yine kaçtı.")
        menu = false
        time = 10_000
        sender.poll()
        assertTrue(sink.sent.isEmpty())
    }

    @Test
    fun shortMenuSendsEveryHeldLineAtOnce() {
        val sink = Sink()
        var menu = true
        var time = 0L
        val sender = MenuHeldSender(sink, { menu }, clock = { time })
        sender.sendSubtitle("Bir")
        time = 100
        sender.sendSubtitle("İki")
        menu = false
        time = 200
        sender.poll()
        assertEquals(listOf("Bir", "İki"), sink.sent)
    }
}
