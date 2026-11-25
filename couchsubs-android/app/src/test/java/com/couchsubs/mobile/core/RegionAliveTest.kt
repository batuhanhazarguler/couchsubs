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

    /** Gerçek kare (testdata/frames/gta6-harita-kart.jpg): desenli açık haritanın üstündeki tuş listesi menüde alan olur. */
    @Test
    fun outlinedMapHintsOnARealMapFrameAreFound() {
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
