// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Açık zemin üzerindeki koyu yazı (duvardaki kâğıt ilan, tabela, afiş) altyazı değildir. Kullanıcı bildirimi (GitHub
/// #1124, GTA 6): altyazı alanına denk gelen otel odasındaki kâğıt ilan ("SOILED SHEETS, … WILL BE BILLED TO YOUR ROOM";
/// beyaz kâğıt, siyah yazı) altyazı sanılıp çevriliyordu; plaka/tabela kuralı (`SceneText.isSign`, #1052) uzun cümleli
/// ilanı yakalamıyor. Oyun altyazısı açık renkli yazıdır (beyaz/sarı), koyu dış çizgiyle ya da yarı saydam koyu zeminde.
///
/// Satır kutusunun içindeki ve hemen dışındaki şeridin parlaklığına bakılır (`isDarkOnLight`): şerit (yerel zemin) açık
/// (ortancası en az `lightGround`) ve düz (`groundSpread`), kutunun içindeki koyu küme (Otsu eşiği) hem koyu (ortalaması
/// en çok `darkInk`) hem zeminden belirgin koyu (en az `inkGap`), yazı payı makul (`minInk`–`maxInk`) ve kutuda zeminden parlak harf yoksa
/// (`glowShare`; koyu dış çizgili beyaz yazı açık gökyüzünün önünde de parlak harf taşır) yazı koyu, zemin açıktır.
/// Bloğun satırlarının yarıdan çoğu böyleyse blok sahne yazısıdır (`isDarkBlock`); konuşan adlı blok hep altyazıdır.
///
/// Koyu altyazılı oyun bozulmasın diye kural oturumda kendini kapatır (`DarkInkStyle`): ortalanmış, birbirinden farklı
/// `DarkInkStyle.distinctBlocks` koyu yazılı blok atılınca bu oyunun altyazısı koyu yazı sayılır, kural o oturumda
/// çalışmaz. Duvardaki ilan aynı yazıyı taşır, sayılmaz.
/// Windows (InkTone.cs) ve Android (InkTone.kt) aynı kuralları ve eşikleri uygular; ortak deneme dosyası
/// Tests/CouchSubsCoreTests/Fixtures/dark-ink.json.
public enum InkTone {
    /// Yerel zemin (kutunun dışındaki şeridin ortanca parlaklığı) en az bu kadarsa açıktır.
    public static let lightGround = 150
    /// Yazı kümesinin ortalama parlaklığı en çok bu kadarsa koyudur.
    public static let darkInk = 110
    /// Yazı kümesi zeminden en az bu kadar koyu olmalı.
    public static let inkGap = 70
    /// Kutudaki yazı noktalarının payı bu aralıkta olmalı (boş kâğıt ya da tümü koyu kutu yazı değildir).
    public static let minInk = 0.04
    public static let maxInk = 0.5
    /// Zeminden bu kadar (en çok `glowCeiling`'e kadar) parlak nokta harftir: payı `glowShare`'i aşarsa yazı açık renklidir.
    public static let glow = 20
    public static let glowCeiling = 250
    public static let glowShare = 0.03
    /// Yerel zemin düz olmalı: şeridin çeyrekler açıklığı (üst çeyrek − alt çeyrek) en çok bu kadar (kâğıt düzdür; oyun
    /// sahnesi çoğu zaman değil).
    public static let groundSpread = 40
    /// Kutunun dışındaki şeridin kalınlığı (satır yüksekliğine oranla).
    public static let ringShare = 0.3
    /// Altyazı günlüğündeki atılma nedeni.
    public static let reason = "koyu yazı açık zeminde (kâğıt/tabela)"

    static let samplesX = 48
    static let samplesY = 10
    static let ringSamples = 2
    static let minSamples = 16

    /// `box` (görüntüye oranla) açık zemin üzerinde koyu yazı mı. `luma(x, y)`: görüntünün (piksel) parlaklığı, 0–255.
    public static func isDarkOnLight(_ box: TextBox, width: Int, height: Int, luma: (Int, Int) -> Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        let w = Double(width), h = Double(height)
        let left = max(0, min(1, box.left)) * w, right = max(0, min(1, box.right)) * w
        let top = max(0, min(1, box.top)) * h, bottom = max(0, min(1, box.bottom)) * h
        guard right - left >= 2, bottom - top >= 2 else { return false }
        let inside = grid(left, top, right, bottom, samplesX, samplesY, width, height, luma)
        let d = (bottom - top) * ringShare
        var ring: [Int] = []
        if d >= 1 {
            let strips = [
                (left, top - d, right, top, samplesX, ringSamples),
                (left, bottom, right, bottom + d, samplesX, ringSamples),
                (left - d, top, left, bottom, ringSamples, samplesY),
                (right, top, right + d, bottom, ringSamples, samplesY),
            ]
            for (l, t, r, b, nx, ny) in strips where l >= 0 && t >= 0 && r <= w && b <= h {
                ring += grid(l, t, r, b, nx, ny, width, height, luma)
            }
        }
        return decide(inside: inside, ring: ring)
    }

    /// Kutunun içindeki (`inside`) ve dışındaki şeridin (`ring`) parlaklıklarıyla karar.
    static func decide(inside: [Int], ring: [Int]) -> Bool {
        guard inside.count >= minSamples, ring.count >= minSamples else { return false }
        let sorted = ring.sorted()
        let ground = sorted[sorted.count / 2]
        guard ground >= lightGround, sorted[sorted.count * 3 / 4] - sorted[sorted.count / 4] <= groundSpread else { return false }
        let threshold = otsu(inside)
        let ink = inside.filter { $0 <= threshold }
        guard !ink.isEmpty, ink.count < inside.count else { return false }
        let share = Double(ink.count) / Double(inside.count)
        guard share >= minInk, share <= maxInk else { return false }
        let inkMean = Double(ink.reduce(0, +)) / Double(ink.count)
        guard inkMean <= Double(darkInk), Double(ground) - inkMean >= Double(inkGap) else { return false }
        let bright = min(ground + glow, glowCeiling)
        let glowing = inside.filter { $0 >= bright }.count
        return Double(glowing) / Double(inside.count) < glowShare
    }

    /// Bloğun kutulu satırlarının yarıdan çoğu açık zeminde koyu yazı mı (`dark`: satır kutusu için `isDarkOnLight`).
    public static func isDarkBlock(_ block: Reading, dark: (TextBox) -> Bool) -> Bool {
        let boxes = block.lines.compactMap(\.box)
        guard !boxes.isEmpty else { return false }
        return boxes.filter(dark).count * 2 > boxes.count
    }

    /// Okunan alanın görüntüsü için satır kutusu denetimi (kutular görüntüye oranla). Görüntü ilk soruda bir kez çözülür.
    public static func sampler(_ image: CGImage) -> (TextBox) -> Bool {
        let pixels = LazyPixels(image)
        return { box in
            guard let grid = pixels.value else { return false }
            return isDarkOnLight(box, width: grid.width, height: grid.height) { x, y in
                let i = (y * grid.width + x) * 4
                return (299 * Int(grid.bytes[i]) + 587 * Int(grid.bytes[i + 1]) + 114 * Int(grid.bytes[i + 2])) / 1000
            }
        }
    }

    private final class LazyPixels {
        private let image: CGImage
        private var loaded = false
        private var pixels: GamePhonePixels?
        init(_ image: CGImage) { self.image = image }
        var value: GamePhonePixels? {
            if !loaded {
                loaded = true
                pixels = GamePhonePixels(image)
            }
            return pixels
        }
    }

    private static func grid(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double, _ nx: Int, _ ny: Int,
                             _ width: Int, _ height: Int, _ luma: (Int, Int) -> Int) -> [Int] {
        var values: [Int] = []
        values.reserveCapacity(nx * ny)
        for sy in 0..<ny {
            let y = min(height - 1, Int(top + (Double(sy) + 0.5) * (bottom - top) / Double(ny)))
            for sx in 0..<nx {
                let x = min(width - 1, Int(left + (Double(sx) + 0.5) * (right - left) / Double(nx)))
                values.append(max(0, min(255, luma(x, y))))
            }
        }
        return values
    }

    private static func otsu(_ values: [Int]) -> Int {
        var histogram = [Int](repeating: 0, count: 256)
        for value in values { histogram[value] += 1 }
        let total = Double(values.count)
        var sum = 0.0
        for i in 0..<256 { sum += Double(i * histogram[i]) }
        var below = 0.0, belowSum = 0.0, best = -1.0
        var threshold = 127
        for t in 0..<255 {
            below += Double(histogram[t])
            if below == 0 { continue }
            let above = total - below
            if above == 0 { break }
            belowSum += Double(t * histogram[t])
            let gap = belowSum / below - (sum - belowSum) / above
            let between = below * above * gap * gap
            if between > best {
                best = between
                threshold = t
            }
        }
        return threshold
    }
}

/// Oturumun koyu yazılı altyazı biçimi: ortalanmış, birbirinden farklı (biri ötekini içermeyen, benzemeyen) en az
/// `distinctBlocks` koyu yazılı blok atılınca oyunun altyazısı koyu yazı sayılır ve `InkTone` kuralı o oturumda kapanır
/// (`isGameStyle`). Duvardaki ilan hep aynı yazıdır (kısmi okunsa da), sayılmaz. Hat sıfırlanınca unutulur
/// (Windows: DarkInkStyle, Android: DarkInkStyle).
public struct DarkInkStyle: Equatable, Sendable {
    public static let distinctBlocks = 4

    private(set) var texts: [String] = []

    public init() {}

    public var isGameStyle: Bool { texts.count >= Self.distinctBlocks }

    /// Koyu yazılı diye atılan blok (satır kutuları `area`'ya oranlı). Kural bu blokla kapandıysa true.
    @discardableResult
    public mutating func observe(_ block: Reading, in area: TextBox) -> Bool {
        guard !isGameStyle, let box = block.box?.placed(in: area), SceneText.isCentered(box) else { return false }
        let text = TextMatch.normalize(block.text)
        guard !text.isEmpty,
              !texts.contains(where: { $0.contains(text) || text.contains($0) || TextMatch.isSimilar($0, text) })
        else { return false }
        texts.append(text)
        return isGameStyle
    }

    public mutating func reset() { texts = [] }
}
