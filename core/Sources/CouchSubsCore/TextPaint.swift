// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Bir ekran yazısının yerinde, arayüz Türkçe yapılmış gibi çizilmesi için göndericinin kareden ölçtükleri (TV pikselleri
/// okuyamaz). Yalnız yazı değişince ölçülür (Windows: TextPaint.cs, Android: TextPaint.kt; aynı kurallar ve eşikler).
/// TV'ye öğenin `bg`, `bg2`, `bgDir`, `bgPat`, `fg`, `weight`, `upper`, `align`, `lineH`, `cover`, `grow`, `group`
/// alanlarıyla gider; eski TV bunları yok sayıp eski çizimi sürdürür.
public struct TextPaint: Equatable, Sendable {
    public enum Direction: String, Sendable { case horizontal = "h", vertical = "v" }
    /// Kutunun zemini (degradede başlangıç ucu: sol ya da üst). Opak çizilir.
    public var background: String
    /// Degradenin öbür ucu (sağ ya da alt); düz zeminde nil.
    public var background2: String? = nil
    public var direction: Direction? = nil
    /// Zemin desenli (harita, dünya): `background` ortalama renktir.
    public var patterned = false
    /// Satır aralığı (bir satırın üstünden ötekinin üstüne), kareye oranla; tek satırda satır yüksekliği.
    public var pitch: Double
    /// Özgün yazıyı tam örten kutu: yazı tanıma kutusu ve dışına taşan harf noktaları, en çok `marginMax` piksel payla.
    /// Simgeye doğru taşmaz.
    public var cover: TextBox
    /// Kutunun yana uzayabileceği alan (yalnız tek satırlık etikette, hizanın açık tarafında): o yönde başka yazı, simge
    /// ya da kutu yok, yalnız oyunun zemini var. Simgeyle ya da komşuyla arada `ScreenFit.gapLines` kadar boşluk kalır.
    /// nil: uzayamaz.
    public var grow: TextBox? = nil
    /// Aynı listede alt alta (ya da aynı satırda) duran, özgün hâlinde aynı boydaki etiketlerin ortak numarası; grubun
    /// hepsi aynı yazı boyunda çizilir. nil: tek başına.
    public var group: Int? = nil

    public init(background: String, pitch: Double, cover: TextBox) {
        self.background = background
        self.pitch = pitch
        self.cover = cover
    }

    /// Bu ölçüler `area` içindeki oranlarsa, aynı yerin `area`'yı içeren çerçevedeki oranları.
    public func placed(in area: TextBox) -> TextPaint {
        var paint = self
        paint.cover = cover.placed(in: area)
        paint.grow = grow?.placed(in: area)
        paint.pitch = pitch * (area.bottom - area.top)
        return paint
    }
}

/// `TextPaint` ölçümü. Piksel erişimi soyuttur (`color(x, y)`): ortak deneme dosyası (Fixtures/text-paint.json) üç
/// platformda aynı yapay kareyi kurar.
public enum TextPainter {
    public typealias RGB = (r: Int, g: Int, b: Int)

    /// Ölçülecek yazı: kareye oranla kutusu ve satır yüksekliği, özgün satır sayısı, sampler'ın bulduğu zemin/yazı rengi
    /// ve hizası.
    public struct Target: Sendable {
        public var box: TextBox
        public var lineHeight: Double
        public var rows: Int
        public var background: String
        public var foreground: String
        public var upper: Bool
        public var align: TextLook.Align

        public init(box: TextBox, lineHeight: Double, rows: Int, background: String, foreground: String, upper: Bool,
                    align: TextLook.Align) {
            self.box = box
            self.lineHeight = lineHeight
            self.rows = rows
            self.background = background
            self.foreground = foreground
            self.upper = upper
            self.align = align
        }
    }

    /// Nokta zeminden bu kadar (en büyük renk bileşeni farkı) uzak ve yazı rengine zeminden yakınsa harf noktasıdır.
    public static let inkDistance = 40
    /// Bir satır/sütunun en az bu kadarı harf noktasıysa orada yazı sürer.
    public static let inkShare = 0.03
    /// Kutu yazı tanıma kutusunun dışına en çok bu kadar satır yüksekliği uzar (taşan harf ucu).
    public static let reachLines = 0.5
    /// Kenar payı: satır yüksekliğinin bu kadarı, en az 1, en çok `marginMax` piksel.
    public static let marginLines = 0.08
    public static let marginMax = 3
    /// İki uç arasındaki fark (en büyük renk bileşeni) en az bu kadarsa zemin degradedir.
    public static let gradientStep = 10
    /// Zeminin kendi içindeki sapması bundan büyükse zemin desenlidir.
    public static let patternDeviation = TextStyleSampler.flatDeviation
    /// Kenar şeridinin ortalaması sampler'ın zemininden bu kadar uzaksa (seçili satırın kendi kutusu dar) sampler'ınki kalır.
    public static let trustDistance = 48
    /// Boş alan en çok bu kadar satır yüksekliği taranır.
    public static let growLines = 12.0
    /// Aynı grup: satır yükseklikleri en çok bu oranda farklı (`ScreenFit.sameLine`).
    public static let sameLine = ScreenFit.sameLine

    /// Ölçümler (hedeflerle aynı sırada). `width`/`height`: karenin piksel boyu.
    public static func paints(_ targets: [Target], width: Int, height: Int, color: (Int, Int) -> RGB) -> [TextPaint] {
        guard width > 0, height > 0 else { return [] }
        let fw = Double(width), fh = Double(height)
        // Hedeflerin piksel kutuları (öbür hedefler engeldir); karenin dışına taşan kutu kareye kırpılır (#1255).
        func pixel(_ v: Double, _ size: Int, up: Bool) -> Int {
            guard v.isFinite else { return v > 0 ? size : 0 }
            let p = (v * Double(size)).rounded(up ? .up : .down)
            return Int(min(Double(size), max(0, p)))
        }
        let rects = targets.map { t in
            (l: pixel(t.box.left, width, up: false), t: pixel(t.box.top, height, up: false),
             r: pixel(t.box.right, width, up: true), b: pixel(t.box.bottom, height, up: true))
        }
        var result: [TextPaint] = []
        for (index, target) in targets.enumerated() {
            let bg = rgb(target.background), fg = rgb(target.foreground)
            let line = max(1, target.lineHeight * fh)
            func isInk(_ c: RGB) -> Bool {
                let toBg = distance(c, bg)
                return toBg > inkDistance && distance(c, fg) < toBg
            }
            func others(_ x: Int, _ y: Int) -> Bool {
                rects.indices.contains { j in j != index && x >= rects[j].l && x < rects[j].r && y >= rects[j].t && y < rects[j].b }
            }
            func inkRow(_ y: Int, _ x0: Int, _ x1: Int) -> Bool {
                guard y >= 0, y < height, x1 > x0 else { return false }
                let step = max(1, (x1 - x0) / 200)
                var n = 0, ink = 0
                for x in stride(from: max(0, x0), to: min(width, x1), by: step) {
                    if others(x, y) { return false }
                    n += 1
                    if isInk(color(x, y)) { ink += 1 }
                }
                return n > 0 && ink >= max(2, Int((inkShare * Double(n)).rounded(.up)))
            }
            func inkColumn(_ x: Int, _ y0: Int, _ y1: Int) -> Bool {
                guard x >= 0, x < width, y1 > y0 else { return false }
                var n = 0, ink = 0
                for y in max(0, y0)..<min(height, y1) {
                    if others(x, y) { return false }
                    n += 1
                    if isInk(color(x, y)) { ink += 1 }
                }
                return n > 0 && ink >= max(1, Int((inkShare * Double(n)).rounded(.up)))
            }
            // 1) Örtü: yazı tanıma kutusunun dışına taşan harf noktaları (bitişik satır/sütunlar) kutuya katılır.
            var (l, t, r, b) = rects[index]
            let reach = max(1, Int((reachLines * line).rounded()))
            var y = b
            while y < min(height, rects[index].b + reach), inkRow(y, l, r) { y += 1 }
            b = y
            y = t - 1
            while y >= max(0, rects[index].t - reach), inkRow(y, l, r) { y -= 1 }
            t = y + 1
            var x = r
            while x < min(width, rects[index].r + reach), inkColumn(x, t, b) { x += 1 }
            r = x
            x = l - 1
            while x >= max(0, rects[index].l - reach), inkColumn(x, t, b) { x -= 1 }
            l = x + 1
            // Kenar payı: yazının yanındaki boş noktalar; ötesinde başka yazı/simge varsa pay ona değmez.
            let margin = max(1, min(marginMax, Int((marginLines * line).rounded())))
            func pad(_ blank: (Int) -> Bool) -> Int {
                var k = 0
                while k < margin, blank(k + 1) { k += 1 }
                return k
            }
            let padL = pad { k in l - k >= 0 && !inkColumn(l - k, t, b) && !(t..<b).contains { others(l - k, $0) } }
            let padR = pad { k in r - 1 + k < width && !inkColumn(r - 1 + k, t, b) && !(t..<b).contains { others(r - 1 + k, $0) } }
            let padT = pad { k in t - k >= 0 && !inkRow(t - k, l, r) }
            let padB = pad { k in b - 1 + k < height && !inkRow(b - 1 + k, l, r) }
            let cl = l - padL, cr = r + padR, ct = t - padT, cb = b + padB
            let cover = TextBox(left: Double(cl) / fw, top: Double(ct) / fh, right: Double(cr) / fw, bottom: Double(cb) / fh)

            // 2) Zemin: kutunun üstündeki ve altındaki şerit (yanlarda simge olabilir); sol/sağ üçte bir ve üst/alt farkı.
            let strip = max(2, Int((0.25 * line).rounded()))
            var samples: [(c: RGB, fx: Double, top: Bool)] = []
            func collect(_ y0: Int, _ y1: Int, top: Bool) {
                guard y0 >= 0, y1 <= height, y1 > y0 else { return }
                let step = max(1, (cr - cl) / 64)
                let rowStep = max(1, (y1 - y0) / 4)
                var strip: [(c: RGB, fx: Double, top: Bool)] = []
                for yy in stride(from: y0, to: y1, by: rowStep) {
                    for xx in stride(from: max(0, cl), to: min(width, cr), by: step) {
                        if others(xx, yy) { return }
                        let c = color(xx, yy)
                        if isInk(c) { continue }
                        strip.append((c, Double(xx - cl) / Double(max(1, cr - cl - 1)), top))
                    }
                }
                samples += strip
            }
            collect(ct - strip, ct, top: true)
            collect(cb, cb + strip, top: false)
            var paint = TextPaint(background: target.background, pitch: pitch(target), cover: cover)
            if samples.count >= 16 {
                let all = samples.map(\.c)
                let average = mean(all)
                if distance(average, bg) <= trustDistance {
                    let left = samples.filter { $0.fx < 1.0 / 3 }.map(\.c), right = samples.filter { $0.fx > 2.0 / 3 }.map(\.c)
                    let above = samples.filter(\.top).map(\.c), below = samples.filter { !$0.top }.map(\.c)
                    // Desen: her parçanın kendi içindeki sapması (degrade kendi başına desen sayılmaz).
                    var parts: [[RGB]] = []
                    for side in [true, false] {
                        for third in 0..<3 {
                            let part: [RGB] = samples.filter { $0.top == side && min(2, Int($0.fx * 3)) == third }.map(\.c)
                            if part.count >= 4 { parts.append(part) }
                        }
                    }
                    let spread = parts.isEmpty ? deviation(all) : parts.map(deviation).reduce(0, +) / Double(parts.count)
                    let dh = left.count >= 4 && right.count >= 4 ? distance(mean(left), mean(right)) : 0
                    let dv = above.count >= 4 && below.count >= 4 ? distance(mean(above), mean(below)) : 0
                    if spread > patternDeviation {
                        paint.patterned = true
                        paint.background = hex(average)
                    } else if dh >= gradientStep, dh >= dv {
                        // Üçte birlerin ortası 1/6 ve 5/6'da: uçlara doğrusal uzatılır.
                        let a = mean(left), z = mean(right)
                        paint.background = hex(extend(a, z, 0.25))
                        paint.background2 = hex(extend(z, a, 0.25))
                        paint.direction = .horizontal
                    } else if dv >= gradientStep {
                        let a = mean(above), z = mean(below)
                        // Şeritlerin ortası kutunun yarım şerit dışında: uçlar içeri doğru aradeğerlenir.
                        let span = Double(cb - ct + strip)
                        let inward = span > 0 ? Double(strip) / 2 / span : 0
                        paint.background = hex(extend(a, z, -inward))
                        paint.background2 = hex(extend(z, a, -inward))
                        paint.direction = .vertical
                    } else {
                        paint.background = hex(average)
                    }
                }
            }

            // 3) Boş alan: tek satırlık etiket hizasının açık tarafına (sağa yaslıda sola, sola yaslıda sağa, ortalıda iki
            // yana) uzayabilir; başka yazıya, simgeye, kutu kenarına ya da karenin kenarına `gapLines` kala durur.
            if target.rows <= 1 {
                let band = stride(from: ct + max(1, (cb - ct) / 6), to: max(ct + 1, cb - max(1, (cb - ct) / 6)),
                                  by: max(1, (cb - ct) / 6)).map { min(height - 1, max(0, $0)) }
                let gap = Int((ScreenFit.gapLines * line).rounded(.up))
                let limit = Int((growLines * line).rounded())
                func scan(from start: Int, step: Int, ground first: RGB) -> Int {
                    var ground = first
                    var x = start
                    let end = step < 0 ? max(-1, start - limit) : min(width, start + limit)
                    // Sınır karşılaştırması ve adım sınırı: başlangıç karenin dışında kalsa da döngü biter (#1255).
                    var steps = 0
                    while step < 0 ? x > end : x < end, x >= 0, x < width, steps <= width {
                        steps += 1
                        if band.contains(where: { others(x, $0) }) || rects.indices.contains(where: { j in
                            j != index && x >= rects[j].l && x < rects[j].r && rects[j].b > ct && rects[j].t < cb
                        }) { return x - step * gap }
                        var sum = (0, 0, 0)
                        for yy in band {
                            let c = color(x, yy)
                            if distance(c, ground) > ScreenFit.inkDistance { return x - step * gap }
                            sum = (sum.0 + c.r, sum.1 + c.g, sum.2 + c.b)
                        }
                        let n = band.count
                        // Degrade zeminde zemin yavaşça izlenir (ScreenFit.withRoom ile aynı).
                        ground = ((ground.r * 7 + sum.0 / n) / 8, (ground.g * 7 + sum.1 / n) / 8, (ground.b * 7 + sum.2 / n) / 8)
                        x += step
                    }
                    return step < 0 ? max(0, end + 1) : min(width, end)
                }
                let startColor = rgb(paint.background), endColor = rgb(paint.background2 ?? paint.background)
                var gl = cl, gr = cr
                if !band.isEmpty, target.align != .left { gl = min(cl, max(0, scan(from: cl - 1, step: -1, ground: startColor) + 1)) }
                if !band.isEmpty, target.align != .right { gr = max(cr, min(width, scan(from: cr, step: 1, ground: endColor))) }
                if gl < cl || gr > cr {
                    paint.grow = TextBox(left: Double(gl) / fw, top: cover.top, right: Double(gr) / fw, bottom: cover.bottom)
                }
            }
            result.append(paint)
        }
        // 4) Grup: aynı sütunda (ortak sol ya da sağ kenar, düzenli aralık) ya da aynı satırda duran, BÜYÜK HARF'i ve
        // satır yüksekliği aynı tek satırlık etiketler.
        for (members, id) in groups(targets) { for i in members { result[i].group = id } }
        return result
    }

    /// Kare (CGImage) üzerinden ölçüm.
    public static func paints(_ targets: [Target], frame: CGImage) -> [TextPaint] {
        guard let pixels = GamePhonePixels(frame) else { return [] }
        return paints(targets, width: pixels.width, height: pixels.height) { x, y in
            let p = pixels.offset(x, y)
            return (Int(pixels.bytes[p]), Int(pixels.bytes[p + 1]), Int(pixels.bytes[p + 2]))
        }
    }

    /// Satır aralığı: çok satırlı yazıda kutudan ((satır sayısı - 1) aralık + bir satır yüksekliği), tek satırda satır yüksekliği.
    static func pitch(_ target: Target) -> Double {
        let height = target.box.bottom - target.box.top
        guard target.rows > 1, target.lineHeight > 0 else { return target.lineHeight > 0 ? target.lineHeight : height }
        return max(target.lineHeight, (height - target.lineHeight) / Double(target.rows - 1))
    }

    /// Grup üyeleri ve numarası (grubun en küçük sıra numarası); tek üyeli grup yok.
    static func groups(_ targets: [Target]) -> [([Int], Int)] {
        let labels = targets.indices.filter { targets[$0].rows <= 1 }
        var parent = Dictionary(uniqueKeysWithValues: labels.map { ($0, $0) })
        func root(_ i: Int) -> Int { var i = i; while parent[i]! != i { i = parent[i]! }; return i }
        func overlap(_ a: TextBox, _ b: TextBox) -> Double {
            max(0, min(a.bottom, b.bottom) - max(a.top, b.top)) / max(1e-9, min(a.bottom - a.top, b.bottom - b.top))
        }
        for a in labels {
            for b in labels where b > a {
                let x = targets[a], y = targets[b]
                let line = max(x.lineHeight, y.lineHeight)
                guard x.upper == y.upper, abs(x.lineHeight - y.lineHeight) <= sameLine * line else { continue }
                // Satır yüksekliği kareye oranla; yatay pay aynı piksele denk gelsin diye en-boy oranı bilinmez, yarım satır
                // yüksekliğinin yarısı kadar (16:9'da ~0,28 satır) alınır.
                let tolerance = 0.5 * line * 9 / 16
                let sameRow = overlap(x.box, y.box) >= 0.5
                let column = (abs(x.box.left - y.box.left) <= tolerance || abs(x.box.right - y.box.right) <= tolerance)
                    && overlap(x.box, y.box) == 0 && abs(x.box.top - y.box.top) <= 3 * line
                if sameRow || column { parent[root(a)] = root(b) }
            }
        }
        return Dictionary(grouping: labels, by: root).values.filter { $0.count >= 2 }.map { ($0.sorted(), $0.min()!) }
            .sorted { $0.1 < $1.1 }
    }

    static func rgb(_ hex: String) -> RGB {
        guard let (r, g, b) = SpeakerColors.rgb(hex) else { return (0, 0, 0) }
        return (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    static func hex(_ c: RGB) -> String {
        String(format: "#%02X%02X%02X", max(0, min(255, c.r)), max(0, min(255, c.g)), max(0, min(255, c.b)))
    }

    static func distance(_ a: RGB, _ b: RGB) -> Int { max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b)) }

    static func mean(_ list: [RGB]) -> RGB {
        let n = max(1, list.count)
        return (list.map(\.r).reduce(0, +) / n, list.map(\.g).reduce(0, +) / n, list.map(\.b).reduce(0, +) / n)
    }

    /// `a`'dan `b`'nin tersine `share` kadar (eksiyse `b`'ye doğru) uzatılmış renk.
    static func extend(_ a: RGB, _ b: RGB, _ share: Double) -> RGB {
        func one(_ x: Int, _ y: Int) -> Int { Int((Double(x) + Double(x - y) * share).rounded()) }
        return (one(a.r, b.r), one(a.g, b.g), one(a.b, b.b))
    }

    static func deviation(_ list: [RGB]) -> Double {
        guard !list.isEmpty else { return 0 }
        func spread(_ values: [Int]) -> Double {
            let average = Double(values.reduce(0, +)) / Double(values.count)
            return (values.map { (Double($0) - average) * (Double($0) - average) }.reduce(0, +) / Double(values.count)).squareRoot()
        }
        return (spread(list.map(\.r)) + spread(list.map(\.g)) + spread(list.map(\.b))) / 3
    }
}
