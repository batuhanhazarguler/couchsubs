// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Yerinde birebir çizim: göndericinin kareden ölçtükleri ([TextPainter]: örtü kutusu, zemin/degrade/desen, boş alan,
 * grup) ve çizicilerin ortak yerleşimi ([ScreenFit.exact]). Ortak deneme dosyası fixtures/text-paint.json (Mac
 * TextPaintTests.swift, Windows TextPaintTests.cs ve TV scripts/tv-exact-fit.test.js aynı vakalar).
 */
class TextPaintTest {
    private val fixture = JSONObject(Fixtures.text("text-paint.json"))

    private fun doubles(array: JSONArray) = (0 until array.length()).map { array.getDouble(it) }

    private fun near(a: Double, b: Double, tolerance: Double, name: String) =
        assertTrue("$name: $a ≠ $b", abs(a - b) <= tolerance)

    /** Renkler kanal başına en çok 4 farklı. */
    private fun nearColor(a: String, b: String) = TextPainter.distance(TextPainter.rgb(a), TextPainter.rgb(b)) <= 4

    /** Yapay karenin noktası (0xRRGGBB): zemin, üstüne sırayla çizilen dikdörtgenler. */
    private fun pixel(frame: JSONObject, x: Int, y: Int): Int {
        val rects = frame.getJSONArray("rects")
        for (k in rects.length() - 1 downTo 0) {
            val rect = rects.getJSONObject(k)
            val b = doubles(rect.getJSONArray("box"))
            if (x >= b[0] && x < b[2] && y >= b[1] && y < b[3]) return pack(TextPainter.rgb(rect.getString("color")))
        }
        val background = frame.getJSONObject("background")
        val from = TextPainter.rgb(background.getString("from"))
        val to = TextPainter.rgb(background.optString("to", background.getString("from")))
        fun round(v: Double) = if (v >= 0) kotlin.math.floor(v + 0.5).toInt() else -kotlin.math.floor(-v + 0.5).toInt()
        fun mix(f: Double) = pack(TextPainter.Rgb(round(from.r + (to.r - from.r) * f), round(from.g + (to.g - from.g) * f),
            round(from.b + (to.b - from.b) * f)))
        val width = frame.getInt("width")
        val height = frame.getInt("height")
        return when (background.getString("kind")) {
            "h" -> mix(x.toDouble() / (width - 1))
            "v" -> mix(y.toDouble() / (height - 1))
            "checker" -> {
                val cell = background.optInt("cell", 6)
                if ((x / cell + y / cell) % 2 == 0) pack(from) else pack(to)
            }
            else -> pack(from)
        }
    }

    private fun pack(c: TextPainter.Rgb) = (c.r shl 16) or (c.g shl 8) or c.b

    @Test
    fun sharedPaintVectors() {
        val frames = fixture.getJSONArray("paint")
        for (f in 0 until frames.length()) {
            val frame = frames.getJSONObject(f)
            val width = frame.getInt("width")
            val height = frame.getInt("height")
            val w = width.toDouble()
            val h = height.toDouble()
            val raw = frame.getJSONArray("targets")
            val targets = (0 until raw.length()).map { k ->
                val t = raw.getJSONObject(k)
                val b = doubles(t.getJSONArray("box"))
                TextPainter.Target(TextBox(b[0] / w, b[1] / h, b[2] / w, b[3] / h), t.getDouble("line") / h, t.getInt("rows"),
                    t.getString("bg"), t.getString("fg"), t.getBoolean("upper"), t.getString("align"), t.optInt("words", 0))
            }
            val paints = TextPainter.paints(targets, width, height) { x, y -> pixel(frame, x, y) }
            val expects = frame.getJSONArray("expect")
            val id = frame.getString("id")
            assertEquals(id, expects.length(), paints.size)
            for (k in 0 until minOf(expects.length(), paints.size)) {
                val expect = expects.getJSONObject(k)
                val paint = paints[k]
                val name = "$id#$k"
                if (expect.has("cover")) {
                    val got = listOf(paint.cover.left * w, paint.cover.top * h, paint.cover.right * w, paint.cover.bottom * h)
                    got.zip(doubles(expect.getJSONArray("cover"))).forEach { (a, b) -> near(a, b, 1.01, "$name örtü $got") }
                }
                if (expect.has("bg")) assertTrue("$name zemin ${paint.background} ≠ ${expect.getString("bg")}",
                    nearColor(paint.background, expect.getString("bg")))
                if (expect.has("bg2")) {
                    if (expect.isNull("bg2")) assertNull(name, paint.background2)
                    else assertTrue("$name bg2 ${paint.background2}", paint.background2?.let { nearColor(it, expect.getString("bg2")) } ?: false)
                }
                if (expect.has("bgDir")) assertEquals(name, expect.getString("bgDir"), paint.direction)
                if (expect.has("patterned")) assertEquals(name, expect.getBoolean("patterned"), paint.patterned)
                if (expect.has("grow")) {
                    if (expect.isNull("grow")) assertNull(name, paint.grow)
                    else {
                        val grow = doubles(expect.getJSONArray("grow"))
                        assertNotNull(name, paint.grow)
                        near((paint.grow?.left ?: -1.0) * w, grow[0], 1.01, "$name uzama solu")
                        near((paint.grow?.right ?: -1.0) * w, grow[1], 1.01, "$name uzama sağı")
                    }
                }
                if (expect.has("group")) assertEquals(name, if (expect.isNull("group")) null else expect.getInt("group"), paint.group)
                if (expect.has("pitch")) near(paint.pitch * h, expect.getDouble("pitch"), 0.5, "$name satır aralığı")
                if (expect.has("side")) {
                    val want = if (expect.isNull("side")) null else expect.getString("side")
                    assertEquals("$name simge yanı", want, paint.iconSide)
                }
            }
        }
    }

    private fun exactVector(id: String): JSONObject {
        val list = fixture.getJSONArray("exact")
        return (0 until list.length()).map { list.getJSONObject(it) }.first { it.getString("id") == id }
    }

    private fun exactInputs(vector: JSONObject): List<ScreenFit.ExactInput> {
        val items = vector.getJSONArray("items")
        return (0 until items.length()).map { k ->
            val item = items.getJSONObject(k)
            val box = doubles(item.getJSONArray("box"))
            val grow = if (item.has("grow") && !item.isNull("grow")) doubles(item.getJSONArray("grow")) else null
            ScreenFit.ExactInput(item.getString("text"), box[0], box[1], box[2], box[3], grow?.get(0), grow?.get(1),
                item.getDouble("line"), if (item.has("pitch") && !item.isNull("pitch")) item.getDouble("pitch") else null,
                item.optInt("rows", 1), item.getString("align"),
                if (item.has("group") && !item.isNull("group")) item.getInt("group") else null)
        }
    }

    private fun placed(vector: JSONObject): List<ScreenFit.ExactPlacement> {
        val charWidth = vector.getDouble("charWidth")
        return ScreenFit.exact(exactInputs(vector)) { text, size -> text.length * charWidth * size }
    }

    @Test
    fun sharedExactVectors() {
        val list = fixture.getJSONArray("exact")
        for (v in 0 until list.length()) {
            val vector = list.getJSONObject(v)
            if (!vector.has("expect")) continue
            val placed = placed(vector)
            val expect = vector.getJSONArray("expect")
            val id = vector.getString("id")
            assertEquals(id, expect.length(), placed.size)
            for (k in 0 until minOf(expect.length(), placed.size)) {
                val e = expect.getJSONObject(k)
                val p = placed[k]
                val lines = e.getJSONArray("lines").let { a -> (0 until a.length()).map { a.getString(it) } }
                val name = "$id $lines"
                assertEquals(name, lines, p.lines)
                near(p.left, e.getDouble("left"), 0.05, "$name sol")
                near(p.top, e.getDouble("top"), 0.05, "$name üst")
                near(p.width, e.getDouble("width"), 0.05, "$name genişlik")
                near(p.height, e.getDouble("height"), 0.05, "$name yükseklik")
                near(p.fontSize, e.getDouble("fontSize"), 0.05, "$name yazı boyu")
                near(p.lineHeight, e.getDouble("lineHeight"), 0.05, "$name satır aralığı")
                near(p.rowHeight, e.getDouble("rowHeight"), 0.05, "$name satır yüksekliği")
            }
        }
    }

    /**
     * Kurallar ortak dosyadan bağımsız da: grup içinde yazı boyu eşit, uzun çeviri boş alana uzar, kutu simgeye/ekran
     * kenarına taşmaz, yazı kesilmez.
     */
    @Test
    fun groupKeepsOneSizeAndGrowsIntoFreeSide() {
        val vector = exactVector("grup-esit-boy-bos-alana-uzar")
        val inputs = exactInputs(vector)
        val placed = placed(vector)
        assertEquals("grubun yazı boyu tek", 1, placed.map { (it.fontSize * 100).roundToInt() }.toSet().size)
        for ((input, p) in inputs.zip(placed)) {
            assertEquals("yazı kesilmez", input.text, p.lines.joinToString(" "))
            near(p.left + p.width, input.right, 0.01, "sağ kenar (simge tarafı) yerinde")
            assertTrue("boş alanın dışına taşmaz", p.left >= input.growLeft - 0.01)
            assertEquals("boş alan varken satır kırılmaz", 1, p.lines.size)
        }
        // "HEDEF BELİRLE" kendi kutusundan uzun: boş sol tarafa uzar, yazı boyu küçülmez.
        assertTrue(placed[3].left < inputs[3].left)
        near(placed[3].fontSize, ScreenFit.EXACT_FONT * 20, 0.01, "yazı boyu")
    }

    @Test
    fun wholeGroupShrinksTogetherWhenNoRoom() {
        val vector = exactVector("bos-alan-yok-grup-birlikte-kuculur")
        val inputs = exactInputs(vector)
        val placed = placed(vector)
        assertEquals("grup birlikte küçülür", 1, placed.map { (it.fontSize * 100).roundToInt() }.toSet().size)
        assertTrue(placed[0].fontSize < ScreenFit.EXACT_FONT * 20)
        for ((input, p) in inputs.zip(placed)) {
            assertTrue(p.left >= input.growLeft - 0.01)
            assertTrue(p.left + p.width <= input.growRight + 0.01)
            assertEquals(input.text, p.lines.joinToString(" "))
        }
    }

    /**
     * Gerçek kare (testdata/frames/gta6-menu-harita.jpg): harita ipuçları tek grup, sağa yaslı; uzun çeviri boş sola
     * uzar; zemin mavi degradenin rengi (koyu kutu değil). Mac testRealMapHints ile aynı kutular.
     */
    @Test
    fun realMapHints() {
        val directory = generateSequence(File(System.getProperty("user.dir")!!).absoluteFile) { it.parentFile }
            .map { File(it, "testdata/frames") }
            .first { File(it, "frames.json").isFile }
        val file = File(directory, "gta6-menu-harita.jpg")
        val buffered = Class.forName("javax.imageio.ImageIO").getMethod("read", File::class.java).invoke(null, file)
        val type = buffered.javaClass
        val width = type.getMethod("getWidth").invoke(buffered) as Int
        val height = type.getMethod("getHeight").invoke(buffered) as Int
        val rgb = type.getMethod("getRGB", Int::class.java, Int::class.java, Int::class.java, Int::class.java, IntArray::class.java,
            Int::class.java, Int::class.java).invoke(buffered, 0, 0, width, height, null, 0, width) as IntArray
        // Kayıtlı okumanın kutuları (simge kırpılmış): RECENTER, 2D VIEW, ADD MARKER, SET DESTINATION, EXIT.
        val boxes = listOf(listOf(0.8689, 0.7194, 0.9334, 0.7544), listOf(0.8791, 0.766, 0.9334, 0.8018),
            listOf(0.8499, 0.8135, 0.9334, 0.852), listOf(0.8268, 0.8632, 0.9334, 0.8996), listOf(0.9055, 0.9147, 0.9334, 0.9483))
        val targets = boxes.map { b ->
            TextPainter.Target(TextBox(b[0], b[1], b[2], b[3]), 0.036, 1, "#0A6BEB", "#FFFFFF", true, "right")
        }
        val paints = TextPainter.paints(targets, width, height) { x, y -> rgb[y * width + x] and 0xFFFFFF }
        assertEquals(5, paints.size)
        assertEquals("ipuçları tek grup", 1, paints.mapNotNull { it.group }.toSet().size)
        assertTrue(paints.all { it.group != null })
        for (paint in paints) {
            val bg = TextPainter.rgb(paint.background)
            assertTrue("zemin mavi: ${paint.background}", bg.b > 180)
            assertTrue("zemin mavi: ${paint.background}", bg.r < 60)
            // Simge (x ≈ 0.94) tarafına taşmaz.
            assertTrue(paint.cover.right < 0.9405)
            assertNotNull("sol taraf boş", paint.grow)
            assertTrue(paint.grow!!.left < paint.cover.left - 0.05)
        }
    }

    /**
     * #1255: kare dışına taşan kutu (sol, sağ, üst, alt) boş alan taramasını sonsuz döngüye sokmaz; ölçüm biter ve kutular
     * kareye kırpılır. Nokta okuması kenara sabitlenir; sayaç bütçeyi aşarsa (eski kodda sonsuz döngü) farklı renk döner ki
     * deneme takılmasın, sonra bütçe aşımı hata sayılır.
     */
    @Test
    fun paintsEndsWhenBoxOverflowsFrame() {
        val width = 200
        val height = 100
        val budget = 2_000_000
        val boxes = listOf(
            TextBox(-0.08, 0.4, 0.3, 0.6),
            TextBox(0.7, 0.4, 1.08, 0.6),
            TextBox(0.3, -0.1, 0.6, 0.15),
            TextBox(0.3, 0.85, 0.6, 1.1),
            TextBox(-0.2, -0.2, 1.2, 1.2),
        )
        for (box in boxes) {
            var calls = 0
            val target = TextPainter.Target(box, 0.1, 1, "#202020", "#F0F0F0", false, "center")
            val paints = TextPainter.paints(listOf(target), width, height) { x, y ->
                calls++
                if (calls > budget) return@paints 0xFF0000
                val cx = x.coerceIn(0, width - 1)
                val cy = y.coerceIn(0, height - 1)
                val fx = cx.toDouble() / width
                val fy = cy.toDouble() / height
                val ink = fx > maxOf(0.0, box.left) + 0.02 && fx < minOf(1.0, box.right) - 0.02 && cy % 4 == 0 &&
                    fy > maxOf(0.0, box.top) && fy < minOf(1.0, box.bottom)
                if (ink) 0xF0F0F0 else 0x202020
            }
            assertTrue("sonsuz döngü: $box", calls <= budget)
            assertEquals(1, paints.size)
            for (b in listOfNotNull(paints[0].cover, paints[0].grow)) {
                assertTrue("$box: $b", b.left >= 0 && b.top >= 0 && b.right <= 1 && b.bottom <= 1)
                assertTrue("$box: $b", b.left <= b.right && b.top <= b.bottom)
            }
        }
    }

    /** #1264: komşusu olmayan, ekranın ortasındaki tek satır (görev yazısı) ortalı; kenardaki tek satır hizasını korur. */
    @Test
    fun loneCenteredLineIsCentered() {
        assertEquals("center", ScreenFit.loneAlign(TextBox(0.385, 0.94, 0.614, 0.97), 1))
        assertNull(ScreenFit.loneAlign(TextBox(0.385, 0.94, 0.614, 0.97), 2))
        assertNull(ScreenFit.loneAlign(TextBox(0.05, 0.1, 0.3, 0.13), 1))
    }

    /** #1267: gösterilen satırın zemini açıktan koyuya dönünce (seçim kaydı) eski kutular hemen kalkar. */
    @Test
    fun selectionMoveIsSeenFromTheFlippedBackground() {
        val box = TextBox(0.02, 0.2, 0.27, 0.25)
        val shown = listOf(box to "#E8E8F0")
        assertTrue(RegionWatcher.selectionMoved(shown, listOf(box to "#202030")))
        assertTrue(!RegionWatcher.selectionMoved(shown, listOf(box to "#E0E0E8")))
        assertTrue(!RegionWatcher.selectionMoved(shown, listOf(TextBox(0.02, 0.3, 0.27, 0.35) to "#202030")))
    }

    /** #1266, #1267: okunan yazının sözcük sayısında simge sanılan karakterler sayılmaz. */
    @Test
    fun iconGlyphsAreNotWords() {
        assertEquals(1, TextPainter.words("I Map"))
        assertEquals(2, TextPainter.words("II Photo Studio"))
        assertEquals(1, TextPainter.words("SELECT ⊗"))
        assertEquals(2, TextPainter.words("Retry Checkpoint"))
    }
}
