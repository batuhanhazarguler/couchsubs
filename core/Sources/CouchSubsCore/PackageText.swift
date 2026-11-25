// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Oyun dünyasındaki ürün, ambalaj ve etiket yazısı (bira kutusu, süt kartonu, şişe etiketi) yerinde dursa da ekran yazısı
/// ya da altyazı değildir. Sinan Bey (beta.101, GTA 6, buzdolabı): ambalajların yazıları ekran yazısı sayılıp ürünlerin
/// üstüne üst üste çiziliyordu. Kamerayla kayan tabela `SceneMotion` ile, alt alta kısa tabela `SceneText.isSign` ile
/// yakalanıyor; hareketsiz ambalaj hiçbirine takılmıyordu (bulanık zeminde birlikte belirince menü de sanılıyordu).
///
/// Satır ancak bunların HEPSİ tutarsa ambalaj yazısıdır (gerçek ekran yazısı düşmesin diye muhafazakâr):
/// - marka biçimi: bir-üç sözcük, en çok `maxLength` karakter, her sözcük büyük harfle başlar (BÜYÜK HARF ya da Baş Harf);
///   cümle noktalaması yok (sonda tek "!"/"?" yalnız iki-üç sözcükte); tuş simgesi, tuş ipucu, arayüz sözlüğü etiketi ve
///   konuşan adı yok (`isBrandShape`),
/// - sahnede: satırın ortası karenin kenar şeritleri (HUD: harita, para, görev, altyazı, bildirim) dışında ve satır büyük
///   başlık boyunda değil (`inScene`),
/// - yazı arayüz mürekkebi değil: kutunun en parlak noktaları açık ve renksiz değil (`Look.uiInk`; oyun arayüzünün yazısı
///   ışıktan etkilenmez, beyazdır; sahnedeki etiket sahnenin ışığını alır),
/// - ve zemin desenli (`Look.textured`: satırın üstündeki ve altındaki şeritte komşu noktalar arası ortalama parlaklık farkı
///   en az `textureStep`; menünün bulanık/karartılmış zemini ve arayüz kutusu düzdür; komşu satırların kutuları sayılmaz)
///   ya da taban çizgisi eğik (perspektifli: sözcüklerin dikey ortası satır boyunca tek yöne kayıyor, `isTilted`).
/// Görüntü yoksa (`look` nil) hiçbir satır atılmaz. Windows (PackageText.cs) ve Android (PackageText.kt) aynı kuralları ve
/// eşikleri uygular; ortak deneme dosyası Tests/CouchSubsCoreTests/Fixtures/package-text.json.
public enum PackageText {
    public static let reason = "ambalaj/etiket yazısı (sahnede, desenli zeminde)"
    public static let maxWords = 3
    public static let maxLength = 20
    /// Sahne bölgesi (karenin oranı): satırın ortası bunun içinde olmalı. Dışı HUD şeritleridir.
    public static let sceneLeft = 0.08
    public static let sceneRight = 0.92
    public static let sceneTop = 0.10
    public static let sceneBottom = 0.80
    /// Satır (karede) bundan yüksekse büyük başlıktır (bölüm adı, "WASTED"), etiket değil.
    public static let maxHeight = 0.045
    /// Desenli zemin: satırın üst/alt şeridinde komşu iki nokta arasındaki ortalama parlaklık farkı en az bu kadar.
    public static let textureStep = 10.0
    /// Arayüz mürekkebi: kutunun en parlak çeyreğinin ortalama parlaklığı en az `uiLuma`, renk açıklığı (en büyük − en
    /// küçük kanal) en çok `uiChroma`.
    public static let uiLuma = 185
    public static let uiChroma = 30
    /// Şerit kalınlığı ve kutudan uzaklığı (satır yüksekliğine oranla).
    public static let ringShare = 0.5
    public static let ringGap = 0.15
    /// Sözcüklerin dikey ortası ilk sözcükten sonuncuya bu kadar sözcük boyu kayarsa taban çizgisi eğiktir.
    public static let tiltShift = 0.35

    static let samplesX = 32
    static let samplesY = 8
    static let ringSamples = 2
    static let minPairs = 16

    /// Satırın görüntüden ölçülen görünüşü.
    public struct Look: Equatable, Sendable {
        public var textured: Bool
        public var uiInk: Bool
        public init(textured: Bool, uiInk: Bool) {
            self.textured = textured
            self.uiInk = uiInk
        }
    }

    /// Satır ambalaj yazısı mı. `box` karede (0–1); `look` satırın görünüşü (görüntü yoksa nil: atılmaz).
    public static func isPackage(_ line: TextLine, box: TextBox, look: Look?) -> Bool {
        guard let look, !look.uiInk, line.icons?.isEmpty ?? true, isBrandShape(line.text), inScene(box) else { return false }
        return look.textured || isTilted(line.words)
    }

    /// Marka/etiket biçimi (bkz. tür açıklaması).
    public static func isBrandShape(_ text: String) -> Bool {
        let plain = text.trimmingCharacters(in: .whitespaces)
        guard !plain.isEmpty, plain.count <= maxLength, !plain.contains(ButtonIcons.marker),
              !plain.contains(where: { ".,;:\"“”()[]/".contains($0) }), let first = plain.first, !"-–—".contains(first),
              SpeakerPrefix.split(plain) == nil, !ButtonPrompts.isPrompt(plain),
              UiCommands.translateLabelLoosely(plain) == nil else { return false }
        var body = plain
        if let last = body.last, "!?".contains(last) { body.removeLast() }
        guard !body.contains(where: { "!?".contains($0) }) else { return false }
        let words = body.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) }
        guard (1...maxWords).contains(words.count), !(body.count < plain.count && words.count < 2) else { return false }
        return words.allSatisfy { word in word.first(where: \.isLetter)?.isUppercase == true }
    }

    /// Satırın ortası sahnede (HUD şeritleri dışında) ve satır büyük başlık boyunda değil.
    public static func inScene(_ box: TextBox) -> Bool {
        let x = (box.left + box.right) / 2, y = (box.top + box.bottom) / 2
        return x >= sceneLeft && x <= sceneRight && y >= sceneTop && y <= sceneBottom && box.bottom - box.top <= maxHeight
    }

    /// Taban çizgisi eğik mi (en az iki sözcük): sözcüklerin dikey ortası ilk sözcükten sonuncuya `tiltShift` sözcük boyu
    /// kayıyor ve aradakiler geri dönmüyor. Arayüz yazısı yataydır.
    static func isTilted(_ words: [TextWord]?) -> Bool {
        guard let words, words.count >= 2 else { return false }
        let heights = words.map { $0.box.bottom - $0.box.top }.sorted()
        let median = heights[heights.count / 2]
        guard median > 0 else { return false }
        let middles = words.sorted { $0.box.left < $1.box.left }.map { ($0.box.top + $0.box.bottom) / 2 }
        let shift = middles.last! - middles.first!
        guard abs(shift) > tiltShift * median else { return false }
        let direction: Double = shift > 0 ? 1 : -1
        return zip(middles, middles.dropFirst()).allSatisfy { ($1 - $0) * direction >= -0.15 * median }
    }

    /// Satırın görünüşü. `box` ve `others` (alandaki öbür satırlar) görüntüye oranla; `rgb(x, y)`: noktanın rengi (0xRRGGBB).
    /// Kutu çok küçük ya da şerit için yeterli nokta yoksa nil.
    public static func look(_ box: TextBox, others: [TextBox], width: Int, height: Int, rgb: (Int, Int) -> Int) -> Look? {
        guard width > 0, height > 0 else { return nil }
        let w = Double(width), h = Double(height)
        let left = max(0, box.left) * w, right = min(1, box.right) * w
        let top = max(0, box.top) * h, bottom = min(1, box.bottom) * h
        guard right - left >= 4, bottom - top >= 3 else { return nil }
        // Arayüz mürekkebi: kutunun en parlak çeyreği.
        var inside: [(luma: Int, chroma: Int)] = []
        for sy in 0..<samplesY {
            let y = min(height - 1, Int(top + (Double(sy) + 0.5) * (bottom - top) / Double(samplesY)))
            for sx in 0..<samplesX {
                let x = min(width - 1, Int(left + (Double(sx) + 0.5) * (right - left) / Double(samplesX)))
                inside.append(split(rgb(x, y)))
            }
        }
        inside.sort { $0.luma > $1.luma }
        let bright = inside.prefix(inside.count / 4)
        let luma = bright.reduce(0) { $0 + $1.luma } / bright.count
        let chroma = bright.reduce(0) { $0 + $1.chroma } / bright.count
        let uiInk = luma >= uiLuma && chroma <= uiChroma
        // Desen: üst ve alt şeritte yan yana noktaların parlaklık farkı (öbür satırların kutusuna düşen nokta sayılmaz).
        let line = bottom - top, gap = line * ringGap, thick = line * ringShare
        let blocked = others.map { other -> (Double, Double, Double, Double) in
            let pad = (other.bottom - other.top) * h * ringGap
            return (other.left * w - pad, other.top * h - pad, other.right * w + pad, other.bottom * h + pad)
        }
        var sum = 0.0, pairs = 0
        for (stripTop, stripBottom) in [(top - gap - thick, top - gap), (bottom + gap, bottom + gap + thick)] {
            guard stripTop >= 0, stripBottom <= h else { continue }
            for row in 0..<ringSamples {
                let yf = stripTop + (Double(row) + 0.5) * (stripBottom - stripTop) / Double(ringSamples)
                let y = min(height - 1, Int(yf))
                var previous: Int?
                for sx in 0..<samplesX {
                    let xf = left + (Double(sx) + 0.5) * (right - left) / Double(samplesX)
                    if blocked.contains(where: { xf >= $0.0 && xf <= $0.2 && yf >= $0.1 && yf <= $0.3 }) {
                        previous = nil
                        continue
                    }
                    let value = split(rgb(min(width - 1, Int(xf)), y)).luma
                    if let previous {
                        sum += Double(abs(value - previous))
                        pairs += 1
                    }
                    previous = value
                }
            }
        }
        return Look(textured: pairs >= minPairs && sum / Double(pairs) >= textureStep, uiInk: uiInk)
    }

    private static func split(_ rgb: Int) -> (luma: Int, chroma: Int) {
        let r = (rgb >> 16) & 0xff, g = (rgb >> 8) & 0xff, b = rgb & 0xff
        return ((299 * r + 587 * g + 114 * b) / 1000, max(r, g, b) - min(r, g, b))
    }

    /// Okumadan ambalaj yazısı satırlarını çıkarır. Satır kutuları okunan alana oranlı; `area` alanın karedeki yeri;
    /// `look(kutu, öbür kutular)` okunan alanın görüntüsünden ölçer (kutular görüntüye oranla).
    public static func filter(_ reading: Reading, in area: TextBox,
                              look: ((TextBox, [TextBox]) -> Look?)?) -> (kept: Reading, removed: [TextLine]) {
        guard let look, !reading.lines.isEmpty else { return (reading, []) }
        var kept: [TextLine] = [], removed: [TextLine] = []
        for (index, line) in reading.lines.enumerated() {
            guard let box = line.box, isBrandShape(line.text), line.icons?.isEmpty ?? true,
                  inScene(box.placed(in: area)) else {
                kept.append(line)
                continue
            }
            let others = reading.lines.enumerated().compactMap { $0.offset == index ? nil : $0.element.box }
            if isPackage(line, box: box.placed(in: area), look: look(box, others)) { removed.append(line) } else { kept.append(line) }
        }
        guard !removed.isEmpty else { return (reading, []) }
        var result = reading
        result.lines = kept
        return (result, removed)
    }

    /// Okunan alanın görüntüsü için ölçücü. Görüntü ilk soruda bir kez çözülür.
    public static func sampler(_ image: CGImage) -> (TextBox, [TextBox]) -> Look? {
        var loaded = false
        var pixels: GamePhonePixels?
        return { box, others in
            if !loaded {
                loaded = true
                pixels = GamePhonePixels(image)
            }
            guard let grid = pixels else { return nil }
            return look(box, others: others, width: grid.width, height: grid.height) { x, y in
                let i = (y * grid.width + x) * 4
                return (Int(grid.bytes[i]) << 16) | (Int(grid.bytes[i + 1]) << 8) | Int(grid.bytes[i + 2])
            }
        }
    }
}
