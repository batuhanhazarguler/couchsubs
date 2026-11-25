// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// Ürün/ambalaj/etiket yazısı (bira kutusu, süt kartonu) ekran yazısı ve altyazı sayılmaz; menü, istem, görev, bildirim ve
/// telefon yazısı kalır (Sinan Bey beta.101). Örnekler ortak deneme dosyasından (Fixtures/package-text.json; Windows
/// PackageTextTests.cs ve Android PackageTextTest.kt aynı dosyayı okur).
final class PackageTextTests: XCTestCase {
    private struct Vectors: Decodable {
        struct Shape: Decodable { let text: String; let brand: Bool }
        struct Product: Decodable { let text: String; let keep: Bool }
        struct Word: Decodable { let text: String; let box: [Double] }
        struct Line: Decodable { let text: String; let box: [Double]; let words: [Word]? }
        struct Look: Decodable { let textured: Bool; let uiInk: Bool }
        struct Case: Decodable { let name: String; let area: [Double]; let lines: [Line]; let look: Look?; let kept: [String] }
        struct Ground: Decodable { let kind: String; let a: [Int]; let b: [Int]; let period: Int }
        struct Pixels: Decodable {
            let name: String; let size: [Int]; let ground: Ground; let ink: [Int]; let box: [Double]; let others: [[Double]]
            let look: Look
        }
        let shapes: [Shape]
        let products: [Product]
        let cases: [Case]
        let pixels: [Pixels]
    }

    private static func box(_ v: [Double]) -> TextBox { TextBox(left: v[0], top: v[1], right: v[2], bottom: v[3]) }

    private func vectors() throws -> Vectors {
        let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("package-text.json")
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }

    func testBrandShape() throws {
        for shape in try vectors().shapes {
            XCTAssertEqual(PackageText.isBrandShape(shape.text), shape.brand, shape.text)
        }
    }

    func testProductNamesAreKept() throws {
        for product in try vectors().products {
            XCTAssertEqual(ScreenTranslation.keepsNames(product.text), product.keep, product.text)
        }
    }

    func testSharedCases() throws {
        for vector in try vectors().cases {
            let reading = Reading(lines: vector.lines.map { line in
                TextLine(line.text, box: Self.box(line.box), words: line.words?.map { TextWord($0.text, box: Self.box($0.box)) })
            })
            let look = vector.look.map { PackageText.Look(textured: $0.textured, uiInk: $0.uiInk) }
            let result = PackageText.filter(reading, in: Self.box(vector.area), look: { _, _ in look })
            XCTAssertEqual(result.kept.lines.map(\.text), vector.kept, vector.name)
            XCTAssertEqual(result.removed.count, vector.lines.count - vector.kept.count, vector.name)
        }
    }

    func testLookFromPixels() throws {
        for vector in try vectors().pixels {
            let w = vector.size[0], h = vector.size[1]
            let boxes = [vector.box] + vector.others
            let rgb = { (x: Int, y: Int) -> Int in
                for b in boxes {
                    let top = b[1] * Double(h), height = (b[3] - b[1]) * Double(h)
                    if x >= Int((b[0] * Double(w)).rounded(.down)), x < Int((b[2] * Double(w)).rounded(.up)),
                       y >= Int(top.rounded(.down)), y < Int((b[3] * Double(h)).rounded(.up)),
                       Double(y) >= top + 0.15 * height, Double(y) < top + 0.85 * height, (x / 2) % 2 == 0 {
                        return Self.pack(vector.ink)
                    }
                }
                let g = vector.ground
                switch g.kind {
                case "checker": return Self.pack((x / g.period + y / g.period) % 2 == 0 ? g.a : g.b)
                case "gradient": return Self.pack((0..<3).map { g.a[$0] + (g.b[$0] - g.a[$0]) * x / (w - 1) })
                default: return Self.pack(g.a)
                }
            }
            let look = PackageText.look(Self.box(vector.box), others: vector.others.map(Self.box), width: w, height: h, rgb: rgb)
            XCTAssertEqual(look, PackageText.Look(textured: vector.look.textured, uiInk: vector.look.uiInk), vector.name)
        }
    }

    private static func pack(_ c: [Int]) -> Int { (c[0] << 16) | (c[1] << 8) | c[2] }
}
