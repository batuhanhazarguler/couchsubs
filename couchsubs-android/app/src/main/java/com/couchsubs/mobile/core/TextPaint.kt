// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Bir ekran yazısının yerinde, arayüz Türkçe yapılmış gibi çizilmesi için göndericinin kareden ölçtükleri (TV pikselleri
 * okuyamaz). Yalnız yazı değişince ölçülür (Mac/iPhone: TextPaint.swift, Windows: TextPaint.cs; aynı kurallar ve
 * eşikler). TV'ye öğenin `bg`, `bg2`, `bgDir`, `bgPat`, `fg`, `weight`, `upper`, `align`, `lineH`, `cover`, `grow`,
 * `group` alanlarıyla gider; eski TV bunları yok sayıp eski çizimi sürdürür.
 */
data class TextPaint(
    /** Kutunun zemini (degradede başlangıç ucu: sol ya da üst). Opak çizilir. */
    val background: String,
    /** Satır aralığı (bir satırın üstünden ötekinin üstüne), kareye oranla; tek satırda satır yüksekliği. */
    val pitch: Double,
    /**
     * Özgün yazıyı tam örten kutu: yazı tanıma kutusu ve dışına taşan harf noktaları, en çok [TextPainter.MARGIN_MAX]
     * piksel payla. Simgeye doğru taşmaz.
     */
    val cover: TextBox,
    /** Degradenin öbür ucu (sağ ya da alt); düz zeminde null. */
    val background2: String? = null,
    /** Degradenin yönü: "h" (yatay) ya da "v" (dikey); düz zeminde null. */
    val direction: String? = null,
    /** Zemin desenli (harita, dünya): [background] ortalama renktir. */
    val patterned: Boolean = false,
    /**
     * Kutunun yana uzayabileceği alan (yalnız tek satırlık etikette, hizanın açık tarafında): o yönde başka yazı, simge
     * ya da kutu yok, yalnız oyunun zemini var. Simgeyle ya da komşuyla arada [ScreenFit.GAP_LINES] kadar boşluk kalır.
     * null: uzayamaz.
     */
    val grow: TextBox? = null,
    /**
     * Aynı listede alt alta (ya da aynı satırda) duran, özgün hâlinde aynı boydaki etiketlerin ortak numarası; grubun
     * hepsi aynı yazı boyunda çizilir. null: tek başına.
     */
    val group: Int? = null,
    /**
     * Yazı tanıma kutusunun ucundaki simge (menü simgesi, tuş simgesi) yazının hangi yanında ("left", "right"): örtü ve uzama
     * o simgeye girmez, yazı o yana yaslanır (TV'ye `align` olarak gider). null: simge yok.
     */
    val iconSide: String? = null,
) {
    /** Bu ölçüler [area] içindeki oranlarsa, aynı yerin [area]'yı içeren çerçevedeki oranları. */
    fun placedIn(area: TextBox): TextPaint =
        copy(cover = cover.placedIn(area), grow = grow?.placedIn(area), pitch = pitch * (area.bottom - area.top))
}

/**
 * [TextPaint] ölçümü. Piksel erişimi soyuttur (`color(x, y)`, 0xRRGGBB): ortak deneme dosyası (fixtures/text-paint.json)
 * üç platformda aynı yapay kareyi kurar.
 */
object TextPainter {
    /** Bir noktanın rengi (0-255 kanallar). */
    data class Rgb(val r: Int, val g: Int, val b: Int)

    /**
     * Ölçülecek yazı: kareye oranla kutusu ve satır yüksekliği, özgün satır sayısı, sampler'ın bulduğu zemin/yazı rengi
     * ve hizası ("left", "center", "right").
     */
    data class Target(
        val box: TextBox, val lineHeight: Double, val rows: Int, val background: String, val foreground: String,
        val upper: Boolean, val align: String,
        /** Okunan yazının sözcük sayısı (simge sanılan karakterler sayılmaz, [words]); 0: bilinmiyor, kutunun ucundaki simge aranmaz. */
        val words: Int = 0,
    )

    /** Nokta zeminden bu kadar (en büyük renk bileşeni farkı) uzak ve yazı rengine zeminden yakınsa harf noktasıdır. */
    const val INK_DISTANCE = 40
    /** Bir satır/sütunun en az bu kadarı harf noktasıysa orada yazı sürer. */
    const val INK_SHARE = 0.03
    /** Kutu yazı tanıma kutusunun dışına en çok bu kadar satır yüksekliği uzar (taşan harf ucu). */
    const val REACH_LINES = 0.5
    /** Kenar payı: satır yüksekliğinin bu kadarı, en az 1, en çok [MARGIN_MAX] piksel. */
    const val MARGIN_LINES = 0.08
    const val MARGIN_MAX = 3
    /** İki uç arasındaki fark (en büyük renk bileşeni) en az bu kadarsa zemin degradedir. */
    const val GRADIENT_STEP = 10
    /** Zeminin kendi içindeki sapması bundan büyükse zemin desenlidir. */
    const val PATTERN_DEVIATION = TextStyleSampler.FLAT_DEVIATION
    /** Kenar şeridinin ortalaması sampler'ın zemininden bu kadar uzaksa (seçili satırın kendi kutusu dar) sampler'ınki kalır. */
    const val TRUST_DISTANCE = 48
    /** Boş alan en çok bu kadar satır yüksekliği taranır. */
    const val GROW_LINES = 12.0
    /** Aynı grup: satır yükseklikleri en çok bu oranda farklı ([ScreenFit.SAME_LINE]). */
    const val SAME_LINE = ScreenFit.SAME_LINE

    /**
     * Kutunun ucundaki simgeyi yazıdan ayıran en dar boşluk, satır yüksekliğinin katı (harf arası bundan dardır; GTA 6
     * menüsünde simgeyle yazı arası ~0,4 satır).
     */
    const val ICON_GAP_LINES = 0.3
    /** Simge parçasının genişliği satır yüksekliğinin bu katları arasında ("I" harfi gibi ince parça simge sayılmaz). */
    const val ICON_MIN_WIDE = 0.45
    const val ICON_MAX_WIDE = 1.6
    /** Simge sanılıp yazı olarak okunan karakterler (GTA 6 menü simgesi "I", "II"; tuş simgeleri). */
    private const val ICON_GLYPHS = "I|l![]()©®@○◯●□■△▲✕✖×◎⊗⊙"

    /**
     * Okunan yazının sözcük sayısı: simge sanılan bir iki karakterlik parçalar ve harfi/rakamı olmayan parçalar sayılmaz
     * ("I Map" → 1, "SELECT ⊗" → 1, "- SMASH 'N' GRABS" → 3, "• Objective" → 1). Menü simgesi (yön tuşu, renkli nokta)
     * "-", "•", "+" diye okununca sözcük sayılıyor, simge bulunmuyordu: kutu simgenin üstüne çiziliyordu (#1268, #1270;
     * Mac/iPhone, Windows ile aynı).
     */
    fun words(text: String): Int =
        IconText.plain(text).split(Regex("\\s+")).filter { it.isNotEmpty() }
            .count { token -> !(token.length <= 2 && token.all { it in ICON_GLYPHS }) && token.any { it.isLetterOrDigit() } }

    /** Simge parçası: [l, r) piksel sütunları. */
    data class Span(val l: Int, val r: Int)

    /** [iconSpans] sonucu: simgeler ve onlar çıkınca yazının sol/sağ kenarı. */
    data class Icons(val left: Span?, val right: Span?, val textLeft: Int, val textRight: Int)

    /**
     * Kutunun ([l, r), piksel) ucundaki simge: harf sütunları ([ink]) [ICON_GAP_LINES] satırdan geniş boşluklarla parçalara
     * bölünür; parça sayısı sözcük sayısından çoksa uçtaki simge genişliğindeki ([ICON_MIN_WIDE]-[ICON_MAX_WIDE] satır)
     * parça simgedir. İki uç da uyarsa hizanın yanı (sola yaslıda sol, öbürlerinde sağ) önce; ikincisi ancak iki fazla parça
     * varsa. Simgeler çıkınca kalan parça sözcüklerden çoksa simge yoktur.
     */
    fun iconSpans(l: Int, r: Int, line: Double, words: Int, align: String, ink: (Int) -> Boolean): Icons {
        val none = Icons(null, null, l, r)
        if (words <= 0 || r - l < 2) return none
        val gap = max(2, round(ICON_GAP_LINES * line))
        val spans = mutableListOf<Span>()
        var start: Int? = null
        var last = l
        var blank = 0
        for (x in l until r) {
            if (ink(x)) {
                if (start == null) start = x
                last = x
                blank = 0
            } else if (start != null) {
                blank++
                if (blank >= gap) {
                    spans.add(Span(start, last + 1))
                    start = null
                    blank = 0
                }
            }
        }
        start?.let { spans.add(Span(it, last + 1)) }
        if (spans.size < 2 || spans.size <= words) return none
        fun isIcon(span: Span): Boolean {
            val wide = (span.r - span.l).toDouble()
            return wide >= ICON_MIN_WIDE * line && wide <= ICON_MAX_WIDE * line
        }
        val extra = spans.size - words
        val first = spans.first()
        val end = spans.last()
        var left: Span? = null
        var right: Span? = null
        if (align == "left") {
            if (isIcon(first)) left = first
            if (isIcon(end) && (left == null || extra >= 2)) right = end
        } else {
            if (isIcon(end)) right = end
            if (isIcon(first) && (right == null || extra >= 2)) left = first
        }
        // Simgeler çıkınca kalan parçalar sözcüklerden çok olamaz: harfleri aralıklı tek sözcük simge sanılmaz.
        if (spans.size - (if (left == null) 0 else 1) - (if (right == null) 0 else 1) > words) return none
        return Icons(left, right, if (left != null) spans[1].l else l, if (right != null) spans[spans.size - 2].r else r)
    }

    private class Rect(val l: Int, val t: Int, val r: Int, val b: Int)
    private class Sample(val c: Rgb, val fx: Double, val top: Boolean)

    /** Swift `rounded()` gibi: yarım sıfırdan uzağa. */
    private fun round(value: Double): Int = if (value >= 0) floor(value + 0.5).toInt() else -floor(-value + 0.5).toInt()

    private fun rgbOf(value: Int) = Rgb((value shr 16) and 255, (value shr 8) and 255, value and 255)

    /** Ölçümler (hedeflerle aynı sırada). [width]/[height]: karenin piksel boyu; [color]: (x, y) noktası, 0xRRGGBB. */
    fun paints(targets: List<Target>, width: Int, height: Int, color: (Int, Int) -> Int): List<TextPaint> {
        if (width <= 0 || height <= 0) return emptyList()
        val fw = width.toDouble()
        val fh = height.toDouble()
        val pixel = { x: Int, y: Int -> rgbOf(color(x, y)) }
        // Hedeflerin piksel kutuları (öbür hedefler engeldir); karenin dışına taşan kutu kareye kırpılır (#1255).
        fun px(v: Double, size: Int, up: Boolean): Int {
            if (!v.isFinite()) return if (v > 0) size else 0
            val p = if (up) ceil(v * size) else floor(v * size)
            return p.coerceIn(0.0, size.toDouble()).toInt()
        }
        val rects = targets.map { t ->
            Rect(px(t.box.left, width, false), px(t.box.top, height, false), px(t.box.right, width, true), px(t.box.bottom, height, true))
        }
        val result = mutableListOf<TextPaint>()
        for ((index, target) in targets.withIndex()) {
            val bg = rgb(target.background)
            val fg = rgb(target.foreground)
            val line = max(1.0, target.lineHeight * fh)
            fun isInk(c: Rgb): Boolean {
                val toBg = distance(c, bg)
                return toBg > INK_DISTANCE && distance(c, fg) < toBg
            }
            // Kutunun ucundaki kendi simgesi (0. adım): öbür hedefler gibi engeldir; araya `GAP_LINES` boşluk kalır.
            val zones = mutableListOf<Span>()
            fun others(x: Int, y: Int): Boolean = zones.any { x >= it.l && x < it.r } || rects.indices.any { j ->
                j != index && x >= rects[j].l && x < rects[j].r && y >= rects[j].t && y < rects[j].b
            }
            fun inkRow(y: Int, x0: Int, x1: Int): Boolean {
                if (y < 0 || y >= height || x1 <= x0) return false
                val step = max(1, (x1 - x0) / 200)
                var n = 0
                var ink = 0
                var x = max(0, x0)
                val end = min(width, x1)
                while (x < end) {
                    if (others(x, y)) return false
                    n++
                    if (isInk(pixel(x, y))) ink++
                    x += step
                }
                return n > 0 && ink >= max(2, ceil(INK_SHARE * n).toInt())
            }
            fun inkColumn(x: Int, y0: Int, y1: Int): Boolean {
                if (x < 0 || x >= width || y1 <= y0) return false
                var n = 0
                var ink = 0
                for (y in max(0, y0) until min(height, y1)) {
                    if (others(x, y)) return false
                    n++
                    if (isInk(pixel(x, y))) ink++
                }
                return n > 0 && ink >= max(1, ceil(INK_SHARE * n).toInt())
            }
            val own = rects[index]
            var l = own.l
            var t = own.t
            var r = own.r
            var b: Int
            // 0) Kutunun ucundaki simge (#1266, #1267): yazı tanıma kutusu menü/tuş simgesini de alıyordu; kutu simgenin
            // üstüne çiziliyor, simge kayboluyordu. Simge kutudan çıkar ve engel olur: örtü, kenar payı ve uzama ona girmez.
            var iconLeft = false
            var iconRight = false
            if (target.rows <= 1) {
                val found = iconSpans(l, r, line, target.words, target.align) { at -> inkColumn(at, own.t, own.b) }
                val keep = ceil(ScreenFit.GAP_LINES * line).toInt()
                found.left?.let { zones.add(Span(it.l - keep, it.r + keep)); iconLeft = true }
                found.right?.let { zones.add(Span(it.l - keep, it.r + keep)); iconRight = true }
                l = found.textLeft
                r = found.textRight
            }
            val textLeft = l
            val textRight = r
            // 1) Örtü: yazı tanıma kutusunun dışına taşan harf noktaları (bitişik satır/sütunlar) kutuya katılır.
            val reach = max(1, round(REACH_LINES * line))
            var y = own.b
            while (y < min(height, own.b + reach) && inkRow(y, l, r)) y++
            b = y
            y = t - 1
            while (y >= max(0, own.t - reach) && inkRow(y, l, r)) y--
            t = y + 1
            var x = r
            while (x < min(width, textRight + reach) && inkColumn(x, t, b)) x++
            r = x
            x = l - 1
            while (x >= max(0, textLeft - reach) && inkColumn(x, t, b)) x--
            l = x + 1
            // Kenar payı: yazının yanındaki boş noktalar; ötesinde başka yazı/simge varsa pay ona değmez.
            val margin = max(1, min(MARGIN_MAX, round(MARGIN_LINES * line)))
            fun pad(blank: (Int) -> Boolean): Int {
                var k = 0
                while (k < margin && blank(k + 1)) k++
                return k
            }
            val padL = pad { k -> l - k >= 0 && !inkColumn(l - k, t, b) && (t until b).none { others(l - k, it) } }
            val padR = pad { k -> r - 1 + k < width && !inkColumn(r - 1 + k, t, b) && (t until b).none { others(r - 1 + k, it) } }
            val padT = pad { k -> t - k >= 0 && !inkRow(t - k, l, r) }
            val padB = pad { k -> b - 1 + k < height && !inkRow(b - 1 + k, l, r) }
            val cl = l - padL
            val cr = r + padR
            val ct = t - padT
            val cb = b + padB
            val cover = TextBox(cl / fw, ct / fh, cr / fw, cb / fh)

            // 2) Zemin: kutunun üstündeki ve altındaki şerit (yanlarda simge olabilir); sol/sağ üçte bir ve üst/alt farkı.
            val strip = max(2, round(0.25 * line))
            val samples = mutableListOf<Sample>()
            fun collect(y0: Int, y1: Int, top: Boolean) {
                if (y0 < 0 || y1 > height || y1 <= y0) return
                val step = max(1, (cr - cl) / 64)
                val rowStep = max(1, (y1 - y0) / 4)
                val found = mutableListOf<Sample>()
                var yy = y0
                while (yy < y1) {
                    var xx = max(0, cl)
                    val end = min(width, cr)
                    while (xx < end) {
                        if (others(xx, yy)) return
                        val c = pixel(xx, yy)
                        if (!isInk(c)) found.add(Sample(c, (xx - cl).toDouble() / max(1, cr - cl - 1), top))
                        xx += step
                    }
                    yy += rowStep
                }
                samples += found
            }
            collect(ct - strip, ct, top = true)
            collect(cb, cb + strip, top = false)
            var paint = TextPaint(target.background, pitch(target), cover,
                iconSide = if (iconLeft == iconRight) null else if (iconLeft) "left" else "right")
            if (samples.size >= 16) {
                val all = samples.map { it.c }
                val average = mean(all)
                if (distance(average, bg) <= TRUST_DISTANCE) {
                    val left = samples.filter { it.fx < 1.0 / 3 }.map { it.c }
                    val right = samples.filter { it.fx > 2.0 / 3 }.map { it.c }
                    val above = samples.filter { it.top }.map { it.c }
                    val below = samples.filter { !it.top }.map { it.c }
                    // Desen: her parçanın kendi içindeki sapması (degrade kendi başına desen sayılmaz).
                    val parts = listOf(true, false).flatMap { side ->
                        (0 until 3).map { third -> samples.filter { it.top == side && min(2, (it.fx * 3).toInt()) == third }.map { it.c } }
                    }.filter { it.size >= 4 }
                    val spread = if (parts.isEmpty()) deviation(all) else parts.sumOf { deviation(it) } / parts.size
                    val dh = if (left.size >= 4 && right.size >= 4) distance(mean(left), mean(right)) else 0
                    val dv = if (above.size >= 4 && below.size >= 4) distance(mean(above), mean(below)) else 0
                    paint = when {
                        spread > PATTERN_DEVIATION -> paint.copy(patterned = true, background = hex(average))
                        dh >= GRADIENT_STEP && dh >= dv -> {
                            // Üçte birlerin ortası 1/6 ve 5/6'da: uçlara doğrusal uzatılır.
                            val a = mean(left)
                            val z = mean(right)
                            paint.copy(background = hex(extend(a, z, 0.25)), background2 = hex(extend(z, a, 0.25)), direction = "h")
                        }
                        dv >= GRADIENT_STEP -> {
                            val a = mean(above)
                            val z = mean(below)
                            // Şeritlerin ortası kutunun yarım şerit dışında: uçlar içeri doğru aradeğerlenir.
                            val span = (cb - ct + strip).toDouble()
                            val inward = if (span > 0) strip.toDouble() / 2 / span else 0.0
                            paint.copy(background = hex(extend(a, z, -inward)), background2 = hex(extend(z, a, -inward)), direction = "v")
                        }
                        else -> paint.copy(background = hex(average))
                    }
                }
            }

            // 3) Boş alan: tek satırlık etiket hizasının açık tarafına (sağa yaslıda sola, sola yaslıda sağa, ortalıda iki
            // yana) uzayabilir; başka yazıya, simgeye, kutu kenarına ya da karenin kenarına `GAP_LINES` kala durur. Kutunun
            // ucunda simge varsa yalnız simgenin öbür yanına uzar (sağdaki tuş simgesinde sola, soldaki menü simgesinde sağa).
            if (target.rows <= 1) {
                val sixth = max(1, (cb - ct) / 6)
                val band = mutableListOf<Int>()
                run {
                    var yy = ct + sixth
                    val end = max(ct + 1, cb - sixth)
                    while (yy < end) {
                        band.add(min(height - 1, max(0, yy)))
                        yy += sixth
                    }
                }
                val gap = ceil(ScreenFit.GAP_LINES * line).toInt()
                val limit = round(GROW_LINES * line)
                fun scan(start: Int, step: Int, first: Rgb): Int {
                    var ground = first
                    var at = start
                    val end = if (step < 0) max(-1, start - limit) else min(width, start + limit)
                    // Sınır karşılaştırması ve adım sınırı: başlangıç karenin dışında kalsa da döngü biter (#1255).
                    var steps = 0
                    while ((if (step < 0) at > end else at < end) && at >= 0 && at < width && steps <= width) {
                        steps++
                        if (band.any { others(at, it) } || rects.indices.any { j ->
                                j != index && at >= rects[j].l && at < rects[j].r && rects[j].b > ct && rects[j].t < cb
                            }) return at - step * gap
                        var sr = 0
                        var sg = 0
                        var sb = 0
                        for (yy in band) {
                            val c = pixel(at, yy)
                            if (distance(c, ground) > ScreenFit.INK_DISTANCE) return at - step * gap
                            sr += c.r
                            sg += c.g
                            sb += c.b
                        }
                        val n = band.size
                        // Degrade zeminde zemin yavaşça izlenir (ScreenFit.withRoom ile aynı).
                        ground = Rgb((ground.r * 7 + sr / n) / 8, (ground.g * 7 + sg / n) / 8, (ground.b * 7 + sb / n) / 8)
                        at += step
                    }
                    return if (step < 0) max(0, end + 1) else min(width, end)
                }
                val startColor = rgb(paint.background)
                val endColor = rgb(paint.background2 ?: paint.background)
                var gl = cl
                var gr = cr
                val toLeft = !iconLeft && (target.align != "left" || iconRight)
                val toRight = !iconRight && (target.align != "right" || iconLeft)
                if (band.isNotEmpty() && toLeft) gl = min(cl, max(0, scan(cl - 1, -1, startColor) + 1))
                if (band.isNotEmpty() && toRight) gr = max(cr, min(width, scan(cr, 1, endColor)))
                if (gl < cl || gr > cr) paint = paint.copy(grow = TextBox(gl / fw, cover.top, gr / fw, cover.bottom))
            }
            result.add(paint)
        }
        // 4) Grup: aynı sütunda (ortak sol ya da sağ kenar, düzenli aralık) ya da aynı satırda duran, BÜYÜK HARF'i ve
        // satır yüksekliği aynı tek satırlık etiketler.
        for ((members, id) in groups(targets)) for (i in members) result[i] = result[i].copy(group = id)
        return result
    }

    /** Kare üzerinden ölçüm: [color] verilirse gerçek renk (0xRRGGBB), yoksa gri ton. */
    fun paints(targets: List<Target>, frame: GrayFrame, color: ((Int, Int) -> Int)? = null): List<TextPaint> {
        if (!frame.isValid) return emptyList()
        return paints(targets, frame.width, frame.height, color ?: { x, y -> frame.at(x, y).let { (it shl 16) or (it shl 8) or it } })
    }

    /** Satır aralığı: çok satırlı yazıda kutudan ((satır sayısı - 1) aralık + bir satır yüksekliği), tek satırda satır yüksekliği. */
    internal fun pitch(target: Target): Double {
        val height = target.box.bottom - target.box.top
        if (target.rows <= 1 || target.lineHeight <= 0) return if (target.lineHeight > 0) target.lineHeight else height
        return max(target.lineHeight, (height - target.lineHeight) / (target.rows - 1))
    }

    /** Grup üyeleri ve numarası (grubun en küçük sıra numarası); tek üyeli grup yok. */
    internal fun groups(targets: List<Target>): List<Pair<List<Int>, Int>> {
        val labels = targets.indices.filter { targets[it].rows <= 1 }
        val parent = labels.associateWith { it }.toMutableMap()
        fun root(start: Int): Int {
            var i = start
            while (parent[i] != i) i = parent[i]!!
            return i
        }
        fun overlap(a: TextBox, b: TextBox): Double =
            max(0.0, min(a.bottom, b.bottom) - max(a.top, b.top)) / max(1e-9, min(a.bottom - a.top, b.bottom - b.top))
        for (a in labels) for (b in labels) {
            if (b <= a) continue
            val x = targets[a]
            val y = targets[b]
            val line = max(x.lineHeight, y.lineHeight)
            if (x.upper != y.upper || abs(x.lineHeight - y.lineHeight) > SAME_LINE * line) continue
            // Satır yüksekliği kareye oranla; yatay pay aynı piksele denk gelsin diye en-boy oranı bilinmez, yarım satır
            // yüksekliğinin yarısı kadar (16:9'da ~0,28 satır) alınır.
            val tolerance = 0.5 * line * 9 / 16
            val sameRow = overlap(x.box, y.box) >= 0.5
            val column = (abs(x.box.left - y.box.left) <= tolerance || abs(x.box.right - y.box.right) <= tolerance) &&
                overlap(x.box, y.box) == 0.0 && abs(x.box.top - y.box.top) <= 3 * line
            if (sameRow || column) parent[root(a)] = root(b)
        }
        return labels.groupBy { root(it) }.values.filter { it.size >= 2 }.map { it.sorted() to it.min() }.sortedBy { it.second }
    }

    fun rgb(hex: String): Rgb {
        if (hex.length != 7 || hex[0] != '#') return Rgb(0, 0, 0)
        val value = hex.substring(1).toIntOrNull(16) ?: return Rgb(0, 0, 0)
        return rgbOf(value)
    }

    fun hex(c: Rgb): String = String.format(java.util.Locale.ROOT, "#%02X%02X%02X", c.r.coerceIn(0, 255), c.g.coerceIn(0, 255), c.b.coerceIn(0, 255))

    fun distance(a: Rgb, b: Rgb): Int = maxOf(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))

    internal fun mean(list: List<Rgb>): Rgb {
        val n = max(1, list.size)
        return Rgb(list.sumOf { it.r } / n, list.sumOf { it.g } / n, list.sumOf { it.b } / n)
    }

    /** [a]'dan [b]'nin tersine [share] kadar (eksiyse [b]'ye doğru) uzatılmış renk. */
    internal fun extend(a: Rgb, b: Rgb, share: Double): Rgb {
        fun one(x: Int, y: Int) = round(x + (x - y) * share)
        return Rgb(one(a.r, b.r), one(a.g, b.g), one(a.b, b.b))
    }

    internal fun deviation(list: List<Rgb>): Double {
        if (list.isEmpty()) return 0.0
        fun spread(values: List<Int>): Double {
            val average = values.sum().toDouble() / values.size
            return sqrt(values.sumOf { (it - average) * (it - average) } / values.size)
        }
        return (spread(list.map { it.r }) + spread(list.map { it.g }) + spread(list.map { it.b })) / 3
    }
}
