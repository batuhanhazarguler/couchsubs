// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import CoreGraphics
import Foundation
import ImageIO
import XCTest

/// Çizim kipinin gerçek karelerde seçimi (`TextPaint.mode`): yazı tanıma yok, yazıların yeri sabit (karede, kenarlara
/// oranla); stil `TextStyleSampler`'dan, ölçüm `TextPainter`'dan. Ortak vakalar Fixtures/text-paint-modes.json (Windows
/// TextPaintModeFrameTests.cs, Android TextPaintModeFrameTest.kt aynı kareler ve beklentiler).
final class TextPaintModeFrameTests: XCTestCase {
    struct Vectors: Decodable {
        struct Target: Decodable {
            let text: String; let box: [Double]; let kind: String?; let prompt: Bool?; let rows: Int?
        }
        struct Expect: Decodable { let mode: String; let portrait: Bool?; let side: String?; let twinSide: String? }
        struct Frame: Decodable { let id: String; let file: String; let targets: [Target]; let expect: [Expect]; let same: [[Int]]? }
        let frames: [Frame]
    }

    static func vectors() throws -> Vectors {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/text-paint-modes.json")
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }

    static func image(_ file: String) throws -> CGImage {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("testdata/frames/\(file)")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), file)
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), file)
    }

    /// `a` kutusu `b`'nin hangi yanında (left/right/below/above); kesişiyorsa nil.
    static func side(_ a: TextBox, of b: TextBox) -> String? {
        if a.right <= b.left + 1e-9 { return "left" }
        if a.left >= b.right - 1e-9 { return "right" }
        if a.top >= b.bottom - 1e-9 { return "below" }
        if a.bottom <= b.top + 1e-9 { return "above" }
        return nil
    }

    func testRealFrameModes() throws {
        for frame in try Self.vectors().frames {
            let image = try Self.image(frame.file)
            let boxes = frame.targets.map { TextBox(left: $0.box[0], top: $0.box[1], right: $0.box[2], bottom: $0.box[3]) }
            let targets = zip(frame.targets, boxes).map { target, box -> TextPainter.Target in
                let rows = target.rows ?? 1
                let (style, look) = TextStyleSampler.sample(image, box: box, lines: [TextLine(target.text, box: box)],
                                                            source: target.text)
                return TextPainter.Target(box: box, lineHeight: (box.bottom - box.top) / Double(rows), rows: rows,
                                          background: style.background, foreground: style.foreground, upper: look.upper,
                                          align: look.align, words: TextPainter.words(target.text),
                                          kind: target.kind.flatMap(ScreenTextKind.init(rawValue:)), prompt: target.prompt ?? false)
            }
            let paints = TextPainter.paints(targets, frame: image)
            XCTAssertEqual(paints.count, frame.expect.count, frame.id)
            for (k, expect) in frame.expect.enumerated() where k < paints.count {
                let paint = paints[k], name = "\(frame.id)#\(k) \(frame.targets[k].text)"
                XCTAssertEqual(paint.mode.rawValue, expect.mode, name)
                if let face = expect.portrait { XCTAssertEqual(paint.portrait != nil, face, "\(name) resim") }
                // İkiz (Sinan Bey, beta.100): özgün kutu örtülmez; ikiz aynı boyda (küçültme yok), yanında, altında ya da üstünde.
                if paint.mode == .twin, let twin = paint.twin, let spot = paint.spot {
                    XCTAssertEqual(paint.scale, 1, accuracy: 1e-9, name)
                    XCTAssertEqual(spot.bottom - spot.top, paint.cover.bottom - paint.cover.top, accuracy: 1e-6, name)
                    XCTAssertNotNil(Self.side(twin, of: paint.cover), "\(name) ikiz özgünü örtüyor")
                    if let want = expect.twinSide { XCTAssertEqual(Self.side(twin, of: boxes[k]), want, "\(name) ikiz yanı") }
                }
                // Yanına yazma: arka plansız, özgünün yanında; Türkçe özgün yazıya binmez.
                if paint.mode == .beside, let spot = paint.spot, let room = paint.spotRoom {
                    if let want = expect.side { XCTAssertEqual(Self.side(spot, of: paint.cover), want, "\(name) yan") }
                    XCTAssertNotNil(Self.side(room, of: paint.cover), "\(name) özgüne biner")
                }
            }
            // Liste birlikte: sütunda Türkçelerin ortak kenarı (solda sağ kenar, sağda sol kenar), satırda ortak üst çizgi.
            for list in frame.same ?? [] {
                let spots = list.compactMap { paints[$0].spot }
                XCTAssertEqual(spots.count, list.count, "\(frame.id) liste")
                guard let first = spots.first, let side = Self.side(first, of: paints[list[0]].cover) else { continue }
                for spot in spots {
                    switch side {
                    case "left": XCTAssertEqual(spot.right, first.right, accuracy: 1e-6, "\(frame.id) sütun")
                    case "right": XCTAssertEqual(spot.left, first.left, accuracy: 1e-6, "\(frame.id) sütun")
                    default: XCTAssertEqual(spot.top, first.top, accuracy: 1e-6, "\(frame.id) satır")
                    }
                }
            }
        }
    }
}
