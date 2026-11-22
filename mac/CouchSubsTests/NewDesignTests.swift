// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import XCTest
@testable import CouchSubs

/// Yeni arayüzün mantık parçaları: tasarım değerleri, sürüm notları, altyazı görünümü eşlemeleri, hazır bekleme değerleri.
@MainActor
final class NewDesignTests: XCTestCase {
    /// tasarim.json uygulama paketinde ve okunuyor (eksikse açılışta çökerdi).
    func testDesignTokensLoad() {
        XCTAssertEqual(DS.size("windowWidth"), 1200)
        XCTAssertEqual(DS.size("windowHeight"), 760)
        XCTAssertNotNil(DS.tokens.color["amber"])
        XCTAssertEqual(DSTokens.rgba("#F5B83D33")?.3 ?? 0, 0.2, accuracy: 0.01)
    }

    func testReleaseNotesParseCurrentAndPrevious() {
        let text = """
        Giriş.

        **Bu sürümde yeni** (yalnız hata düzeltmeleri)

        - **Android TV'de siyah ekran**: Görüntü modu Otomatik.
        - **Güncelleme penceresi:** Yalnız yeni notlar.

        **beta.83'te gelenler:** GTA 6 telefon mesajları, haber bandı (#933), Samsung'da AS400 uyarısı düzeltmesi.
        """
        let notes = ReleaseNotes.parse(text)
        XCTAssertEqual(notes.current, ["Android TV'de siyah ekran: Görüntü modu Otomatik.", "Güncelleme penceresi: Yalnız yeni notlar."])
        XCTAssertEqual(notes.previous.count, 3)
        XCTAssertEqual(notes.previous.first, "GTA 6 telefon mesajları.")
        // Uygulamayla gelen dosya da okunuyor.
        XCTAssertFalse(ReleaseNotes.load().current.isEmpty)
    }

    /// 16–50 kaydırıcısı TV yazı boyuna (16–90) doğrusal eşlenir; uçlar korunur, varsayılan 46 ≈ 30.
    func testTextSizeMapping() {
        XCTAssertEqual(SubtitlePalette.fontSize(16), 16)
        XCTAssertEqual(SubtitlePalette.fontSize(50), 90)
        XCTAssertEqual(SubtitlePalette.display(90), 50)
        XCTAssertEqual(SubtitlePalette.display(46), 30)
        for value in 16...50 { XCTAssertEqual(SubtitlePalette.display(SubtitlePalette.fontSize(value)), value) }
    }

    func testLowContrastWarning() {
        var style = SubtitleStyle()
        style.textHex = "#FFFFFF"
        XCTAssertFalse(SubtitlePalette.lowContrast(style))
        style.textHex = "#111114"
        XCTAssertTrue(SubtitlePalette.lowContrast(style))
        style.backgroundColor = "#FFFFFF"
        style.background = 100
        XCTAssertFalse(SubtitlePalette.lowContrast(style))
    }

    /// Hızlı / Dengeli / Doğru mevcut iki beklemenin hazır değerleridir; Dengeli varsayılandır.
    func testTranslationPacePresets() {
        XCTAssertEqual(TranslationPace.of(UserSettings()), .balanced)
        var settings = UserSettings()
        settings.misreadWaitMs = 400
        settings.partialWaitMs = 0
        XCTAssertEqual(TranslationPace.of(settings), .fast)
        settings.partialWaitMs = 123
        XCTAssertNil(TranslationPace.of(settings))
    }

    func testSpeakerSplit() {
        let split = SpeakerSplit("Jason: Tamam. Gidelim.")
        XCTAssertEqual(split.speaker, "Jason:")
        XCTAssertEqual(split.line, "Tamam. Gidelim.")
        XCTAssertNil(SpeakerSplit("Gel buraya.").speaker)
    }

    /// Denetimler her maddeyi döner; PS5 bulunamadıysa "PS5 Yanıt Veriyor" sorunlu, Uzaktan Oynama hep bilinmiyor.
    func testSetupChecksNeverGuess() {
        let checks = SetupCheck.run(consoles: [])
        XCTAssertEqual(checks.map(\.kind), SetupCheck.Kind.allCases)
        XCTAssertEqual(checks.first { $0.kind == .ps5Responds }?.state, .problem)
        XCTAssertEqual(checks.first { $0.kind == .remotePlay }?.state, .unknown)
        XCTAssertEqual(checks.first { $0.kind == .restModeInternet }?.state, .unknown)
    }

    /// Dikey ritim tek yerde: başlık → denetim 8, denetim → açıklama 6, birimler arası 24.
    func testVerticalRhythmTokens() {
        XCTAssertEqual(DS.unitTitleGap, 8)
        XCTAssertEqual(DS.unitHintGap, 6)
        XCTAssertEqual(DS.unitGap, 24)
    }

    /// "Günlüğü Kopyala": güncel .log dosyaları maskelenip zip'e girer, eski ve günlük olmayan dosyalar girmez; büyük
    /// günlüğün yalnız sonu alınır. Gerçek ~/Library/Logs'a dokunmaz (geçici klasör).
    func testLogArchiveMasksSecretsAndZips() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("logarchive-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Logs", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let now = Date()
        try Data("passphrase=A1B2C3 api_key: AIzaSyX\nPS5 192.168.1.20 bağlandı\n".utf8).write(to: source.appendingPathComponent("tvinstall.log"))
        try Data("access_token=eyJhbGciOiJIUzI1NiJ9 Bearer abc.def\n".utf8).write(to: source.appendingPathComponent("altyazi.log"))
        try Data("x".utf8).write(to: source.appendingPathComponent("notlar.txt"))
        let old = source.appendingPathComponent("eski.log")
        try Data("eski\n".utf8).write(to: old)
        try manager.setAttributes([.modificationDate: now.addingTimeInterval(-30 * 24 * 3600)], ofItemAtPath: old.path)

        XCTAssertEqual(LogArchive.logs(in: source, now: now).map(\.lastPathComponent), ["altyazi.log", "tvinstall.log"])
        let zip = try LogArchive.make(from: source, into: output, header: "CouchSubs test", now: now)
        XCTAssertEqual(zip.lastPathComponent, LogArchive.fileName(now))
        XCTAssertTrue(zip.lastPathComponent.hasPrefix("CouchSubs-gunluk-"))

        let unzip = root.appendingPathComponent("unzip", isDirectory: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unzip.path]
        try ditto.run()
        ditto.waitUntilExit()
        let folder = unzip.appendingPathComponent("CouchSubs-gunluk", isDirectory: true)
        let names = try manager.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names, ["altyazi.log", "bilgi.txt", "tvinstall.log"])
        let tv = try String(contentsOf: folder.appendingPathComponent("tvinstall.log"), encoding: .utf8)
        XCTAssertFalse(tv.contains("A1B2C3"))
        XCTAssertFalse(tv.contains("AIzaSyX"))
        XCTAssertTrue(tv.contains("192.168.1.20"))
        let subtitles = try String(contentsOf: folder.appendingPathComponent("altyazi.log"), encoding: .utf8)
        XCTAssertFalse(subtitles.contains("eyJhbGciOiJIUzI1NiJ9"))
        XCTAssertFalse(subtitles.contains("abc.def"))
    }

    func testLogArchiveTakesTailOfLargeLog() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("buyuk-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: file) }
        let line = String(repeating: "a", count: 99) + "\n"
        try Data(String(repeating: line, count: 30_000).utf8).write(to: file)
        let tail = try XCTUnwrap(LogArchive.tail(file))
        XCTAssertLessThanOrEqual(tail.utf8.count, LogArchive.maxBytesPerLog)
        XCTAssertTrue(tail.hasPrefix(line))
    }
}
