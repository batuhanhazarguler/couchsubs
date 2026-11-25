// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.abs

/**
 * Oyun dünyasındaki ürün, ambalaj ve etiket yazısı (bira kutusu, süt kartonu, şişe etiketi) yerinde dursa da ekran yazısı
 * ya da altyazı değildir. Sinan Bey (beta.101, GTA 6, buzdolabı): ambalajların yazıları ekran yazısı sayılıp ürünlerin
 * üstüne üst üste çiziliyordu. Kamerayla kayan tabela [SceneMotion] ile, alt alta kısa tabela [SceneText] ile yakalanıyor;
 * hareketsiz ambalaj hiçbirine takılmıyordu.
 *
 * Satır ancak bunların HEPSİ tutarsa ambalaj yazısıdır (muhafazakâr): marka biçimi ([isBrandShape]), sahnede ([inScene]:
 * HUD şeritleri dışında, büyük başlık boyunda değil), yazı arayüz mürekkebi değil (en parlak noktalar açık ve renksiz
 * değil) ve zemin desenli ya da taban çizgisi eğik. Görüntü yoksa hiçbir satır atılmaz. Mac/iPhone (PackageText.swift) ve
 * Windows (PackageText.cs) aynı kuralları ve eşikleri uygular; ortak deneme dosyası package-text.json.
 */
object PackageText {
    const val REASON = "ambalaj/etiket yazısı (sahnede, desenli zeminde)"
    const val MAX_WORDS = 3
    const val MAX_LENGTH = 20
    const val SCENE_LEFT = 0.08
    const val SCENE_RIGHT = 0.92
    const val SCENE_TOP = 0.10
    const val SCENE_BOTTOM = 0.80
    const val MAX_HEIGHT = 0.045
    const val TEXTURE_STEP = 10.0
    const val UI_LUMA = 185
    const val UI_CHROMA = 30
    const val RING_SHARE = 0.5
    const val RING_GAP = 0.15
    const val TILT_SHIFT = 0.35

    private const val SAMPLES_X = 32
    private const val SAMPLES_Y = 8
    private const val RING_SAMPLES = 2
    private const val MIN_PAIRS = 16

    /** Satırın görüntüden ölçülen görünüşü. */
    data class Look(val textured: Boolean, val uiInk: Boolean)

    /** Satır ambalaj yazısı mı. [box] karede (0–1); görünüş yoksa atılmaz. */
    fun isPackage(line: TextLine, box: TextBox, look: Look?): Boolean {
        if (look == null || look.uiInk || !line.icons.isNullOrEmpty() || !isBrandShape(line.text) || !inScene(box)) return false
        return look.textured || isTilted(line.words)
    }

    /** Marka/etiket biçimi: bir-üç sözcük, her biri büyük harfle başlar; cümle noktalaması, tuş, konuşan adı yok. */
    fun isBrandShape(text: String): Boolean {
        val plain = text.trim(' ')
        if (plain.isEmpty() || plain.length > MAX_LENGTH || ButtonIcons.MARKER in plain ||
            plain.any { it in ".,;:\"“”()[]/" } || plain[0] in "-–—" || SpeakerPrefix.split(plain) != null ||
            ButtonPrompts.isPrompt(plain) || UiCommands.translateLabelLoosely(plain) != null) return false
        val body = if (plain.last() in "!?") plain.dropLast(1) else plain
        if (body.any { it == '!' || it == '?' }) return false
        val words = body.split(Regex("\\s+")).filter { word -> word.any { it.isLetter() } }
        if (words.size !in 1..MAX_WORDS || (body.length < plain.length && words.size < 2)) return false
        return words.all { word -> word.first { it.isLetter() }.isUpperCase() }
    }

    /** Satırın ortası sahnede (HUD şeritleri dışında) ve satır büyük başlık boyunda değil. */
    fun inScene(box: TextBox): Boolean {
        val x = (box.left + box.right) / 2
        val y = (box.top + box.bottom) / 2
        return x >= SCENE_LEFT && x <= SCENE_RIGHT && y >= SCENE_TOP && y <= SCENE_BOTTOM && box.bottom - box.top <= MAX_HEIGHT
    }

    internal fun isTilted(words: List<TextWord>?): Boolean {
        if (words == null || words.size < 2) return false
        val heights = words.map { it.box.bottom - it.box.top }.sorted()
        val median = heights[heights.size / 2]
        if (median <= 0) return false
        val middles = words.sortedBy { it.box.left }.map { (it.box.top + it.box.bottom) / 2 }
        val shift = middles.last() - middles.first()
        if (abs(shift) <= TILT_SHIFT * median) return false
        val direction = if (shift > 0) 1.0 else -1.0
        return middles.zipWithNext().all { (a, b) -> (b - a) * direction >= -0.15 * median }
    }

    /** Satırın görünüşü. Kutular görüntüye oranla; [rgb] noktanın rengi (0xRRGGBB). Kutu çok küçükse null. */
    fun measure(box: TextBox, others: List<TextBox>, width: Int, height: Int, rgb: (Int, Int) -> Int): Look? {
        if (width <= 0 || height <= 0) return null
        val w = width.toDouble()
        val h = height.toDouble()
        val left = maxOf(0.0, box.left) * w
        val right = minOf(1.0, box.right) * w
        val top = maxOf(0.0, box.top) * h
        val bottom = minOf(1.0, box.bottom) * h
        if (right - left < 4 || bottom - top < 3) return null
        val inside = ArrayList<Pair<Int, Int>>(SAMPLES_X * SAMPLES_Y)
        for (sy in 0 until SAMPLES_Y) {
            val y = minOf(height - 1, (top + (sy + 0.5) * (bottom - top) / SAMPLES_Y).toInt())
            for (sx in 0 until SAMPLES_X) {
                val x = minOf(width - 1, (left + (sx + 0.5) * (right - left) / SAMPLES_X).toInt())
                inside += split(rgb(x, y))
            }
        }
        val bright = inside.sortedByDescending { it.first }.take(inside.size / 4)
        val luma = bright.sumOf { it.first } / bright.size
        val chroma = bright.sumOf { it.second } / bright.size
        val uiInk = luma >= UI_LUMA && chroma <= UI_CHROMA
        val line = bottom - top
        val gap = line * RING_GAP
        val thick = line * RING_SHARE
        val blocked = others.map { o ->
            val pad = (o.bottom - o.top) * h * RING_GAP
            doubleArrayOf(o.left * w - pad, o.top * h - pad, o.right * w + pad, o.bottom * h + pad)
        }
        var sum = 0.0
        var pairs = 0
        for ((stripTop, stripBottom) in listOf(top - gap - thick to top - gap, bottom + gap to bottom + gap + thick)) {
            if (stripTop < 0 || stripBottom > h) continue
            for (row in 0 until RING_SAMPLES) {
                val yf = stripTop + (row + 0.5) * (stripBottom - stripTop) / RING_SAMPLES
                val y = minOf(height - 1, yf.toInt())
                var previous: Int? = null
                for (sx in 0 until SAMPLES_X) {
                    val xf = left + (sx + 0.5) * (right - left) / SAMPLES_X
                    if (blocked.any { xf >= it[0] && xf <= it[2] && yf >= it[1] && yf <= it[3] }) {
                        previous = null
                        continue
                    }
                    val value = split(rgb(minOf(width - 1, xf.toInt()), y)).first
                    if (previous != null) {
                        sum += abs(value - previous)
                        pairs++
                    }
                    previous = value
                }
            }
        }
        return Look(pairs >= MIN_PAIRS && sum / pairs >= TEXTURE_STEP, uiInk)
    }

    private fun split(rgb: Int): Pair<Int, Int> {
        val r = (rgb shr 16) and 0xff
        val g = (rgb shr 8) and 0xff
        val b = rgb and 0xff
        return (299 * r + 587 * g + 114 * b) / 1000 to maxOf(r, g, b) - minOf(r, g, b)
    }

    /**
     * Okumadan ambalaj yazısı satırlarını çıkarır. Satır kutuları okunan alana oranlı; [area] alanın karedeki yeri; [look]
     * (kutu, öbür kutular) okunan alanın görüntüsünden ölçer.
     */
    fun filter(reading: Reading, area: TextBox, look: ((TextBox, List<TextBox>) -> Look?)?): Pair<Reading, List<TextLine>> {
        if (look == null || reading.lines.isEmpty()) return reading to emptyList()
        val kept = ArrayList<TextLine>()
        val removed = ArrayList<TextLine>()
        reading.lines.forEachIndexed { i, line ->
            val box = line.box
            if (box == null || !isBrandShape(line.text) || !line.icons.isNullOrEmpty() || !inScene(box.placedIn(area))) {
                kept += line
                return@forEachIndexed
            }
            val others = reading.lines.filterIndexed { j, other -> j != i && other.box != null }.map { it.box!! }
            if (isPackage(line, box.placedIn(area), look(box, others))) removed += line else kept += line
        }
        return if (removed.isEmpty()) reading to emptyList() else Reading(kept) to removed
    }

    /**
     * Okunan alanın görüntüsü için ölçücü: renk varsa [color] (0xRRGGBB), yoksa parlaklık (NV21 sınırlı aralığı tam aralığa
     * açılır; renk açıklığı 0 sayılır).
     */
    fun sampler(frame: GrayFrame?, color: ((Int, Int) -> Int)?): ((TextBox, List<TextBox>) -> Look?)? {
        if (frame == null || !frame.isValid) return null
        val rgb: (Int, Int) -> Int = color ?: { x, y ->
            val v = ((frame.at(x, y) - 16) * 255 / 219).coerceIn(0, 255)
            (v shl 16) or (v shl 8) or v
        }
        return { box, others -> measure(box, others, frame.width, frame.height, rgb) }
    }
}
