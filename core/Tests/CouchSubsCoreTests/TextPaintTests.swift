// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import CoreGraphics
import Foundation
import ImageIO
import XCTest

/// Yerinde birebir çizim: göndericinin kareden ölçtükleri (`TextPainter`: örtü kutusu, zemin/degrade/desen, boş alan,
/// grup) ve çizicilerin ortak yerleşimi (`ScreenFit.exact`). Ortak deneme dosyası Fixtures/text-paint.json (Windows
/// TextPaintTests.cs, Android TextPaintTest.kt ve TV scripts/tv-exact-fit.test.js aynı vakalar).
final class TextPaintTests: XCTestCase {
    struct Fixture: Decodable {
        struct Background: Decodable { let kind: String; let from: String; let to: String?; let cell: Int? }
        struct Rect: Decodable { let box: [Int]; let color: String }
        struct Target: Decodable {
            let box: [Double]; let line: Double; let rows: Int; let bg: String; let fg: String; let upper: Bool; let align: String
        }
        struct Expect: Decodable {
            let cover: [Double]?; let bg: String?; let bg2: String??; let bgDir: String?; let patterned: Bool?
            let grow: [Double]??; let group: Int??; let pitch: Double?

            enum CodingKeys: String, CodingKey { case cover, bg, bg2, bgDir, patterned, grow, group, pitch }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                cover = try c.decodeIfPresent([Double].self, forKey: .cover)
                bg = try c.decodeIfPresent(String.self, forKey: .bg)
                bg2 = c.contains(.bg2) ? .some(try c.decodeIfPresent(String.self, forKey: .bg2)) : nil
                bgDir = try c.decodeIfPresent(String.self, forKey: .bgDir)
                patterned = try c.decodeIfPresent(Bool.self, forKey: .patterned)
                grow = c.contains(.grow) ? .some(try c.decodeIfPresent([Double].self, forKey: .grow)) : nil
                group = c.contains(.group) ? .some(try c.decodeIfPresent(Int.self, forKey: .group)) : nil
                pitch = try c.decodeIfPresent(Double.self, forKey: .pitch)
            }
        }
        struct Paint: Decodable {
            let id: String; let width: Int; let height: Int; let background: Background; let rects: [Rect]
            let targets: [Target]; let expect: [Expect]
        }
        struct ExactItem: Decodable {
            let text: String; let box: [Double]; let grow: [Double]?; let line: Double; let pitch: Double?; let rows: Int?
            let align: String; let group: Int?
        }
        struct Placement: Decodable {
            let left: Double; let top: Double; let width: Double; let height: Double; let fontSize: Double; let lines: [String]
            let lineHeight: Double; let rowHeight: Double
        }
        struct Exact: Decodable { let id: String; let charWidth: Double; let items: [ExactItem]; let expect: [Placement]? }
        let paint: [Paint]
        let exact: [Exact]
    }

    static func fixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/text-paint.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// Yapay karenin noktası: zemin, üstüne sırayla çizilen dikdörtgenler.
    static func pixel(_ frame: Fixture.Paint, _ x: Int, _ y: Int) -> TextPainter.RGB {
        for rect in frame.rects.reversed() where x >= rect.box[0] && x < rect.box[2] && y >= rect.box[1] && y < rect.box[3] {
            return TextPainter.rgb(rect.color)
        }
        let from = TextPainter.rgb(frame.background.from), to = TextPainter.rgb(frame.background.to ?? frame.background.from)
        func mix(_ f: Double) -> TextPainter.RGB {
            (Int((Double(from.r) + Double(to.r - from.r) * f).rounded()), Int((Double(from.g) + Double(to.g - from.g) * f).rounded()),
             Int((Double(from.b) + Double(to.b - from.b) * f).rounded()))
        }
        switch frame.background.kind {
        case "h": return mix(Double(x) / Double(frame.width - 1))
        case "v": return mix(Double(y) / Double(frame.height - 1))
        case "checker":
            let cell = frame.background.cell ?? 6
            return (x / cell + y / cell) % 2 == 0 ? from : to
        default: return from
        }
    }

    static func align(_ text: String) -> TextLook.Align { TextLook.Align(rawValue: text) ?? .left }

    /// Renkler kanal başına en çok 4 farklı.
    static func near(_ a: String, _ b: String) -> Bool { TextPainter.distance(TextPainter.rgb(a), TextPainter.rgb(b)) <= 4 }

    func testSharedPaintVectors() throws {
        for frame in try Self.fixture().paint {
            let w = Double(frame.width), h = Double(frame.height)
            let targets = frame.targets.map { t in
                TextPainter.Target(box: TextBox(left: t.box[0] / w, top: t.box[1] / h, right: t.box[2] / w, bottom: t.box[3] / h),
                                   lineHeight: t.line / h, rows: t.rows, background: t.bg, foreground: t.fg, upper: t.upper,
                                   align: Self.align(t.align))
            }
            let paints = TextPainter.paints(targets, width: frame.width, height: frame.height) { Self.pixel(frame, $0, $1) }
            XCTAssertEqual(paints.count, frame.expect.count, frame.id)
            for (k, expect) in frame.expect.enumerated() where k < paints.count {
                let paint = paints[k], name = "\(frame.id)#\(k)"
                if let cover = expect.cover {
                    let got = [paint.cover.left * w, paint.cover.top * h, paint.cover.right * w, paint.cover.bottom * h]
                    for (a, b) in zip(got, cover) { XCTAssertEqual(a, b, accuracy: 1.01, "\(name) örtü \(got)") }
                }
                if let bg = expect.bg { XCTAssertTrue(Self.near(paint.background, bg), "\(name) zemin \(paint.background) ≠ \(bg)") }
                if let bg2 = expect.bg2 {
                    if let bg2 { XCTAssertTrue(paint.background2.map { Self.near($0, bg2) } ?? false, "\(name) bg2 \(String(describing: paint.background2))") }
                    else { XCTAssertNil(paint.background2, name) }
                }
                if let direction = expect.bgDir { XCTAssertEqual(paint.direction?.rawValue, direction, name) }
                if let patterned = expect.patterned { XCTAssertEqual(paint.patterned, patterned, name) }
                if let grow = expect.grow {
                    if let grow {
                        XCTAssertNotNil(paint.grow, name)
                        XCTAssertEqual((paint.grow?.left ?? -1) * w, grow[0], accuracy: 1.01, "\(name) uzama solu")
                        XCTAssertEqual((paint.grow?.right ?? -1) * w, grow[1], accuracy: 1.01, "\(name) uzama sağı")
                    } else { XCTAssertNil(paint.grow, name) }
                }
                if let group = expect.group { XCTAssertEqual(paint.group, group, name) }
                if let pitch = expect.pitch { XCTAssertEqual(paint.pitch * h, pitch, accuracy: 0.5, name) }
            }
        }
    }

    static func exactInputs(_ vector: Fixture.Exact) -> [ScreenFit.ExactInput] {
        vector.items.map { item in
            ScreenFit.ExactInput(text: item.text, left: item.box[0], top: item.box[1], right: item.box[2], bottom: item.box[3],
                                 growLeft: item.grow?[0], growRight: item.grow?[1], line: item.line, pitch: item.pitch,
                                 rows: item.rows ?? 1, align: align(item.align), group: item.group)
        }
    }

    func testSharedExactVectors() throws {
        var out: [[String: Any]] = []
        for vector in try Self.fixture().exact {
            let placed = ScreenFit.exact(Self.exactInputs(vector)) { text, size in Double(text.count) * vector.charWidth * size }
            out.append(["id": vector.id, "expect": placed.map { p -> [String: Any] in
                ["left": round(p.left * 100) / 100, "top": round(p.top * 100) / 100, "width": round(p.width * 100) / 100,
                 "height": round(p.height * 100) / 100, "fontSize": round(p.fontSize * 100) / 100, "lines": p.lines,
                 "lineHeight": round(p.lineHeight * 100) / 100, "rowHeight": round(p.rowHeight * 100) / 100]
            }])
            guard let expect = vector.expect else { continue }
            XCTAssertEqual(placed.count, expect.count, vector.id)
            for (p, e) in zip(placed, expect) {
                let name = "\(vector.id) \(e.lines)"
                XCTAssertEqual(p.lines, e.lines, name)
                XCTAssertEqual(p.left, e.left, accuracy: 0.05, name)
                XCTAssertEqual(p.top, e.top, accuracy: 0.05, name)
                XCTAssertEqual(p.width, e.width, accuracy: 0.05, name)
                XCTAssertEqual(p.height, e.height, accuracy: 0.05, name)
                XCTAssertEqual(p.fontSize, e.fontSize, accuracy: 0.05, name)
                XCTAssertEqual(p.lineHeight, e.lineHeight, accuracy: 0.05, name)
                XCTAssertEqual(p.rowHeight, e.rowHeight, accuracy: 0.05, name)
            }
        }
        if ProcessInfo.processInfo.environment["TEXT_PAINT_OUT"] != nil {
            let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        }
    }

    /// Kurallar ortak dosyadan bağımsız da: grup içinde yazı boyu eşit, uzun çeviri boş alana uzar, kutu simgeye/ekran
    /// kenarına taşmaz, yazı kesilmez.
    func testGroupKeepsOneSizeAndGrowsIntoFreeSide() throws {
        let vector = try XCTUnwrap(Self.fixture().exact.first { $0.id == "grup-esit-boy-bos-alana-uzar" })
        let inputs = Self.exactInputs(vector)
        let placed = ScreenFit.exact(inputs) { text, size in Double(text.count) * vector.charWidth * size }
        XCTAssertEqual(Set(placed.map { ($0.fontSize * 100).rounded() }).count, 1, "grubun yazı boyu tek")
        for (input, p) in zip(inputs, placed) {
            XCTAssertEqual(p.lines.joined(separator: " "), input.text, "yazı kesilmez")
            XCTAssertEqual(p.left + p.width, input.right, accuracy: 0.01, "sağ kenar (simge tarafı) yerinde")
            XCTAssertGreaterThanOrEqual(p.left, input.growLeft - 0.01, "boş alanın dışına taşmaz")
            XCTAssertEqual(p.lines.count, 1, "boş alan varken satır kırılmaz")
        }
        // "HEDEF BELİRLE" kendi kutusundan uzun: boş sol tarafa uzar, yazı boyu küçülmez.
        XCTAssertLessThan(placed[3].left, inputs[3].left)
        XCTAssertEqual(placed[3].fontSize, ScreenFit.exactFont * 20, accuracy: 0.01)
    }

    func testWholeGroupShrinksTogetherWhenNoRoom() throws {
        let vector = try XCTUnwrap(Self.fixture().exact.first { $0.id == "bos-alan-yok-grup-birlikte-kuculur" })
        let inputs = Self.exactInputs(vector)
        let placed = ScreenFit.exact(inputs) { text, size in Double(text.count) * vector.charWidth * size }
        XCTAssertEqual(Set(placed.map { ($0.fontSize * 100).rounded() }).count, 1, "grup birlikte küçülür")
        XCTAssertLessThan(placed[0].fontSize, ScreenFit.exactFont * 20)
        for (input, p) in zip(inputs, placed) {
            XCTAssertGreaterThanOrEqual(p.left, input.growLeft - 0.01)
            XCTAssertLessThanOrEqual(p.left + p.width, input.growRight + 0.01)
            XCTAssertEqual(p.lines.joined(separator: " "), input.text)
        }
    }

    /// Gerçek kare (testdata/frames/gta6-menu-harita.jpg): harita ipuçları tek grup, sağa yaslı; uzun çeviri boş sola uzar;
    /// zemin mavi degradenin rengi (koyu kutu değil); görev kartının üç satırlık açıklaması özgün satır aralığında.
    func testRealMapHints() throws {
        let url = ScreenFitTests.directory.appendingPathComponent("gta6-menu-harita.jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        // Kayıtlı okumanın kutuları (simge kırpılmış): RECENTER, 2D VIEW, ADD MARKER, SET DESTINATION, EXIT.
        let boxes: [[Double]] = [[0.8689, 0.7194, 0.9334, 0.7544], [0.8791, 0.766, 0.9334, 0.8018],
                                 [0.8499, 0.8135, 0.9334, 0.852], [0.8268, 0.8632, 0.9334, 0.8996], [0.9055, 0.9147, 0.9334, 0.9483]]
        let targets = boxes.map { b in
            TextPainter.Target(box: TextBox(left: b[0], top: b[1], right: b[2], bottom: b[3]), lineHeight: 0.036, rows: 1,
                               background: "#0A6BEB", foreground: "#FFFFFF", upper: true, align: .right)
        }
        let paints = TextPainter.paints(targets, frame: image)
        XCTAssertEqual(paints.count, 5)
        XCTAssertEqual(Set(paints.compactMap(\.group)).count, 1, "ipuçları tek grup")
        XCTAssertTrue(paints.allSatisfy { $0.group != nil })
        for paint in paints {
            let bg = TextPainter.rgb(paint.background)
            XCTAssertGreaterThan(bg.b, 180, "zemin mavi: \(paint.background)")
            XCTAssertLessThan(bg.r, 60, "zemin mavi: \(paint.background)")
            // Simge (x ≈ 0.94) tarafına taşmaz.
            XCTAssertLessThan(paint.cover.right, 0.9405)
            XCTAssertNotNil(paint.grow, "sol taraf boş")
            XCTAssertLessThan(paint.grow!.left, paint.cover.left - 0.05)
        }
    }

    /// Kapsama: tek sözcüklük menü/ipucu etiketi kısa metin filtresine takılmaz; logo ve stilize başlık çevrilmez.
    @MainActor
    func testShortUiLabelsAreTranslatedAndTitleMarksKept() {
        func candidate(_ text: String) -> RegionWatcher.Candidate {
            RegionWatcher.Candidate(paragraphs: [text], box: nil, lineHeight: nil, key: text)
        }
        for label in ["Map", "Settings", "EXIT", "Help", "Photo Studio", "Set Destination"] {
            XCTAssertTrue(RegionWatcher.isUiLabel(candidate(label), uiCommands: true), label)
            if !label.contains(" ") { XCTAssertTrue(ScreenTextNoise.isNoise(label, menu: false), "eski filtre \(label) etiketini atıyordu") }
            XCTAssertFalse(ScreenTextNoise.isNoise(label, menu: true), label)
        }
        XCTAssertFalse(RegionWatcher.isUiLabel(candidate("Map"), uiCommands: false), "yalnız İngilizceden Türkçeye")
        XCTAssertFalse(RegionWatcher.isUiLabel(candidate("Bonus"), uiCommands: true))
        for title in ["VI", "Grand Theft Auto VI", "GRAND THEFT AUTO", "GTA VI", "Rockstar Games"] {
            XCTAssertTrue(ScreenTranslation.keepsNames(title), title)
        }
        for text in ["Map", "VIEW", "Grand prize", "I told you"] { XCTAssertFalse(ScreenTranslation.keepsNames(text), text) }
    }
}
