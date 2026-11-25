// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import XCTest
@testable import CouchSubsCore

/// Kamerayla kayan yazı (plaka, tabela, dükkân adı) altyazı sayılmaz; yerinde duran altyazı hiç çıkarılmaz (GitHub #1259).
/// Ortak deneme dosyası Fixtures/scene-motion.json (Windows SceneMotionTests.cs ve Android SceneMotionTest.kt aynı
/// dosyayı okur).
final class SceneMotionTests: XCTestCase {
    private struct Vectors: Decodable {
        struct Line: Decodable { let text: String; let box: [Double]? }
        struct Frame: Decodable { let time: Int; let lines: [Line]; let kept: [String] }
        struct Case: Decodable { let name: String; let area: [Double]; let frames: [Frame] }
        let cases: [Case]
    }

    private func vectors() throws -> Vectors {
        let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("scene-motion.json")
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }

    private func box(_ values: [Double]) -> TextBox {
        TextBox(left: values[0], top: values[1], right: values[2], bottom: values[3])
    }

    func testSharedVectors() throws {
        let cases = try vectors().cases
        XCTAssertFalse(cases.isEmpty)
        for vector in cases {
            var motion = SceneMotion()
            let area = box(vector.area)
            for frame in vector.frames {
                let reading = Reading(lines: frame.lines.map { TextLine($0.text, box: $0.box.map(box)) })
                let kept = motion.filter(reading, in: area, at: frame.time)
                XCTAssertEqual(kept.lines.map(\.text), frame.kept, "\(vector.name) @\(frame.time)")
                XCTAssertEqual(motion.removed.count, reading.lines.count - frame.kept.count, "\(vector.name) @\(frame.time)")
            }
        }
    }

    func testResetForgetsSeenText() {
        var motion = SceneMotion()
        let area = TextBox(left: 0, top: 0, right: 1, bottom: 1)
        _ = motion.filter(Reading(lines: [TextLine("Charters", box: TextBox(left: 0.1, top: 0.5, right: 0.2, bottom: 0.55))]), in: area, at: 0)
        motion.reset()
        let kept = motion.filter(Reading(lines: [TextLine("Charters", box: TextBox(left: 0.4, top: 0.5, right: 0.5, bottom: 0.55))]),
                                 in: area, at: 100)
        XCTAssertEqual(kept.lines.map(\.text), ["Charters"])
    }
}
