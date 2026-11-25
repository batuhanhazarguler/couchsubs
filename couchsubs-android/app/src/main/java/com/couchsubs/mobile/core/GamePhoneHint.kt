// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * "Telefon çevirisi kapalı, açmak ister misiniz?" ipucu (#1202): GTA 6 telefonu ayarı kapalıyken telefonun mesaj listesi
 * altyazı alanına düşünce altyazı yolu onu sahne yazısı sayıp atıyor ("eğik satır", "koyu yazı açık zeminde"), kullanıcı
 * telefonun neden çevrilmediğini anlamıyordu. Böyle bir ret oturumda bir kez ipucu doğurur. Mac/iPhone ve Windows
 * (GamePhoneHint) aynı kuralı uygular.
 */
class GamePhoneHint {
    /** Bu oturumda ipucu önerildi. */
    var offered = false
        private set
    /** Telefonun art arda kaç bakışta bulunduğu ([observePhone]); tek karelik yanlış bulma ipucu doğurmasın. */
    private var sightings = 0

    /** Sahne yazısı reddi ipucu doğurur mu: telefon kapalı, oyun GTA 6, neden telefon listesine uyuyor; oturumda bir kez. */
    fun observe(reason: String, readsPhone: Boolean, game: String?): Boolean {
        if (offered || readsPhone || game == null || GameName.key(game) != "gta 6" || !isPhoneList(reason)) return false
        offered = true
        return true
    }

    /**
     * Altyazı okuması telefonu aradı (telefon ayarı kapalıyken de GTA 6'da aranır, #1282). Telefon kapalıyken telefonun
     * mesaj listesi altyazı olarak kabul edilip çevrilip gidip geliyordu; sahne yazısı reddi olmadığı için ipucu da
     * çıkmıyordu. Telefon art arda [PHONE_SIGHTINGS] bakışta bulunursa ipucu oturumda bir kez önerilir (Mac/iPhone ve
     * Windows ile aynı).
     */
    fun observePhone(found: Boolean, readsPhone: Boolean, game: String?): Boolean {
        sightings = if (found) sightings + 1 else 0
        if (offered || readsPhone || game == null || GameName.key(game) != "gta 6" || sightings < PHONE_SIGHTINGS) return false
        offered = true
        return true
    }

    /** Yeni oturum: ipucu yeniden önerilebilir. */
    fun reset() {
        offered = false
        sightings = 0
    }

    companion object {
        /** İpucu için telefonun art arda bulunması gereken bakış sayısı (bakışlar [GamePhoneTracker.INTERVAL_MS] arayla). */
        const val PHONE_SIGHTINGS = 2

        /** Telefonun mesaj listesinin altyazı yolunda aldığı ret nedenleri (eğik satır, açık zeminde koyu yazı). */
        fun isPhoneList(reason: String): Boolean = reason.startsWith("eğik satır") || reason == InkTone.REASON
    }
}
