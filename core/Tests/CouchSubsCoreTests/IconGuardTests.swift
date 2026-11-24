// SPDX-License-Identifier: AGPL-3.0-only

@testable import CouchSubsCore
import CoreGraphics
import Foundation
import ImageIO
import XCTest

/// Çeviri kutusu tuş simgesinin (△ ○ ✕ □, R2, L1) ve menü simgesinin üstüne binmez (#1203).
/// - Metin: okunmuş simge ("A Turn Off", "[] Map") ipucu sayılır; "Ekranı çevir" simgeyi ayırır, yalnız yazıyı çevirir.
/// - Kutu: yazı tanıma kutusunun ucundaki simge (`ScreenFit.iconEdges`) kutunun dışında kalır; kenar payı simgeye girmez.
/// - Gerçek kare (yerelde): GTA 6 ayarlarının tuş listesi. Kareler depoya girmez; `COUCHSUBS_LOCAL_FRAMES` (varsayılan
///   ~/Desktop/CouchSubs-test/kayit-gta6-23kas/kare) yoksa bu ölçüm atlanır. Yazı tanıma koşmaz: kutular elle verildi.
final class IconGuardTests: XCTestCase {
    // MARK: - Metin

    func testReadIconAtTheStartIsAPrompt() {
        // △ "A", □ "[]", ○ "()" diye okunur; ardından kısa, büyük harfle başlayan, noktalamasız bir eylem.
        XCTAssertTrue(ButtonPrompts.isPrompt("A Turn Off"))
        XCTAssertTrue(ButtonPrompts.isPrompt("[] Map"))
        XCTAssertTrue(ButtonPrompts.isPrompt("() Back"))
        XCTAssertTrue(ButtonPrompts.isPrompt("Δ Pick Up"))
        XCTAssertTrue(ButtonPrompts.isPrompt("Turn Off △"))
        // Konuşma bozulmaz: "A" artikeliyle başlayan cümle, noktalamalı ya da küçük harfle süren satır ipucu değildir.
        XCTAssertFalse(ButtonPrompts.isPrompt("A little help here"))
        XCTAssertFalse(ButtonPrompts.isPrompt("A Turn Off."))
        XCTAssertFalse(ButtonPrompts.isPrompt("A man walks into a bar"))
        XCTAssertFalse(ButtonPrompts.isPrompt("A"))
        XCTAssertFalse(ButtonPrompts.isPrompt("A LIBERTY CITY MEMOIR"))
    }

    /// "Ekranı çevir": "A Turn Off" satırında okunmuş simge çeviriye girmez, kutu yalnız "Turn Off"u kapsar.
    func testScreenTranslationLeavesTheReadIconOutside() {
        let line = TextLine("A Turn Off", box: TextBox(left: 0.40, top: 0.80, right: 0.52, bottom: 0.83), confidence: 0.9,
                            words: [TextWord("A", box: TextBox(left: 0.40, top: 0.80, right: 0.415, bottom: 0.83)),
                                    TextWord("Turn", box: TextBox(left: 0.425, top: 0.80, right: 0.47, bottom: 0.83)),
                                    TextWord("Off", box: TextBox(left: 0.478, top: 0.80, right: 0.52, bottom: 0.83))])
        let groups = ScreenTranslation.groups(Reading(lines: [line]), wholeScreen: true)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.paragraphs, ["Turn Off"])
        XCTAssertEqual(groups.first?.box.left ?? 0, 0.425, accuracy: 1e-6)
    }

    // MARK: - Kutu

    /// Çizici ne kadar uzun çeviri alırsa alsın yazının alanı özgün kutudur; kenar payı alanın dışına çıkmaz.
    func testLongTranslationNeverWidens() {
        let measure = { (text: String) in Double(text.count) * 10 }
        for (text, rows) in [("YÜKLEME DONANIMI", 1), ("NİŞAN AL / ETKİLEŞİME GEÇ", 1), ("Sahil güvenlik gelmeden marinada buluş", 2)] {
            let fit = ScreenFit.lines(text, width: 70, rows: rows, measure: measure)
            let widest = fit.lines.map(measure).max() ?? 0
            XCTAssertLessThanOrEqual(widest * fit.scale * fit.squeeze, 70.01, text)
            XCTAssertGreaterThanOrEqual(fit.scale, ScreenFit.lastScale, text)
        }
        let pads = ScreenFit.pads(left: 100, width: 70, room: (100, 172), pad: 6)
        XCTAssertEqual(pads.left, 0)
        XCTAssertEqual(pads.right, 2, accuracy: 1e-9)
    }

    // MARK: - Gerçek kare (yerelde)

    private static var localFrames: URL {
        let path = ProcessInfo.processInfo.environment["COUCHSUBS_LOCAL_FRAMES"]
            ?? NSHomeDirectory() + "/Desktop/CouchSubs-test/kayit-gta6-23kas/kare"
        return URL(fileURLWithPath: path)
    }

    private func frame(_ name: String) throws -> CGImage {
        let url = Self.localFrames.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("yerel kare yok: \(url.path)") }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Kare noktası (piksel) → kareye oranla kutu.
    private func box(_ v: [Double], _ image: CGImage) -> TextBox {
        TextBox(left: v[0] / Double(image.width), top: v[1] / Double(image.height),
                right: v[2] / Double(image.width), bottom: v[3] / Double(image.height))
    }

    private func item(_ name: String, _ box: TextBox, _ image: CGImage) -> ScreenTranslation.Item {
        var item = ScreenTranslation.Item(source: name, translation: name, box: box, lineHeight: box.bottom - box.top)
        // Zemin: kutunun hemen üstündeki nokta (GTA 6 ayarlarının mor zemini).
        let pixels = GamePhonePixels(image)!
        let p = pixels.offset(Int(box.left * Double(image.width)), Int(box.top * Double(image.height)) - 3)
        item.style = PhoneTextStyle(background: String(format: "#%02X%02X%02X", pixels.bytes[p], pixels.bytes[p + 1], pixels.bytes[p + 2]),
                                    foreground: "#E0E0E0")
        item.look = TextLook(bold: true, condensed: true, align: .left, upper: true, flat: true)
        return item
    }

    /// GTA 6 ayarları › Kontrol düzeni (960×536): yazı tanıma kutusu simgeyi de içine alsa çeviri kutusu simgeden önce
    /// biter; simgesiz yazıya dokunulmaz. Simgenin yeri karede elle ölçüldü ([sol, üst, sağ, alt] piksel).
    func testRealFrameIconsStayOutsideTheBox() throws {
        let image = try frame("k0010.jpg")
        let cases: [(name: String, box: [Double], icon: [Double]?, side: String?)] = [
            ("LOADOUT", [439, 157, 511, 177], [487.5, 157.5, 510, 177], "right"),
            ("INTERACT", [789, 226, 857, 241], [790, 226, 805, 240.5], "left"),
            ("MELEE", [789, 259, 841, 275], [790, 259.5, 805, 274], "left"),
            ("BACK", [894, 507, 941, 523], [926, 508, 940, 522.5], "right"),
            ("RESTORE DEFAULT", [777, 507, 886, 523], [870, 508, 885.5, 522.5], "right"),
            ("AIM / INTERACT", [409, 192, 486, 206], nil, nil),
            ("ON FOOT", [621, 95, 675, 109], nil, nil),
            ("RUN", [462, 361, 486, 375], nil, nil),
        ]
        let items = cases.map { item($0.name, box($0.box, image), image) }
        let fitted = ScreenFit.fitted(items, frame: image)
        let w = Double(image.width)
        var report: [String] = []
        for (c, fit) in zip(cases, fitted) {
            let original = box(c.box, image)
            report.append("\(c.name): \(Int(fit.box.left * w))-\(Int(fit.box.right * w)) alan \(Int((fit.room?.left ?? 0) * w))-\(Int((fit.room?.right ?? 0) * w))")
            guard let icon = c.icon else {
                XCTAssertEqual(fit.box.left, original.left, accuracy: 1e-9, c.name)
                XCTAssertEqual(fit.box.right, original.right, accuracy: 1e-9, c.name)
                continue
            }
            let iconBox = box(icon, image)
            let room = try XCTUnwrap(fit.room, c.name)
            if c.side == "right" {
                XCTAssertLessThanOrEqual(fit.box.right, iconBox.left, c.name)
                XCTAssertLessThanOrEqual(room.right, iconBox.left, c.name)
                // Yazının kendisi kesilmez: simgenin önündeki boşluğa kadar.
                XCTAssertGreaterThan(fit.box.right, iconBox.left - 8 / w, c.name)
            } else {
                XCTAssertGreaterThanOrEqual(fit.box.left, iconBox.right, c.name)
                XCTAssertGreaterThanOrEqual(room.left, iconBox.right, c.name)
                XCTAssertLessThan(fit.box.left, iconBox.right + 8 / w, c.name)
            }
        }
        print("simge koruma k0010: " + report.joined(separator: " | "))
    }

    /// Yazı tanıma kutusu yalnız yazıyı alsa da kenar payı yandaki simgeye girmez.
    func testRealFrameRoomStopsBeforeTheIcon() throws {
        let image = try frame("k0010.jpg")
        let cases: [(name: String, box: [Double], iconEdge: Double, side: String)] = [
            ("LOADOUT", [440, 160, 485, 173], 487.5, "right"),
            ("INTERACT", [809, 228, 857, 239], 805, "left"),
            ("BACK", [894, 509, 921, 521], 926, "right"),
        ]
        let fitted = ScreenFit.fitted(cases.map { item($0.name, box($0.box, image), image) }, frame: image)
        for (c, fit) in zip(cases, fitted) {
            let room = try XCTUnwrap(fit.room, c.name)
            let edge = c.iconEdge / Double(image.width)
            if c.side == "right" { XCTAssertLessThanOrEqual(room.right, edge, c.name) }
            else { XCTAssertGreaterThanOrEqual(room.left, edge, c.name) }
        }
    }
}
