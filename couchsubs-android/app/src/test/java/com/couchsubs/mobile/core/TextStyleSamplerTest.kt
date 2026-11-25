// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Otomatik ekran yazısının özgün stili: sentetik görüntüler (Windows TextStyleSamplerTests ile aynı durumlar). */
class TextStyleSamplerTest {
    /** [ground] zeminde [ink] renkli yatay çizgiler: her 10 satırın [thick] kadarı yazı, sütunların 3/4'ü. */
    private fun image(ground: Int, ink: Int, thick: Int, width: Int = 200, height: Int = 40): GrayFrame {
        val luma = ByteArray(width * height) { index ->
            val x = index % width
            val y = index / width
            (if (y % 10 < thick && x % 4 != 0) ink else ground).toByte()
        }
        return GrayFrame(luma, width, height)
    }

    @Test
    fun lightTextOnDarkFlatBox() {
        val style = TextStyleSampler.sample(image(30, 230, 2), 0, 0, 200, 40, 10.0, "Go to the Saloon.")
        assertNotNull(style)
        assertEquals("#E6E6E6", style!!.surface.foreground)
        assertEquals("#1E1E1E", style.surface.background)
        assertTrue(style.surface.flat)
        assertFalse(style.look.bold)
        assertFalse(style.look.upper)
    }

    @Test
    fun darkTextOnLightBox() {
        val style = TextStyleSampler.sample(image(220, 20, 2), 0, 0, 200, 40, 10.0, "Photo Studio")!!
        assertEquals("#141414", style.surface.foreground)
        assertEquals("#DCDCDC", style.surface.background)
    }

    @Test
    fun boldUpperCaseHeading() {
        // Kalın yazı: pikselin ~%37'si mürekkep; dar başlık: 30 karakter 200 px'e (harf başına 6,7 px, satır 20 px).
        val style = TextStyleSampler.sample(image(30, 230, 5), 0, 0, 200, 40, 20.0, "ROB VICKI'S BOSS AND HIS CREW!")!!
        assertTrue(style.look.bold)
        assertTrue(style.look.upper)
        assertTrue(style.look.condensed)
    }

    @Test
    fun turkishUpperCase() {
        assertEquals("VİCKİ'NİN PATRONUNU SOY", TextStyleSampler.upper("vicki'nin patronunu soy"))
        assertEquals("ISIK", TextStyleSampler.upper("ışık").replace('Ş', 'S'))
        assertTrue(TextStyleSampler.isUpper("ROB VICKI'S BOSS"))
        assertFalse(TextStyleSampler.isUpper("Photo Studio"))
    }

    @Test
    fun alignmentFromLineEdges() {
        assertEquals("left", TextStyleSampler.align(listOf(0.1 to 0.5, 0.1 to 0.3)))
        assertEquals("right", TextStyleSampler.align(listOf(0.2 to 0.6, 0.4 to 0.6)))
        assertEquals("center", TextStyleSampler.align(listOf(0.2 to 0.6, 0.3 to 0.5)))
    }

    @Test
    fun noisyGroundIsNotFlat() {
        val width = 200
        val height = 40
        val luma = ByteArray(width * height) { index ->
            val x = index % width
            val y = index / width
            (if (y % 10 < 2 && x % 4 != 0) 240 else 20 + (x * 7 + y * 13) % 80).toByte()
        }
        val style = TextStyleSampler.sample(GrayFrame(luma, width, height), 0, 0, width, height, 10.0, "Go to the Saloon.")!!
        assertFalse(style.surface.flat)
    }

    /**
     * #1268 (gerçek karede "ADD MARKER"): kontur yazının zemin kümesi denizle kontur grisinin karışımı; ikisinin parlaklığı
     * aynı (125) ama rengi değil. Zemin renk sapmasıyla düz sayılmaz, yanındaki şerit de konturlu olduğundan bir şerit ötedeki
     * düz deniz zemin olur. Eskiden sapma yalnız parlaklıktan ölçülüyor, kutu grimsi çiziliyordu (Mac ve Windows ile aynı
     * görüntü).
     */
    @Test
    fun lumaFlatButColouredGroundTakesTheFarBand() {
        val width = 400
        val height = 100
        val rgb = IntArray(width * height) { index ->
            val x = index % width
            val y = index / width
            when {
                y in 30 until 70 && x % 16 < 5 -> 0xF0F0F0
                y in 20 until 80 && x % 16 in 5 until 10 -> 0x7D7D7D
                else -> 0x3A94BB
            }
        }
        val luma = ByteArray(rgb.size) { i ->
            val c = rgb[i]
            ((299 * ((c shr 16) and 0xff) + 587 * ((c shr 8) and 0xff) + 114 * (c and 0xff)) / 1000).toByte()
        }
        val style = TextStyleSampler.sample(GrayFrame(luma, width, height), 40, 30, 360, 70, 40.0, "ADD MARKER",
            color = { x, y -> rgb[y * width + x] })!!
        fun distance(hex: String, r: Int, g: Int, b: Int): Int {
            val c = hex.removePrefix("#").toInt(16)
            return maxOf(kotlin.math.abs(((c shr 16) and 0xff) - r), kotlin.math.abs(((c shr 8) and 0xff) - g),
                kotlin.math.abs((c and 0xff) - b))
        }
        assertFalse(style.surface.flat)
        assertTrue(style.surface.background, distance(style.surface.background, 58, 148, 187) <= 8)
        assertTrue(style.surface.foreground, distance(style.surface.foreground, 240, 240, 240) <= 8)
    }
}
