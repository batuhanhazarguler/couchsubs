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
            let text: String; let box: [Double]; let kind: String?; let prompt: Bool?
        }
        struct Expect: Decodable { let mode: String; let portrait: Bool?; let twinAbove: Bool? }
        struct Frame: Decodable { let id: String; let file: String; let targets: [Target]; let expect: [Expect] }
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

    func testRealFrameModes() throws {
        for frame in try Self.vectors().frames {
            let image = try Self.image(frame.file)
            let boxes = frame.targets.map { TextBox(left: $0.box[0], top: $0.box[1], right: $0.box[2], bottom: $0.box[3]) }
            let targets = zip(frame.targets, boxes).map { target, box -> TextPainter.Target in
                let (style, look) = TextStyleSampler.sample(image, box: box, lines: [TextLine(target.text, box: box)],
                                                            source: target.text)
                return TextPainter.Target(box: box, lineHeight: box.bottom - box.top, rows: 1, background: style.background,
                                          foreground: style.foreground, upper: look.upper, align: look.align,
                                          words: TextPainter.words(target.text),
                                          kind: target.kind.flatMap(ScreenTextKind.init(rawValue:)), prompt: target.prompt ?? false)
            }
            let paints = TextPainter.paints(targets, frame: image)
            XCTAssertEqual(paints.count, frame.expect.count, frame.id)
            for (k, expect) in frame.expect.enumerated() where k < paints.count {
                let paint = paints[k], name = "\(frame.id)#\(k) \(frame.targets[k].text)"
                XCTAssertEqual(paint.mode.rawValue, expect.mode, name)
                if let face = expect.portrait { XCTAssertEqual(paint.portrait != nil, face, "\(name) resim") }
                if let above = expect.twinAbove, let twin = paint.twin { XCTAssertEqual(twin.bottom <= boxes[k].top, above, "\(name) ikiz üstte") }
                // İkiz (Sinan Bey, #1296): özgünden belirgin küçük, sol kenarı özgün panelle hizalı, özgün paneli örtmez.
                if paint.mode == .twin, let twin = paint.twin, let spot = paint.spot {
                    // Belirgin küçük (en çok 1, en az twinScale); küçük bildirimde yazı okunabilirlik sınırında (twinMinShare).
                    XCTAssertTrue(paint.scale >= TextPainter.twinScale - 0.001 && paint.scale <= 1, name)
                    XCTAssertTrue(paint.scale >= 1 || ScreenFit.exactFont * (boxes[k].bottom - boxes[k].top) * paint.scale >= TextPainter.twinMinShare - 0.002, name)
                    XCTAssertEqual((spot.bottom - spot.top) / (paint.cover.bottom - paint.cover.top), paint.scale, accuracy: 0.05, name)
                    XCTAssertLessThan(twin.left, paint.cover.left, name)
                    XCTAssertTrue(twin.bottom <= paint.cover.top || twin.top >= paint.cover.bottom, name)
                    XCTAssertGreaterThan(paint.radius, 0, name)
                }
                // Yanına yazma (Sinan Bey: "SELAMLA  GREET"): aynı satırda, aynı yükseklikte, özgünün solunda.
                if paint.mode == .beside, let spot = paint.spot, expect.mode == "beside" {
                    XCTAssertEqual(spot.top, paint.cover.top, accuracy: 1e-9, name)
                    XCTAssertEqual(spot.bottom, paint.cover.bottom, accuracy: 1e-9, name)
                    XCTAssertLessThanOrEqual(spot.right, paint.cover.left, name)
                }
                // Yanına yazılan Türkçe özgün yazıya binmez.
                if paint.mode == .beside, let room = paint.spotRoom {
                    let a = room, b = paint.cover
                    XCTAssertFalse(min(a.right, b.right) > max(a.left, b.left) && min(a.bottom, b.bottom) > max(a.top, b.top), name)
                }
            }
        }
    }
}
