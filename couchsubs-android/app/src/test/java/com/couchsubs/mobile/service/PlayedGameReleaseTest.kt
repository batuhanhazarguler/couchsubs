// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.service

import com.couchsubs.mobile.core.GamePackLibrary
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayedGameReleaseTest {
    @Test
    fun stoppedSessionDoesNotKeepThePackLibrary() {
        // #1282: biten oturumun kitaplığı tutuluyordu; sonraki oturum yenisini açarken bellek yetmiyor, paketsiz sürüyordu.
        PlayedGame.packs = GamePackLibrary(bundled = null, userDirectory = null)
        PlayedGame.packTitles = { listOf("Örnek Oyun") }
        PlayedGame.stop()
        assertNull(PlayedGame.packs)
        assertTrue(PlayedGame.packTitles().isEmpty())
    }
}
