// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import XCTest
@testable import CouchSubsCore

/// GTA 6 telefonunun çevirisi kararlı (X, 22 Kas: "sağ tarafta kutu çıkarıyorsun ama her saniye şekli de hareketi de
/// değişiyor"): aynı ekran gürültülü okunsa da (bir harf, birkaç piksel, telefon bir an kaybolup geri gelse de) çizilen
/// Türkçe birebir aynı kalır; aynı mesaj bir kez yazılır, yeniden çevrilmez; yeni mesajda yalnız o balon eklenir.
/// Windows (PhoneSteadyOutputTests.cs) ve Android (PhoneSteadyOutputTest.kt) aynı durumları sınar. Metinler uydurmadır.
@MainActor
final class PhoneSteadyOutputTests: XCTestCase {
    private final class Reader: TextReader, @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [TextLine] = []
        func set(_ lines: [TextLine]) { lock.withLock { self.lines = lines } }
        func read(_ image: CGImage) throws -> String { try readLines(image, deep: false).text }
        func read(_ image: CGImage, deep: Bool) throws -> String { try read(image) }
        func readLines(_ image: CGImage, deep: Bool) throws -> Reading { lock.withLock { Reading(lines: lines) } }
    }

    /// Her çağrıda başka Türkçe veren motor (yapay zekâ gibi): aynı mesaj yeniden çevrilirse ekrandaki yazı değişir.
    private actor Translator: TextTranslator {
        nonisolated let translatesTogether = true
        private(set) var calls: [String] = []
        func translate(_ text: String) async throws -> String {
            calls.append(text)
            return "Çeviri \(calls.count): \(text)"
        }
    }

    private final class Server: RegionSending {
        var sent: [[ScreenTranslation.Item]] = []
        func sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?) {
            sendRegion(id: id, text: text, box: box, lineHeight: lineHeight, icons: nil, blocks: nil)
        }
        func sendRegion(id: String, text: String, box: TextBox?, lineHeight: Double?,
                        icons: [IconPlacement]?, blocks: [ScreenTranslation.Item]?) {
            sent.append(blocks ?? [])
        }
        func clearRegions() {}
    }

    private struct TimedOut: Error {}

    private func wait(_ done: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await done()) {
            if Date() >= deadline { throw TimedOut() }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private static let first = "Are you coming to the barbecue tonight?"
    private static let second = "Bring the folding chairs from the garage."
    private static let third = "Sure, I will be there around eight."

    /// Balon kutusu (düz ekranda), `shift` kadar kaymış (OCR kutusunun okumadan okumaya oynaması).
    private static func box(_ top: Double, _ left: Double, shift: Double = 0) -> TextBox {
        TextBox(left: left + shift, top: top + shift, right: left + 0.50 + shift, bottom: top + 0.06 + shift)
    }

    private static func chat(_ first: String = first, _ second: String = second, shift: Double = 0) -> [TextLine] {
        [TextLine(first, box: box(0.30, 0.05, shift: shift)), TextLine(second, box: box(0.50, 0.45, shift: shift))]
    }

    /// Kartın mesajları (zemin hariç): çizicilerin gördüğü her şey.
    private static func picture(_ items: [ScreenTranslation.Item]) -> [String] {
        items.map { "\($0.panel?.rawValue ?? "-")|\($0.translation)|\($0.lineHeight)" }
    }

    func testNoisyReadingsKeepTheSidePanelIdentical() async throws {
        let reader = Reader(), translator = Translator(), server = Server()
        var clock = 0
        let watcher = RegionWatcher(reader: reader, translator: translator, server: server, clock: { clock })
        let pose = try XCTUnwrap(GamePhoneGeometry.locate(GamePhoneTestFrame.phone()))
        // Sallanan telefonun kareleri: yazının pikselleri her karede biraz başka yerde, telefon her turda yeniden okunur.
        let frames = (0..<6).map { GamePhoneTestFrame.phone(patch: CGRect(x: 168 + 10 * $0, y: 94, width: 8, height: 12)) }
        reader.set(Self.chat())
        watcher.offer(frames[0], areas: [], phone: pose)
        try await wait { !watcher.isBusy }
        let shown = try XCTUnwrap(server.sent.last)
        let card = try XCTUnwrap(shown.first { $0.panel == .card })
        XCTAssertEqual(shown.filter { $0.panel == .theirs || $0.panel == .mine }.count, 2)

        // Gürültülü okumalar: bir harf oynuyor, kutular birkaç piksel kayıyor, bir okumada ilk mesaj iki kez geliyor, bir
        // okumada da telefon bir an kayboluyor.
        let noisy: [[TextLine]] = [
            Self.chat("Are you cominq to the barbecue tonight?", shift: 0.004),
            Self.chat(Self.first, "Bring the fo1ding chairs from the garage.", shift: -0.004),
            [TextLine(Self.first, box: Self.box(0.30, 0.05)), TextLine(Self.first, box: Self.box(0.37, 0.05)),
             TextLine(Self.second, box: Self.box(0.50, 0.45))],
            [TextLine(Self.first, box: Self.box(0.30, 0.05)), TextLine(Self.first, box: Self.box(0.40, 0.05)),
             TextLine(Self.second, box: Self.box(0.50, 0.45))],
            Self.chat("Are you coming to the barbecue tonight", shift: 0.003),
        ]
        for (index, lines) in noisy.enumerated() {
            clock += 450
            reader.set(lines)
            watcher.offer(frames[(index + 1) % frames.count], areas: [], phone: pose)
            try await wait { !watcher.isBusy }
            if index == 2 {
                // Telefon bir an kayboldu (izleyici kapattı) ve geri geldi.
                watcher.offer(frames[0], areas: [], phone: nil)
                clock += 450
                watcher.offer(frames[index % frames.count], areas: [], phone: pose)
                try await wait { !watcher.isBusy }
            }
        }
        let pictures = server.sent.filter { !$0.isEmpty }
        XCTAssertGreaterThanOrEqual(pictures.count, 1)
        for picture in pictures {
            XCTAssertEqual(Self.picture(picture), Self.picture(shown), "aynı ekranda çizilen Türkçe birebir aynı")
            XCTAssertEqual(picture.first { $0.panel == .card }?.box, card.box, "kartın yeri ve boyu aynı")
        }
        let calls = await translator.calls
        XCTAssertEqual(calls.count, 2, "her mesaj bir kez çevrilir: \(calls)")
    }

    func testNewMessageAddsOnlyItsBubble() async throws {
        let reader = Reader(), translator = Translator(), server = Server()
        var clock = 0
        let watcher = RegionWatcher(reader: reader, translator: translator, server: server, clock: { clock })
        let pose = try XCTUnwrap(GamePhoneGeometry.locate(GamePhoneTestFrame.phone()))
        reader.set(Self.chat())
        watcher.offer(GamePhoneTestFrame.phone(), areas: [], phone: pose)
        try await wait { !watcher.isBusy }
        let before = try XCTUnwrap(server.sent.last).filter { $0.panel == .theirs || $0.panel == .mine }

        // Sohbet yukarı kaydı, yeni mesaj altta.
        reader.set(Self.chat(shift: -0.08) + [TextLine(Self.third, box: Self.box(0.62, 0.05))])
        clock = 450
        watcher.offer(GamePhoneTestFrame.phone(patch: CGRect(x: 170, y: 150, width: 20, height: 12)), areas: [], phone: pose)
        try await wait { !watcher.isBusy }
        let after = try XCTUnwrap(server.sent.last).filter { $0.panel == .theirs || $0.panel == .mine }
        XCTAssertEqual(after.count, 3)
        XCTAssertEqual(Array(after.prefix(2)).map(\.translation), before.map(\.translation), "eski balonlar aynı")
        XCTAssertEqual(Set(after.map(\.lineHeight)).count, 1, "gruptaki bütün balonlar aynı boyda")
        XCTAssertEqual(after[0].lineHeight, before[0].lineHeight, "yazı boyu değişmez")
        let calls = await translator.calls
        XCTAssertEqual(calls, [Self.first, Self.second, Self.third])
    }

    func testBubblesOnTopShareOneTextSize() async throws {
        let reader = Reader(), translator = Translator(), server = Server()
        var clock = 0
        let watcher = RegionWatcher(reader: reader, translator: translator, server: server, clock: { clock })
        watcher.phonePanel = { PhonePanelOptions(enabled: false) }
        let pose = try XCTUnwrap(GamePhoneGeometry.locate(GamePhoneTestFrame.phone()))
        var lines = Self.chat()
        lines[1].box = TextBox(left: 0.45, top: 0.50, right: 0.95, bottom: 0.575)
        reader.set(lines)
        watcher.offer(GamePhoneTestFrame.phone(), areas: [], phone: pose)
        try await wait { !watcher.isBusy }
        let first = try XCTUnwrap(server.sent.last)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(Set(first.map(\.lineHeight)).count, 1, "iki balon aynı yazı boyunda")

        // Aynı ekran biraz farklı satır yüksekliğiyle okunur: yazı boyu değişmez, yeniden gönderilmez.
        lines[0].box = TextBox(left: 0.05, top: 0.30, right: 0.55, bottom: 0.368)
        reader.set(lines)
        clock = 450
        watcher.offer(GamePhoneTestFrame.phone(patch: CGRect(x: 170, y: 94, width: 10, height: 12)), areas: [], phone: pose)
        try await wait { !watcher.isBusy }
        XCTAssertEqual(server.sent.last.map { $0.map(\.lineHeight) }, first.map(\.lineHeight))
    }

    // MARK: Kurallar

    private static func item(_ source: String, _ translation: String, top: Double = 0.3, line: Double = 0.02,
                             role: ScreenPhoneCard.Role? = .incoming) -> ScreenTranslation.Item {
        var item = ScreenTranslation.Item(source: source, translation: translation,
                                          box: TextBox(left: 0.6, top: top, right: 0.8, bottom: top + 0.05), lineHeight: line)
        if let role { item.phone = ScreenPhoneCard.Placement(role: role, spot: TextBox(left: 0.1, top: top, right: 0.9, bottom: top + 0.05)) }
        return item
    }

    func testSameMessageIsWrittenOnce() {
        let items = [Self.item(Self.first, "A"), Self.item("Are you cominq to the barbecue tonight?", "B", top: 0.4),
                     Self.item(Self.second, "C", top: 0.5)]
        XCTAssertEqual(PhoneSteady.withoutRepeats(items).map(\.translation), ["A", "C"])
        // Araları açık iki kısa "Ok" gerçekten iki mesajdır; art arda iki "Ok" tek okumanın yinelenmesidir.
        let short = [Self.item("Ok", "Tamam"), Self.item(Self.second, "C", top: 0.4), Self.item("Ok", "Tamam", top: 0.5)]
        XCTAssertEqual(PhoneSteady.withoutRepeats(short).count, 3)
        XCTAssertEqual(PhoneSteady.withoutRepeats([Self.item("Ok", "Tamam"), Self.item("Ok", "Tamam", top: 0.4)]).count, 1)
        // Uzun mesaj araya başka mesaj girse de bir kez.
        let far = [Self.item(Self.first, "A"), Self.item(Self.second, "C", top: 0.4), Self.item(Self.first, "A", top: 0.5)]
        XCTAssertEqual(PhoneSteady.withoutRepeats(far).map(\.translation), ["A", "C"])
        // Telefon dışı öğelere dokunulmaz.
        XCTAssertEqual(PhoneSteady.withoutRepeats([Self.item("Ok", "x", role: nil), Self.item("Ok", "x", role: nil)]).count, 2)
    }

    func testShownTranslationIsKeptForTheSameMessage() {
        let previous = [Self.item(Self.first, "Bu akşam mangala geliyor musun?")]
        let fresh = [Self.item("Are you cominq to the barbecue tonight?", "Bu gece mangala gelir misin?"),
                     Self.item(Self.second, "Katlanır sandalyeleri getir.", top: 0.5)]
        let kept = PhoneSteady.keptTranslations(fresh, previous: previous)
        XCTAssertEqual(kept.map(\.translation), ["Bu akşam mangala geliyor musun?", "Katlanır sandalyeleri getir."])
        XCTAssertEqual(kept[0].source, Self.first)
        // Sayı değişen mesaj yeni mesajdır.
        let time = [Self.item("Meet me at the station at 5", "5'te")]
        XCTAssertEqual(PhoneSteady.keptTranslations([Self.item("Meet me at the station at 6", "6'da")], previous: time)
            .map(\.translation), ["6'da"])
    }

    func testMessageBubblesShareTheLockedLine() {
        let items = [Self.item("Rose", "Rose", line: 0.03, role: .header), Self.item(Self.first, "A", line: 0.018),
                     Self.item(Self.second, "B", line: 0.023), Self.item("x", "x", line: 0.05, role: nil)]
        XCTAssertEqual(PhoneSteady.uniformLine(items, line: 0.02).map(\.lineHeight), [0.03, 0.02, 0.02, 0.05])
    }

    func testCardDoesNotShrinkWhileThePhoneStays() {
        func card(_ bottom: Double, left: Double = 0.7) -> ScreenTranslation.Item {
            var item = ScreenTranslation.Item(source: "", translation: ScreenPhoneCard.backdropText,
                                              box: TextBox(left: left, top: 0.2, right: left + 0.2, bottom: bottom), lineHeight: 0.02)
            item.panel = .card
            return item
        }
        XCTAssertEqual(PhoneSteady.steadyCard([card(0.7)], previous: [card(0.8)]).first?.box.bottom, 0.8)
        XCTAssertEqual(PhoneSteady.steadyCard([card(0.9)], previous: [card(0.8)]).first?.box.bottom, 0.9, "uzayan kart uzar")
        XCTAssertEqual(PhoneSteady.steadyCard([card(0.7, left: 0.6)], previous: [card(0.8)]).first?.box.bottom, 0.7,
                       "telefon kıpırdadı, yeni kart")
    }

    func testRepeatedTextIsCollapsed() {
        XCTAssertEqual(GamePhoneText.withoutRepeat("Grab some ice on the way. Grab some ice on the way."),
                       "Grab some ice on the way.")
        XCTAssertEqual(GamePhoneText.withoutRepeat("Yolda buz al. Yolda buz al."), "Yolda buz al.")
        XCTAssertEqual(GamePhoneText.withoutRepeat("no no"), "no no", "kısa yineleme anlamlıdır")
        XCTAssertEqual(GamePhoneText.withoutRepeat("Call me at 5. Call me at 6."), "Call me at 5. Call me at 6.")
        let lines = [TextLine("Grab some ice on the way", box: Self.box(0.3, 0.05)),
                     TextLine("Grab some ice on the way", box: Self.box(0.34, 0.05)),
                     TextLine("and some plates", box: Self.box(0.38, 0.05))]
        XCTAssertEqual(GamePhoneText.withoutRepeatedLines(lines).map(\.text), ["Grab some ice on the way", "and some plates"])
    }

    func testPanelRemembersItsTextSizeAndFollowsAMoveWithTheSameSize() {
        let still = GamePhoneGeometry.Pose(topX: 0.5, topY: 0.19, bottomX: 0.5, bottomY: 0.87)
        var steady = PhonePanelSteady()
        _ = steady.steadyPose(still, now: 0)
        XCTAssertEqual(steady.steadyLine(0.02, now: 0), 0.02)
        // Telefon bir an kayboldu: yer unutulur, aynı boydaki telefonun yazı boyu kalır.
        steady.reset()
        let back = steady.steadyPose(GamePhoneGeometry.Pose(topX: 0.505, topY: 0.2, bottomX: 0.505, bottomY: 0.885), now: 450)
        XCTAssertFalse(back.resized)
        XCTAssertEqual(steady.steadyLine(0.024, now: 450), 0.02)
        // Biraz büyük okunan telefon başka yere geçti: panel aynı boyda, sabit uzaklıkla izler.
        let moved = GamePhoneGeometry.Pose(topX: 0.30, topY: 0.21, bottomX: 0.31, bottomY: 0.91)
        _ = steady.steadyPose(moved, now: 900)
        let placed = steady.steadyPose(moved, now: 1950)
        XCTAssertFalse(placed.resized)
        XCTAssertEqual(placed.pose.bottomY - placed.pose.topY, 0.885 - 0.2, accuracy: 1e-9)
        XCTAssertEqual((placed.pose.bounds.left + placed.pose.bounds.right) / 2,
                       (moved.bounds.left + moved.bounds.right) / 2, accuracy: 1e-9)
        // Çeviri durunca her şey unutulur.
        steady.forget()
        XCTAssertTrue(steady.steadyPose(still, now: 2400).resized)
    }

    func testMemoryKeepsTranslationsAndForgetsTheOldest() {
        let memory = PhoneMemory()
        memory.remember(Self.first, "Bu akşam mangala geliyor musun?")
        XCTAssertEqual(memory.translation(of: "Are you cominq to the barbecue tonight?"), "Bu akşam mangala geliyor musun?")
        for index in 0..<PhoneMemory.capacity { memory.remember("Message number \(index) about the party", "\(index)") }
        XCTAssertNil(memory.known[Self.first])
        XCTAssertEqual(memory.known.count, PhoneMemory.capacity)
        memory.clear()
        XCTAssertTrue(memory.known.isEmpty)
    }
}
