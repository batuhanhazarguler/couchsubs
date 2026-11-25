// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.abs

/**
 * Çizim kipinin gerçek karelerde seçimi ([TextPaint.mode]): yazı tanıma yok, yazıların yeri sabit (karede, kenarlara
 * oranla); stil [TextStyleSampler]'dan, ölçüm [TextPainter]'dan. Ortak vakalar fixtures/text-paint-modes.json (Mac
 * TextPaintModeFrameTests.swift, Windows TextPaintModeFrameTests.cs aynı kareler ve beklentiler).
 */
class TextPaintModeFrameTest {
    private class Picture(val rgb: IntArray, val width: Int, val height: Int)

    private fun frame(name: String): Picture {
        val directory = generateSequence(File(System.getProperty("user.dir")!!).absoluteFile) { it.parentFile }
            .map { File(it, "testdata/frames") }
            .first { File(it, "frames.json").isFile }
        val file = File(directory, name)
        val buffered = Class.forName("javax.imageio.ImageIO").getMethod("read", File::class.java).invoke(null, file)
        val type = buffered.javaClass
        val width = type.getMethod("getWidth").invoke(buffered) as Int
        val height = type.getMethod("getHeight").invoke(buffered) as Int
        val rgb = type.getMethod("getRGB", Int::class.java, Int::class.java, Int::class.java, Int::class.java, IntArray::class.java,
            Int::class.java, Int::class.java).invoke(buffered, 0, 0, width, height, null, 0, width) as IntArray
        for (i in rgb.indices) rgb[i] = rgb[i] and 0xFFFFFF
        return Picture(rgb, width, height)
    }

    @Test
    fun realFrameModes() {
        val frames = JSONObject(Fixtures.text("text-paint-modes.json")).getJSONArray("frames")
        for (f in 0 until frames.length()) {
            val vector = frames.getJSONObject(f)
            val picture = frame(vector.getString("file"))
            val width = picture.width
            val height = picture.height
            val rgb = picture.rgb
            val color = { x: Int, y: Int -> rgb[y.coerceIn(0, height - 1) * width + x.coerceIn(0, width - 1)] }
            val gray = GrayFrame(ByteArray(rgb.size) { i ->
                val c = rgb[i]
                ((299 * ((c shr 16) and 0xff) + 587 * ((c shr 8) and 0xff) + 114 * (c and 0xff)) / 1000).toByte()
            }, width, height)
            val raw = vector.getJSONArray("targets")
            val boxes = (0 until raw.length()).map { k ->
                val b = raw.getJSONObject(k).getJSONArray("box")
                TextBox(b.getDouble(0), b.getDouble(1), b.getDouble(2), b.getDouble(3))
            }
            val targets = (0 until raw.length()).map { k ->
                val t = raw.getJSONObject(k)
                val box = boxes[k]
                val text = t.getString("text")
                val x0 = (box.left * width).toInt()
                val y0 = (box.top * height).toInt()
                val x1 = kotlin.math.ceil(box.right * width).toInt()
                val y1 = kotlin.math.ceil(box.bottom * height).toInt()
                val style = TextStyleSampler.sample(gray, x0, y0, x1, y1, (y1 - y0).toDouble(), text, color = color)!!
                TextPainter.Target(box, box.bottom - box.top, 1, style.surface.background, style.surface.foreground,
                    style.look.upper, style.look.align, TextPainter.words(text),
                    if (t.has("kind")) ScreenTextKind.valueOf(t.getString("kind").uppercase()) else null, t.optBoolean("prompt", false))
            }
            val paints = TextPainter.paints(targets, gray, color)
            val expects = vector.getJSONArray("expect")
            val id = vector.getString("id")
            assertEquals(id, expects.length(), paints.size)
            for (k in 0 until minOf(paints.size, expects.length())) {
                val expect = expects.getJSONObject(k)
                val paint = paints[k]
                val name = "$id#$k"
                assertEquals(name, expect.getString("mode"), paint.mode)
                if (expect.has("portrait")) assertEquals("$name resim", expect.getBoolean("portrait"), paint.portrait != null)
                val twin = paint.twin
                if (expect.has("twinAbove") && twin != null) assertEquals("$name ikiz üstte", expect.getBoolean("twinAbove"), twin.bottom <= boxes[k].top)
                // İkiz (Sinan Bey, #1296): özgünden belirgin küçük, sol kenarı hizalı, özgün paneli örtmez.
                val spot = paint.spot
                if (paint.mode == TextPaint.MODE_TWIN && twin != null && spot != null) {
                    assertTrue(name, paint.scale >= TextPainter.TWIN_SCALE - 0.001 && paint.scale <= 1.0)
                    assertTrue(name, paint.scale >= 1.0 || ScreenFit.EXACT_FONT * (boxes[k].bottom - boxes[k].top) * paint.scale >= TextPainter.TWIN_MIN_SHARE - 0.002)
                    assertTrue(name, abs((spot.bottom - spot.top) / (paint.cover.bottom - paint.cover.top) - paint.scale) <= 0.05)
                    assertTrue(name, twin.left < paint.cover.left)
                    assertTrue(name, twin.bottom <= paint.cover.top || twin.top >= paint.cover.bottom)
                    assertTrue(name, paint.radius > 0)
                    if (paint.portrait != null) assertTrue("$name resim kesilir", TextPainter.portraitImage(paint.portrait!!, width, height, color)
                        ?.startsWith("data:image/png;base64,") == true)
                }
                // Yanına yazma (Sinan Bey: "SELAMLA  GREET"): aynı satırda, aynı yükseklikte, özgünün solunda.
                if (paint.mode == TextPaint.MODE_BESIDE && spot != null) {
                    assertEquals(name, paint.cover.top, spot.top, 1e-9)
                    assertEquals(name, paint.cover.bottom, spot.bottom, 1e-9)
                    assertTrue(name, spot.right <= paint.cover.left)
                }
            }
        }
    }
}
