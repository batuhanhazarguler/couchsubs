// SPDX-License-Identifier: AGPL-3.0-only
// Masaüstündeki windows/src/CouchSubs.TvInstall/TvLane.cs ve Mac/iPhone'daki TVLane.swift ile aynı kural.
package com.couchsubs.mobile.tv

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit

/**
 * TV adresi başına tek kanal: aynı TV'ye giden geliştirici bağlantıları (Samsung sdb, Android TV ADB) sırayla çalışır.
 *
 * #1223 (Windows beta.93, Samsung): çeviri başlarken bekçinin açma denemesi (sdb `was_execute`) ile sürüm denetimi / kurulum
 * aynı saniyede aynı TV'ye ayrı sdb oturumları açıyordu; TV bağlantıyı zorla kapatıyor, kurulum "TV bu cihazı kabul etmedi"
 * diye bitiyordu. "Güncelle"ye arka arkaya basılınca aynı TV'ye birden çok kurulum başlıyordu. Artık:
 * - Aynı TV'deki işlemler sırayla çalışır; kurulum sürerken bekçinin açma denemesi kurulumun bitmesini bekler. Takılan bir
 *   işlem kanalı sonsuza dek tutmasın diye en çok [DEFAULT_MAX_WAIT_MS] beklenir, sonra beklemeden sürülür ve günlüğe yazılır.
 * - Aynı TV için kurulum sürerken gelen ikinci kurulum isteği yeni kurulum başlatmaz; sürenin sonucunu bekler.
 * Aynı iş parçacığında iç içe çağrı (kanalı tutan işlemin aynı TV'ye yeniden girmesi) beklemeden çalışır.
 */
class TvLane(private val maxWaitMs: Long = DEFAULT_MAX_WAIT_MS) {
    companion object {
        /** Kanalı tutan işlem en çok bu kadar beklenir (kurulumun her adımının ayrıca süre sınırı var, bkz. [TvStall]). */
        const val DEFAULT_MAX_WAIT_MS = 300_000L

        /** Uygulamanın ortak kanalı. */
        val shared = TvLane()

        /** Kanalın anahtarı: adres, boşluksuz ve küçük harfle. */
        fun key(host: String) = host.trim().lowercase()
    }

    private val gates = ConcurrentHashMap<String, Semaphore>()
    private val busy = ConcurrentHashMap.newKeySet<String>()
    private val installs = ConcurrentHashMap<String, Install>()
    private val held = ThreadLocal.withInitial { HashSet<String>() }

    private class Install {
        val done = CountDownLatch(1)
        @Volatile var result: Result<Any?>? = null
    }

    /** Bu TV'de şu an bir işlem sürüyor mu. */
    fun isBusy(host: String) = busy.contains(key(host))

    /** Bu TV'de şu an kurulum sürüyor mu. */
    fun isInstalling(host: String) = installs.containsKey(key(host))

    /** [work]'ü bu TV'nin kanalında çalıştırır: aynı TV'deki başka işlem bitene kadar bekler. Bloklar. */
    fun <T> run(host: String, what: String, log: (String) -> Unit = {}, work: () -> T): T {
        val key = key(host)
        if (key.isEmpty() || key in held.get()) return work()
        val gate = gates.computeIfAbsent(key) { Semaphore(1, true) }
        var entered = gate.tryAcquire()
        if (!entered) {
            log("TV $host: aynı TV'de başka bir işlem sürüyor; $what sırasını bekliyor (aynı anda iki bağlantıyı TV kapatıyor)")
            entered = gate.tryAcquire(maxWaitMs, TimeUnit.MILLISECONDS)
            if (!entered) log("TV $host: önceki işlem ${maxWaitMs / 60_000} dk'da bitmedi; $what beklemeden başlıyor")
        }
        busy.add(key)
        held.get().add(key)
        try {
            return work()
        } finally {
            held.get().remove(key)
            busy.remove(key)
            if (entered) gate.release()
        }
    }

    /**
     * Kurulumu bu TV'nin kanalında çalıştırır. Aynı TV'de kurulum zaten sürüyorsa yenisi başlatılmaz: sürenin sonucu (ya da
     * hatası) döner. Bloklar.
     */
    @Suppress("UNCHECKED_CAST")
    fun <T> install(host: String, log: (String) -> Unit = {}, work: () -> T): T {
        val key = key(host)
        if (key.isEmpty() || key in held.get()) return work()
        val mine = Install()
        val running = installs.putIfAbsent(key, mine)
        if (running != null) {
            log("TV $host: kurulum zaten sürüyor; yeni kurulum başlatılmadı, sürenin bitmesi bekleniyor")
            running.done.await()
            return running.result!!.getOrThrow() as T
        }
        try {
            val value = run(host, "kurulum", log, work)
            mine.result = Result.success(value)
            return value
        } catch (error: Throwable) {
            mine.result = Result.failure(error)
            throw error
        } finally {
            installs.remove(key, mine)
            mine.done.countDown()
        }
    }
}
