// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import XCTest
@testable import CouchSubsCore

/// Duraklatma menüsünün konuşma/yardım geçmişi listesi (Sinan Bey beta.100, 3380-3383). Ortak deneme dosyası
/// Fixtures/menu-list.json (Windows MenuListTests.cs ve Android MenuListTest.kt aynı dosyayı okur). Vision kullanmaz.
final class MenuListTests: XCTestCase {
    private struct Line: Decodable { let text: String; let box: [Double] }
    private struct ListCase: Decodable { let name: String; let list: Bool; let lines: [Line] }
    private struct Pieces: Decodable { let name: String; let aspect: Double; let lines: [Line]; let expected: [String] }
    private struct Cut: Decodable { let name: String; let region: [Double]; let box: [Double]; let cut: Bool }
    private struct Label: Decodable { let text: String; let prefix: String; let core: String }
    private struct Shown: Decodable { let source: String; let box: [Double] }
    private struct Current: Decodable { let text: String; let box: [Double] }
    private struct Scroll: Decodable { let name: String; let moved: Bool; let rendered: [Shown]; let current: [Current] }
    private struct Vectors: Decodable {
        let lists: [ListCase]
        let pieces: [Pieces]
        let cuts: [Cut]
        let labels: [Label]
        let scrolls: [Scroll]
    }

    private func vectors() throws -> Vectors {
        let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("menu-list.json")
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }

    private func box(_ v: [Double]) -> TextBox { TextBox(left: v[0], top: v[1], right: v[2], bottom: v[3]) }
    private func reading(_ lines: [Line]) -> Reading { Reading(lines: lines.map { TextLine($0.text, box: box($0.box)) }) }

    /// Liste satırları altyazı seçilmez: alt kutuda "Staff Member: …" gösterilmiyor, gerçek altyazı seçilmeye devam ediyor.
    func testHistoryListIsNeverASubtitle() throws {
        let area = TextBox(left: 0.14, top: 0.62, right: 0.86, bottom: 0.97)
        for item in try vectors().lists {
            let read = reading(item.lines)
            XCTAssertEqual(read.isHistoryList, item.list, item.name)
            var reasons: [String] = []
            let block = read.subtitleBlock(in: area, dropped: { _, reason in reasons.append(reason) })
            if item.list {
                XCTAssertTrue(block.lines.isEmpty, item.name)
                XCTAssertEqual(reasons, [Reading.listReason], item.name)
            } else {
                XCTAssertFalse(reasons.contains(Reading.listReason), item.name)
            }
        }
    }

    @MainActor
    func testPiecesOfOneRowAreJoined() throws {
        for item in try vectors().pieces {
            let joined = RegionWatcher.joinedPieces(item.lines.map { TextLine($0.text, box: box($0.box)) }, aspect: item.aspect)
            XCTAssertEqual(joined.map(\.text), item.expected, item.name)
        }
    }

    @MainActor
    func testRowCutAtTheAreaEdgeIsSkipped() throws {
        for item in try vectors().cuts {
            let region = CropRegion(top: item.region[1], bottom: item.region[3], left: item.region[0], right: item.region[2])
            XCTAssertEqual(RegionWatcher.cutAtAreaEdge(TextLine("Clerk: Need a hand", box: box(item.box)), region: region),
                           item.cut, item.name)
        }
    }

    /// Konuşan adı ve özel ad çeviriye gitmez ("JASON & LUCIA MAP" → yalnız "MAP" çevrilir).
    @MainActor
    func testSpeakerAndNameHeadsStayUntranslated() throws {
        for item in try vectors().labels {
            let parts = RegionWatcher.splitLabel(item.text)
            XCTAssertEqual(parts.count, 1, item.text)
            XCTAssertEqual(parts.first?.prefix, item.prefix, item.text)
            XCTAssertEqual(parts.first?.core, item.core, item.text)
        }
    }

    /// Liste kayınca eski kutular kalkar (gösterilen satır başka yerde ya da yerinde başka satır).
    @MainActor
    func testScrollingListDropsOldBoxes() throws {
        for item in try vectors().scrolls {
            let rendered = item.rendered.map {
                ScreenTranslation.Item(source: $0.source, translation: "çeviri", box: box($0.box), lineHeight: $0.box[3] - $0.box[1])
            }
            let current = item.current.map { (box: box($0.box), text: $0.text) }
            XCTAssertEqual(RegionWatcher.listMoved(rendered: rendered, current: current), item.moved, item.name)
        }
    }

    /// Liste okunurken menü durumu bitmez: konuşan adlı satır (kaydırırken tek satır okunabilir) menüyü kapatmaz, menü
    /// süresi (`menuLifeMs`) de dolmaz. Liste ekrandan kalkınca konuşma satırı yine menüyü hemen bitirir (#1240).
    func testListKeepsTheMenuAndDialogueEndsItOnlyAfterwards() {
        var pixels = [UInt8](repeating: 70, count: 640 * 360 * 4)
        for (column, row, width) in [(8, 4, 1), (16, 2, 1), (24, 4, 1), (27, 9, 1), (13, 8, 6)] {
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
        for time in stride(from: 500, through: 8000, by: ScreenTextDetector.sampleIntervalMs) {
            if time % 500 == 0 { detector.noteList(now: time) }
            if time % 700 == 0 { detector.noteDialogue(now: time) }
            detector.sample(image, now: time, excluded: [])
            XCTAssertTrue(detector.inMenu, "\(time) ms")
        }
        detector.noteDialogue(now: 9700)
        detector.sample(image, now: 9700, excluded: [])
        XCTAssertFalse(detector.inMenu)
    }

    private final class Sink: SubtitleSending {
        var sent: [String] = []
        func sendSubtitle(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) { sent.append(text) }
        func clear() {}
    }

    func testListLinesHeldDuringTheMenuAreNotSentAfterIt() {
        let sink = Sink()
        var menu = true
        var time = 0
        let sender = MenuHeldSender(sink, inMenu: { menu }, log: { _ in }, clock: { time })
        XCTAssertTrue(sender.poll())
        time = 1000
        sender.sendSubtitle("Clerk: Take it easy.", durationMs: 15000, box: nil, replaces: false)
        sender.forget()
        menu = false
        time = 2000
        sender.poll()
        XCTAssertEqual(sink.sent, [])
    }

    private final class Fixed: TextReader, @unchecked Sendable {
        let reading: Reading
        init(_ reading: Reading) { self.reading = reading }
        func read(_ image: CGImage) throws -> String { reading.text }
        func readLines(_ image: CGImage, deep: Bool) throws -> Reading { reading }
    }

    private final class Echo: TextTranslator, @unchecked Sendable {
        func translate(_ text: String) async throws -> String { "TR " + text }
    }

    /// Uçtan uca: altyazı alanında geçmiş listesi 15 sn okunur; hiçbir satır altyazı olarak gönderilmez (bekçi de
    /// göndermez), konuşan adı menüyü bitirmez (`onDialogue` çağrılmaz), liste bildirilir (`onList`).
    @MainActor
    func testPipelineSendsNothingFromTheList() async throws {
        let list = try XCTUnwrap(try vectors().lists.first { $0.list && $0.lines.count >= 4 })
        var now = 1_000_000
        let sink = Sink()
        let pipeline = SubtitlePipeline(reader: Fixed(reading(list.lines)), translator: Echo(), server: sink, clock: { now })
        var dialogue = 0, listed = 0
        pipeline.onDialogue = { dialogue += 1 }
        pipeline.onList = { listed += 1 }
        let frame = try XCTUnwrap(CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        for _ in 0..<150 {
            await pipeline.process(frame, region: CropRegion())
            await pipeline.waitForTranslations()
            now += 100
        }
        XCTAssertEqual(sink.sent, [])
        XCTAssertEqual(dialogue, 0)
        XCTAssertGreaterThan(listed, 0)
    }
}
