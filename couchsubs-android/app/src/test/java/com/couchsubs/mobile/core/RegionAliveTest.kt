// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #1268, #1270, #1271 (Mac/iPhone RegionAliveTests + ScreenTextDetectorTests + TextPaintTests, Windows RegionAliveTests
 * ile aynı): okuma turu dönmezse alanlar TV'de yenilenmez; menüde kontur yazı (haritanın tuş listesi) alan olur; harfsiz
 * simge okunuşu sözcük sayılmaz.
 */
class RegionAliveTest {
    private class Recorder : RegionSender {
        var alive = 0
        override fun sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?) {}
        override fun clearRegions() {}
        override fun regionsAlive() {
            alive++
        }
    }

    private val crop = GrayFrame(ByteArray(64 * 36) { 20 }, 64, 36)

    @Test
    fun everyPassAndAreaReportsTheWatcherAlive() {
        val recorder = Recorder()
        val watcher = RegionWatcher({ Reading.Empty }, { it }, recorder)
        watcher.onLog = {}
        val areas = listOf("a", "b").map { ExtraArea(it, it, CropRegion(top = 0.0, bottom = 0.5, left = 0.0, right = 0.5)) }
        val signature = ByteArray(RegionSignature.WIDTH * RegionSignature.HEIGHT) { 1 }
        watcher.pass(areas.map { it.id }.toSet(), areas.map { it to RegionWatcher.Crop(Unit, signature, crop) })
        // Tur başı, iki alan ve tur sonu.
        assertEquals(4, recorder.alive)
        watcher.pass(emptySet(), emptyList())
        assertEquals(6, recorder.alive)
    }

    @Test
    fun regionsAreKeptOnlyWhileTheWatcherTurns() {
        assertTrue(SubtitleServer.keepsRegions(-1, 1_000_000))
        assertTrue(SubtitleServer.keepsRegions(100_000, 100_000 + SubtitleServer.REGION_ALIVE_MS))
        assertFalse(SubtitleServer.keepsRegions(100_000, 100_001 + SubtitleServer.REGION_ALIVE_MS))
    }

    @Test
    fun letterlessTokensAreNotWords() {
        assertEquals(3, TextPainter.words("- SMASH 'N' GRABS"))
        assertEquals(1, TextPainter.words("• Objective"))
        assertEquals(1, TextPainter.words("+ CLUBS"))
        assertEquals(3, TextPainter.words("Buck's Jewelry & Pawn"))
        assertEquals(1, TextPainter.words("I Map"))
        assertEquals(2, TextPainter.words("2D VIEW"))
        assertEquals(2, TextPainter.words("\$1,000 - \$10,000"))
        val spans = listOf(0 until 20, 28 until 90, 98 until 112, 120 until 180)
        val found = TextPainter.iconSpans(0, 180, 20.0, TextPainter.words("- SMASH 'N' GRABS"), "left") { x -> spans.any { x in it } }
        assertNotNull(found.left)
        assertEquals(28, found.textLeft)
    }

    @Test
    fun outlinedTileRule() {
        assertTrue(ScreenTextDetector.outlined(48, 74))
        assertFalse(ScreenTextDetector.outlined(8, 71))
        assertFalse(ScreenTextDetector.outlined(0, 576))
        assertFalse(ScreenTextDetector.outlined(400, 100))
    }

    private class Picture(val rgb: IntArray, val width: Int, val height: Int)

    private fun mapFrame(): Picture {
        val directory = generateSequence(File(System.getProperty("user.dir")!!).absoluteFile) { it.parentFile }
            .map { File(it, "testdata/frames") }
            .first { File(it, "frames.json").isFile }
        val file = File(directory, "gta6-harita-kart.jpg")
        val buffered = Class.forName("javax.imageio.ImageIO").getMethod("read", File::class.java).invoke(null, file)
        val type = buffered.javaClass
        val width = type.getMethod("getWidth").invoke(buffered) as Int
        val height = type.getMethod("getHeight").invoke(buffered) as Int
        val rgb = type.getMethod("getRGB", Int::class.java, Int::class.java, Int::class.java, Int::class.java, IntArray::class.java,
            Int::class.java, Int::class.java).invoke(buffered, 0, 0, width, height, null, 0, width) as IntArray
        for (i in rgb.indices) rgb[i] = rgb[i] and 0xFFFFFF
        return Picture(rgb, width, height)
    }

    /**
     * Gerçek kare: tuş listesinin kutuları denizin renginde, yazı koyu lacivert (yanındaki Ⓛ3/Ⓡ3 simgesi ve taşan harf
     * konturu zemine karışmaz). Eskiden "RECENTER" ve "2D VIEW" açık gri, "ADD MARKER" grimsi (#608096) çiziliyordu
     * (Mac ile aynı vaka ve aralık; Mac: #3A94BF, #3992BE, #3A90BB).
     */
    @Test
    fun outlinedMapHintsAreDrawnInTheSeaColour() {
        val picture = mapFrame()
        val (width, height, rgb) = Triple(picture.width, picture.height, picture.rgb)
        val gray = GrayFrame(ByteArray(rgb.size) { i ->
            val c = rgb[i]
            ((299 * ((c shr 16) and 0xff) + 587 * ((c shr 8) and 0xff) + 114 * (c and 0xff)) / 1000).toByte()
        }, width, height)
        fun distance(hex: String, r: Int, g: Int, b: Int): Int {
            val c = hex.removePrefix("#").toInt(16)
            return maxOf(kotlin.math.abs(((c shr 16) and 0xff) - r), kotlin.math.abs(((c shr 8) and 0xff) - g),
                kotlin.math.abs((c and 0xff) - b))
        }
        // Kayıtlı okumanın kutuları (alan 0.812-1.0 x 0.639-1.0'a oranla).
        val lines = listOf("RECENTER" to listOf(0.378, 0.183, 0.772, 0.258), "2D VIEW" to listOf(0.450, 0.343, 0.761, 0.431),
            "ADD MARKER" to listOf(0.278, 0.507, 0.750, 0.596), "SET DESTINATION" to listOf(0.128, 0.672, 0.750, 0.759))
        for ((text, b) in lines) {
            fun x(v: Double) = ((0.812 + v * 0.188) * width).toInt()
            fun y(v: Double) = ((0.639 + v * 0.361) * height).toInt()
            val style = TextStyleSampler.sample(gray, x(b[0]), y(b[1]), x(b[2]), y(b[3]), (y(b[3]) - y(b[1])).toDouble(), text,
                color = { px, py -> rgb[py * width + px] })!!
            assertTrue("$text: ${style.surface.background}", distance(style.surface.background, 0x3A, 0x94, 0xBB) <= 24)
            assertTrue("$text: ${style.surface.foreground}", distance(style.surface.foreground, 0x1E, 0x2E, 0x3E) <= 24)
            assertFalse("$text: deniz düz zemin değil", style.surface.flat)
        }
    }

    /** Gerçek kare (testdata/frames/gta6-harita-kart.jpg): desenli açık haritanın üstündeki tuş listesi menüde alan olur. */
    @Test
    fun outlinedMapHintsOnARealMapFrameAreFound() {
        val picture = mapFrame()
        val (width, height, rgb) = Triple(picture.width, picture.height, picture.rgb)
        val detector = ScreenTextDetector()
        val sample = detector.sample(width, height) { x, y ->
            val c = rgb[y * width + x]
            (299 * ((c shr 16) and 0xff) + 587 * ((c shr 8) and 0xff) + 114 * (c and 0xff)) / 1000
        }
        var areas = emptyList<ExtraArea>()
        for (now in 0L..2000L step 100L) areas = detector.update(sample, emptyList(), now)
        assertTrue(detector.menu)
        fun holds(left: Double, top: Double, right: Double, bottom: Double) = areas.any { a ->
            a.region.left <= left && a.region.right >= right && a.region.top <= top && a.region.bottom >= bottom
        }
        assertTrue("tuş listesi: ${areas.map { it.region }}", holds(0.84, 0.70, 0.98, 0.97))
    }
}
