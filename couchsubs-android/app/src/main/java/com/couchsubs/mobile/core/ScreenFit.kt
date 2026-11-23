// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * "Ekranı çevir" öğelerinin yerleşimi: çeviri özgün yazının birebir yerinde ve boyunda çizilsin, simgeleri örtmesin
 * (Mac: CouchSubsCore/ScreenFit.swift, Windows: ScreenFit.cs; aynı kurallar). TV ve öbür çiziciler bunlara göre çizer:
 * - [ScreenTranslation.Item.room]: kutunun genişleyebileceği yatay alan. Özgün yazının iki yanında, zeminden belirgin
 *   ayrılan ilk noktaya (kumanda simgesi, menü simgesi, fotoğraf, başka yazı) kadar, araya satır yüksekliğinin çeyreği
 *   boşluk bırakılarak; aynı satırdaki komşu öğeyle arası ortadan bölünür. Kutu bu alanın dışına hiç taşmaz.
 * - Kutu yalnız yazının noktalarını kapsar: ucundaki ayrı duran küçük leke simgedir, kutunun dışında kalır.
 * - Hiza: alt alta dizilmiş kısa etiketlerin sağ kenarları aynıysa hepsi sağa yaslı, sol kenarları aynıysa sola; aynı
 *   satırda en az üç etiket varsa (menü şeridinin sekmeleri) ortalı.
 * - Eş öğeler (aynı satırdaki sekmeler, alt alta menü satırları) aynı yazı boyunda (#859).
 */
object ScreenFit {
    const val GAP_LINES = 0.25
    const val GROW_LINES = 8.0
    const val SAME_LINE = 0.15
    const val INK_DISTANCE = 56

    /** Öğeler yerleşim bilgileriyle; kare yoksa olduğu gibi. [color]: (x, y) rengi 0xRRGGBB; yoksa parlaklık kullanılır. */
    fun fitted(items: List<ScreenTranslation.Item>, frame: GrayFrame?, color: ((Int, Int) -> Int)? = null): List<ScreenTranslation.Item> {
        if (frame == null || frame.width <= 0 || frame.height <= 0 || !frame.isValid) return items
        val aspect = frame.width.toDouble() / frame.height
        val laid = uniform(aligned(tightened(items, frame, aspect), aspect), aspect)
        return withRoom(laid, aspect, { x, y ->
            if (color != null) color(x, y) else frame.at(x, y).let { (it shl 16) or (it shl 8) or it }
        }, frame.width, frame.height)
    }

    internal fun takesPart(item: ScreenTranslation.Item): Boolean =
        item.look != null && !ScreenTranslation.isCardPart(item) && !item.bubble

    private fun height(box: TextBox) = box.bottom - box.top

    private fun rowOverlap(a: TextBox, b: TextBox): Double =
        max(0.0, min(a.bottom, b.bottom) - max(a.top, b.top)) / max(1e-9, min(height(a), height(b)))

    internal fun tightened(items: List<ScreenTranslation.Item>, frame: GrayFrame, aspect: Double): List<ScreenTranslation.Item> =
        items.map { item ->
            if (!takesPart(item) || !item.icons.isNullOrEmpty()) return@map item
            val box = item.box
            val lineX = item.lineHeight / aspect
            val spans = ScreenTranslation.inkSpans(frame, box, 0.6 * lineX)
            if (spans.size < 2) return@map item
            var left = box.left
            var right = box.right
            if (spans.last().second - spans.last().first <= 1.5 * lineX) right = spans[spans.size - 2].second
            if (spans[0].second - spans[0].first <= 1.5 * lineX && (spans.size >= 3 || right == box.right)) left = spans[1].first
            if (right - left < 0.5 * (box.right - box.left)) item else item.copy(box = TextBox(left, box.top, right, box.bottom))
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

    /** Her öğenin genişleyebileceği yatay alan. [color]: karenin noktası, 0xRRGGBB. */
    internal fun withRoom(
        items: List<ScreenTranslation.Item>, aspect: Double, color: (Int, Int) -> Int, frameWidth: Int, frameHeight: Int,
    ): List<ScreenTranslation.Item> = items.mapIndexed { i, item ->
        if (!takesPart(item)) return@mapIndexed item
        val box = item.box
        val lineX = item.lineHeight / aspect
        val gap = GAP_LINES * lineX
        var left = max(0.0, box.left - GROW_LINES * lineX)
        var right = min(1.0, box.right + GROW_LINES * lineX)
        for ((j, other) in items.withIndex()) {
            if (j == i || rowOverlap(box, other.box) < 0.3) continue
            if (other.box.left >= box.right - 1e-9) right = min(right, (box.right + other.box.left) / 2)
            if (other.box.right <= box.left + 1e-9) left = max(left, (other.box.right + box.left) / 2)
        }
        val background = item.surface?.background?.let(::hexRgb)
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
            scan(box.right + edge, right)?.let { right = min(right, it - gap) }
            scan(box.left - edge, left)?.let { left = max(left, it + gap) }
        }
        item.copy(room = TextBox(min(box.left, left), box.top, max(box.right, right), box.bottom))
    }
}
