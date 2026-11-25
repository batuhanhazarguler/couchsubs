// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.abs

/**
 * Telefon listesi kartlarının ([ScreenPhoneCard.ListRow]) oyundan kesilen görüntüleri: avatar (bileşende simge), sağdaki
 * rozet ve seçili satırın çerçevesi. Sinan Bey (beta.100, 3399): kart telefondaki satırın Türkçe kopyası olsun; avatar,
 * okunmamış kırmızı nokta (avatarın köşesinde, kesilen resmin içinde kalır), rozet ve seçim çerçevesi de.
 *
 * Kararlılık (#1279): aynı satırın resmi bir kez kesilir ve saklanır (anahtar: kişi adının özgün yazısı); her okumada
 * yeniden kesilen resim, sıkıştırma gürültüsüyle her gönderiyi farklı gösterip TV'de titretirdi. Rozet ve seçim ancak
 * art arda [TURNS] okumada aynı yeni değeri gösterirse değişir. Resimler küçük PNG'dir (en çok [AVATAR_MAX] piksel).
 * Mac/iPhone (PhoneListLook.swift) ve Windows (PhoneListLook.cs) aynı kuralı, aynı eşikleri kullanır.
 */
class PhoneListLook {
    companion object {
        /** Avatarın ve rozetin en uzun kenarı (piksel). */
        const val AVATAR_MAX = 48
        const val BADGE_MAX = 32
        /** Rozet ve seçim bu kadar art arda okumada aynı yeni değeri gösterirse değişir. */
        const val TURNS = 2
        /** En çok bu kadar satır saklanır (dolunca hepsi unutulur). */
        const val CAPACITY = 64
        /**
         * Satırın üstünde seçim çerçevesi var mı: kutunun bir yatay sırasındaki noktaların en az [FRAME_SHARE]'i mavi.
         */
        const val FRAME_SHARE = 0.6
        /**
         * Rozetin yerinde düz kart zemini değil bir simge var mı: noktaların en az [BADGE_SHARE]'i zeminden (kutunun
         * köşelerinin ortancası) belirgin farklı ve renkli/koyu.
         */
        const val BADGE_SHARE = 0.12

        /** Belirgin mavi (seçim çerçevesi, gönder rozeti). */
        internal fun isBlue(c: Int): Boolean {
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            return b >= 140 && b - (r + g) / 2 >= 45
        }

        /** Örnek ızgarası (kutunun içinde [columns]×[rows] nokta). */
        internal fun samples(box: TextBox, width: Int, height: Int, columns: Int, rows: Int, color: (Int, Int) -> Int): List<List<Int>> =
            (0 until rows).map { j ->
                val y = minOf(height - 1, maxOf(0, ((box.top + (j + 0.5) / rows * (box.bottom - box.top)) * height).toInt()))
                (0 until columns).map { i ->
                    val x = minOf(width - 1, maxOf(0, ((box.left + (i + 0.5) / columns * (box.right - box.left)) * width).toInt()))
                    color(x, y)
                }
            }

        /** Seçim çerçevesinin rengi (mavi noktaların ortalaması); çerçeve yoksa null. */
        internal fun frameColor(box: TextBox, width: Int, height: Int, color: (Int, Int) -> Int): String? {
            val grid = samples(box, width, height, 24, 12, color)
            for (line in grid) {
                val blue = line.filter(::isBlue)
                if (blue.size >= line.size * FRAME_SHARE) {
                    val r = blue.sumOf { (it shr 16) and 0xFF } / blue.size
                    val g = blue.sumOf { (it shr 8) and 0xFF } / blue.size
                    val b = blue.sumOf { it and 0xFF } / blue.size
                    return String.format(java.util.Locale.ROOT, "#%02X%02X%02X", r, g, b)
                }
            }
            return null
        }

        internal fun hasBadge(box: TextBox, width: Int, height: Int, color: (Int, Int) -> Int): Boolean {
            val grid = samples(box, width, height, 10, 10, color)
            fun tone(c: Int) = (((c shr 16) and 0xFF) + 2 * ((c shr 8) and 0xFF) + (c and 0xFF)) / 4
            val base = listOf(grid[0][0], grid[0][9], grid[9][0], grid[9][9]).map(::tone).sorted()[1]
            val marked = grid.flatten().count { c ->
                val r = (c shr 16) and 0xFF
                val g = (c shr 8) and 0xFF
                val b = c and 0xFF
                maxOf(r, g, b) - minOf(r, g, b) >= 60 && abs(tone(c) - base) >= 25
            }
            return marked >= 100 * BADGE_SHARE
        }
    }

    private class Entry {
        var avatar: String? = null
        var badge: String? = null
        var selected: String? = null
        /** Bekleyen yeni değer; [hasPendingBadge] false ise bekleyen yok (bekleyen değer null da olabilir). */
        var pendingBadge: String? = null
        var hasPendingBadge = false
        var pendingSelected: String? = null
        var hasPendingSelected = false
        var badgeVotes = 0
        var selectedVotes = 0
    }

    /** Oylamanın sonucu: geçerli değer, bekleyen (varsa) ve oy sayısı. */
    private class Vote(var current: String?, var pending: String?, var hasPending: Boolean, var votes: Int)

    private val entries = HashMap<String, Entry>()

    @Synchronized fun clear() = entries.clear()

    /** Kare ([PhoneImage]) üzerinden. */
    fun apply(items: List<ScreenTranslation.Item>, frame: PhoneImage): List<ScreenTranslation.Item> {
        if (items.none { it.listRow != null }) return items
        return apply(items, frame.width, frame.height) { x, y -> frame.rgb(x, y) }
    }

    /** Liste kartlarına resimleri koyar. [color]: karenin (x, y) pikseli, 0xRRGGBB. */
    @Synchronized
    fun apply(items: List<ScreenTranslation.Item>, width: Int, height: Int, color: (Int, Int) -> Int): List<ScreenTranslation.Item> {
        if (width <= 0 || height <= 0) return items
        if (entries.size > CAPACITY) entries.clear()
        return items.map { item ->
            val row = item.listRow ?: return@map item
            val key = (if (row.widget) "w|" else "r|") + item.source.split('\n').first()
            val first = entries[key] == null
            val entry = entries[key] ?: Entry()
            if (entry.avatar == null) row.portraitSpot?.let { spot ->
                entry.avatar = TextPainter.portraitImage(spot, width, height, color, AVATAR_MAX)
            }
            row.badgeSpot?.let { spot ->
                val fresh = if (hasBadge(spot, width, height, color)) TextPainter.portraitImage(spot, width, height, color, BADGE_MAX) else null
                val vote = Vote(entry.badge, entry.pendingBadge, entry.hasPendingBadge, entry.badgeVotes)
                vote(fresh, vote, first)
                entry.badge = vote.current
                entry.pendingBadge = vote.pending
                entry.hasPendingBadge = vote.hasPending
                entry.badgeVotes = vote.votes
            }
            row.frameSpot?.let { spot ->
                val fresh = frameColor(spot, width, height, color)
                val vote = Vote(entry.selected, entry.pendingSelected, entry.hasPendingSelected, entry.selectedVotes)
                vote(fresh, vote, first)
                entry.selected = vote.current
                entry.pendingSelected = vote.pending
                entry.hasPendingSelected = vote.hasPending
                entry.selectedVotes = vote.votes
            }
            entries[key] = entry
            item.copy(listRow = row.copy(avatar = entry.avatar, badge = entry.badge, selected = entry.selected))
        }
    }

    /**
     * Yeni değer (varlığı geçerli değerden farklı) art arda [TURNS] okumada gelirse geçer; ilk görülen satırda hemen geçer.
     * Değerler varlıklarıyla karşılaştırılır (iki ayrı kesilmiş rozet aynı sayılır; iPhone ile aynı).
     */
    private fun vote(fresh: String?, state: Vote, first: Boolean) {
        fun same(a: String?, b: String?) = (a == null) == (b == null)
        if (first) {
            state.current = fresh
            return
        }
        if (same(fresh, state.current)) {
            state.votes = 0
            state.pending = null
            state.hasPending = false
            return
        }
        if (state.hasPending && same(state.pending, fresh)) {
            state.votes += 1
        } else {
            state.pending = fresh
            state.hasPending = true
            state.votes = 1
        }
        if (state.votes >= TURNS) {
            state.current = fresh
            state.votes = 0
            state.pending = null
            state.hasPending = false
        }
    }
}
