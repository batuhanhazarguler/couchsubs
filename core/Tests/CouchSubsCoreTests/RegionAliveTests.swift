// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import XCTest
@testable import CouchSubsCore

/// #1271: gösterilen ek alanlar TV'de yalnız okuma turu dönerken yenilenir; uygulama donunca TV son çeviriyi kendisi
/// kaldırır (Windows RegionAliveTests, Android RegionAliveTest ile aynı).
@MainActor
final class RegionAliveTests: XCTestCase {
    private final class Reader: TextReader, @unchecked Sendable {
        func read(_ image: CGImage) throws -> String { "" }
        func read(_ image: CGImage, deep: Bool) throws -> String { "" }
        func readLines(_ image: CGImage, deep: Bool) throws -> Reading { Reading(lines: []) }
    }

    private final class Translator: TextTranslator {
        func translate(_ text: String) async throws -> String { text }
    }

    private final class Server: RegionSending {
        var alive = 0
        func sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?) {}
        func clearRegions() {}
        func regionsAlive() { alive += 1 }
    }

    func testEveryPassAndAreaReportsTheWatcherAlive() async {
        let server = Server()
        let watcher = RegionWatcher(reader: Reader(), translator: Translator(), server: server)
        let frame = ScreenTextDetectorTests.scene(1)
        let areas = ["a", "b"].map { ExtraArea(id: $0, name: $0, region: CropRegion(top: 0, bottom: 0.5, left: 0, right: 0.5)) }
        await watcher.pass(frame, areas: areas)
        // Tur başı, iki alan ve tur sonu.
        XCTAssertEqual(server.alive, 4)
        await watcher.pass(frame, areas: [])
        XCTAssertEqual(server.alive, 6)
    }

    func testRegionsAreKeptOnlyWhileTheWatcherTurns() {
        XCTAssertTrue(SubtitleServer.keepsRegions(aliveAt: nil, now: 1_000_000), "turu bildirmeyen eski akış")
        XCTAssertTrue(SubtitleServer.keepsRegions(aliveAt: 100_000, now: 100_000 + SubtitleServer.regionAliveMs))
        XCTAssertFalse(SubtitleServer.keepsRegions(aliveAt: 100_000, now: 100_001 + SubtitleServer.regionAliveMs),
                       "donan uygulamanın alanları yenilenmez")
        // TV'deki ömür (15 sn) ile birlikte donmadan en geç ~35 sn sonra çeviri TV'den kalkar; en uzun tur (8 sn çeviri
        // sınırı + okuma, 4 kat yavaşlatılmış 1 sn'lik aralık) sınırın altında kalır.
        XCTAssertGreaterThan(SubtitleServer.regionAliveMs, 8000 + 4 * RegionWatcher.defaultIntervalMs + 4000)
    }
}
