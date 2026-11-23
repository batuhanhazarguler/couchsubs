// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// "Sil ve yeniden çiz" prototipinin ölçümü (docs/ekran-yazisi-sil-ciz.md), gerçek karelerin kayıtlı okumalarıyla (yazı
/// tanıma koşmaz): GTA 6 menü/görev kareleri ("Ekranı çevir" öğeleri) ve bütün oyunların (GTA 6, RDR2, Elden Ring, AC
/// Shadows) altyazı satırları. Ölçüler: silme sonrası kalan harf noktası oranı, temiz silinebilen (düz/degrade zemin)
/// yazı payı, simge/fotoğraf alanlarının değişmediği, yazı başına süre. `TEXT_ERASE_OUT=<klasör>`: silinmiş ve yeniden
/// çizilmiş kareler PNG olarak yazılır (gözle denetim).
final class TextEraseTests: XCTestCase {
    private struct Manifest: Decodable {
        struct Frame: Decodable { let id: String; let file: String; let game: String? }
        let frames: [Frame]
    }

    private struct Fixture: Decodable {
        struct Line: Decodable { let text: String; let box: [Double]? }
        let region: [Double]
        let lines: [Line]
    }

    private static func box(_ v: [Double]) -> TextBox { TextBox(left: v[0], top: v[1], right: v[2], bottom: v[3]) }

    private static func load(_ file: String) throws -> CGImage {
        let url = ScreenFitTests.directory.appendingPathComponent(file)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private static func save(_ image: TextErase.Image, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TEXT_ERASE_OUT"], let cg = image.cgImage(),
              let target = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir).appendingPathComponent(name + ".png") as CFURL,
                                                           UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(target, cg, nil)
        CGImageDestinationFinalize(target)
    }

    /// Menü/görev ekranı: silme yalnız yazının noktalarına dokunur; simge ve fotoğraf alanlarının hiçbir noktası değişmez,
    /// düz menü zemininde kalan harf noktası yok denecek kadar az.
    func testMenuTextIsErasedWithoutTouchingIcons() async throws {
        var residuals: [Double] = [], clean = 0, total = 0, seconds = 0.0
        for frame in try ScreenFitTests.frames() {
            let items = try await ScreenTranslation.translate(frame.reading, using: { ScreenFitTests.translateWord($0) }, frame: frame.image)
            var image = try XCTUnwrap(TextErase.Image(frame.image))
            let original = image.bytes
            for item in items {
                let start = Date()
                guard let patch = TextErase.erase(&image, box: item.box) else { continue }
                seconds += Date().timeIntervalSince(start)
                total += 1
                if patch.clean { clean += 1; residuals.append(patch.residual) }
                TextErase.draw(item.translation.replacingOccurrences(of: "\n", with: " "), in: &image, box: item.box,
                               lineHeight: item.lineHeight, rows: item.rows, patch: patch, bold: item.look?.bold ?? false, align: item.look?.align ?? .left)
            }
            // Simge/fotoğraf alanları birebir aynı kalır (çizim dahil).
            for zone in frame.clear {
                let x0 = Int(zone.left * Double(image.width)) + 1, x1 = Int(zone.right * Double(image.width)) - 1
                let y0 = Int(zone.top * Double(image.height)) + 1, y1 = Int(zone.bottom * Double(image.height)) - 1
                var changed = 0
                for y in y0...y1 { for x in x0...x1 {
                    let p = (y * image.width + x) * 4
                    if image.bytes[p] != original[p] || image.bytes[p + 1] != original[p + 1] || image.bytes[p + 2] != original[p + 2] { changed += 1 }
                } }
                XCTAssertEqual(changed, 0, "\(frame.id): simge/fotoğraf alanı değişti \(zone)")
            }
            Self.save(image, frame.id + "-sil-ciz")
        }
        residuals.sort()
        let median = residuals.isEmpty ? 1 : residuals[residuals.count / 2]
        print(String(format: "ölçüm menü: %d yazı, temiz %d, kalan harf ortanca %.3f en çok %.3f, yazı başına %.1f ms",
                     total, clean, median, residuals.last ?? 1, seconds * 1000 / Double(max(1, total))))
        XCTAssertGreaterThan(total, 20)
        XCTAssertLessThanOrEqual(median, 0.05)
    }

    /// Bütün oyunların altyazı satırları (3B dünya ve video üstünde): temiz silinebileni ve dokulu zemini (kutuya dönüş)
    /// sayar; oyun başına ölçü yazdırılır. Genel yöntem: oyuna özel ayar yok.
    func testSubtitleLinesAcrossGames() throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: ScreenFitTests.directory.appendingPathComponent("frames.json")))
        var byGame: [String: (total: Int, clean: Int, residual: [Double])] = [:]
        for frame in manifest.frames {
            let url = ScreenFitTests.directory.appendingPathComponent("ocr/\(frame.id).json")
            guard let data = try? Data(contentsOf: url), let fixture = try? JSONDecoder().decode(Fixture.self, from: data),
                  let cg = try? Self.load(frame.file), var image = TextErase.Image(cg) else { continue }
            let region = Self.box(fixture.region)
            let game = frame.game ?? String(frame.id.prefix { $0 != "-" })
            for line in fixture.lines where line.text.filter(\.isLetter).count >= 4 {
                guard let b = line.box, let patch = TextErase.erase(&image, box: Self.box(b).placed(in: region)) else { continue }
                var entry = byGame[game] ?? (0, 0, [])
                entry.total += 1
                if patch.clean { entry.clean += 1 }
                entry.residual.append(patch.residual)
                byGame[game] = entry
            }
            Self.save(image, frame.id + "-sil")
        }
        for (game, entry) in byGame.sorted(by: { $0.key < $1.key }) {
            let sorted = entry.residual.sorted()
            print(String(format: "ölçüm altyazı %@: %d satır, temiz silinebilen %d, kalan harf ortanca %.3f",
                         game, entry.total, entry.clean, sorted[sorted.count / 2]))
        }
        XCTAssertGreaterThanOrEqual(byGame.count, 3)
    }
}
