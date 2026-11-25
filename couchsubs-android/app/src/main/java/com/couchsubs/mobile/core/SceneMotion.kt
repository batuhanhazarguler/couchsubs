// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Kamerayla kayan yazı (plaka, tabela, dükkân adı, haritadaki yer adı) altyazı değildir. Oyunun altyazısı ekranda hep
 * aynı yerde ve aynı boyda durur; oyun dünyasındaki yazı ise kamera, araç ya da harita oynadıkça yana kayar ya da
 * yaklaşıp büyür. Kullanıcı bildirimleri (GitHub #1259, #1203, GTA 6): "MOTOR OIL MOTOR OIL" tabelası, "Game Base" dükkân
 * adı, haritada "Tola Bay", teknedeki "Charters" yazısı altyazı alanından okunup çevriliyor, "Charters / We're doing that
 * tomorrow." diye konuşmanın başına yapışıyordu; kısa tek satır oldukları için [SceneText]'in plaka ve eğik satır
 * kurallarına takılmıyorlardı.
 *
 * Aynı yazı (birebir aynı okunan satır) [WINDOW_MS] içinde yatay ortası karenin genişliğinin [SHIFT] kadarı kaydıysa ya
 * da boyu [SCALE] katı değiştiyse kayan yazıdır; son kaydığı andan [HOLD_MS] sonrasına dek okumadan çıkarılır. Gerçek
 * altyazıyı düşürmemek için konuşan adlı satır ve küçük harfli, [MAX_WORDS]'ten uzun satır hiç çıkarılmaz; yalnız yatay
 * kayma ve boy değişimi sayılır (yukarı itilen altyazı satırı kalır); yalnız birebir aynı okuma, önceki okumalarla
 * karşılaştırılır. Tek karede hiçbir şey çıkarılmaz. Mac/iPhone (SceneMotion.swift) ve Windows (SceneMotion.cs) aynı
 * kuralları ve eşikleri uygular; ortak deneme dosyası fixtures/scene-motion.json.
 */
class SceneMotion {
    companion object {
        /** Kayma bu süre içindeki ilk görüşe göre ölçülür (yavaş kayan yazı birikerek yakalanır). */
        const val WINDOW_MS = 2000L
        /** Yatay ortanın en az bu kadar kayması (karenin genişliğine oranla). */
        const val SHIFT = 0.02
        /** Satır boyu en az bu kat değişirse (yaklaşan/uzaklaşan tabela) kayan yazıdır. */
        const val SCALE = 1.4
        /** Son kaymadan bu kadar sonra yazı yeniden aday olur. */
        const val HOLD_MS = 1000L
        /** Küçük harfli satır en çok bu kadar sözcükse kayan yazı sayılabilir. */
        const val MAX_WORDS = 3
        /** Günlükte atılma nedeni. */
        const val REASON = "kayan yazı (kamerayla kayan tabela/plaka)"

        /**
         * Satır kayan yazı sayılabilir mi: konuşan adı yok, en az üç harf/rakam; küçük harf taşıyorsa en çok [MAX_WORDS]
         * sözcük (konuşma cümlesi hiç çıkarılmaz).
         */
        internal fun eligible(text: String): Boolean {
            if (SpeakerPrefix.split(text) != null || text.count { it.isLetterOrDigit() } < 3) return false
            return text.none { it.isLowerCase() } || SceneText.wordCount(text) <= MAX_WORDS
        }

        private fun key(text: String) = text.trim().lowercase()
    }

    private class Anchor(
        val text: String,
        var center: Double,
        var height: Double,
        var since: Long,
        var lastSeen: Long,
        var movedAt: Long? = null,
    ) {
        fun moved(center: Double, height: Double): Boolean {
            if (abs(center - this.center) >= SHIFT) return true
            if (this.height <= 0 || height <= 0) return false
            return max(height, this.height) >= SCALE * min(height, this.height)
        }
    }

    private val anchors = mutableListOf<Anchor>()

    /** Son [filter] çağrısında kayan yazı sayılıp okumadan çıkarılan satırlar (günlük için). */
    var removed: List<TextLine> = emptyList()
        private set

    /**
     * Okumanın kayan yazıları çıkarılmış hali. Satır kutuları [area]'ya oranlıdır; [area] okunan alanın karedeki yeridir.
     * [time]: milisaniye saati.
     */
    fun filter(reading: Reading, area: TextBox, time: Long): Reading {
        val dropped = mutableListOf<TextLine>()
        anchors.removeAll { time - it.lastSeen > WINDOW_MS }
        val previous = anchors.filter { it.since < time }
        val used = mutableSetOf<Anchor>()
        val fresh = mutableListOf<Anchor>()
        val kept = mutableListOf<TextLine>()
        for (line in reading.lines) {
            val relative = line.box
            if (relative == null || !eligible(line.text)) {
                kept += line
                continue
            }
            val box = relative.placedIn(area)
            val text = key(line.text)
            val center = (box.left + box.right) / 2
            val height = box.bottom - box.top
            val match = previous.filter { it !in used && it.text == text }.minByOrNull { abs(it.center - center) }
            if (match == null) {
                fresh += Anchor(text, center, height, time, time)
                kept += line
                continue
            }
            used += match
            match.lastSeen = time
            if (match.moved(center, height)) {
                match.movedAt = time
                match.center = center
                match.height = height
                match.since = time
            } else if (time - match.since > WINDOW_MS) {
                // Yerinde duran yazının ölçüsü tazelenir: çok yavaş kayma (pencere başına SHIFT'ten az) birikmez.
                match.center = center
                match.height = height
                match.since = time
            }
            val moved = match.movedAt
            if (moved != null && time - moved <= HOLD_MS) dropped += line else kept += line
        }
        anchors += fresh
        removed = dropped
        return if (dropped.isEmpty()) reading else Reading(kept)
    }

    fun reset() {
        anchors.clear()
        removed = emptyList()
    }
}
