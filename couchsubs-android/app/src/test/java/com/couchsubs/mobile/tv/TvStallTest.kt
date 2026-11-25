// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import com.couchsubs.mobile.tv.android.AndroidInstallError
import com.couchsubs.mobile.tv.android.AndroidInstallException
import com.couchsubs.mobile.tv.android.AndroidTvInstaller
import com.couchsubs.mobile.tv.samsung.InstallStep
import com.couchsubs.mobile.tv.samsung.SamsungInstallError
import com.couchsubs.mobile.tv.samsung.SamsungInstallException
import com.couchsubs.mobile.tv.samsung.SamsungInstaller
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException
import java.net.SocketException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * TV uygulaması güncellemesi takılınca: adımın süresi dolar, bağlantı kapatılır, bir kez daha denenir; yine takılırsa
 * "bağlantı koptu, tekrar dene" gösterilir (Windows TvStallTests ve iPhone TVStallTests ile aynı durumlar).
 */
class TvStallTest {
    private fun short(ms: Long): (String) -> Long? = { if (it == "signin" || it == "play") null else ms }

    @Test
    fun stalledStepClosesTheConnectionAndFails() {
        val stall = TvStall(short(100))
        val closed = CountDownLatch(1)
        stall.onStall { closed.countDown() }
        try {
            stall.run<Int> {
                stall.enter("installing")
                // Bloklayan okuma: bağlantı kapanınca hatayla döner.
                closed.await(5, TimeUnit.SECONDS)
                throw SocketException("Socket closed")
            }
            fail("takılma bekleniyordu")
        } catch (error: TvStepTimeoutException) {
            assertEquals("installing", error.step)
            assertTrue(error.message!!.contains("paket gönderme ve kurulum"))
        }
    }

    @Test
    fun eachStepGetsItsOwnTime() {
        val stall = TvStall(short(300))
        val result = stall.run {
            for (step in listOf("reading", "closing", "installing", "launching")) {
                stall.enter(step)
                Thread.sleep(150)
            }
            42
        }
        assertEquals(42, result)
    }

    /** Samsung girişi ve TV'deki Play sayfası kullanıcıyı bekler: süre işlemez. */
    @Test
    fun stepsWaitingForTheUserHaveNoLimit() {
        val stall = TvStall(short(100))
        val result = stall.run {
            stall.enter(InstallStep.SIGN_IN)
            Thread.sleep(400)
            "tamam"
        }
        assertEquals("tamam", result)
    }

    /** Takılan bağlantının hatasını yutan adım ("açılamadı, kurulum yine tamam") da başarı sayılmaz. */
    @Test
    fun swallowedErrorAfterStallStillCountsAsStall() {
        val stall = TvStall(short(100))
        try {
            stall.run {
                stall.enter(InstallStep.LAUNCHING)
                Thread.sleep(400)
                1
            }
            fail("takılma bekleniyordu")
        } catch (_: TvStepTimeoutException) {
        }
    }

    @Test
    fun stallIsRetriedOnceWithAFreshAttempt() {
        val attempts = mutableListOf<Int>()
        val lines = mutableListOf<String>()
        val result = TvStall.retryOnce(lines::add, { SamsungInstaller.isRetryable(it) }) { attempt ->
            attempts += attempt
            if (attempt == 1) throw TvStepTimeoutException("installing", 360_000)
            "0.9.104"
        }
        assertEquals("0.9.104", result)
        assertEquals(listOf(1, 2), attempts)
        assertTrue(lines.any { it.contains("bir kez daha deneniyor") && it.contains("360 sn") })
    }

    @Test
    fun secondStallIsReported() {
        var attempts = 0
        try {
            TvStall.retryOnce<String>({}, { AndroidTvInstaller.isRetryable(it) }) {
                attempts++
                throw TvStepTimeoutException("launching", 60_000)
            }
            fail("hata bekleniyordu")
        } catch (error: TvStepTimeoutException) {
            assertTrue(error.gaveUp.contains("bir kez daha denendi"))
        }
        assertEquals(2, attempts)
    }

    @Test
    fun onlyStallsAndDroppedConnectionsAreRetried() {
        assertTrue(SamsungInstaller.isRetryable(TvStepTimeoutException("reading", 60_000)))
        assertTrue(SamsungInstaller.isRetryable(IOException("Connection reset")))
        assertTrue(SamsungInstaller.isRetryable(SamsungInstallException(SamsungInstallError.CONNECTION_LOST, "")))
        // Geliştirici modu kapalı, yer yok, onay verilmedi: yeniden denemek düzeltmez.
        assertFalse(SamsungInstaller.isRetryable(SamsungInstallException(SamsungInstallError.UNREACHABLE, "")))
        assertFalse(SamsungInstaller.isRetryable(SamsungInstallException(SamsungInstallError.NOT_ENOUGH_SPACE, "")))
        assertFalse(AndroidTvInstaller.isRetryable(AndroidInstallException(AndroidInstallError.NOT_APPROVED, "")))
        assertTrue(AndroidTvInstaller.isRetryable(AndroidInstallException(AndroidInstallError.CONNECTION_LOST, "")))
    }

    /** Güncellemeden önce TV'de çalışan eski uygulama kapatılır; kapatılamasa da kurulum sürer. */
    @Test
    fun samsungClosesTheRunningAppBeforeUpdating() {
        val sent = mutableListOf<String>()
        val lines = mutableListOf<String>()
        var paused = false
        SamsungInstaller.closeOverSdb(shell = { command ->
            sent += command
            if (command.endsWith("CouchSubsT")) throw IOException("bilinmeyen komut")
            "app_id[CouchSubsT.CouchSubs] kill success"
        }, pause = { paused = true }, log = { lines += it })
        assertEquals(listOf("0 was_kill CouchSubsT.CouchSubs", "0 was_kill CouchSubsT"), sent)
        assertTrue(paused)
        assertEquals(2, lines.size)
    }

    @Test
    fun everyStepHasALimitExceptTheOnesWaitingForTheUser() {
        for (step in listOf("connecting", "approve", "reading", "certificate", "signing", "closing", "installing", "uninstalling", "launching"))
            assertNotNull(step, TvStall.limitFor(step))
        assertNull(TvStall.limitFor(TvStall.key(InstallStep.SIGN_IN)))
        assertNull(TvStall.limitFor(TvStall.key(InstallStep.OPEN_PLAY)))
    }
}
