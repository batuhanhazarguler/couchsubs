// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * TV kimliği (USN/UDN, Samsung id/wifiMac) ve kimlikle yeniden bulma (Mac/iPhone `TVIdentityTests`, Windows
 * `TvIdentityTests` ile aynı vakalar); arka plan bekçisinin yeniden bulması ve telefonun adres değişikliği.
 */
class TvIdentityTest {
    @Test fun parsesUsnFromSsdpResponse() {
        val response = "HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.5:1990/\r\nSERVER: WebOS/4.4.0 UPnP/1.0\r\n" +
            "ST: urn:lge-com:service:webos-second-screen:1\r\n" +
            "USN: uuid:7A2B9C4E-1111-2222-3333-ABCDEF012345::urn:lge-com:service:webos-second-screen:1\r\n\r\n"
        assertEquals("7a2b9c4e-1111-2222-3333-abcdef012345", TvIdentity.uuidFromSsdp(response))
        assertNull(TvIdentity.uuidFromSsdp("HTTP/1.1 200 OK\r\nLOCATION: http://x/\r\n\r\n"))
    }

    @Test fun parsesUdnAndSamsungIdentity() {
        val xml = "<root><device><friendlyName>Salon</friendlyName><UDN>uuid:ABC-1</UDN>" +
            "<deviceList><device><UDN>uuid:child</UDN></device></deviceList></device></root>"
        assertEquals("abc-1", TvIdentity.uuidFromDescription(xml))
        assertNull(TvIdentity.uuidFromDescription(null))
        val json = """{"id":"uuid:top","device":{"name":"[TV] Samsung","id":"uuid:4C1E-99","wifiMac":"F4:7B:09:AA:BB:CC"}}"""
        assertEquals("4c1e-99" to "f4:7b:09:aa:bb:cc", TvIdentity.samsungIdentity(json))
        assertEquals(null to null, TvIdentity.samsungIdentity("not json"))
        val samsung = PairedTv.withIdentity(FoundTv("[TV] Samsung", "192.168.1.9", TvBrand.SAMSUNG), json, null, null)
        assertEquals(FoundTv("[TV] Samsung", "192.168.1.9", TvBrand.SAMSUNG, "4c1e-99", "f4:7b:09:aa:bb:cc"), samsung)
        assertEquals("abc-1", PairedTv.withIdentity(FoundTv("Android TV", "10.0.0.4", TvBrand.ANDROID_TV), null, null, xml).uuid)
    }

    @Test fun normalizesMac() {
        assertEquals("a4:30:7a:12:34:56", TvIdentity.normalizedMac("A4-30-7A-12-34-56"))
        assertEquals("a4:30:7a:12:34:56", TvIdentity.normalizedMac("a4307a123456"))
        assertNull(TvIdentity.normalizedMac("00:00:00:00:00:00"))
        assertNull(TvIdentity.normalizedMac("a4:30:7a"))
    }

    @Test fun findsTvByUuidAfterRenameAndMove() {
        val saved = FoundTv("Salon", "192.168.1.5", TvBrand.LG, "aaa")
        val renamed = FoundTv("[LG] webOS TV OLED55", "192.168.1.77", TvBrand.LG, "aaa")
        val other = FoundTv("Yatak odası", "192.168.1.8", TvBrand.LG, "bbb")
        assertEquals(renamed to TvIdentity.Match.UUID, TvIdentity.locate(saved, listOf(other, renamed)))
        assertEquals(renamed, TvReach.relocated(saved, listOf(other, renamed)))
    }

    @Test fun picksTheRightOneOfTwoTvsWithTheSameName() {
        val saved = FoundTv("LG TV", "192.168.1.5", TvBrand.LG, "aaa")
        val mine = FoundTv("LG TV", "192.168.1.40", TvBrand.LG, "aaa")
        val neighbour = FoundTv("LG TV", "192.168.1.41", TvBrand.LG, "bbb")
        assertEquals(mine, TvReach.relocated(saved, listOf(neighbour, mine)))
        // Kimliği farklı tek TV, adı aynı ya da ağdaki tek TV olsa da seçilmez.
        assertNull(TvReach.relocated(saved, listOf(neighbour)))
    }

    @Test fun anotherTvAtTheSavedAddressDoesNotHideTheMove() {
        val saved = FoundTv("Salon", "192.168.1.5", TvBrand.LG, "aaa")
        val moved = FoundTv("Salon", "192.168.1.6", TvBrand.LG, "aaa")
        assertEquals(moved, TvReach.relocated(saved, listOf(FoundTv("Salon", "192.168.1.5", TvBrand.LG, "bbb"), moved)))
    }

    @Test fun matchesByMacWhenUuidIsMissing() {
        val saved = FoundTv("Samsung", "192.168.1.5", TvBrand.SAMSUNG, mac = "a4:30:7a:12:34:56")
        val found = FoundTv("Renamed", "192.168.1.9", TvBrand.SAMSUNG, "zzz", "A4-30-7A-12-34-56")
        assertEquals(TvIdentity.Match.MAC, TvIdentity.locate(saved, listOf(found))?.second)
    }

    @Test fun oldRecordFallsBackToNameAndLearnsIdentity() {
        val saved = FoundTv("Salon", "192.168.1.5", TvBrand.LG)
        val moved = FoundTv("Salon", "192.168.1.6", TvBrand.LG, "aaa")
        val other = FoundTv("Mutfak", "192.168.1.7", TvBrand.LG, "bbb")
        assertEquals("aaa", TvReach.relocated(saved, listOf(other, moved))?.uuid)
        assertEquals(TvIdentity.Match.NAME, TvIdentity.locate(saved, listOf(other, moved))?.second)
        val here = FoundTv("[LG] webOS TV", "192.168.1.5", TvBrand.LG, "aaa")
        assertNull(TvReach.relocated(saved, listOf(here)))
        assertEquals(FoundTv("Salon", "192.168.1.5", TvBrand.LG, "aaa"), TvIdentity.learned(saved, listOf(here)))
        assertNull(TvIdentity.learned(saved.copy(uuid = "aaa"), listOf(here)))
        assertEquals("TV yeni adreste bulundu: 192.168.1.5 → 192.168.1.6 (UUID ile)",
            TvIdentity.movedLine("192.168.1.5", "192.168.1.6", TvIdentity.Match.UUID))
        assertEquals("TV kimliği kayda yazıldı: 192.168.1.5 (UUID aaa)", TvIdentity.learnedLine(here))
    }

    @Test fun choosingATvStoresItsIdentity() {
        val tv = FoundTv("Salon", "192.168.1.30", TvBrand.LG, "AAA")
        assertEquals(InstalledTv(TvBrand.LG, "192.168.1.30", uuid = "aaa"), TvChoice.select(null, tv))
        val old = InstalledTv(TvBrand.LG, "192.168.1.30", 0, "0.9.80")
        assertEquals(old.copy(uuid = "aaa"), TvChoice.select(old, tv))
    }

    /** Arka plandaki LG bekçisi bağlanamayınca TV'yi yeniden arar ve yeni adresle hemen yeniden dener. */
    @Test fun lgKeeperRelocatesAndRetriesWhenItCannotConnect() {
        var saved: InstalledTv? = InstalledTv(TvBrand.LG, "192.168.1.5")
        val tried = mutableListOf<String>()
        var relocations = 0
        val control = TvSessionLauncher.openLg({ saved }, relocate = {
            relocations++
            saved = InstalledTv(TvBrand.LG, "192.168.1.9")
            true
        }) { tv -> tried += tv.host; if (tv.host == "192.168.1.9") NoopControl else null }
        assertEquals(NoopControl, control)
        assertEquals(listOf("192.168.1.5", "192.168.1.9"), tried)
        assertEquals(1, relocations)
        // TV bulunamazsa yeniden denenmez.
        tried.clear()
        saved = InstalledTv(TvBrand.LG, "192.168.1.5")
        assertNull(TvSessionLauncher.openLg({ saved }, relocate = { false }) { tv -> tried += tv.host; null })
        assertEquals(listOf("192.168.1.5"), tried)
    }

    /** Samsung bekçisi uygulama bağlı değilken açmadan önce TV'yi gerekirse yeniden bulur. */
    @Test fun samsungKeeperRelocatesBeforeReopening() {
        val order = mutableListOf<String>()
        var opens = 0
        TvSessionLauncher.keepSamsungOpen(InstalledTv(TvBrand.SAMSUNG, "192.168.1.50"), connected = { false }, active = { opens < 2 },
            sleep = { true }, relocate = { order += "ara"; false }) { opens++; order += "aç" }
        assertEquals(listOf("ara", "aç", "ara", "aç"), order)
        // Bağlıyken aranmaz.
        var searched = 0
        TvSessionLauncher.keepSamsungOpen(InstalledTv(TvBrand.SAMSUNG, "192.168.1.50"), connected = { true }, active = { searched == 0 && opens++ < 5 },
            sleep = { true }, relocate = { searched++; false }) { }
        assertEquals(0, searched)
    }

    @Test fun senderAddressChangeIsReportedOnlyWhenTheHomeAddressChanges() {
        assertTrue(SenderAddressWatcher.changed(listOf("192.168.1.20"), listOf("192.168.1.34")))
        assertFalse(SenderAddressWatcher.changed(listOf("192.168.1.20", "10.0.0.2"), listOf("10.0.0.2", "192.168.1.20")))
        assertFalse(SenderAddressWatcher.changed(listOf("192.168.1.20"), emptyList()))
        var addresses = listOf("192.168.1.20")
        val reports = mutableListOf<String>()
        val watcher = SenderAddressWatcher({ addresses }) { old, new -> reports += SenderAddressWatcher.line(old, new) }
        watcher.check()
        assertTrue(reports.isEmpty())
        addresses = listOf("192.168.1.34")
        watcher.check()
        assertEquals(listOf("Bu cihazın adresi değişti: 192.168.1.20 → 192.168.1.34; TV'ye yeni adres bildiriliyor."), reports)
    }

    private object NoopControl : LgControl {
        override fun launch() {}
        override fun foregroundAppId(): String = ""
        override fun close() {}
    }
}
