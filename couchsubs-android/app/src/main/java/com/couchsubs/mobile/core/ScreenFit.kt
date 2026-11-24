// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * "Ekranı çevir" öğelerinin yerleşimi: çeviri özgün yazının birebir yerinde çizilsin, simgeleri hiç örtmesin
 * (Mac: CouchSubsCore/ScreenFit.swift, Windows: ScreenFit.cs; aynı kurallar). TV ve öbür çiziciler bunlara göre çizer:
 * - Çeviri yatayda özgün yazının kutusundan hiç taşmaz: önce en çok %10 yatay sıkıştırma, sonra yazı küçülür, sonra satır
 *   kırılır ve kutu aşağı uzar ([lines]). Önceden kutu simgeye kadar yana genişliyor, tuş simgesinin üstüne biniyordu (#1203).
 * - [ScreenTranslation.Item.room]: kenar payının gidebileceği yatay alan. Özgün yazının iki yanında en çok [EDGE_LINES]
 *   satır yüksekliği; zeminden belirgin ayrılan ilk noktadan (kumanda simgesi, menü simgesi, fotoğraf, başka yazı) satır
 *   yüksekliğinin çeyreği önce biter; aynı satırdaki komşu öğeyle arası ortadan bölünür. Zemin rengi bilinmiyorsa kutudur.
 * - Kutu yalnız yazının noktalarını kapsar: yazı tanıma kutusunun ucundaki simge ([iconEdges]) kutunun dışında kalır.
 * - Hiza: alt alta dizilmiş kısa etiketlerin sağ kenarları aynıysa hepsi sağa yaslı, sol kenarları aynıysa sola; aynı
 *   satırda en az üç etiket varsa (menü şeridinin sekmeleri) ortalı.
 * - Eş öğeler (aynı satırdaki sekmeler, alt alta menü satırları) aynı yazı boyunda (#859).
 */
object ScreenFit {
    const val GAP_LINES = 0.25
    /** Kenar payı kutunun her yanında en çok bu kadar satır yüksekliği; yazının kendisi kutunun dışına çıkmaz. */
    const val EDGE_LINES = 0.3
    const val SAME_LINE = 0.15
    /** Düşük: kumanda düğmesinin koyu halkası zemine yakındır; yanlış bulunan nokta yalnız kenar payını daraltır. */
    const val INK_DISTANCE = 32
    const val ICON_GAP_LINES = 0.1
    const val ICON_TALLER = 1.1
    const val ICON_TALLER_ALONE = 1.5
    const val ICON_INK = 30

    /** Öğeler yerleşim bilgileriyle; kare yoksa olduğu gibi. [color]: (x, y) rengi 0xRRGGBB; yoksa parlaklık kullanılır. */
    fun fitted(items: List<ScreenTranslation.Item>, frame: GrayFrame?, color: ((Int, Int) -> Int)? = null): List<ScreenTranslation.Item> {
        if (frame == null || frame.width <= 0 || frame.height <= 0 || !frame.isValid) return items
        val aspect = frame.width.toDouble() / frame.height
        val tight = tightened(items, frame, aspect) { box, lineX, words ->
            iconEdges(box, lineX, words, frame.width, frame.height) { x, y ->
                if (color != null) color(x, y).let { (299 * ((it shr 16) and 255) + 587 * ((it shr 8) and 255) + 114 * (it and 255)) / 1000 }
                else frame.at(x, y)
            }
        }
        val laid = uniform(aligned(tight, aspect), aspect)
        val rgb: (Int, Int) -> Int = { x, y -> if (color != null) color(x, y) else frame.at(x, y).let { (it shl 16) or (it shl 8) or it } }
        val roomy = withRoom(laid, aspect, rgb, frame.width, frame.height)
        return painted(roomy, frame.width, frame.height, rgb)
    }

    /**
     * Yerinde birebir çizim ölçüleri ([TextPainter]): özgün stilli her öğeye `paint` (yalnız yazı değişince; çağıran
     * okuma turudur, her kare değil). [color]: karenin noktası, 0xRRGGBB.
     */
    internal fun painted(
        items: List<ScreenTranslation.Item>, width: Int, height: Int, color: (Int, Int) -> Int,
    ): List<ScreenTranslation.Item> {
        val indices = items.indices.filter { takesPart(items[it]) && items[it].surface != null && items[it].look != null }
        if (indices.isEmpty()) return items
        val paints = TextPainter.paints(indices.map { target(items[it]) }, width, height, color)
        val result = items.toMutableList()
        for ((k, i) in indices.withIndex()) if (k < paints.size) result[i] = result[i].copy(paint = paints[k])
        return result
    }

    internal fun target(item: ScreenTranslation.Item): TextPainter.Target =
        TextPainter.Target(item.box, item.lineHeight, if (item.paragraphs) max(2, item.rows) else item.rows,
            item.surface!!.background, item.surface.foreground, item.look!!.upper, item.look.align)

    /**
     * Konuşma satırı (#1224, #1255, #1259): konuşan adıyla başlar ("Lucia: Evet.") ya da küçük harf taşıyan tek satır olup
     * cümle sonu noktalamasıyla biter ("Ne?", "Yoldan çık."). Oyunun altyazısı ekran yazısı olarak da okunabiliyor; kısa
     * replik etiket sayılıp özgün yazının dar ailesiyle çiziliyor, TV'de "dar ve basık" görünüyordu. Konuşma satırı hiçbir
     * zaman dar aile almaz ([ScreenStyleLock.steady]). Mac/iPhone: ScreenFit.isDialogue, Windows: ScreenFit.IsDialogue,
     * TV: app.js isDialogue.
     */
    fun isDialogue(text: String, rows: Int = 1): Boolean {
        val line = text.trim()
        if (line.isEmpty()) return false
        if (SpeakerPrefix.split(line) != null) return true
        if (rows > 1 || line.contains('\n') || line.none { it.isLowerCase() }) return false
        val end = line.trimEnd('"', '\'', '”', '’', '»', ')', ']')
        return end.isNotEmpty() && end.last() in ".!?…"
    }

    internal fun isDialogue(item: ScreenTranslation.Item): Boolean =
        isDialogue(item.translation, if (item.paragraphs) max(2, item.rows) else item.rows)

    internal fun takesPart(item: ScreenTranslation.Item): Boolean =
        item.look != null && !ScreenTranslation.isCardPart(item) && !item.bubble

    private fun height(box: TextBox) = box.bottom - box.top

    private fun rowOverlap(a: TextBox, b: TextBox): Double =
        max(0.0, min(a.bottom, b.bottom) - max(a.top, b.top)) / max(1e-9, min(height(a), height(b)))

    internal fun tightened(
        items: List<ScreenTranslation.Item>, frame: GrayFrame, aspect: Double,
        icons: ((TextBox, Double, List<String>) -> Pair<Double?, Double?>)? = null,
    ): List<ScreenTranslation.Item> =
        items.map { item ->
            if (!takesPart(item) || !item.icons.isNullOrEmpty()) return@map item
            val box = item.box
            val lineX = item.lineHeight / aspect
            // Kutunun en az yarısı kalmalı; kalmıyorsa o kesim yanlıştır (koyu dokulu zemin), yapılmaz.
            fun keeps(l: Double, r: Double) = r - l >= 0.5 * (box.right - box.left)
            var left = box.left
            var right = box.right
            val spans = ScreenTranslation.inkSpans(frame, box, 0.6 * lineX)
            if (spans.size >= 2) {
                var l = box.left
                var r = box.right
                if (spans.last().second - spans.last().first <= 1.5 * lineX) r = spans[spans.size - 2].second
                if (spans[0].second - spans[0].first <= 1.5 * lineX && (spans.size >= 3 || r == box.right)) l = spans[1].first
                if (keeps(l, r)) { left = l; right = r }
            }
            if (item.rows <= 1 && icons != null) {
                val edges = icons(box, lineX, item.source.split(Regex("\\s+")).filter { it.isNotEmpty() })
                val l = max(left, edges.first ?: left)
                val r = min(right, edges.second ?: right)
                if (keeps(l, r)) { left = l; right = r }
            }
            if (left == box.left && right == box.right) item else item.copy(box = TextBox(left, box.top, right, box.bottom))
        }

    /**
     * Yazı tanıma kutusunun ucundaki kumanda/menü simgesi (Mac: ScreenFit.iconEdges, aynı örnekleme): kutunun yatay alanı,
     * üstünden ve altından yarım kutu yüksekliği fazlasıyla taranır; zeminden (ortanca parlaklık) [ICON_INK]'ten çok ayrılan
     * noktalar [ICON_GAP_LINES]'tan geniş boşluklarla parçalara bölünür. Uçtaki parça aşağı yukarı kare (en/boy 0,6-1,8) ve
     * öbür parçaların en uzunundan uzunsa simgedir: okunan yazı o parçayı açıklamıyorsa [ICON_TALLER] kat (uçtaki sözcük
     * okunmuş simge ya da küçük harfsiz kısa etikette parça sayısı sözcüklerden çok), açıklıyorsa [ICON_TALLER_ALONE] kat ve
     * hem üste hem alta taşarak. Dönen: (yazının başladığı yer, bittiği yer), simge yoksa null.
     */
    fun iconEdges(
        box: TextBox, lineX: Double, words: List<String>?, frameWidth: Int, frameHeight: Int, luma: (Int, Int) -> Int,
    ): Pair<Double?, Double?> {
        val fw = frameWidth.toDouble()
        val fh = frameHeight.toDouble()
        val half = 0.5 * (box.bottom - box.top)
        val top = max(0.0, box.top - half)
        val bottom = min(1.0, box.bottom + half)
        val left = max(0.0, box.left)
        val right = min(1.0, box.right)
        val width = (right - left) * fw
        val height = (bottom - top) * fh
        if (width < 8 || height < 6 || frameWidth <= 0 || frameHeight <= 0) return null to null
        val columns = Math.round(width).toInt().coerceIn(8, 800)
        val rows = 24
        val cells = IntArray(columns * rows)
        for (y in 0 until rows) {
            val py = min(frameHeight - 1, (top * fh + (y + 0.5) * height / rows).toInt())
            for (x in 0 until columns) {
                val px = min(frameWidth - 1, (left * fw + (x + 0.5) * width / columns).toInt())
                cells[y * columns + x] = luma(px, py)
            }
        }
        val median = cells.sorted()[cells.size / 2]
        val ink = BooleanArray(cells.size) { abs(cells[it] - median) > ICON_INK }
        val step = (right - left) / columns
        val blank = max(1, kotlin.math.ceil(ICON_GAP_LINES * lineX / max(1e-9, step)).toInt())
        // Parça: [ilk sütun, son sütun, en üst satır, en alt satır].
        val spans = mutableListOf<IntArray>()
        var open: IntArray? = null
        var run = 0
        for (x in 0 until columns) {
            var first = -1
            var last = -1
            for (y in 0 until rows) {
                if (!ink[y * columns + x]) continue
                if (first < 0) first = y
                last = y
            }
            if (first >= 0) {
                val span = open
                if (span == null) open = intArrayOf(x, x, first, last)
                else { span[1] = x; span[2] = min(span[2], first); span[3] = max(span[3], last) }
                run = 0
            } else if (open != null && ++run > blank) {
                spans.add(open)
                open = null
                run = 0
            }
        }
        open?.let { spans.add(it) }
        if (spans.size < 2) return null to null
        val cellWidth = width / columns
        val cellHeight = height / rows
        val extra = words != null && spans.size > words.size && words.size <= 5 && words.joinToString("").none { it.isLowerCase() }
        fun isIcon(span: IntArray, others: List<IntArray>, edge: String?): Boolean {
            val reference = others.maxOfOrNull { it[3] - it[2] + 1 } ?: 0
            val tall = span[3] - span[2] + 1
            val wide = span[1] - span[0] + 1
            val shape = wide * cellWidth / (tall * cellHeight)
            if (reference <= 0 || shape < 0.6 || shape > 1.8) return false
            if (extra || (edge != null && ButtonIcons.isIconToken(edge))) return tall >= ICON_TALLER * reference
            val above = others.minOf { it[2] }
            val below = others.maxOf { it[3] }
            return tall >= ICON_TALLER_ALONE * reference && span[2] < above && span[3] > below
        }
        val start = if (isIcon(spans[0], spans.drop(1), words?.firstOrNull())) left + spans[1][0] * step else null
        val end = if (isIcon(spans.last(), spans.dropLast(1), words?.lastOrNull())) left + (spans[spans.size - 2][1] + 1) * step else null
        // İki parçalı kutuda ikisi birden simge olamaz.
        if (start != null && end != null && spans.size < 3) return null to null
        return start to end
    }

    internal fun aligned(items: List<ScreenTranslation.Item>, aspect: Double): List<ScreenTranslation.Item> {
        val labels = items.indices.filter { takesPart(items[it]) && items[it].rows <= 1 }
        val result = items.toMutableList()
        for (i in labels) {
            val box = items[i].box
            val tolerance = 0.5 * items[i].lineHeight / aspect
            val column = labels.filter { j ->
                j != i && rowOverlap(box, items[j].box) == 0.0 &&
                    abs((box.top + box.bottom) - (items[j].box.top + items[j].box.bottom)) / 2 <= 8 * items[i].lineHeight
            }
            val rights = column.count { abs(items[it].box.right - box.right) <= tolerance && abs(items[it].box.left - box.left) > tolerance }
            val lefts = column.count { abs(items[it].box.left - box.left) <= tolerance && abs(items[it].box.right - box.right) > tolerance }
            val row = labels.count { j -> j != i && rowOverlap(box, items[j].box) >= 0.5 }
            val align = when {
                rights >= 2 && rights > lefts -> "right"
                lefts >= 2 -> "left"
                row >= 2 -> "center"
                else -> null
            }
            if (align != null) result[i] = result[i].copy(look = result[i].look!!.copy(align = align))
        }
        return result
    }

    internal fun uniform(items: List<ScreenTranslation.Item>, aspect: Double): List<ScreenTranslation.Item> {
        val labels = items.indices.filter { takesPart(items[it]) && items[it].rows <= 1 }
        val parent = labels.associateWith { it }.toMutableMap()
        fun root(start: Int): Int {
            var i = start
            while (parent[i] != i) i = parent[i]!!
            return i
        }
        for (a in labels) for (b in labels) {
            if (b <= a) continue
            val x = items[a]
            val y = items[b]
            if (x.look!!.upper != y.look!!.upper || x.look.bold != y.look.bold ||
                abs(x.lineHeight - y.lineHeight) > SAME_LINE * max(x.lineHeight, y.lineHeight)) continue
            val tolerance = 0.5 * max(x.lineHeight, y.lineHeight) / aspect
            val sameRow = rowOverlap(x.box, y.box) >= 0.5
            val sameColumn = (abs(x.box.left - y.box.left) <= tolerance || abs(x.box.right - y.box.right) <= tolerance) &&
                abs(x.box.top - y.box.top) <= 3 * max(x.lineHeight, y.lineHeight)
            if (sameRow || sameColumn) parent[root(a)] = root(b)
        }
        val result = items.toMutableList()
        for (members in labels.groupBy { root(it) }.values) {
            if (members.size < 2) continue
            val lines = members.map { items[it].lineHeight }.sorted()
            val median = lines[lines.size / 2]
            for (i in members) result[i] = result[i].copy(lineHeight = median)
        }
        return result
    }

    private fun hexRgb(hex: String): Int? =
        if (hex.length == 7 && hex[0] == '#') hex.substring(1).toIntOrNull(16) else null

    /** Her öğenin kenar payının gidebileceği yatay alan. [color]: karenin noktası, 0xRRGGBB. */
    internal fun withRoom(
        items: List<ScreenTranslation.Item>, aspect: Double, color: (Int, Int) -> Int, frameWidth: Int, frameHeight: Int,
    ): List<ScreenTranslation.Item> = items.mapIndexed { i, item ->
        if (!takesPart(item)) return@mapIndexed item
        val box = item.box
        val lineX = item.lineHeight / aspect
        val gap = GAP_LINES * lineX
        val background = item.surface?.background?.let(::hexRgb)
        // Zemin bilinmiyorsa yandaki simge aranamaz: kenar payı da kutunun içinde kalır.
        val edgeX = if (background != null) EDGE_LINES * lineX else 0.0
        var left = max(0.0, box.left - edgeX)
        var right = min(1.0, box.right + edgeX)
        for ((j, other) in items.withIndex()) {
            if (j == i || rowOverlap(box, other.box) < 0.3) continue
            if (other.box.left >= box.right - 1e-9) right = min(right, (box.right + other.box.left) / 2)
            if (other.box.right <= box.left + 1e-9) left = max(left, (other.box.right + box.left) / 2)
        }
        if (background != null) {
            val y0 = ((box.top + 0.2 * height(box)) * frameHeight).roundToInt()
            val y1 = ((box.bottom - 0.2 * height(box)) * frameHeight).roundToInt()
            val rows = (y0..max(y0, y1) step max(1, (y1 - y0) / 6)).map { it.coerceIn(0, frameHeight - 1) }
            fun scan(start: Double, end: Double): Double? {
                val a = (start * frameWidth).roundToInt()
                val b = (end * frameWidth).roundToInt()
                if (a == b) return null
                val step = if (b > a) 1 else -1
                var gr = (background shr 16) and 255
                var gg = (background shr 8) and 255
                var gb = background and 255
                var x = a
                while (x != b) {
                    if (x in 0 until frameWidth) {
                        var far = 0
                        var sr = 0
                        var sg = 0
                        var sb = 0
                        for (y in rows) {
                            val c = color(x, y)
                            val r = (c shr 16) and 255
                            val g = (c shr 8) and 255
                            val bl = c and 255
                            far = maxOf(far, abs(r - gr), abs(g - gg), abs(bl - gb))
                            sr += r
                            sg += g
                            sb += bl
                        }
                        if (far > INK_DISTANCE) return x.toDouble() / frameWidth
                        val n = rows.size
                        gr = (gr * 7 + sr / n) / 8
                        gg = (gg * 7 + sg / n) / 8
                        gb = (gb * 7 + sb / n) / 8
                    }
                    x += step
                }
                return null
            }
            val edge = 2.0 / frameWidth
            // Simgeyle arada gap kalsın diye tarama kenar payından gap kadar öteye gider.
            scan(box.right + edge, min(1.0, right + gap))?.let { right = min(right, it - gap) }
            scan(box.left - edge, max(0.0, left - gap))?.let { left = max(left, it + gap) }
        }
        item.copy(room = TextBox(min(box.left, left), box.top, max(box.right, right), box.bottom))
    }

    // --- Yerinde birebir çizim (TV fitExact ile aynı sıra; [TextPaint] gelen öğeler; Mac/iPhone ve Windows ile aynı) ---

    /**
     * Birebir çizilecek bir öğe (piksel, çizilen ekranda). [left]/[top]/[right]/[bottom]: örtü kutusu; [growLeft]/
     * [growRight]: kutunun yana uzayabileceği sınırlar (uzayamıyorsa örtünün kenarı); [line]: özgün satır yüksekliği;
     * [pitch]: özgün satır aralığı; [align]: "left", "center", "right".
     */
    class ExactInput(
        val text: String, val left: Double, val top: Double, val right: Double, val bottom: Double,
        growLeft: Double? = null, growRight: Double? = null, val line: Double, pitch: Double? = null, val rows: Int = 1,
        val align: String = "left", val group: Int? = null,
    ) {
        val growLeft: Double = min(left, growLeft ?: left)
        val growRight: Double = max(right, growRight ?: right)
        val pitch: Double = pitch ?: line

        companion object {
            /** Ekrana oranlı öğeden (`Item.paint` olmalı) [width] x [height] piksellik çizim alanına. */
            fun of(item: ScreenTranslation.Item, width: Double, height: Double): ExactInput? {
                val paint = item.paint ?: return null
                return ExactInput(item.translation, paint.cover.left * width, paint.cover.top * height,
                    paint.cover.right * width, paint.cover.bottom * height, paint.grow?.let { it.left * width },
                    paint.grow?.let { it.right * width }, max(1.0, item.lineHeight * height), max(1.0, paint.pitch * height),
                    if (item.paragraphs) max(2, item.rows) else item.rows, item.look?.align ?: "left", paint.group)
            }
        }
    }

    /**
     * Bir öğenin çizimi: kutu (piksel), yazı boyu, satırlar ve satır aralığı. Kutu opak, köşesiz, gölgesiz çizilir;
     * satırlar [lineHeight] aralıkla (k. satır `top + k * lineHeight`'tan başlar), her biri [rowHeight] yüksekliğinin
     * dikey ortasında, hizaya göre.
     */
    data class ExactPlacement(
        val left: Double, val top: Double, val width: Double, val height: Double, val fontSize: Double,
        val lines: List<String>, val lineHeight: Double, val rowHeight: Double,
    )

    /** Yazı boyu özgün satır yüksekliğinin bu katı (TV, Mac, Windows, iPhone, Android aynı). */
    const val EXACT_FONT = 0.95
    /** Sığmayan etiket (ve grubu) yazı boyunda en çok bu orana kadar küçülür; sonra satır kırılır. */
    const val EXACT_GROUP_MIN = 0.7
    /** Çok satırlı yazı en çok bu orana kadar küçülür; sonra kutu aşağı uzar. */
    const val EXACT_PARAGRAPH_MIN = 0.8
    /** Satır kırılan etiketin satır aralığı, yazı boyunun katı. */
    const val EXACT_WRAP_GAP = 1.2

    private fun exactWords(text: String) = text.split(Regex("\\s+")).filter { it.isNotEmpty() }

    /**
     * Birebir yerleşim (Mac: ScreenFit.exact, aynı sıra). Sırasıyla: (1) grubun (aynı listedeki etiketler) yazı boyu
     * üyelerinin özgün boyunun ortancası; (2) sığmayan etiket hizasının açık tarafındaki boş alana uzar, yazı boyu sabit;
     * (3) boş alan da yetmezse grubun tamamı birlikte küçülür (en çok [EXACT_GROUP_MIN]); (4) yine sığmayan etiketin satırı
     * kırılır, kutu aşağı uzar; tek sözcük yine sığmıyorsa yalnız o küçülür. Çok satırlı yazı özgün genişlik ve satır
     * aralığında kalır; sığmazsa [EXACT_PARAGRAPH_MIN]'e kadar küçülür, sonra aşağı uzar. Yazı hiçbir zaman "…" ile
     * kesilmez. [measure] (yazı, boy): yazının çizicinin kendi yazı tipiyle genişliği.
     */
    fun exact(items: List<ExactInput>, measure: (String, Double) -> Double): List<ExactPlacement> {
        val base = items.map { EXACT_FONT * it.line }.toMutableList()
        val members = LinkedHashMap<Int, MutableList<Int>>()
        for ((i, item) in items.withIndex()) item.group?.let { members.getOrPut(it) { mutableListOf() }.add(i) }
        for (list in members.values) {
            if (list.size < 2) continue
            val sizes = list.map { base[it] }.sorted()
            val median = sizes[sizes.size / 2]
            for (i in list) base[i] = median
        }
        fun isLabel(item: ExactInput) = item.rows <= 1 && !item.text.contains('\n')
        val natural = items.indices.map { i -> if (isLabel(items[i])) measure(items[i].text, base[i]) else 0.0 }
        val scale = items.indices.map { i ->
            if (!isLabel(items[i]) || natural[i] <= 0) 1.0
            else max(EXACT_GROUP_MIN, min(1.0, (items[i].growRight - items[i].growLeft) / natural[i]))
        }.toMutableList()
        for (list in members.values) {
            if (list.size < 2) continue
            val least = list.minOf { scale[it] }
            for (i in list) scale[i] = least
        }
        return items.indices.map { i ->
            val item = items[i]
            val coverWidth = item.right - item.left
            val coverHeight = item.bottom - item.top
            if (!isLabel(item)) return@map exactParagraph(item, base[i], measure)
            var font = base[i] * scale[i]
            val avail = item.growRight - item.growLeft
            var width = natural[i] * scale[i]
            var lines = listOf(item.text)
            var gap = coverHeight
            if (width > avail + 0.5) {
                val words = exactWords(item.text)
                val widestWord = words.maxOfOrNull { measure(it, font) } ?: width
                if (words.size >= 2) {
                    // Satır kırılır; satıra sığmayan sözcük varsa yazı yalnız bu öğede küçülür (yana taşmaz).
                    if (widestWord > avail + 0.5) font *= avail / widestWord
                    val size = font
                    lines = exactWrap(words, avail) { measure(it, size) }
                } else {
                    font *= avail / max(1e-9, width)
                }
                val size = font
                width = lines.maxOfOrNull { measure(it, size) } ?: avail
                if (lines.size > 1) gap = max(coverHeight / lines.size, font * EXACT_WRAP_GAP)
            }
            val boxWidth = max(coverWidth, min(avail, width))
            var left = when (item.align) {
                "right" -> item.right - boxWidth
                "center" -> item.left - (boxWidth - coverWidth) / 2
                else -> item.left
            }
            left = min(max(left, item.growLeft), item.growRight - boxWidth)
            ExactPlacement(left, item.top, boxWidth, max(coverHeight, lines.size * gap), font, lines, gap, gap)
        }
    }

    /** Çok satırlı yazı: özgün genişlik ve satır aralığı; sığmazsa [EXACT_PARAGRAPH_MIN]'e kadar küçülür, sonra aşağı uzar. */
    private fun exactParagraph(item: ExactInput, base: Double, measure: (String, Double) -> Double): ExactPlacement {
        val coverWidth = item.right - item.left
        val coverHeight = item.bottom - item.top
        var factor = 1.0
        // Özgün bir satırın yüksekliği (kenar payıyla): son satır tam aralık değil, bu kadar yer kaplar.
        val row = max(base * 1.05, coverHeight - (max(1, item.rows) - 1) * item.pitch)
        class Laid(val font: Double, val lines: List<String>, val gap: Double)
        fun layout(): Laid {
            val font = base * factor
            val gap = max(item.pitch, base * 1.05) * factor
            val lines = item.text.split("\n").flatMap { paragraph ->
                val words = exactWords(paragraph)
                if (words.isEmpty()) listOf("") else exactWrap(words, coverWidth) { measure(it, font) }
            }
            return Laid(font, lines, gap)
        }
        var laid = layout()
        fun tall(laid: Laid) = (laid.lines.size - 1) * laid.gap + row * factor
        while (tall(laid) > coverHeight + 1 && factor > EXACT_PARAGRAPH_MIN + 1e-6) {
            factor = max(EXACT_PARAGRAPH_MIN, Math.round((factor - 0.05) * 100) / 100.0)
            laid = layout()
        }
        // Satıra sığmayan tek sözcük: yazı küçülür (yana taşmaz).
        val widest = laid.lines.maxOfOrNull { measure(it, laid.font) } ?: 0.0
        if (widest > coverWidth + 0.5) {
            factor *= coverWidth / widest
            laid = layout()
        }
        return ExactPlacement(item.left, item.top, coverWidth, max(coverHeight, tall(laid)), laid.font, laid.lines, laid.gap, row * factor)
    }

    /** Sözcükler satırlara: her satır [limit]'e kadar dolar. */
    internal fun exactWrap(words: List<String>, limit: Double, measure: (String) -> Double): List<String> {
        val lines = mutableListOf<String>()
        var current = ""
        for (word in words) {
            val next = if (current.isEmpty()) word else "$current $word"
            if (current.isNotEmpty() && measure(next) > limit + 0.5) {
                lines.add(current)
                current = word
            } else current = next
        }
        if (current.isNotEmpty() || lines.isEmpty()) lines.add(current)
        return lines
    }

    // --- Çizicilerin ortak satır yerleşimi (TV fitStyled ile aynı sıra; Mac/iPhone ve Windows ile aynı) ---

    /** Bir çevirinin çizimi: satırları, yalnız yatay ölçeği ve yazı boyunun ölçeği. Alan her zaman özgün kutudur. */
    data class Lines(val lines: List<String>, val squeeze: Double, val scale: Double)

    /** Yatay sıkıştırma yalnız en çok iki sözcüklük tek satırlık etikette ve en çok %10. */
    const val FIRST_SQUEEZE = 0.9
    /** Sığmayan çok satırlı yazı önce bu orana kadar küçülür, sonra satır eklenir. */
    const val MIN_SCALE = 0.6
    /** Sığmayan tek satırlık etiket ve tek sözcük en çok bu orana kadar küçülür (etiket sonra satıra iner). */
    const val LAST_SCALE = 0.5
    /** Ekran yazısının en küçük boyu, konuşma altyazısının (öntanımlı, 1080 satırlık ekranda) bu kadarı. */
    const val FLOOR_SHARE = 0.6
    const val SUBTITLE_FONT = 46.0

    /** Ekran yazısı alt sınırının özgün yazı boyuna oranı ([lines]'ın `floor`'u). */
    fun floor(fontSize: Double, screenHeight: Double): Double =
        if (fontSize > 0) FLOOR_SHARE * SUBTITLE_FONT * screenHeight / 1080 / fontSize else 0.0

    /**
     * Çeviriyi özgün yazının alanına (genişliği [width], piksel) yerleştirir; alan yana hiç genişlemez (Mac: ScreenFit.lines,
     * aynı sıra). Sığmazsa: en çok iki sözcüklük etikette en çok %10 yatay sıkıştırma, yazının küçülmesi (tek satırlık
     * etiket [LAST_SCALE]'e, çok satırlı yazı [MIN_SCALE]'e kadar, alt sınırın altına inmeden), satır kırma (kutu aşağı
     * uzar), tek sözcükte [LAST_SCALE]'e kadar.
     */
    fun lines(text: String, width: Double, rows: Int, floorScale: Double = 0.0, measure: (String) -> Double): Lines {
        val words = text.split(Regex("\\s+")).filter { it.isNotEmpty() }
        var lines = text.split("\n")
        val count = max(rows, lines.size)
        val squeezable = count <= 1 && words.size <= 2
        // Alt sınır yalnız cümlede (en az üç sözcük ya da çok satırlı yazı): kısa etiket simgeye taşmasın diye küçülebilir.
        val floor = if (squeezable) 0.0 else floorScale
        val limit = if (squeezable) width / FIRST_SQUEEZE else width
        if (lines.size == 1 && count > 1) lines = wrapped(words, max(limit, measure(text) / count), count, measure)
        var widest = lines.maxOfOrNull(measure) ?: 0.0
        val start = max(1.0, floor)
        var scale = start
        if (widest * start > limit) {
            val least = max(floor, if (count > 1) MIN_SCALE else LAST_SCALE)
            if (widest * least > limit && words.size >= 2) {
                lines = lines.flatMap { line ->
                    wrapped(line.split(Regex("\\s+")).filter { it.isNotEmpty() }, limit / least, Int.MAX_VALUE, measure)
                }
                widest = lines.maxOfOrNull(measure) ?: 0.0
            }
            // Satıra sığmayan tek sözcük alt sınırın da altına küçülür: yana taşmamak önce gelir.
            scale = max(LAST_SCALE, min(start, limit / max(1e-9, widest)))
        }
        val squeeze = if (squeezable && widest > 0) max(FIRST_SQUEEZE, min(1.0, width / (widest * scale))) else 1.0
        return Lines(lines, squeeze, scale)
    }

    /** Sözcükler satırlara: her satır [limit]'e kadar dolar, en çok [cap] satır (sonuncusu kalanı alır). */
    private fun wrapped(words: List<String>, limit: Double, cap: Int, measure: (String) -> Double): List<String> {
        val made = mutableListOf<String>()
        var current = ""
        for (word in words) {
            val next = if (current.isEmpty()) word else "$current $word"
            if (current.isNotEmpty() && measure(next) > limit && made.size < cap - 1) {
                made.add(current)
                current = word
            } else current = next
        }
        if (current.isNotEmpty() || made.isEmpty()) made.add(current)
        return made
    }

    /**
     * Kutunun sol ve sağ kenar payı (piksel): en çok [pad], kenar payı alanının ([room]: sol, sağ) dışına çıkmadan. Alan
     * bilinmiyorsa kenar payı yoktur: yandaki simgenin yeri bilinmez.
     */
    fun pads(left: Double, width: Double, room: Pair<Double, Double>?, pad: Double): Pair<Double, Double> =
        if (room == null) 0.0 to 0.0
        else min(pad, max(0.0, left - room.first)) to min(pad, max(0.0, room.second - (left + width)))
}
