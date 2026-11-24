// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import XCTest
@testable import CouchSubsCore

/// Ekrandaki menüler (Windows ScreenMenuTests ve Android ScreenMenuTest ile aynı sentetik tekerlek menü).
final class ScreenMenuTests: XCTestCase {
    // 640x360 karede karo 20x20 piksel. Tekerlek menünün sekiz etiketi, ortada başlık ve gri alt başlık.
    private static let labels: [(column: Int, row: Int, width: Int)] =
        [(8, 4, 1), (16, 2, 1), (24, 4, 1), (27, 9, 1), (24, 14, 1), (16, 16, 1), (8, 14, 1), (4, 9, 1)]

    private struct Canvas {
        var pixels: [UInt8]
        let width = 640, height = 360
        init(fill: UInt8) { pixels = [UInt8](repeating: fill, count: 640 * 360 * 4) }
        mutating func set(_ x: Int, _ y: Int, _ value: UInt8) {
            let p = (y * width + x) * 4
            (pixels[p], pixels[p + 1], pixels[p + 2]) = (value, value, value)
        }
        mutating func paint(_ column: Int, _ row: Int, _ width: Int, ink: UInt8) {
            for y in (row * 20 + 3)..<(row * 20 + 17) {
                for x in (column * 20)..<((column + width) * 20) {
                    set(x, y, [2, 3].contains((y - row * 20) % 6) && x % 5 < 2 ? ink : 24)
                }
            }
        }
        var image: CGImage { ScreenTextDetectorTests.image(pixels, width: width, height: height) }
    }

    /// Bulanık (düz gri) zeminde tekerlek menü.
    private static func wheel() -> Canvas {
        var canvas = Canvas(fill: 70)
        for label in labels { canvas.paint(label.column, label.row, label.width, ink: 240) }
        canvas.paint(13, 8, 6, ink: 240)
        canvas.paint(14, 10, 4, ink: 175)
        return canvas
    }

    private func run(_ detector: ScreenTextDetector, _ from: Int, _ to: Int, _ frame: (Int) -> CGImage) {
        for time in stride(from: from, through: to, by: ScreenTextDetector.sampleIntervalMs) {
            detector.sample(frame(time), now: time, excluded: [])
        }
    }

    func testWheelMenuIsDetectedWithItsShortLabels() {
        let detector = ScreenTextDetector()
        run(detector, 0, 400) { _ in Self.wheel().image }
        XCTAssertTrue(detector.inMenu)
        XCTAssertEqual(detector.areas.count, 10)
        XCTAssertTrue(detector.areas.allSatisfy { $0.menu && $0.auto })
    }

    func testClosingTheMenuRemovesEveryBoxAtOnce() {
        let detector = ScreenTextDetector()
        run(detector, 0, 400) { _ in Self.wheel().image }
        XCTAssertFalse(detector.areas.isEmpty)
        detector.sample(Canvas(fill: 70).image, now: 500, excluded: [])
        XCTAssertFalse(detector.inMenu)
        XCTAssertTrue(detector.areas.isEmpty)
    }

    func testNavigatingKeepsTheOtherBoxes() {
        let detector = ScreenTextDetector()
        run(detector, 0, 400) { _ in Self.wheel().image }
        let before = Set(detector.areas.map(\.id))
        // Seçim çerçevesi bir etiketin üstüne geçti: o etiketin karosu değişti, diğerleri yerinde.
        run(detector, 500, 800) { time in
            var canvas = Self.wheel()
            canvas.paint(8, 4, 1, ink: time % 200 == 0 ? 200 : 250)
            for x in 160..<180 {
                let p = ((4 * 20 + 1) * canvas.width + x) * 4
                canvas.pixels[p] = UInt8(truncatingIfNeeded: time / 10)
            }
            return canvas.image
        }
        XCTAssertTrue(detector.inMenu)
        XCTAssertGreaterThanOrEqual(detector.areas.filter { before.contains($0.id) }.count, 9)
    }

    /// Menü kapandıktan sonra sakin (karanlık) sahnede ayrı ayrı belirmiş üç yazı (görev satırı, PS5 bildirimi, HUD)
    /// menüyü sürdürmez. GTA 6 "Gone Fishing" (Mac ve iPhone günlükleri, 2026-11-22): menü durumu bitmedi, altyazı
    /// bütün oturum okunmadı; diyalog ve görev satırı yalnız ekran yazısı olarak çevrildi.
    func testMenuEndsWhenItsOwnLabelsLeaveEvenIfOtherTextStays() {
        let scene: [(column: Int, row: Int, width: Int, from: Int)] = [(1, 0, 2, 500), (29, 0, 2, 900), (1, 17, 3, 1300)]
        func frame(_ time: Int, wheel: Bool) -> CGImage {
            var canvas = wheel ? Self.wheel() : Canvas(fill: 70)
            for label in scene where time >= label.from { canvas.paint(label.column, label.row, label.width, ink: 240) }
            return canvas.image
        }
        let detector = ScreenTextDetector()
        run(detector, 0, 1900) { frame($0, wheel: true) }
        XCTAssertTrue(detector.inMenu)
        // Eski kuralda (menü yalnız "≥3 bileşen + sakin zemin" ile sürüyordu) burada menü durumu hiç bitmiyordu.
        run(detector, 2000, 4000) { frame($0, wheel: false) }
        XCTAssertFalse(detector.inMenu)
    }

    /// Menüde hiçbir şey değişmeden 5 sn geçince menü durumu biter ve aynı yazılarla yeniden açılmaz: menü sanılan sabit
    /// HUD altyazıyı en çok 5 sn susturur. Yeni beliren bir menü yeniden menü sayılır.
    func testStillMenuExpiresAndOnlyANewMenuReopens() {
        let detector = ScreenTextDetector()
        run(detector, 0, 400) { _ in Self.wheel().image }
        XCTAssertTrue(detector.inMenu)
        run(detector, 500, 5000) { _ in Self.wheel().image }
        XCTAssertTrue(detector.inMenu)
        run(detector, 5100, 8000) { _ in Self.wheel().image }
        XCTAssertFalse(detector.inMenu)
        run(detector, 8100, 8200) { _ in Canvas(fill: 70).image }
        run(detector, 8300, 8800) { _ in Self.wheel().image }
        XCTAssertTrue(detector.inMenu)
    }

    /// #1198: menü durumu süresi dolup bitince menüde bulunan alanların hepsi kalkar (RegionWatcher çevirilerini TV'den
    /// kaldırır). Eskiden karoları yerinde duran alan menü alanı olarak yaşamaya devam ediyor, çevirisi ekranda kalıyordu.
    func testExpiredMenuDropsEveryMenuArea() {
        let detector = ScreenTextDetector()
        run(detector, 0, 400) { _ in Self.wheel().image }
        let before = Set(detector.areas.map(\.id))
        XCTAssertFalse(before.isEmpty)
        run(detector, 500, 8000) { _ in Self.wheel().image }
        XCTAssertFalse(detector.inMenu)
        XCTAssertTrue(detector.areas.allSatisfy { !before.contains($0.id) && !$0.menu }, "\(detector.areas)")
    }

    /// #1240, GTA 6 karanlık balık tutma sahnesi: tuş ipucu (sağ alt), görev yazısı (alt orta) ve HUD (sol üst) birlikte
    /// belirince menü sanılıyordu (Windows ve Android ile aynı sahne).
    private static func fishing() -> Canvas {
        var canvas = Canvas(fill: 70)
        canvas.paint(26, 15, 3, ink: 240)
        canvas.paint(12, 16, 8, ink: 240)
        canvas.paint(1, 1, 3, ink: 240)
        return canvas
    }

    func testPromptAndMissionTextDoNotMakeAMenu() {
        let detector = ScreenTextDetector()
        run(detector, 0, 400) { _ in Self.fishing().image }
        XCTAssertTrue(detector.inMenu)
        // Alt bantta okunan alanlar tuş ipucu ve görev yazısı çıktı (RegionWatcher.onAutoHud).
        for area in detector.areas where area.region.top > 0.7 { detector.markHud(area.id) }
        run(detector, 500, 1500) { _ in Self.fishing().image }
        XCTAssertFalse(detector.inMenu)
    }

    func testDialogueEndsAFalseMenuAtOnce() {
        let detector = ScreenTextDetector()
        run(detector, 0, 400) { _ in Self.fishing().image }
        XCTAssertTrue(detector.inMenu)
        detector.noteDialogue(now: 450)
        XCTAssertFalse(detector.inMenu)
        XCTAssertFalse(detector.areas.contains { $0.menu })
        run(detector, 500, 1500) { _ in Self.fishing().image }
        XCTAssertFalse(detector.inMenu)
    }

    func testARealMenuStaysAMenuWhenOneLabelIsAPrompt() {
        let detector = ScreenTextDetector()
        run(detector, 0, 400) { _ in Self.wheel().image }
        XCTAssertTrue(detector.inMenu)
        detector.markHud(detector.areas[0].id)
        run(detector, 500, 1500) { _ in Self.wheel().image }
        XCTAssertTrue(detector.inMenu)
    }

    func testPromptsAndMissionTextAreHud() {
        XCTAssertTrue(ScreenTextKind.isHud(["R2 Reel in"]))
        XCTAssertTrue(ScreenTextKind.isHud(["Catch a fish."]))
        XCTAssertFalse(ScreenTextKind.isHud(["MAP", "BRIEF"]))
        XCTAssertFalse(ScreenTextKind.isHud(["SETTINGS"]))
        XCTAssertFalse(ScreenTextKind.isHud(["Resume Game", "Settings", "Quit"]))
    }

    func testLabelsOnABusyMovingSceneAreNotAMenu() {
        let detector = ScreenTextDetector()
        run(detector, 0, 1000) { time in
            var generator = ScreenTextDetectorTests.SplitMix(seed: UInt64(time) &+ 7)
            var canvas = Canvas(fill: 0)
            for i in 0..<canvas.pixels.count { canvas.pixels[i] = UInt8(truncatingIfNeeded: generator.next()) }
            for label in Self.labels { canvas.paint(label.column, label.row, label.width, ink: 240) }
            return canvas.image
        }
        XCTAssertFalse(detector.inMenu)
    }

    func testShortLabelsAreTranslatedOnlyInAMenu() {
        for (text, noiseInMenu) in [("OFF", false), ("ON", false), ("OUTFITS", false), ("CURRENT OUTFIT", false),
                                    ("40", true), ("0", true), ("x3", true), ("100%", true)] {
            XCTAssertEqual(ScreenTextNoise.isNoise(text, menu: true), noiseInMenu, text)
            XCTAssertTrue(ScreenTextNoise.isNoise(text, menu: false), text)
        }
    }

    func testShortLabelsComeFromTheDictionaryKeepingTheirCase() {
        for (label, turkish) in [("OFF", "KAPALI"), ("Off", "Kapalı"), ("off", "kapalı"), ("ON", "AÇIK"),
                                 ("SETTINGS", "AYARLAR"), ("Inventory", "Envanter"), ("STATS", "İSTATİSTİKLER"),
                                 ("EXIT", "ÇIK")] {
            XCTAssertEqual(UiCommands.translateLabel(label), turkish, label)
        }
        XCTAssertNil(UiCommands.translateLabel("CURRENT OUTFIT"))
        XCTAssertNil(UiCommands.translateLabel("40"))
    }

    /// Seçili menü satırı (#1267): açık şeritte koyu yazı. Karo baştan sona açık, yazı koyu çizgiler.
    private static func selected(_ canvas: inout Canvas, _ column: Int, _ row: Int) {
        for y in (row * 20)..<(row * 20 + 20) {
            for x in (column * 20)..<(column * 20 + 20) {
                canvas.set(x, y, [2, 3].contains((y - row * 20) % 6) && y - row * 20 >= 3 && y - row * 20 < 17 && x % 5 < 2 ? 30 : 230)
            }
        }
    }

    func testSelectedRowWithDarkTextOnALightBarIsFoundInAMenu() {
        let detector = ScreenTextDetector()
        run(detector, 0, 600) { _ in
            var canvas = Self.wheel()
            Self.selected(&canvas, 28, 16)
            return canvas.image
        }
        XCTAssertTrue(detector.inMenu)
        XCTAssertEqual(detector.areas.count, 11, "seçili satır da alan")
        // Menü dışında açık zemindeki koyu leke (gökyüzü, kar) yazı sayılmaz.
        let outside = ScreenTextDetector()
        run(outside, 0, 1500) { _ in
            var canvas = Canvas(fill: 70)
            Self.selected(&canvas, 20, 10)
            Self.selected(&canvas, 21, 10)
            return canvas.image
        }
        XCTAssertTrue(outside.areas.isEmpty)
    }

    /// #1264: komşusu olmayan, ekranın ortasındaki tek satır (görev yazısı) ortalı; kenardaki tek satır hizasını korur.
    @MainActor
    func testLoneCenteredLineIsCentered() {
        let look = TextLook(bold: false, condensed: false, align: .left, upper: false, flat: true)
        let mission = RegionWatcher.Block(start: 0, count: 1, box: TextBox(left: 0.385, top: 0.94, right: 0.614, bottom: 0.97),
                                          lineHeight: 0.03, look: look)
        let corner = RegionWatcher.Block(start: 1, count: 1, box: TextBox(left: 0.05, top: 0.1, right: 0.3, bottom: 0.13),
                                         lineHeight: 0.03, look: look)
        let aligned = RegionWatcher.alignByNeighbours([mission, corner])
        XCTAssertEqual(aligned[0].look?.align, .center)
        XCTAssertEqual(aligned[1].look?.align, .left)
        XCTAssertEqual(ScreenFit.loneAlign(mission.box, rows: 1), .center)
        XCTAssertNil(ScreenFit.loneAlign(mission.box, rows: 2), "çok satırlı yazının hizası satırlarından çıkar")
        XCTAssertNil(ScreenFit.loneAlign(corner.box, rows: 1))
    }

    /// #1267: gösterilen satırın zemini açıktan koyuya dönünce (seçim kaydı) eski kutular hemen kalkar.
    @MainActor
    func testSelectionMoveIsSeenFromTheFlippedBackground() {
        let box = TextBox(left: 0.02, top: 0.2, right: 0.27, bottom: 0.25)
        var shown = ScreenTranslation.Item(source: "Map", translation: "Harita", box: box, lineHeight: 0.04)
        shown.style = PhoneTextStyle(background: "#E8E8F0", foreground: "#202020")
        let look = TextLook(bold: false, condensed: false, align: .left, upper: false, flat: true)
        let dark = RegionWatcher.Block(start: 0, count: 1, box: box, lineHeight: 0.04,
                                       style: PhoneTextStyle(background: "#202030", foreground: "#F0F0F0"), look: look)
        let light = RegionWatcher.Block(start: 0, count: 1, box: box, lineHeight: 0.04,
                                        style: PhoneTextStyle(background: "#E0E0E8", foreground: "#202020"), look: look)
        var below = dark
        below.box = TextBox(left: 0.02, top: 0.3, right: 0.27, bottom: 0.35)
        XCTAssertTrue(RegionWatcher.selectionMoved(rendered: [shown], current: [dark]))
        XCTAssertFalse(RegionWatcher.selectionMoved(rendered: [shown], current: [light]), "renk aynı tonda")
        XCTAssertFalse(RegionWatcher.selectionMoved(rendered: [shown], current: [below]), "başka satır")
    }

    /// #1266, #1267: okunan yazının sözcük sayısında simge sanılan karakterler sayılmaz.
    func testIconGlyphsAreNotWords() {
        XCTAssertEqual(TextPainter.words("I Map"), 1)
        XCTAssertEqual(TextPainter.words("II Photo Studio"), 2)
        XCTAssertEqual(TextPainter.words("SELECT ⊗"), 1)
        XCTAssertEqual(TextPainter.words("Retry Checkpoint"), 2)
    }
}
