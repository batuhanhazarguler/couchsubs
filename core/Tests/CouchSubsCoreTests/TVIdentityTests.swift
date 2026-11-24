// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// TV kimliği (USN/UDN, Samsung id/wifiMac) ve kimlikle yeniden bulma (Windows `TvIdentityTests`, Android
/// `TvIdentityTest` ile aynı vakalar).
final class TVIdentityTests: XCTestCase {
    func testParsesUSNFromSSDPResponse() {
        let response = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: http://192.168.1.5:1990/\r\n"
            + "SERVER: WebOS/4.4.0 UPnP/1.0\r\nST: urn:lge-com:service:webos-second-screen:1\r\n"
            + "USN: uuid:7A2B9C4E-1111-2222-3333-ABCDEF012345::urn:lge-com:service:webos-second-screen:1\r\n\r\n"
        XCTAssertEqual(TVIdentity.uuid(fromSSDPResponse: response), "7a2b9c4e-1111-2222-3333-abcdef012345")
        let hit = LGDiscovery.hit(fromSSDPResponse: response)
        XCTAssertEqual(hit?.uuid, "7a2b9c4e-1111-2222-3333-abcdef012345")
        XCTAssertNil(TVIdentity.uuid(fromSSDPResponse: "HTTP/1.1 200 OK\r\nLOCATION: http://x/\r\n\r\n"))
    }

    func testParsesUDNFromDescription() {
        let xml = "<root><device><friendlyName>Salon</friendlyName><UDN>uuid:ABC-1</UDN>"
            + "<deviceList><device><UDN>uuid:child</UDN></device></deviceList></device></root>"
        XCTAssertEqual(TVIdentity.uuid(fromDescription: xml), "abc-1")
        XCTAssertEqual(AndroidTVDiscovery.tv(host: "10.0.0.4", description: xml),
                       LGTV(name: "Salon", host: "10.0.0.4", brand: .androidTV, uuid: "abc-1"))
        XCTAssertNil(AndroidTVDiscovery.tv(host: "10.0.0.4", description: "<root><device></device></root>"))
    }

    func testNormalizesMAC() {
        XCTAssertEqual(TVIdentity.normalizedMAC("A4-30-7A-12-34-56"), "a4:30:7a:12:34:56")
        XCTAssertEqual(TVIdentity.normalizedMAC("a4307a123456"), "a4:30:7a:12:34:56")
        XCTAssertNil(TVIdentity.normalizedMAC("00:00:00:00:00:00"))
        XCTAssertNil(TVIdentity.normalizedMAC("a4:30:7a"))
        XCTAssertNil(TVIdentity.normalizedMAC(nil))
    }

    func testReadsSamsungIdentity() {
        let json = #"{"id":"uuid:top","device":{"name":"[TV] Samsung","id":"uuid:4C1E-99","wifiMac":"F4:7B:09:AA:BB:CC"}}"#
        let tv = SamsungMessages.tv(host: "192.168.1.9", Data(json.utf8))
        XCTAssertEqual(tv, LGTV(name: "[TV] Samsung", host: "192.168.1.9", brand: .samsung, uuid: "4c1e-99", mac: "f4:7b:09:aa:bb:cc"))
    }

    func testOldRecordWithoutIdentityStillDecodes() throws {
        let old = try JSONDecoder().decode(LGTV.self, from: Data(#"{"name":"Salon","host":"192.168.1.5"}"#.utf8))
        XCTAssertEqual(old, LGTV(name: "Salon", host: "192.168.1.5"))
        XCTAssertNil(old.uuid)
        let new = LGTV(name: "Salon", host: "192.168.1.5", uuid: "abc", mac: "a4:30:7a:12:34:56")
        XCTAssertEqual(try JSONDecoder().decode(LGTV.self, from: try JSONEncoder().encode(new)), new)
    }

    // MARK: - Kimlikle eşleştirme

    func testFindsTVByUUIDAfterRenameAndMove() {
        let saved = LGTV(name: "Salon", host: "192.168.1.5", uuid: "aaa")
        let renamed = LGTV(name: "[LG] webOS TV OLED55", host: "192.168.1.77", uuid: "aaa")
        let other = LGTV(name: "Yatak odası", host: "192.168.1.8", uuid: "bbb")
        let located = TVLocator.locate(saved, among: [other, renamed])
        XCTAssertEqual(located?.0, renamed)
        XCTAssertEqual(located?.1, .uuid)
        XCTAssertEqual(TVLocator.moved(saved, among: [other, renamed]), renamed)
    }

    func testPicksTheRightOneOfTwoTVsWithTheSameName() {
        let saved = LGTV(name: "LG TV", host: "192.168.1.5", uuid: "aaa")
        let mine = LGTV(name: "LG TV", host: "192.168.1.40", uuid: "aaa")
        let neighbour = LGTV(name: "LG TV", host: "192.168.1.41", uuid: "bbb")
        XCTAssertEqual(TVLocator.moved(saved, among: [neighbour, mine]), mine)
        // Kimliği farklı tek TV, adı aynı ya da ağdaki tek TV olsa da seçilmez.
        XCTAssertNil(TVLocator.moved(saved, among: [neighbour]))
    }

    func testAnotherTVAtTheSavedAddressDoesNotHideTheMove() {
        let saved = LGTV(name: "Salon", host: "192.168.1.5", uuid: "aaa")
        let intruder = LGTV(name: "Salon", host: "192.168.1.5", uuid: "bbb")
        let moved = LGTV(name: "Salon", host: "192.168.1.6", uuid: "aaa")
        XCTAssertEqual(TVLocator.moved(saved, among: [intruder, moved]), moved)
        XCTAssertNil(TVLocator.moved(saved, among: [LGTV(name: "Salon", host: "192.168.1.5", uuid: "aaa")]))
    }

    func testMatchesByMACWhenUUIDIsMissing() {
        let saved = LGTV(name: "Samsung", host: "192.168.1.5", brand: .samsung, mac: "a4:30:7a:12:34:56")
        let found = LGTV(name: "Renamed", host: "192.168.1.9", brand: .samsung, uuid: "zzz", mac: "A4-30-7A-12-34-56")
        XCTAssertEqual(TVLocator.locate(saved, among: [found])?.1, .mac)
    }

    func testOldRecordFallsBackToNameAndLearnsIdentity() {
        let saved = LGTV(name: "Salon", host: "192.168.1.5")
        let moved = LGTV(name: "Salon", host: "192.168.1.6", uuid: "aaa")
        let other = LGTV(name: "Mutfak", host: "192.168.1.7", uuid: "bbb")
        // Yeni adreste bulunan kayıt kimliğiyle gelir (kayıt güncellenince kimlik de yazılır).
        XCTAssertEqual(TVLocator.moved(saved, among: [other, moved])?.uuid, "aaa")
        XCTAssertEqual(TVLocator.locate(saved, among: [other, moved])?.1, .name)
        // TV kayıtlı adresteyse adres değişmez ama kimlik öğrenilir.
        let here = LGTV(name: "[LG] webOS TV", host: "192.168.1.5", uuid: "aaa")
        XCTAssertNil(TVLocator.moved(saved, among: [here]))
        XCTAssertEqual(TVLocator.learned(saved, among: [here]), LGTV(name: "Salon", host: "192.168.1.5", uuid: "aaa"))
        XCTAssertNil(TVLocator.learned(LGTV(name: "Salon", host: "192.168.1.5", uuid: "aaa"), among: [here]))
    }

    func testLocatorLogsAndReportsLearnedIdentityAndMove() async throws {
        final class Control: TVControlling {
            func launch(appId: String, params: [String: Any]) async throws {}
            func foregroundAppId() async throws -> String { "" }
            func close() {}
        }
        struct Unreachable: Error {}
        let saved = LGTV(name: "Salon", host: "192.168.1.5", uuid: "aaa")
        var lines: [String] = []
        var reported: [LGTV] = []
        let locator = TVLocator(tv: saved, connect: { tv in
            if tv.host == "192.168.1.5" { throw Unreachable() }
            return Control()
        }, search: { [LGTV(name: "Yeni ad", host: "192.168.1.30", uuid: "aaa")] },
           onMoved: { reported.append($0) }, log: { lines.append($0) })
        _ = try await locator.connect()
        XCTAssertEqual(reported.map(\.host), ["192.168.1.30"])
        XCTAssertEqual(lines, ["TV yeni adreste bulundu: 192.168.1.5 → 192.168.1.30 (UUID ile)"])
    }

    // MARK: - Göndericinin adresi değişince

    func testSenderAddressChangeIsReportedOnlyWhenTheHomeAddressChanges() {
        XCTAssertTrue(SenderAddressWatcher.changed(from: ["192.168.1.20"], to: ["192.168.1.34"]))
        XCTAssertFalse(SenderAddressWatcher.changed(from: ["192.168.1.20", "10.0.0.2"], to: ["10.0.0.2", "192.168.1.20"]))
        XCTAssertFalse(SenderAddressWatcher.changed(from: ["192.168.1.20"], to: []))
        XCTAssertTrue(SenderAddressWatcher.changed(from: [], to: ["192.168.1.20"]))
        final class Box: @unchecked Sendable { var addresses = ["192.168.1.20"]; var reports: [String] = [] }
        let box = Box()
        let watcher = SenderAddressWatcher(read: { box.addresses }) { old, new in box.reports.append(SenderAddressWatcher.line(old: old, new: new)) }
        watcher.check()
        XCTAssertTrue(box.reports.isEmpty)
        box.addresses = ["192.168.1.34"]
        watcher.check()
        XCTAssertEqual(box.reports, ["Bu cihazın adresi değişti: 192.168.1.20 → 192.168.1.34; TV'ye yeni adres bildiriliyor."])
    }

    // MARK: - Android TV bekçisinin yeniden bulucusu

    func testAndroidTVLocatorFollowsTheTVAndLearnsIdentity() async {
        final class Box: @unchecked Sendable { var lines: [String] = []; var moved: [LGTV] = []; var searches = 0 }
        let box = Box()
        let locator = AndroidTVLocator(tv: LGTV(name: "Android TV", host: "192.168.1.5", brand: .androidTV),
                                       search: { box.searches += 1; return [LGTV(name: "Salon", host: "192.168.1.9", brand: .androidTV, uuid: "cast-1")] },
                                       identify: { host in LGTV(name: "Salon", host: host, brand: .androidTV, uuid: "cast-1") },
                                       responds: { _ in false },
                                       onMoved: { box.moved.append($0) }, log: { box.lines.append($0) })
        let host = await locator.relocate()
        XCTAssertEqual(host, "192.168.1.9")
        XCTAssertEqual(box.moved.last?.uuid, "cast-1")
        XCTAssertEqual(box.lines, ["TV yeni adreste bulundu: 192.168.1.5 → 192.168.1.9 (ağdaki tek TV)"])
        // Arama hemen yinelenmez.
        let again = await locator.relocate()
        XCTAssertNil(again)
        XCTAssertEqual(box.searches, 1)
        // Kimlik zaten var: yeniden okunmaz.
        await locator.learnIdentity()
        XCTAssertEqual(box.moved.count, 1)
    }

    func testAndroidTVLocatorLearnsIdentityOnceAndDoesNotSearchWhileHostAnswers() async {
        final class Box: @unchecked Sendable { var moved: [LGTV] = []; var searches = 0; var identifies = 0 }
        let box = Box()
        let locator = AndroidTVLocator(tv: LGTV(name: "Android TV", host: "192.168.1.5", brand: .androidTV),
                                       search: { box.searches += 1; return [] },
                                       identify: { host in box.identifies += 1; return LGTV(name: "Salon", host: host, brand: .androidTV, uuid: "cast-1") },
                                       responds: { _ in true }, onMoved: { box.moved.append($0) })
        let host = await locator.relocate()
        XCTAssertNil(host)
        XCTAssertEqual(box.searches, 0)
        await locator.learnIdentity()
        await locator.learnIdentity()
        XCTAssertEqual(box.identifies, 1)
        XCTAssertEqual(box.moved, [LGTV(name: "Android TV", host: "192.168.1.5", brand: .androidTV, uuid: "cast-1")])
    }
}
