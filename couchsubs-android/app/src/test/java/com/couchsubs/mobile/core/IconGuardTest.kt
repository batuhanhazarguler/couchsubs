// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Çeviri kutusu tuş simgesinin (△ ○ ✕ □, R2, L1) üstüne binmez (#1203; Mac IconGuardTests.swift, Windows IconGuardTests.cs).
 * Okunmuş simge ("A Turn Off", "[] Map") ipucu sayılır; uzun çeviri yana genişlemez, kenar payı alanın dışına çıkmaz.
 */
class IconGuardTest {
    @Test
    fun readIconAtTheStartIsAPrompt() {
        for (line in listOf("A Turn Off", "[] Map", "() Back", "Δ Pick Up", "Turn Off △")) {
            assertTrue(line, ButtonPrompts.isPrompt(line))
        }
        for (line in listOf("A little help here", "A Turn Off.", "A man walks into a bar", "A", "A LIBERTY CITY MEMOIR")) {
            assertFalse(line, ButtonPrompts.isPrompt(line))
        }
    }

    @Test
    fun longTranslationNeverWidens() {
        val measure = { text: String -> text.length * 10.0 }
        for ((text, rows) in listOf("YÜKLEME DONANIMI" to 1, "NİŞAN AL / ETKİLEŞİME GEÇ" to 1, "Sahil güvenlik gelmeden marinada buluş" to 2)) {
            val fit = ScreenFit.lines(text, 70.0, rows, measure = measure)
            assertTrue(text, fit.lines.maxOf(measure) * fit.scale * fit.squeeze <= 70.01)
            assertTrue(text, fit.scale >= ScreenFit.LAST_SCALE)
        }
        val pads = ScreenFit.pads(100.0, 70.0, 100.0 to 172.0, 6.0)
        assertEquals(0.0, pads.first, 1e-9)
        assertEquals(2.0, pads.second, 1e-9)
    }
}
