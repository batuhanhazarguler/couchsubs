// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Bir ekran yazısının yerinde, arayüz Türkçe yapılmış gibi çizilmesi için göndericinin kareden ölçtükleri (TV pikselleri
/// okuyamaz). Yalnız yazı değişince ölçülür (Windows: TextPaint.cs, Android: TextPaint.kt; aynı kurallar ve eşikler).
/// TV'ye öğenin `bg`, `bg2`, `bgDir`, `bgPat`, `fg`, `weight`, `upper`, `align`, `lineH`, `cover`, `grow`, `group`
/// alanlarıyla (çizim kipi: `mode`, `spot`, `spotRoom`, `twinBox`, `radius`, `scale`, `tail`, `icon`) gider; eski TV
/// bunları yok sayıp eski çizimi sürdürür.
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
    /// Yazı tanıma kutusunun ucundaki simge (menü simgesi, tuş simgesi) yazının hangi yanında: örtü ve uzama o simgeye
    /// girmez, yazı o yana yaslanır (sol simgede sola, sağ simgede sağa; TV'ye `align` olarak gider). nil: simge yok.
    public var iconSide: TextLook.Align? = nil
    /// Çizim kipi (`TextPainter.Target.kind` verilince seçilir; yalnız otomatik ekran yazısında): örtme, yanına yazma ya da
    /// ikiz panel. TV'ye `mode` olarak gider; eski TV yok sayıp örter.
    public var mode: Mode = .cover
    /// `beside`/`twin`: Türkçenin yazıldığı kutu (yanına yazmada özgün yazının yanındaki boş alan, örtü boyunda; ikizde
    /// özgün yazının ikiz paneldeki yeri). TV'ye `spot`.
    public var spot: TextBox? = nil
    /// `spot`'un yana uzayabileceği alan (yalnız sol ve sağ kenarı anlamlı; yanına yazmada boş alanın tamamı, ikizde panelin
    /// iç genişliği). TV'ye `spotRoom`.
    public var spotRoom: TextBox? = nil
    /// `twin`: ikiz panelin kutusu (özgün panelin hemen üstünde ya da altında, sol kenarı hizalı, `scale` katı boyda). TV'ye `twinBox`.
    public var twin: TextBox? = nil
    /// `twin`: panelin köşe yarıçapı (ikizde), kare yüksekliğine oranla. TV'ye `radius`.
    public var radius: Double = 0
    /// `twin`: ikizin özgüne oranı (`TextPainter.twinScale`): yazı boyu ve satır aralığı bu katta. TV'ye `scale`.
    public var scale: Double = 1
    /// `twin`: konuşma balonunun kuyruğu hangi alt köşede ("left"/"right"); nil: kuyruk yok. TV'ye `tail`.
    public var tail: String? = nil
    /// `twin`: panelin solundaki kare resim (kişi resmi): karedeki yeri (kesmek için) ve ikiz paneldeki yeri.
    public var portrait: TextBox? = nil
    public var portraitTwin: TextBox? = nil
    /// Kesilmiş resim (PNG, data: adresi; en çok `TextPainter.portraitMax` piksel); çağıran keser
    /// (`TextPainter.portraitImage`). TV'ye `icon` ({src, box}).
    public var portraitImage: String? = nil

    /// Çizim kipleri (Sinan Bey: oyun dünyasının üstünde opak yama görünmesin).
    /// - `cover`: düz/opak panel zemininde (menü, görev kartı, ayar listesi) özgün yazıyı örten kutu (eski davranış).
    /// - `beside`: desenli zeminde ya da oyun dünyası üstündeki tek satırlık istemde örtü yok; özgün yazı yerinde kalır,
    ///   Türkçe yanındaki boş alana özgün stille, okunurluk için konturla yazılır.
    /// - `twin`: yuvarlak köşeli düz panel (bildirim, ipucu kutusu) örtülmez; Türkçesi aynı zemin, köşe ve yazı rengiyle
    ///   hemen üstüne (yer yoksa altına) küçük, sol kenarı hizalı ayrı bir panel olarak çizilir (#1296).
    public enum Mode: String, Sendable { case cover, beside, twin }

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
        paint.spot = spot?.placed(in: area)
        paint.spotRoom = spotRoom?.placed(in: area)
        paint.twin = twin?.placed(in: area)
        paint.radius = radius * (area.bottom - area.top)
        paint.portrait = portrait?.placed(in: area)
        paint.portraitTwin = portraitTwin?.placed(in: area)
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
        /// Okunan yazının sözcük sayısı (simge sanılan karakterler sayılmaz, `words(_:)`); 0: bilinmiyor, kutunun ucundaki
        /// simge aranmaz.
        public var words: Int
        /// Yazının türü (`ScreenTextKind`): verilirse çizim kipi seçilir (`TextPaint.mode`); nil: hep örtme ("Ekranı çevir").
        public var kind: ScreenTextKind? = nil
        /// Yazı bir tuş istemi/eylemi ("Hold L2 to aim", "Press ✕ to enter"): düz zeminde de yanına yazılabilir.
        public var prompt = false

        public init(box: TextBox, lineHeight: Double, rows: Int, background: String, foreground: String, upper: Bool,
                    align: TextLook.Align, words: Int = 0, kind: ScreenTextKind? = nil, prompt: Bool = false) {
            self.box = box
            self.lineHeight = lineHeight
            self.rows = rows
            self.background = background
            self.foreground = foreground
            self.upper = upper
            self.align = align
            self.words = words
            self.kind = kind
            self.prompt = prompt
        }
    }

    /// Kutunun ucundaki simgeyi yazıdan ayıran en dar boşluk, satır yüksekliğinin katı (harf arası bundan dardır; GTA 6
    /// menüsünde simgeyle yazı arası ~0,4 satır).
    public static let iconGapLines = 0.3
    /// Simge parçasının genişliği satır yüksekliğinin bu katları arasında ("I" harfi gibi ince parça simge sayılmaz).
    public static let iconMinWide = 0.45
    public static let iconMaxWide = 1.6
    /// Simge sanılıp yazı olarak okunan karakterler (GTA 6 menü simgesi "I", "II"; tuş simgeleri).
    static let iconGlyphs: Set<Character> = ["I", "|", "l", "!", "[", "]", "(", ")", "©", "®", "@", "○", "◯", "●", "□",
                                             "■", "△", "▲", "✕", "✖", "×", "◎", "⊗", "⊙"]

    /// Okunan yazının sözcük sayısı: simge sanılan bir iki karakterlik parçalar ve harfi/rakamı olmayan parçalar sayılmaz
    /// ("I Map" → 1, "SELECT ⊗" → 1, "- SMASH 'N' GRABS" → 3, "• Objective" → 1). Menü simgesi (yön tuşu, renkli nokta)
    /// "-", "•", "+" diye okununca sözcük sayılıyor, parça sayısı sözcükten fazla çıkmıyor, simge bulunmuyordu: kutu
    /// simgenin üstüne çiziliyordu (#1268, #1270).
    public static func words(_ text: String) -> Int {
        IconText.plain(text).split(whereSeparator: \.isWhitespace).filter { token in
            !(token.count <= 2 && token.allSatisfy { iconGlyphs.contains($0) })
                && token.contains { $0.isLetter || $0.isNumber }
        }.count
    }

    /// Kutunun ([l, r), piksel) ucundaki simge: harf sütunları (`ink(x)`) `iconGapLines` satırdan geniş boşluklarla
    /// parçalara bölünür; parça sayısı sözcük sayısından çoksa uçtaki simge genişliğindeki (`iconMinWide`-`iconMaxWide`
    /// satır) parça simgedir. İki uç da uyarsa hizanın yanı (sola yaslıda sol, öbürlerinde sağ) önce; ikincisi ancak iki
    /// fazla parça varsa. Simgeler çıkınca kalan parça sözcüklerden çoksa simge yoktur. Dönen: simgeler ve onlar çıkınca
    /// yazının sol/sağ kenarı.
    static func iconSpans(l: Int, r: Int, line: Double, words: Int, align: TextLook.Align, ink: (Int) -> Bool)
        -> (left: (l: Int, r: Int)?, right: (l: Int, r: Int)?, textLeft: Int, textRight: Int) {
        guard words > 0, r - l >= 2 else { return (nil, nil, l, r) }
        let gap = max(2, Int((iconGapLines * line).rounded()))
        var spans: [(l: Int, r: Int)] = []
        var start: Int? = nil, last = l, blank = 0
        for x in l..<r {
            if ink(x) {
                if start == nil { start = x }
                last = x
                blank = 0
            } else if let s = start {
                blank += 1
                if blank >= gap { spans.append((s, last + 1)); start = nil; blank = 0 }
            }
        }
        if let s = start { spans.append((s, last + 1)) }
        guard spans.count >= 2, spans.count > words else { return (nil, nil, l, r) }
        func isIcon(_ span: (l: Int, r: Int)) -> Bool {
            let wide = Double(span.r - span.l)
            return wide >= iconMinWide * line && wide <= iconMaxWide * line
        }
        let extra = spans.count - words
        let first = spans[0], final = spans[spans.count - 1]
        var left: (l: Int, r: Int)? = nil, right: (l: Int, r: Int)? = nil
        if align == .left {
            if isIcon(first) { left = first }
            if isIcon(final), left == nil || extra >= 2 { right = final }
        } else {
            if isIcon(final) { right = final }
            if isIcon(first), right == nil || extra >= 2 { left = first }
        }
        // Simgeler çıkınca kalan parçalar sözcüklerden çok olamaz: harfleri aralıklı tek sözcük ("P R O G R E S S")
        // simge sanılmaz.
        if spans.count - (left == nil ? 0 : 1) - (right == nil ? 0 : 1) > words { return (nil, nil, l, r) }
        return (left, right, left != nil ? spans[1].l : l, right != nil ? spans[spans.count - 2].r : r)
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

    // MARK: Kip seçimi sabitleri (Windows TextPaint.cs, Android TextPaint.kt aynı)

    /// Panel taramasında nokta zeminden en çok bu kadar uzaksa (en büyük renk bileşeni farkı) panelin zeminidir.
    public static let panelTolerance = 24
    /// Bir satır/sütunun en az bu kadarı zemin (ya da yazı) ise panel o yöne sürer.
    public static let panelShare = 0.7
    /// Panel karenin en çok bu kadarı genişlikte/yükseklikte; daha büyüğü (gökyüzü, menünün kendisi) panel sayılmaz.
    public static let panelMaxWidth = 0.45
    public static let panelMaxHeight = 0.35
    /// Panel yazının her yanında en az bu kadar satır yüksekliği (en az 2 piksel) taşmalı; taşmıyorsa düz kutudur (örtülür).
    public static let panelPadLines = 0.2
    /// Köşe yuvarlak: panelin köşesinden köşegen boyunca en az bu kadar nokta zemin değil (aynı kenardaki iki köşede).
    public static let cornerMin = 2
    /// Yanına yazmada bir sütunda/satırda yazı rengine (`besideInk` kadar yakın) noktaların payı bundan azsa alan boştur.
    public static let besideInk = 48
    public static let besideShare = 0.1
    /// Türkçenin özgün yazıdan uzaklığı, satır yüksekliğinin katı.
    public static let besideGapLines = 0.5
    /// Yanına yazma alanı en çok özgün yazının bu katı (+ bir satır yüksekliği) genişlikte taranır.
    public static let besideMax = 1.6
    /// İkiz panel özgün panelin bu katı boyda (yazı, resim, köşe ve iç boşluk aynı oranda; Sinan Bey, #1296).
    public static let twinScale = 0.58
    /// İkizin yazısı en az karenin bu kadarı (TV app.js DIALOGUE_MIN_SHARE ile aynı): ikiz bundan küçülmez.
    public static let twinMinShare = 0.022
    /// Kişi resmi (ikiz panelde gösterilir) en çok bu kadar piksel kenarlı kesilir.
    public static let portraitMax = 40

    /// Yazının (örtü kutusu [l, r) x [t, b)) çevresindeki düz alan: kutu, satır/sütunlarının en az `panelShare`'i zemin
    /// (`like`: zemin, yazının kendi örtü kutusu ya da başka hedef; harf noktası sayılmaz, koyu oyun dünyası koyu yazıya
    /// benzer) olduğu sürece dört yana büyür. Karenin kenarına değen ya da `panelMaxWidth`/`panelMaxHeight`'tan büyük alan
    /// açık zemindir (gökyüzü, menünün kendisi): nil.
    static func findPanel(l: Int, t: Int, r: Int, b: Int, width: Int, height: Int,
                          like: (Int, Int) -> Bool) -> (l: Int, t: Int, r: Int, b: Int)? {
        func row(_ y: Int, _ x0: Int, _ x1: Int) -> Bool {
            let step = max(1, (x1 - x0) / 64)
            var n = 0, ok = 0
            for x in stride(from: x0, to: x1, by: step) {
                n += 1
                if like(x, y) { ok += 1 }
            }
            return n > 0 && Double(ok) >= panelShare * Double(n)
        }
        func column(_ x: Int, _ y0: Int, _ y1: Int) -> Bool {
            let step = max(1, (y1 - y0) / 64)
            var n = 0, ok = 0
            for y in stride(from: y0, to: y1, by: step) {
                n += 1
                if like(x, y) { ok += 1 }
            }
            return n > 0 && Double(ok) >= panelShare * Double(n)
        }
        guard r > l, b > t else { return nil }
        let maxW = Int(panelMaxWidth * Double(width)), maxH = Int(panelMaxHeight * Double(height))
        var pl = max(0, l), pt = max(0, t), pr = min(width, r), pb = min(height, b)
        var grew = true
        while grew {
            grew = false
            while pl > 0, column(pl - 1, pt, pb) {
                pl -= 1
                grew = true
                if pr - pl > maxW { return nil }
            }
            while pr < width, column(pr, pt, pb) {
                pr += 1
                grew = true
                if pr - pl > maxW { return nil }
            }
            while pt > 0, row(pt - 1, pl, pr) {
                pt -= 1
                grew = true
                if pb - pt > maxH { return nil }
            }
            while pb < height, row(pb, pl, pr) {
                pb += 1
                grew = true
                if pb - pt > maxH { return nil }
            }
        }
        if pl == 0 || pt == 0 || pr == width || pb == height { return nil }
        return (pl, pt, pr, pb)
    }

    /// Panelin ([l, r) x [t, b)) köşe yarıçapı (piksel) ve konuşma balonunun kuyruğu: köşeler (`ground`: yalnız zemin)
    /// köşegen boyunca taranır; üst ya da alt kenarın iki köşesinde en az `cornerMin` nokta zemin değilse panel yuvarlaktır,
    /// yarıçap köşegendeki mesafeden (k / (1 − 1/√2)). Üst köşeler yuvarlakken alt köşelerden yalnız biri köşeliyse o
    /// köşede balonun kuyruğu vardır ("left"/"right"). nil: köşeli kutu.
    static func cornerRadius(l: Int, t: Int, r: Int, b: Int, ground: (Int, Int) -> Bool) -> (radius: Double, tail: String?)? {
        let limit = max(1, min(r - l, b - t) / 4)
        func corner(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int) -> Int {
            var k = 0
            while k <= limit, !ground(x + dx * k, y + dy * k) { k += 1 }
            return k
        }
        let tl = corner(l, t, 1, 1), tr = corner(r - 1, t, -1, 1)
        let bl = corner(l, b - 1, 1, -1), br = corner(r - 1, b - 1, -1, -1)
        func round(_ k: Int) -> Bool { k >= cornerMin && k <= limit }
        let top = round(tl) && round(tr), bottom = round(bl) && round(br)
        guard top || bottom else { return nil }
        let ks = (top ? [tl, tr] : []) + (bottom ? [bl, br] : [])
        let radius = Double(ks.reduce(0, +)) / Double(ks.count) / (1 - 1 / 2.0.squareRoot())
        let tail: String? = !top || bottom ? nil : !round(bl) && round(br) ? "left" : round(bl) && !round(br) ? "right" : nil
        return (radius, tail)
    }

    /// Panelin solundaki kare resim (kişi resmi): panelin solu ile yazının arası, yazının satırı çevresinde (bir satır
    /// yüksekliği yukarı/aşağı); `off` (zeminden belirgin ayrılan, başka yazı olmayan) noktaların sınırı. En az 0,8 satır
    /// yüksekliği (en az 6 piksel), en çok 4 satır yüksekliği, kareye yakın (0,75–1,33) ve yazıdan ayrıksa resimdir.
    static func portrait(panelLeft: Int, panelTop: Int, panelBottom: Int, l: Int, t: Int, b: Int, line: Double,
                         off: (Int, Int) -> Bool) -> (l: Int, t: Int, r: Int, b: Int)? {
        let x0 = panelLeft + 2, x1 = l
        let y0 = max(panelTop + 2, t - Int(line.rounded())), y1 = min(panelBottom - 2, b + Int(line.rounded()))
        guard x1 > x0, y1 > y0 else { return nil }
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in y0..<y1 {
            for x in x0..<x1 where off(x, y) {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let w = maxX - minX + 1, h = maxY - minY + 1
        let least = max(6, Int((0.8 * line).rounded()))
        guard w >= least, h >= least, Double(w) <= 4 * line, Double(h) <= 4 * line,
              Double(w) >= 0.75 * Double(h), Double(w) <= 1.33 * Double(h),
              maxX + 1 + max(2, Int((ScreenFit.gapLines * line).rounded())) <= l else { return nil }
        return (minX, minY, maxX + 1, maxY + 1)
    }

    /// Kişi resmini kareden keser: en çok `portraitMax` piksel kenarlı (en yakın nokta örneklemesi), opak PNG data: adresi.
    public static func portraitImage(_ box: TextBox, width: Int, height: Int, color: (Int, Int) -> RGB) -> String? {
        let l = max(0, Int((box.left * Double(width)).rounded())), t = max(0, Int((box.top * Double(height)).rounded()))
        let r = min(width, Int((box.right * Double(width)).rounded())), b = min(height, Int((box.bottom * Double(height)).rounded()))
        guard r - l >= 2, b - t >= 2 else { return nil }
        let side = max(r - l, b - t)
        let ow = max(1, min(r - l, (r - l) * portraitMax / side)), oh = max(1, min(b - t, (b - t) * portraitMax / side))
        var pixels = [UInt8](repeating: 255, count: ow * oh * 4)
        for j in 0..<oh {
            for i in 0..<ow {
                let c = color(l + i * (r - l) / ow, t + j * (b - t) / oh)
                let p = (j * ow + i) * 4
                pixels[p] = UInt8(max(0, min(255, c.r)))
                pixels[p + 1] = UInt8(max(0, min(255, c.g)))
                pixels[p + 2] = UInt8(max(0, min(255, c.b)))
            }
        }
        return "data:image/png;base64," + ButtonIcons.png(pixels, stride: ow * 4, x: 0, y: 0, width: ow, height: oh)
            .base64EncodedString()
    }

    /// Kare (CGImage) üzerinden kişi resmi.
    public static func portraitImage(_ box: TextBox, frame: CGImage) -> String? {
        guard let pixels = GamePhonePixels(frame) else { return nil }
        return portraitImage(box, width: pixels.width, height: pixels.height) { x, y in
            let p = pixels.offset(x, y)
            return (Int(pixels.bytes[p]), Int(pixels.bytes[p + 1]), Int(pixels.bytes[p + 2]))
        }
    }

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
        // Kip seçimi için: örtü kutuları (piksel), satır yükseklikleri ve ikiz panel adayları.
        var covers: [(l: Int, t: Int, r: Int, b: Int)] = []
        var lines: [Double] = []
        var grounds: [RGB] = []
        var panels: [Int: (l: Int, t: Int, r: Int, b: Int)] = [:]
        /// Bir hedefin kutusu (`except` hariç) bu noktada mı.
        func rectHit(_ x: Int, _ y: Int, except: Int?) -> Bool {
            rects.indices.contains { j in j != except && x >= rects[j].l && x < rects[j].r && y >= rects[j].t && y < rects[j].b }
        }
        for (index, target) in targets.enumerated() {
            let bg = rgb(target.background), fg = rgb(target.foreground)
            let line = max(1, target.lineHeight * fh)
            func isInk(_ c: RGB) -> Bool {
                let toBg = distance(c, bg)
                return toBg > inkDistance && distance(c, fg) < toBg
            }
            // Kutunun ucundaki kendi simgesi (0. adım): öbür hedefler gibi engeldir; araya `ScreenFit.gapLines` boşluk kalır.
            var zones: [(l: Int, r: Int)] = []
            func others(_ x: Int, _ y: Int) -> Bool {
                zones.contains { x >= $0.l && x < $0.r }
                    || rects.indices.contains { j in j != index && x >= rects[j].l && x < rects[j].r && y >= rects[j].t && y < rects[j].b }
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
            var (l, t, r, b) = rects[index]
            // 0) Kutunun ucundaki simge (#1266, #1267): yazı tanıma kutusu menü/tuş simgesini de alıyordu; kutu simgenin
            // üstüne çiziliyor, simge kayboluyordu. Simge kutudan çıkar ve engel olur: örtü, kenar payı ve uzama ona girmez.
            var iconLeft = false, iconRight = false
            if target.rows <= 1 {
                let found = iconSpans(l: l, r: r, line: line, words: target.words, align: target.align) { x in
                    inkColumn(x, t, b)
                }
                let keep = Int((ScreenFit.gapLines * line).rounded(.up))
                if let icon = found.left { zones.append((icon.l - keep, icon.r + keep)); iconLeft = true }
                if let icon = found.right { zones.append((icon.l - keep, icon.r + keep)); iconRight = true }
                l = found.textLeft
                r = found.textRight
            }
            let textLeft = l, textRight = r
            // 1) Örtü: yazı tanıma kutusunun dışına taşan harf noktaları (bitişik satır/sütunlar) kutuya katılır.
            let reach = max(1, Int((reachLines * line).rounded()))
            var y = b
            while y < min(height, rects[index].b + reach), inkRow(y, l, r) { y += 1 }
            b = y
            y = t - 1
            while y >= max(0, rects[index].t - reach), inkRow(y, l, r) { y -= 1 }
            t = y + 1
            var x = r
            while x < min(width, textRight + reach), inkColumn(x, t, b) { x += 1 }
            r = x
            x = l - 1
            while x >= max(0, textLeft - reach), inkColumn(x, t, b) { x -= 1 }
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
            paint.iconSide = iconLeft == iconRight ? nil : iconLeft ? .left : .right
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
            // yana) uzayabilir; başka yazıya, simgeye, kutu kenarına ya da karenin kenarına `gapLines` kala durur. Kutunun
            // ucunda simge varsa yalnız simgenin öbür yanına uzar (sağdaki tuş simgesinde sola, soldaki menü simgesinde sağa).
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
                let toLeft = !iconLeft && (target.align != .left || iconRight)
                let toRight = !iconRight && (target.align != .right || iconLeft)
                if !band.isEmpty, toLeft { gl = min(cl, max(0, scan(from: cl - 1, step: -1, ground: startColor) + 1)) }
                if !band.isEmpty, toRight { gr = max(cr, min(width, scan(from: cr, step: 1, ground: endColor))) }
                if gl < cl || gr > cr {
                    paint.grow = TextBox(left: Double(gl) / fw, top: cover.top, right: Double(gr) / fw, bottom: cover.bottom)
                }
            }

            // 5) Kip (yalnız türü verilen yazıda): menü, görev/harita kartı ve telefon hep örtülür. Düz zemini sınırlı bir
            // alansa (panel) karar döngüden sonra panel panel verilir (`twin` ya da örtme); açık zeminde (desenli zemin,
            // karenin kenarına değen ya da çok büyük düz alan) desenli zeminde ya da tek satırlık istemde Türkçe yanındaki boş
            // alana yazılır; yer bulunamazsa örtülür.
            covers.append((cl, ct, cr, cb))
            lines.append(line)
            grounds.append(rgb(paint.background))
            if let kind = target.kind, kind != .menu, kind != .mission, kind != .phone {
                let ground = rgb(paint.background)
                let panel = paint.patterned || paint.background2 != nil ? nil
                    : findPanel(l: cl, t: ct, r: cr, b: cb, width: width, height: height) { x, y in
                        if rectHit(x, y, except: index) || (x >= cl && x < cr && y >= ct && y < cb) { return true }
                        return distance(color(x, y), ground) <= panelTolerance
                    }
                if let panel {
                    panels[index] = panel
                } else if paint.patterned || (kind == .help && target.prompt && target.rows <= 1),
                          let spot = besideSpot(l: cl, t: ct, r: cr, b: cb, line: line, width: width, height: height,
                                                iconLeft: iconLeft, iconRight: iconRight, free: { x, y in
                                                    if others(x, y) { return nil }
                                                    return distance(color(x, y), fg) <= besideInk
                                                }) {
                    paint.mode = .beside
                    paint.spot = TextBox(left: Double(spot.l) / fw, top: Double(spot.t) / fh, right: Double(spot.r) / fw,
                                         bottom: Double(spot.b) / fh)
                    paint.spotRoom = TextBox(left: Double(spot.roomL) / fw, top: Double(spot.t) / fh,
                                             right: Double(spot.roomR) / fw, bottom: Double(spot.b) / fh)
                }
            }
            result.append(paint)
        }
        // İkiz paneller: kesişen paneller tek paneldir (bildirimin başlığı ve gövdesi; birinin taraması paneldeki resimde
        // erken durabilir), kutusu hepsinin birleşimi. Her yazı panelin içinde her yanda `panelPadLines` boşlukla durmalı;
        // durmuyorsa ya da köşeler yuvarlak değilse (köşeli kutu) örtülür. İkiz panel önce üste, yer yoksa alta (arada
        // `gapLines`); başka yazıya ve karenin dışına taşmaz. Her yazı ikizde kendi yerinde, panelin iç genişliğinde (en
        // küçük sol iç boşluk iki yanda) uzayabilir; paneldeki kişi resmi ikizde de gösterilir.
        let keys = panels.keys.sorted()
        var parent = Dictionary(uniqueKeysWithValues: keys.map { ($0, $0) })
        func root(_ i: Int) -> Int { var i = i; while parent[i]! != i { i = parent[i]! }; return i }
        for a in keys {
            for b in keys where b > a {
                let p = panels[a]!, q = panels[b]!
                if min(p.r, q.r) > max(p.l, q.l) && min(p.b, q.b) > max(p.t, q.t) { parent[root(b)] = root(a) }
            }
        }
        for members in Dictionary(grouping: keys, by: root).values.map({ $0.sorted() }).sorted(by: { $0[0] < $1[0] }) {
            let l = members.map { panels[$0]!.l }.min()!, t = members.map { panels[$0]!.t }.min()!
            let r = members.map { panels[$0]!.r }.max()!, b = members.map { panels[$0]!.b }.max()!
            let padded = members.allSatisfy { m in
                let c = covers[m], pad = max(2, Int((panelPadLines * lines[m]).rounded()))
                return c.l - l >= pad && r - c.r >= pad && c.t - t >= pad && b - c.b >= pad
            }
            let ground = grounds[members[0]]
            guard padded, let corner = cornerRadius(l: l, t: t, r: r, b: b, ground: { x, y in
                distance(color(x, y), ground) <= panelTolerance
            }) else { continue }
            // İkiz özgünün `twinScale` katı boyda (Sinan Bey, #1296: Türkçe balon belirgin küçük), sol kenarı özgünle hizalı;
            // önce hemen üstte, yer yoksa altta (arada `gapLines`). Türkçe uzunsa ikiz özgün panelin genişliğine kadar uzar.
            // Küçük panelde (oyunun bildirimi çoğu zaman küçük) ikizin yazısı okunabilirlik sınırının altına inmez: TV'nin
            // konuşma satırı alt sınırı (app.js DIALOGUE_MIN_SHARE, 1080'de 24 piksel); gerekirse ikiz özgün boyda.
            let least = members.map { lines[$0] }.min() ?? lines[members[0]]
            let scale = min(1, max(twinScale, twinMinShare * Double(height) / (ScreenFit.exactFont * least)))
            let h = Int((Double(b - t) * scale).rounded()), gap = max(2, Int((ScreenFit.gapLines * lines[members[0]]).rounded(.up)))
            func clear(_ y0: Int, _ y1: Int) -> Bool {
                y0 >= 0 && y1 <= height && !rects.indices.contains { j in
                    !members.contains(j) && rects[j].l < r && rects[j].r > l && rects[j].t < y1 && rects[j].b > y0
                }
            }
            guard let top = clear(t - gap - h, t - gap) ? t - gap - h : clear(b + gap, b + gap + h) ? b + gap : nil else { continue }
            func x(_ v: Int) -> Double { (Double(l) + Double(v - l) * scale) / fw }
            func y(_ v: Int) -> Double { (Double(top) + Double(v - t) * scale) / fh }
            var face: (l: Int, t: Int, r: Int, b: Int)? = nil
            for m in members where face == nil {
                face = portrait(panelLeft: l, panelTop: t, panelBottom: b, l: covers[m].l, t: covers[m].t, b: covers[m].b,
                                line: lines[m]) { x, y in
                    !rectHit(x, y, except: nil) && distance(color(x, y), ground) > 2 * panelTolerance
                }
            }
            let inset = max(gap, members.map { covers[$0].l - l }.min() ?? gap)
            for m in members {
                let c = covers[m], align = targets[m].align
                var paint = result[m]
                paint.mode = .twin
                paint.scale = scale
                paint.tail = corner.tail
                paint.twin = TextBox(left: x(l), top: y(t), right: x(r), bottom: y(b))
                paint.radius = corner.radius * scale / fh
                paint.spot = TextBox(left: x(c.l), top: y(c.t), right: x(c.r), bottom: y(c.b))
                paint.spotRoom = TextBox(left: align == .left ? x(c.l) : x(l + inset), top: y(c.t),
                                         right: max(x(c.r), Double(r - Int((Double(inset) * scale).rounded())) / fw),
                                         bottom: y(c.b))
                if let face {
                    paint.portrait = TextBox(left: Double(face.l) / fw, top: Double(face.t) / fh, right: Double(face.r) / fw,
                                             bottom: Double(face.b) / fh)
                    paint.portraitTwin = TextBox(left: x(face.l), top: y(face.t), right: x(face.r), bottom: y(face.b))
                }
                result[m] = paint
            }
        }
        // Çakışma: yanına yazılan Türkçe başka bir hedefin Türkçesine (önceki yanına yazma alanı ya da ikiz panel) binerse
        // örtmeye döner.
        func overlaps(_ a: TextBox, _ b: TextBox) -> Bool {
            min(a.right, b.right) > max(a.left, b.left) && min(a.bottom, b.bottom) > max(a.top, b.top)
        }
        for i in result.indices where result[i].mode == .beside {
            guard let mine = result[i].spotRoom else { continue }
            let hit = result.indices.contains { j in
                guard j != i else { return false }
                if result[j].mode == .twin, let twin = result[j].twin { return overlaps(mine, twin) }
                return j < i && result[j].mode == .beside && result[j].spotRoom.map { overlaps(mine, $0) } == true
            }
            if hit {
                result[i].mode = .cover
                result[i].spot = nil
                result[i].spotRoom = nil
            }
        }
        // 4) Grup: aynı sütunda (ortak sol ya da sağ kenar, düzenli aralık) ya da aynı satırda duran, BÜYÜK HARF'i ve
        // satır yüksekliği aynı tek satırlık etiketler.
        for (members, id) in groups(targets) { for i in members { result[i].group = id } }
        return result
    }

    /// Yanına yazma alanı (Sinan Bey: "SELAMLA  GREET"): önce sol, sonra sağ, sonra üst (simgenin olduğu yana değil). `free(x, y)`: nil başka hedef ya
    /// da simge (alan orada biter), true yazı rengine yakın nokta, false boş zemin. Bir sütun/satır, yazı rengindeki
    /// noktaları `besideShare`'den azsa boştur. Türkçe özgün yazıdan `besideGapLines`, öbür uçta `ScreenFit.gapLines`
    /// uzak; alan en az örtü kutusu genişliğinde olmalı (sol/sağ), üstte örtü kutusu kadar yükseklik boş olmalı.
    /// Dönen: örtü boyundaki yazı kutusu (piksel) ve uzayabileceği sol/sağ sınır.
    static func besideSpot(l: Int, t: Int, r: Int, b: Int, line: Double, width: Int, height: Int, iconLeft: Bool,
                           iconRight: Bool, free: (Int, Int) -> Bool?)
        -> (l: Int, t: Int, r: Int, b: Int, roomL: Int, roomR: Int)? {
        let w = r - l, h = b - t
        guard w > 0, h > 0, t >= 0, b <= height else { return nil }
        let near = max(2, Int((besideGapLines * line).rounded()))
        let far = max(1, Int((ScreenFit.gapLines * line).rounded(.up)))
        let most = Int((besideMax * Double(w) + line).rounded())
        func open(_ cells: [Bool?]) -> Bool {
            guard !cells.isEmpty, !cells.contains(where: { $0 == nil }) else { return false }
            let ink = cells.filter { $0 == true }.count
            return Double(ink) < besideShare * Double(cells.count)
        }
        func column(_ x: Int, _ y0: Int, _ y1: Int) -> Bool {
            guard x >= 0, x < width, y0 >= 0, y1 <= height, y1 > y0 else { return false }
            return open((y0..<y1).map { free(x, $0) })
        }
        func row(_ y: Int, _ x0: Int, _ x1: Int) -> Bool {
            guard y >= 0, y < height, x0 >= 0, x1 <= width, x1 > x0 else { return false }
            return open((x0..<x1).map { free($0, y) })
        }
        /// `x`'ten `step` yönünde art arda boş sütun sayısı (en çok `cap`).
        func run(from x: Int, step: Int, _ y0: Int, _ y1: Int, cap: Int) -> Int {
            var n = 0
            while n < cap, column(x + step * n, y0, y1) { n += 1 }
            return n
        }
        /// `n` boş sütundan yazıya kalan: yakın boşluk ve (alan engelle bittiyse) uzak boşluk çıkar.
        func usable(_ n: Int, cap: Int) -> Int { min(most, n - near - (n < cap ? far : 0)) }
        let cap = near + most + far
        if !iconLeft {
            let n = run(from: l - 1, step: -1, t, b, cap: cap)
            let room = usable(n, cap: cap)
            if room >= w { return (l - near - w, t, l - near, b, l - near - room, l - near) }
        }
        if !iconRight {
            let n = run(from: r, step: 1, t, b, cap: cap)
            let room = usable(n, cap: cap)
            if room >= w { return (r + near, t, r + near + w, b, r + near, r + near + room) }
        }
        let top = t - near - h
        if top >= 0, (top..<(t - near)).allSatisfy({ row($0, l, r) }) {
            let side = w / 2
            let nl = run(from: l - 1, step: -1, top, t - near, cap: side + far)
            let nr = run(from: r, step: 1, top, t - near, cap: side + far)
            let roomL = l - max(0, min(side, nl - (nl < side + far ? far : 0)))
            let roomR = r + max(0, min(side, nr - (nr < side + far ? far : 0)))
            return (l, top, r, t - near, roomL, roomR)
        }
        return nil
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
