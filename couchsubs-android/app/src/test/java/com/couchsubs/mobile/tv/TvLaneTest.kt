// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

/**
 * #1223: bekçinin açma denemesi ile kurulum aynı TV'ye aynı anda geliştirici bağlantısı açıyor, TV bağlantıyı zorla
 * kapatıyordu; "güncelle"ye üç kez basılınca üç kurulum başlıyordu. TV başına tek kanal (Windows TvLaneTests, Mac/iPhone
 * TVLaneTests ile aynı).
 */
class TvLaneTest {
    @Test fun sameTvRunsOneOperationAtATime() {
        val lane = TvLane()
        val running = AtomicInteger()
        val most = AtomicInteger()
        val threads = List(4) { index ->
            thread {
                lane.run(if (index % 2 == 0) "192.168.1.147" else " 192.168.1.147 ", "açma") {
                    most.accumulateAndGet(running.incrementAndGet(), ::maxOf)
                    Thread.sleep(30)
                    running.decrementAndGet()
                }
            }
        }
        threads.forEach { it.join() }
        assertEquals(1, most.get())
    }

    @Test fun differentTvsDoNotWaitForEachOther() {
        val lane = TvLane()
        val release = CountDownLatch(1)
        val first = thread { lane.run("192.168.1.10", "kurulum") { release.await() } }
        Thread.sleep(50)
        val started = System.nanoTime()
        lane.run("192.168.1.11", "açma") { }
        assertTrue(System.nanoTime() - started < 1_000_000_000)
        release.countDown()
        first.join()
    }

    @Test fun openWaitsWhileTheInstallIsRunning() {
        val lane = TvLane()
        val lines = Collections.synchronizedList(mutableListOf<String>())
        val release = CountDownLatch(1)
        val installDone = java.util.concurrent.atomic.AtomicBoolean(false)
        val install = thread { lane.install("tv") { release.await(); installDone.set(true); "0.9.104" } }
        Thread.sleep(50)
        assertTrue(lane.isInstalling("tv"))
        var openedDuringInstall: Boolean? = null
        val opened = CountDownLatch(1)
        thread { lane.run("tv", "açma", { lines += it }) { openedDuringInstall = !installDone.get() }; opened.countDown() }
        assertFalse(opened.await(150, TimeUnit.MILLISECONDS))
        release.countDown()
        assertTrue(opened.await(5, TimeUnit.SECONDS))
        install.join()
        assertEquals(false, openedDuringInstall)
        assertTrue(lines.any { it.contains("sırasını bekliyor") })
        assertFalse(lane.isInstalling("tv"))
    }

    @Test fun secondInstallRequestDoesNotStartANewInstall() {
        val lane = TvLane()
        val lines = Collections.synchronizedList(mutableListOf<String>())
        val release = CountDownLatch(1)
        val started = AtomicInteger()
        val results = Collections.synchronizedList(mutableListOf<String>())
        val threads = List(3) {
            thread { results += lane.install("tv", { lines += it }) { started.incrementAndGet(); release.await(); "0.9.104" } }
        }
        Thread.sleep(100)
        release.countDown()
        threads.forEach { it.join() }
        assertEquals(1, started.get())
        assertEquals(listOf("0.9.104", "0.9.104", "0.9.104"), results.toList())
        assertEquals(2, lines.count { it.contains("yeni kurulum başlatılmadı") })
        // Kurulum bitince yeni istek yeniden kurar.
        lane.install("tv") { started.incrementAndGet() }
        assertEquals(2, started.get())
    }

    @Test fun waitingRequestGetsTheRunningInstallsError() {
        val lane = TvLane()
        val release = CountDownLatch(1)
        var firstError: Throwable? = null
        val first = thread { try { lane.install<Int>("tv") { release.await(); throw IOException("koptu") } } catch (e: Throwable) { firstError = e } }
        Thread.sleep(50)
        thread { Thread.sleep(50); release.countDown() }
        val second = runCatching { lane.install("tv") { 5 } }
        first.join()
        assertTrue(firstError is IOException)
        assertTrue(second.exceptionOrNull() is IOException)
    }

    @Test fun nestedCallOnTheSameTvDoesNotWait() {
        val lane = TvLane(30_000)
        assertEquals(7, lane.install("tv") { lane.run("tv", "açma") { 7 } })
    }

    @Test fun stuckOperationDoesNotBlockTheTvForever() {
        val lane = TvLane(100)
        val lines = mutableListOf<String>()
        val never = CountDownLatch(1)
        thread(isDaemon = true) { lane.run("tv", "kurulum") { never.await() } }
        Thread.sleep(50)
        assertEquals(3, lane.run("tv", "açma", { lines += it }) { 3 })
        assertTrue(lines.any { it.contains("beklemeden başlıyor") })
        never.countDown()
    }
}
