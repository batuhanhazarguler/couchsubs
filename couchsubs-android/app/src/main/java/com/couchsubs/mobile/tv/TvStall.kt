// SPDX-License-Identifier: AGPL-3.0-only
// Masaüstündeki windows/src/CouchSubs.TvInstall/TvStall.cs ve iPhone'daki TVStall.swift ile aynı adımlar ve süreler.
package com.couchsubs.mobile.tv

import com.couchsubs.mobile.tv.samsung.InstallStep
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Kurulumun bir adımı süresinde bitmedi: TV yanıt vermeyi kesti, bağlantı kapatıldı. IOException'dır: yakalanmadığı yerde
 * de "bağlantı koptu" yoluna düşer.
 */
class TvStepTimeoutException(val step: String, val limitMs: Long) :
    IOException("TV \"${TvStall.name(step)}\" adımında ${limitMs / 1000} sn yanıt vermedi") {
    /** İkinci denemede de takılınca kullanıcıya gösterilen ayrıntı. */
    val gaveUp: String get() = "$message; bir kez daha denendi, TV yine yanıt vermedi"
}

/**
 * TV uygulaması güncellemesinin bekçisi: her adımın (bağlanma, sürümü okuma, eski uygulamayı kapatma, kurulum, açma) süre
 * sınırı vardır; süre dolunca TV bağlantısı kapatılır, bekleyen okuma hatayla döner ve deneme [TvStepTimeoutException] ile
 * biter. Önceden yalnız soketin 120 sn'lik okuma süresi vardı, yeniden deneme yoktu: TV takılınca güncelleme dakikalarca
 * "kuruluyor"da kalıp "bağlantı koptu" diyordu.
 *
 * @param limits Adımların süreleri (ms; testlerde kısaltılır); null: sınırsız.
 */
class TvStall(private val limits: (String) -> Long? = { limitFor(it) }) {
    companion object {
        /**
         * Adımların süre sınırı (ms); kullanıcının bir şey yaptığı adımlarda (Samsung girişi, TV'deki Play sayfası) sınır
         * yoktur. Android TV'de onay adımı TV'deki soruyu (en çok 90 sn) bekler.
         */
        fun limitFor(step: String): Long? = when (step) {
            "connecting" -> 45_000L
            "approve" -> 150_000L
            "pairing", "reading", "launching" -> 60_000L
            "signin", "play" -> null
            "certificate" -> 240_000L
            "closing" -> 30_000L
            "installing" -> 360_000L
            else -> 120_000L
        }

        /** Adımın günlükte ve hata ayrıntısında görünen adı. */
        fun name(step: String): String = when (step) {
            "connecting" -> "bağlanma"
            "approve" -> "TV'de onay"
            "pairing" -> "eşleme"
            "reading" -> "TV'deki sürümü okuma"
            "certificate" -> "sertifika"
            "signing" -> "paket imzalama"
            "closing" -> "eski uygulamayı kapatma"
            "installing" -> "paket gönderme ve kurulum"
            "uninstalling" -> "eski kopyayı kaldırma"
            "launching" -> "uygulamayı açma"
            else -> step
        }

        /** Arayüzün adımı bekçinin adımına. */
        fun key(step: InstallStep): String = when (step) {
            InstallStep.CONNECTING -> "connecting"
            InstallStep.READING -> "reading"
            InstallStep.SIGN_IN -> "signin"
            InstallStep.CERTIFICATE -> "certificate"
            InstallStep.SIGNING -> "signing"
            InstallStep.INSTALLING -> "installing"
            InstallStep.UNINSTALLING -> "uninstalling"
            InstallStep.LAUNCHING -> "launching"
            InstallStep.PAIRING -> "pairing"
            InstallStep.APPROVE_ON_TV -> "approve"
            InstallStep.KEY -> "key"
            InstallStep.OPEN_PLAY -> "play"
        }

        private val timer = Executors.newSingleThreadScheduledExecutor { task -> Thread(task, "tv-stall").apply { isDaemon = true } }

        /**
         * İlk deneme takıldıysa ya da bağlantı koptuysa ([retryable]) günlüğe yazılır ve yeni bağlantıyla bir kez daha
         * denenir. İkinci denemenin hatası olduğu gibi yükselir.
         */
        fun <T> retryOnce(log: (String) -> Unit, retryable: (Exception) -> Boolean, attempt: (Int) -> T): T {
            try {
                return attempt(1)
            } catch (error: Exception) {
                if (!retryable(error)) throw error
                log("Takıldı: ${error.message}; bağlantı kapatıldı, bir kez daha deneniyor.")
            }
            return attempt(2)
        }
    }

    private val lock = Any()
    private var generation = 0
    private var current = ""
    private var currentLimit = 0L
    private var future: ScheduledFuture<*>? = null
    private val closers = mutableListOf<() -> Unit>()
    private var stalledStep: String? = null
    private var finished = false

    init {
        enter("connecting")
    }

    /** Takıldıysa adımın hatası; takılmadıysa null. */
    val timeout: TvStepTimeoutException?
        get() = synchronized(lock) { stalledStep?.let { TvStepTimeoutException(it, currentLimit) } }

    /** Yeni adıma geçildi: süre baştan başlar (sınırsız adımda süre durur). */
    fun enter(step: String) {
        synchronized(lock) {
            if (stalledStep != null || finished) return
            future?.cancel(false)
            future = null
            generation += 1
            current = step
            val limit = limits(step) ?: return
            currentLimit = limit
            val armed = generation
            future = timer.schedule({ fire(armed) }, limit, TimeUnit.MILLISECONDS)
        }
    }

    fun enter(step: InstallStep) = enter(key(step))

    /** Takılınca çalışacak kapatma (TV bağlantısı); bekleyen okuma böylece hatayla biter. */
    fun onStall(close: () -> Unit) {
        val now = synchronized(lock) {
            if (stalledStep == null) closers += close
            stalledStep != null
        }
        if (now) runCatching(close)
    }

    private fun fire(armed: Int) {
        val close = synchronized(lock) {
            if (armed != generation || stalledStep != null || finished) return
            stalledStep = current
            closers.toList()
        }
        close.forEach { runCatching(it) }
    }

    /**
     * Denemeyi bekçiyle çalıştırır. Adım takıldıysa sonuç her durumda [TvStepTimeoutException] olur: takılmış bağlantının
     * yuttuğu hata ("kurulum tamam" ama uygulama açılamadı) da sessiz geçmez.
     */
    fun <T> run(body: () -> T): T {
        try {
            val result = try {
                body()
            } catch (error: TvStepTimeoutException) {
                throw error
            } catch (error: Exception) {
                timeout?.let { throw it }
                throw error
            }
            timeout?.let { throw it }
            return result
        } finally {
            synchronized(lock) {
                finished = true
                future?.cancel(false)
            }
        }
    }
}
