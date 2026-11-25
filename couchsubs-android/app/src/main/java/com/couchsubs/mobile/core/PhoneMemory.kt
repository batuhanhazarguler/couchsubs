// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

/**
 * Telefonun açılışları arasında kalan hafıza: mesajların çevirisi ve panelin yazı boyu. Önceden ikisi de telefon
 * oturumunun içindeydi; telefon izleyicisi telefonu bir an kaybedince oturum kapanıyor, yeniden açılışta aynı İngilizce
 * mesajlar motora yeniden gidiyor (yapay zekâ her seferinde biraz başka Türkçe veriyordu) ve yazı boyu baştan ölçülüyordu
 * (X, 22 Kas: "her saniye şekli de hareketi de değişiyor"). Çeviri durunca ([RegionWatcher.reset]) unutulur. Mac/iPhone
 * (PhoneMemory.swift) ve Windows (PhoneMemory.cs) aynı kural, aynı sınır.
 */
internal class PhoneMemory {
    companion object {
        /** En çok bu kadar mesajın çevirisi tutulur; dolunca en eskisi düşer. */
        const val CAPACITY = 256
    }

    private val translations = HashMap<String, String>()
    private val keys = ArrayDeque<String>()

    /** Yanda Panel'in kilitli telefon yeri ve yazı boyu ([PhonePanelSteady]). */
    val steady = PhonePanelSteady()

    /** Telefon listesi kartlarının kesilmiş avatarları, rozetleri ve seçim çerçeveleri ([PhoneListLook]). */
    val rows = PhoneListLook()

    /** Bilinen çevirilerin anlık kopyası. */
    val known: Map<String, String> @Synchronized get() = HashMap(translations)

    /** Bu okunuşun çevirisi birebir biliniyor mu. */
    @Synchronized fun knows(source: String): Boolean = translations.containsKey(source)

    /** Mesajın bilinen çevirisi: birebir aynı okunuşunki, yoksa aynı mesajın biraz farklı okunuşununki. */
    @Synchronized fun translation(source: String): String? = PhoneSteady.translation(source, translations)

    @Synchronized fun remember(source: String, translation: String) {
        if (translations[source] == null) {
            if (keys.size >= CAPACITY) translations.remove(keys.removeFirst())
            keys.addLast(source)
        }
        translations[source] = translation
    }

    /** Çeviri durdu ya da hat yeniden kuruldu. */
    @Synchronized fun clear() {
        translations.clear()
        keys.clear()
        steady.forget()
        rows.clear()
    }
}
