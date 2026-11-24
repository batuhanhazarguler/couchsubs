// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// Menü sırasında gelen altyazı (Windows MenuPausedSenderTests ve Android MenuHeldSenderTest ile aynı).
final class MenuHeldSenderTests: XCTestCase {
    private final class Sink: SubtitleSending {
        var sent: [String] = []
        var clears = 0
        func sendSubtitle(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) { sent.append(text) }
        func clear() { clears += 1 }
    }

    func testMenuLabelsAreNotSentAfterARealMenu() {
        let sink = Sink()
        var menu = false
        var time = 0
        var log: [String] = []
        let sender = MenuHeldSender(sink, inMenu: { menu }, log: { log.append($0) }, clock: { time })
        sender.sendSubtitle("Bir", durationMs: 15000, box: nil, replaces: false)
        menu = true
        time = 100
        sender.sendSubtitle("RESTORE DEFAULT", durationMs: 15000, box: nil, replaces: false)
        sender.clear()
        menu = false
        time = 3000
        sender.sendSubtitle("İki", durationMs: 15000, box: nil, replaces: false)
        XCTAssertEqual(sink.sent, ["Bir", "İki"])
        XCTAssertEqual(sink.clears, 1)
        XCTAssertTrue(log.contains { $0.contains("menü sırasında bekletildi") && $0.contains("RESTORE DEFAULT") })
    }

    /// #1240: karanlık balık tutma sahnesinde tuş ipucu ve görev yazısı birlikte belirince menü sanılıyordu; o sırada gelen
    /// konuşma satırı TV'ye hiç gitmiyordu. Satır bekletilir, menü kapanınca (yeni satır gelmese de) gönderilir.
    func testDialogueDuringAFalseMenuReachesTheTv() {
        let sink = Sink()
        var menu = true
        var time = 0
        var log: [String] = []
        let sender = MenuHeldSender(sink, inMenu: { menu }, log: { log.append($0) }, clock: { time })
        XCTAssertTrue(sender.poll())
        time = 400
        sender.sendSubtitle("Lucia: Balık yine kaçtı.", durationMs: 15000, box: nil, replaces: false)
        time = 900
        sender.sendSubtitle("Jason: Sabret biraz, gelecek.", durationMs: 15000, box: nil, replaces: false)
        XCTAssertEqual(sink.sent, [])
        menu = false
        time = 1500
        XCTAssertFalse(sender.poll())
        XCTAssertEqual(sink.sent, ["Jason: Sabret biraz, gelecek."])
        XCTAssertTrue(log.contains { $0.contains("menü kapanınca gönderildi") && $0.contains("Jason") })
    }

    /// #1240 uçtan uca: ipucu ve görev yazısı birlikte belirip dedektör menü sandı; altyazı alanında konuşan adıyla satır
    /// okundu (SubtitlePipeline.onDialogue) → menü biter, satır TV'ye hemen gider.
    func testPromptAndMissionWithDialogueStillSendsTheLine() {
        var pixels = [UInt8](repeating: 70, count: 640 * 360 * 4)
        for (column, row, width) in [(26, 15, 3), (12, 16, 8), (1, 1, 3)] {
            for y in (row * 20 + 3)..<(row * 20 + 17) {
                for x in (column * 20)..<((column + width) * 20) {
                    let value: UInt8 = [2, 3].contains((y - row * 20) % 6) && x % 5 < 2 ? 240 : 24
                    let p = (y * 640 + x) * 4
                    (pixels[p], pixels[p + 1], pixels[p + 2]) = (value, value, value)
                }
            }
        }
        let image = ScreenTextDetectorTests.image(pixels, width: 640, height: 360)
        let detector = ScreenTextDetector()
        for time in stride(from: 0, through: 400, by: ScreenTextDetector.sampleIntervalMs) {
            detector.sample(image, now: time, excluded: [])
        }
        XCTAssertTrue(detector.inMenu)
        let sink = Sink()
        let sender = MenuHeldSender(sink, inMenu: { detector.inMenu }, log: { _ in }, clock: { 450 })
        XCTAssertTrue(sender.poll())
        detector.noteDialogue(now: 450)
        sender.sendSubtitle("Lucia: Balık yine kaçtı.", durationMs: 15000, box: nil, replaces: false)
        XCTAssertEqual(sink.sent, ["Lucia: Balık yine kaçtı."])
    }

    func testOldHeldLineIsNotSentAfterALongMenu() {
        let sink = Sink()
        var menu = true
        var time = 0
        let sender = MenuHeldSender(sink, inMenu: { menu }, log: { _ in }, clock: { time })
        sender.sendSubtitle("Lucia: Balık yine kaçtı.", durationMs: 15000, box: nil, replaces: false)
        menu = false
        time = 10_000
        sender.poll()
        XCTAssertEqual(sink.sent, [])
    }

    func testShortMenuSendsEveryHeldLineAtOnce() {
        let sink = Sink()
        var menu = true
        var time = 0
        let sender = MenuHeldSender(sink, inMenu: { menu }, log: { _ in }, clock: { time })
        sender.sendSubtitle("Bir", durationMs: 15000, box: nil, replaces: false)
        time = 100
        sender.sendSubtitle("İki", durationMs: 15000, box: nil, replaces: false)
        menu = false
        time = 200
        sender.poll()
        XCTAssertEqual(sink.sent, ["Bir", "İki"])
    }
}
