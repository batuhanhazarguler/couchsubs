// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import XCTest

/// Yazı kontrastı (Windows UiLintTests'in karşılığı): okunacak yazı renkleri tasarim.json'da koyu ve açık temada her
/// zeminde en az 4,5:1 (WCAG AA); Ayarlar ekranlarında `Text` soluk `dsFaint` ile çizilmez (iki temada da 4,5:1'in
/// altında; yalnız simge, nokta ve devre dışı durum için).
final class ContrastLintTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    func testTextColorsMeetContrastInBothThemes() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("design/yeni-arayuz/tasarim.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let colors = try XCTUnwrap(json["color"] as? [String: [String: String]])
        var failures: [String] = []
        for theme in ["light", "dark"] {
            for text in ["text", "muted", "amberText", "liveText", "successText", "infoText"] {
                for background in ["background", "surface", "surfaceRaised", "surfaceHigh", "field"] {
                    let ratio = Self.contrast(try XCTUnwrap(colors[text]?[theme]), try XCTUnwrap(colors[background]?[theme]))
                    if ratio < 4.5 { failures.append("\(theme): \(text) / \(background) = \(String(format: "%.2f", ratio))") }
                }
            }
        }
        XCTAssertEqual(failures, [], "4,5:1'in altında kalan yazı rengi")
    }

    func testSettingsTextIsNotFaint() throws {
        let files = ["CouchSubs/UI/Yeni/SettingsPage.swift", "CouchSubs/UI/Yeni/DSComponents.swift", "CouchSubs/UI/ShortcutsCard.swift",
                     "CouchSubs/UI/SettingsView.swift"]
        var violations: [String] = []
        for path in files {
            let text = try String(contentsOf: Self.root.appendingPathComponent("mac").appendingPathComponent(path), encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated()
            where line.contains("Text(") && line.contains("dsFaint") {
                violations.append("\(path):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(violations, [], "Okunacak yazı için Color.dsMuted kullanın.")
    }

    /// WCAG 2 bağıl parlaklık oranı (#RRGGBB; saydamlık baytı yok sayılır).
    private static func contrast(_ a: String, _ b: String) -> Double {
        func luminance(_ hex: String) -> Double {
            let digits = Array(hex.dropFirst())
            func channel(_ index: Int) -> Double {
                let c = Double(Int(String(digits[index..<index + 2]), radix: 16) ?? 0) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(0) + 0.7152 * channel(2) + 0.0722 * channel(4)
        }
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
