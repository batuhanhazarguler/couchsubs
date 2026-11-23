// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Ekran yazısı çevirisinin takibi ([ScreenPresence]): özgün yazı kalkınca çeviri aynı karede kalkar, titreme yok. Ortak deneme
 * dosyası fixtures/screen-presence.json (Mac ScreenPresenceTests.swift ve Windows ScreenPresenceTests.cs aynı vakalar).
 */
class ScreenPresenceTest {
    private fun item(source: String, tracked: Boolean, left: Double = 0.1) = ScreenTranslation.Item(
        source = source, translation = "TR $source", box = TextBox(left, 0.1, left + 0.2, 0.15), lineHeight = 0.04,
        surface = TextSurface("#1E1E1E", "#E6E6E6"), look = TextLook(false, false, "left", true), bubble = !tracked,
    )

    @Test
    fun sharedPresenceVectors() {
        val cases = JSONObject(Fixtures.text("screen-presence.json")).getJSONArray("cases")
        for (c in 0 until cases.length()) {
            val vector = cases.getJSONObject(c)
            val name = vector.getString("name")
            val entries = vector.getJSONArray("items")
            val items = (0 until entries.length()).map { i ->
                val entry = entries.getJSONObject(i)
                item(entry.getString("source"), entry.getBoolean("tracked"), 0.1 + 0.25 * i)
            }
            val presence = ScreenPresence()
            val frames = vector.getJSONArray("frames")
            for (f in 0 until frames.length()) {
                val frame = frames.getJSONObject(f)
                val patches = frame.getJSONArray("patches")
                val got = presence.visible(items) { box ->
                    val patch = patches.opt(items.indexOfFirst { it.box == box })
                    (patch as? JSONArray)?.let { array -> (0 until array.length()).map { array.getInt(it) } }
                }
                val expect = frame.getJSONArray("expect").let { array -> (0 until array.length()).map { array.getBoolean(it) } }
                assertEquals("$name #$f", expect, got)
            }
        }
    }

    /** Sunucu: özgün yazısı kalkan öğe TV'ye giden `screen` olayından aynı karede düşer, geri gelince döner. */
    @Test
    fun serverDropsTranslationWhoseTextLeft() {
        val server = SubtitleServer(0)
        val events = mutableListOf<List<ScreenTranslation.Item>>()
        server.onEvent = { event -> if (event is SubtitleEvent.Screen) events.add(event.items) }
        val items = listOf(item("MAP", true), item("BRIEF", true, 0.4))
        server.sendScreen(items, 10_000)
        val text = (0 until ScreenPresence.COLS * ScreenPresence.ROWS).map { if (it % 5 == 0) 230 else 30 }
        val flat = List(text.size) { 30 }
        server.observe { text }
        assertEquals(1, events.size)
        server.observe { box -> if (box.left < 0.3) flat else text }
        assertEquals(listOf("BRIEF"), events.last().map { it.source })
        server.sendScreen(items, 10_000)
        assertEquals(listOf("BRIEF"), events.last().map { it.source })
        server.observe { text }
        server.observe { text }
        assertEquals(listOf("MAP", "BRIEF"), events.last().map { it.source })
    }
}
