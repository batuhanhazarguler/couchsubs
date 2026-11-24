// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #1251: telefon ekranda görünürken otomatik okumadan hiç satır gelmiyordu ve günlük de sessizdi. Telefonun açılıp
 * kapanması ve oynadığı için açılmaması artık sınırlı satırlarla günlüğe yazılır (Windows ve Mac/iPhone ile aynı metinler).
 */
class PhoneTraceTest {
    @Test
    fun trackerLogsOpeningClosingAndAMovingPhoneOncePerMinute() {
        val log = mutableListOf<String>()
        var top = 0.15
        var found = true
        val image = TestPhoneImage.phone()
        val tracker = GamePhoneTracker { if (found) GamePhoneGeometry.Pose(0.45, top, 0.45, top + 0.68) else null }
        tracker.onLog = { log.add(it) }
        var time = 0L
        fun sample() { time += 400; tracker.sample(image, time) }

        sample()
        sample()
        assertEquals(listOf("düşen satır [PhoneTrace] telefon açıldı: \"\""), log)
        found = false
        repeat(GamePhoneTracker.MISS_GRACE + 1) { sample() }
        assertEquals("düşen satır [PhoneTrace] telefon kapandı: \"\"", log.last())

        // Elde sallanan telefon: her örnekte %10 kayıyor, iki uyumlu gözlem olmadığı için hiç açılmıyor.
        log.clear()
        found = true
        repeat(6) {
            top = if (top == 0.15) 0.25 else 0.15
            sample()
        }
        assertEquals(1, log.size)
        assertTrue(log[0], log[0].startsWith("düşen satır [PhoneTrace] telefon oynuyor, açılmadı (%10 oynama)"))
        time += DropLog.REPEAT_MS
        top = if (top == 0.15) 0.25 else 0.15
        sample()
        assertEquals(2, log.size)
    }

    @Test
    fun shiftIsTheLargestEdgeMove() {
        assertEquals(0.07, PhoneTrace.shift(CropRegion(0.1, 0.8, 0.3, 0.6), CropRegion(0.12, 0.8, 0.37, 0.6)), 1e-9)
        assertEquals(7, PhoneTrace.percent(0.07))
    }
}
