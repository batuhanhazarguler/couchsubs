// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import CoreText
import Foundation

/// "Ekranı çevir" öğelerinin yerleşimi: çeviri özgün yazının birebir yerinde çizilsin, simgeleri hiç örtmesin
/// (Windows: ScreenFit.cs, Android: ScreenFit.kt; aynı kurallar). TV ve öbür çiziciler bunlara göre çizer:
/// - Çeviri yatayda özgün yazının kutusundan hiç taşmaz. Türkçe uzunsa önce yazı en çok %10 yatayda sıkışır, sonra yazı
///   boyu küçülür (`lastScale`/`minScale`), sonra satır kırılır ve kutu aşağı uzar; tek sözcük yine sığmıyorsa yazı `lastScale`'e
///   kadar küçülür (`lines`). Önceden kutu simgeye kadar yana genişliyordu; tuş simgesinin (△ ○ ✕ □, R2, L1) ve menü
///   simgesinin üstüne biniyor, hangi tuşa basılacağı görünmüyordu (#1203).
/// - `Item.room`: kenar payının gidebileceği yatay alan. Özgün yazının iki yanında en çok `edgeLines` satır yüksekliği;
///   zeminden belirgin ayrılan ilk noktadan (kumanda simgesi, menü simgesi, fotoğraf, başka yazı) satır yüksekliğinin
///   çeyreği önce biter; aynı satırdaki komşu öğeyle arası ortadan bölünür. Zemin rengi bilinmiyorsa kutunun kendisidir.
/// - Kutu yalnız yazının noktalarını kapsar: yazı tanıma kutusunun ucunda yazıdan ayrı duran simge (`tightened`,
///   `iconEdges`) kutunun dışında kalır.
/// - Hiza: alt alta dizilmiş kısa etiketlerin sağ kenarları aynıysa (sağdaki tuş simgelerine yaslı ipuçları) hepsi sağa
///   yaslıdır, sol kenarları aynıysa sola; aynı satırda en az üç etiket varsa (menü şeridinin sekmeleri) ortalıdır.
/// - Eş öğeler (aynı satırdaki sekmeler, alt alta menü satırları) aynı yazı boyunda: satır yükseklikleri ortancaya çekilir.
///   Önceden sığmayan sekme küçülüyor, şerit iki ayrı boyda görünüyordu (#859).
public enum ScreenFit {
    /// Simgeyle (ya da komşu yazıyla) kenar payı arasında bırakılan boşluk, satır yüksekliğinin katı.
    public static let gapLines = 0.25
    /// Kenar payı kutunun her yanında en çok bu kadar satır yüksekliği; yazının kendisi kutunun dışına hiç çıkmaz.
    public static let edgeLines = 0.3
    /// Eş öğelerin satır yükseklikleri en çok bu oranda farklıysa aynı boya çekilir.
    public static let sameLine = 0.15
    /// Bir sütunda zeminden bu kadar (en büyük renk bileşeni farkı) ayrılan nokta varsa orada simge/yazı başlar. Düşük:
    /// kumanda düğmesinin koyu halkası zemine yakındır; yanlış bulunan nokta yalnız kenar payını daraltır.
    public static let inkDistance = 32
    /// Kutunun ucundaki simgeyi yazıdan ayıran en dar boşluk, satır yüksekliğinin katı (`iconEdges`).
    public static let iconGapLines = 0.1
    /// Simge, yazının en uzun harfinden en az bu kat uzundur (kumanda düğmesi yazıdan büyük bir dairedir). Okunan yazı
    /// simgenin yerini açıklamıyorsa (sözcükten fazla parça ya da uçta okunmuş simge) `iconTaller` yeter, yoksa
    /// `iconTallerAlone` ve simge yazının hem üstüne hem altına taşmalı.
    public static let iconTaller = 1.1
    public static let iconTallerAlone = 1.5
    /// `iconEdges`'te zeminden (ortanca parlaklık) bu kadar ayrılan nokta yazı/simgedir. Yazıdan düşük: kumanda
    /// düğmesinin koyu ya da açık halkası zemine yakındır (GTA 6'da mor zeminde ~40), yalnız ortadaki "L1" yazının boyunda.
    public static let iconInk = 30

    /// Öğeler yerleşim bilgileriyle; kare yoksa olduğu gibi.
    public static func fitted(_ items: [ScreenTranslation.Item], frame: CGImage?) -> [ScreenTranslation.Item] {
        guard let frame, frame.width > 0, frame.height > 0, let pixels = GamePhonePixels(frame) else { return items }
        let aspect = Double(frame.width) / Double(frame.height)
        let luma = { (x: Int, y: Int) -> Int in
            let p = pixels.offset(x, y)
            return (299 * Int(pixels.bytes[p]) + 587 * Int(pixels.bytes[p + 1]) + 114 * Int(pixels.bytes[p + 2])) / 1000
        }
        let tight = tightened(items, frame: frame, aspect: aspect) { box, lineX, words in
            iconEdges(box, lineX: lineX, words: words, width: pixels.width, height: pixels.height, luma: luma)
        }
        let laid = uniform(aligned(tight, aspect: aspect), aspect: aspect)
        let color = { (x: Int, y: Int) -> (Int, Int, Int) in
            let p = pixels.offset(x, y)
            return (Int(pixels.bytes[p]), Int(pixels.bytes[p + 1]), Int(pixels.bytes[p + 2]))
        }
        let roomy = withRoom(laid, aspect: aspect, color: color) { (pixels.width, pixels.height) }
        return painted(roomy, width: pixels.width, height: pixels.height) { x, y in
            let c = color(x, y)
            return (c.0, c.1, c.2)
        }
    }

    /// Yerinde birebir çizim ölçüleri (`TextPainter`): özgün stilli her öğeye `paint` (yalnız yazı değişince; çağıran
    /// okuma turudur, her kare değil).
    static func painted(_ items: [ScreenTranslation.Item], width: Int, height: Int,
                        color: (Int, Int) -> TextPainter.RGB) -> [ScreenTranslation.Item] {
        let indices = items.indices.filter { takesPart(items[$0]) && items[$0].style != nil && items[$0].look != nil }
        guard !indices.isEmpty else { return items }
        let targets = indices.map { i in target(items[i]) }
        let paints = TextPainter.paints(targets, width: width, height: height, color: color)
        var result = items
        for (k, i) in indices.enumerated() where k < paints.count {
            result[i].paint = paints[k]
            // Kutunun ucunda simge varsa yazı simgeye yaslanır (#1266, #1267).
            if let side = paints[k].iconSide { result[i].look?.align = side }
        }
        return result
    }

    static func target(_ item: ScreenTranslation.Item) -> TextPainter.Target {
        TextPainter.Target(box: item.box, lineHeight: item.lineHeight, rows: item.paragraphs ? max(2, item.rows) : item.rows,
                           background: item.style!.background, foreground: item.style!.foreground,
                           upper: item.look!.upper, align: item.look!.align, words: TextPainter.words(item.source))
    }

    /// Konuşma satırı (#1224, #1255, #1259): konuşan adıyla başlar ("Lucia: Evet.") ya da küçük harf taşıyan tek satır olup
    /// cümle sonu noktalamasıyla biter ("Ne?", "Yoldan çık."). Oyunun altyazısı ekran yazısı olarak da okunabiliyor (menü
    /// durumunda altyazı alanı dışlanmaz); kısa replik etiket sayılıp özgün yazının dar ailesiyle çiziliyor, TV'de "dar ve
    /// basık" görünüyordu. Konuşma satırı hiçbir zaman dar aile almaz (`ScreenStyleLock.steady`). Menü sekmesi, düğme ve
    /// başlık böyle bitmez; çok satırlı görev/bilgi metni özgün görünüşünde kalır. TV (app.js isDialogue), Windows
    /// (ScreenFit.IsDialogue) ve Android (ScreenFit.isDialogue) aynı kuralı uygular.
    public static func isDialogue(_ text: String, rows: Int = 1) -> Bool {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return false }
        if SpeakerPrefix.split(line) != nil { return true }
        guard rows <= 1, !line.contains("\n"), line.contains(where: \.isLowercase) else { return false }
        let end = line.reversed().drop { "\"'”’»)]".contains($0) }.first
        return end.map { ".!?…".contains($0) } ?? false
    }

    static func isDialogue(_ item: ScreenTranslation.Item) -> Bool {
        isDialogue(item.translation, rows: item.paragraphs ? max(2, item.rows) : item.rows)
    }

    /// Yerleşime giren öğe: özgün stilli, telefon kartının ya da balonun parçası değil.
    public static func takesPart(_ item: ScreenTranslation.Item) -> Bool {
        item.look != nil && !ScreenTranslation.isCardPart(item) && !item.bubble
    }

    /// Kutu yalnız yazının noktalarını kapsar: kutunun ucunda, yazıdan satır yüksekliğinin %60'ından geniş boşlukla ayrılmış
    /// küçük (en çok bir buçuk satır yüksekliği genişliğinde) bir leke varsa o simgedir (yazı tanıma kutusu simgenin kenarını
    /// da alıyordu), kutunun dışında kalır. Yazıya daha yakın duran kumanda simgesi de (`iconEdges`: yazıdan uzun, aşağı
    /// yukarı kare bir leke; GTA 6 ayarlarındaki "LOADOUT (L1)", "(△) INTERACT") dışarıda kalır. Simgesi çeviride yerinde
    /// gösterilen öğeye dokunulmaz. `icons(box, lineX, words)`: kutunun ucundaki simgeden sonra yazının başladığı/bittiği
    /// yer (yalnız tek satırlık yazıda).
    static func tightened(_ items: [ScreenTranslation.Item], frame: CGImage, aspect: Double,
                          icons: ((TextBox, Double, [String]) -> (left: Double?, right: Double?))? = nil)
        -> [ScreenTranslation.Item] {
        var result = items
        for i in items.indices where takesPart(items[i]) && (items[i].icons ?? []).isEmpty {
            let box = items[i].box, lineX = items[i].lineHeight / aspect
            // Kutunun en az yarısı kalmalı; kalmıyorsa o kesim yanlıştır (koyu dokulu zemin), yapılmaz.
            func keeps(_ l: Double, _ r: Double) -> Bool { r - l >= 0.5 * (box.right - box.left) }
            var left = box.left, right = box.right
            let spans = ScreenTranslation.inkSpans(frame, box, gap: 0.6 * lineX)
            if spans.count >= 2 {
                var l = box.left, r = box.right
                if spans[spans.count - 1].right - spans[spans.count - 1].left <= 1.5 * lineX { r = spans[spans.count - 2].right }
                if spans[0].right - spans[0].left <= 1.5 * lineX, spans.count >= 3 || r == box.right { l = spans[1].left }
                if keeps(l, r) { left = l; right = r }
            }
            if items[i].rows <= 1, let edges = icons?(box, lineX, items[i].source.split(whereSeparator: \.isWhitespace).map(String.init)) {
                let l = max(left, edges.left ?? left), r = min(right, edges.right ?? right)
                if keeps(l, r) { left = l; right = r }
            }
            guard left != box.left || right != box.right else { continue }
            result[i].box = TextBox(left: left, top: box.top, right: right, bottom: box.bottom)
        }
        return result
    }

    /// Yazı tanıma kutusunun ucundaki kumanda/menü simgesi: kutunun yatay alanı, üstünden ve altından yarım kutu yüksekliği
    /// fazlasıyla taranır; zeminden (ortanca parlaklık) `iconInk`'ten çok ayrılan noktalar `iconGapLines`'tan geniş
    /// boşluklarla parçalara bölünür. Uçtaki parça aşağı yukarı kare (en/boy 0,6-1,8) ve öbür parçaların en uzunundan uzunsa
    /// simgedir: okunan yazı (`words`) o parçayı açıklamıyorsa `iconTaller` kat (uçtaki sözcük okunmuş simge: "O", "@",
    /// "L1"; ya da küçük harfsiz kısa etikette parça sayısı sözcüklerden çok: "LOADOUT" + simge), açıklıyorsa ya da yazı
    /// bilinmiyorsa `iconTallerAlone` kat ve hem üste hem alta taşarak ("come by" sözcüğü simge sanılmasın). Dönen: simge solda ise yazının başladığı, sağda ise bittiği yer
    /// (kareye oranla); yoksa nil. `luma(x, y)`: karenin noktasının parlaklığı (0-255), `width`/`height`: kare boyu
    /// (Windows: IconEdges, Android: iconEdges; aynı örnekleme).
    public static func iconEdges(_ box: TextBox, lineX: Double, words: [String]? = nil, width frameWidth: Int,
                                 height frameHeight: Int, luma: (Int, Int) -> Int) -> (left: Double?, right: Double?) {
        let fw = Double(frameWidth), fh = Double(frameHeight)
        let half = 0.5 * (box.bottom - box.top)
        let top = max(0, box.top - half), bottom = min(1, box.bottom + half)
        let left = max(0, box.left), right = min(1, box.right)
        let width = (right - left) * fw, height = (bottom - top) * fh
        guard width >= 8, height >= 6, frameWidth > 0, frameHeight > 0 else { return (nil, nil) }
        let columns = max(8, min(800, Int(width.rounded())))
        let rows = 24
        var cells = [Int](repeating: 0, count: columns * rows)
        for y in 0..<rows {
            let py = min(frameHeight - 1, Int(top * fh + (Double(y) + 0.5) * height / Double(rows)))
            for x in 0..<columns {
                let px = min(frameWidth - 1, Int(left * fw + (Double(x) + 0.5) * width / Double(columns)))
                cells[y * columns + x] = luma(px, py)
            }
        }
        let median = cells.sorted()[cells.count / 2]
        let ink = cells.map { abs($0 - median) > iconInk }
        let step = (right - left) / Double(columns)
        let blank = max(1, Int((iconGapLines * lineX / max(1e-9, step)).rounded(.up)))
        // Parça: [ilk sütun, son sütun, en üst satır, en alt satır].
        var spans: [[Int]] = []
        var open: [Int]? = nil
        var run = 0
        for x in 0..<columns {
            var first = -1, last = -1
            for y in 0..<rows where ink[y * columns + x] {
                if first < 0 { first = y }
                last = y
            }
            if first >= 0 {
                if var span = open {
                    span[1] = x
                    span[2] = min(span[2], first)
                    span[3] = max(span[3], last)
                    open = span
                } else {
                    open = [x, x, first, last]
                }
                run = 0
            } else if open != nil {
                run += 1
                if run > blank { spans.append(open!); open = nil; run = 0 }
            }
        }
        if let span = open { spans.append(span) }
        guard spans.count >= 2 else { return (nil, nil) }
        let cellWidth = width / Double(columns), cellHeight = height / Double(rows)
        let extra = words.map { words in
            spans.count > words.count && words.count <= 5 && !words.joined().contains(where: \.isLowercase)
        } ?? false
        func isIcon(_ span: [Int], _ others: ArraySlice<[Int]>, edge: String?) -> Bool {
            let reference = others.map { $0[3] - $0[2] + 1 }.max() ?? 0
            let tall = span[3] - span[2] + 1, wide = span[1] - span[0] + 1
            let shape = Double(wide) * cellWidth / (Double(tall) * cellHeight)
            guard reference > 0, (0.6...1.8).contains(shape) else { return false }
            if extra || edge.map(ButtonIcons.isIconToken) == true { return Double(tall) >= iconTaller * Double(reference) }
            let above = others.map { $0[2] }.min()!, below = others.map { $0[3] }.max()!
            return Double(tall) >= iconTallerAlone * Double(reference) && span[2] < above && span[3] > below
        }
        var start: Double? = isIcon(spans[0], spans.dropFirst(), edge: words?.first) ? left + Double(spans[1][0]) * step : nil
        var end: Double? = isIcon(spans[spans.count - 1], spans.dropLast(), edge: words?.last)
            ? left + Double(spans[spans.count - 2][1] + 1) * step : nil
        // İki parçalı kutuda ikisi birden simge olamaz.
        if start != nil, end != nil, spans.count < 3 { start = nil; end = nil }
        return (start, end)
    }

    private static func height(_ box: TextBox) -> Double { box.bottom - box.top }

    private static func rowOverlap(_ a: TextBox, _ b: TextBox) -> Double {
        max(0, min(a.bottom, b.bottom) - max(a.top, b.top)) / max(1e-9, min(height(a), height(b)))
    }

    /// Alt alta dizilmiş (aynı sütundaki) tek satırlık etiketlerin ortak hizası.
    static func aligned(_ items: [ScreenTranslation.Item], aspect: Double) -> [ScreenTranslation.Item] {
        let labels = items.indices.filter { takesPart(items[$0]) && items[$0].rows <= 1 }
        var result = items
        for i in labels {
            let box = items[i].box, tolerance = 0.5 * items[i].lineHeight / aspect
            let column = labels.filter { j in
                j != i && rowOverlap(box, items[j].box) == 0
                    && abs((box.top + box.bottom) - (items[j].box.top + items[j].box.bottom)) / 2 <= 8 * items[i].lineHeight
            }
            let rights = column.filter { abs(items[$0].box.right - box.right) <= tolerance && abs(items[$0].box.left - box.left) > tolerance }
            let lefts = column.filter { abs(items[$0].box.left - box.left) <= tolerance && abs(items[$0].box.right - box.right) > tolerance }
            // Aynı satırda en az iki eşi olan etiket şeridin sekmesidir: sekme yazısı kendi yerinin ortasındadır.
            let row = labels.filter { j in j != i && rowOverlap(box, items[j].box) >= 0.5 }
            if rights.count >= 2, rights.count > lefts.count { result[i].look?.align = .right }
            else if lefts.count >= 2 { result[i].look?.align = .left }
            else if row.count >= 2 { result[i].look?.align = .center }
            else if column.isEmpty, row.isEmpty, let lone = loneAlign(box, rows: items[i].rows) { result[i].look?.align = lone }
        }
        return result
    }

    /// Ekranın yatay ortasından en çok bu kadar (kareye oranla) uzaktaki yalnız satır ortalıdır.
    public static let centerTolerance = 0.02

    /// Komşusu olmayan tek satırın hizası (#1264): ortası ekranın ortasındaysa (görev yazısı "Go to the motel kitchen with
    /// Lucia", altyazı gibi ortalı) ortalı. Tek satırın kendi kutusundan hiza çıkmıyor, sola yaslı sayılıyordu; Türkçesi
    /// kısa olunca yazı kutunun soluna kayıyor, sağında boş zemin kalıyordu. Değilse nil (hiza değişmez).
    public static func loneAlign(_ box: TextBox, rows: Int) -> TextLook.Align? {
        guard rows <= 1, abs((box.left + box.right) / 2 - 0.5) <= centerTolerance else { return nil }
        return .center
    }

    /// Eş öğeler (aynı satırda ya da aynı sütunda, BÜYÜK HARF/kalınlık aynı, satır yüksekliği yakın) aynı boyda.
    static func uniform(_ items: [ScreenTranslation.Item], aspect: Double) -> [ScreenTranslation.Item] {
        let labels = items.indices.filter { takesPart(items[$0]) && items[$0].rows <= 1 }
        var parent = Dictionary(uniqueKeysWithValues: labels.map { ($0, $0) })
        func root(_ i: Int) -> Int { var i = i; while parent[i]! != i { i = parent[i]! }; return i }
        for a in labels {
            for b in labels where b > a {
                let x = items[a], y = items[b]
                guard x.look?.upper == y.look?.upper, x.look?.bold == y.look?.bold,
                      abs(x.lineHeight - y.lineHeight) <= sameLine * max(x.lineHeight, y.lineHeight) else { continue }
                let tolerance = 0.5 * max(x.lineHeight, y.lineHeight) / aspect
                let sameRow = rowOverlap(x.box, y.box) >= 0.5
                let sameColumn = (abs(x.box.left - y.box.left) <= tolerance || abs(x.box.right - y.box.right) <= tolerance)
                    && abs(x.box.top - y.box.top) <= 3 * max(x.lineHeight, y.lineHeight)
                if sameRow || sameColumn { parent[root(a)] = root(b) }
            }
        }
        var result = items
        for members in Dictionary(grouping: labels, by: root).values where members.count >= 2 {
            let lines = members.map { items[$0].lineHeight }.sorted()
            let median = lines[lines.count / 2]
            for i in members { result[i].lineHeight = median }
        }
        return result
    }

    /// Her öğenin kenar payının gidebileceği yatay alan (`Item.room`). `color(x, y)`: karenin noktası (piksel), `size`:
    /// kare boyu.
    static func withRoom(_ items: [ScreenTranslation.Item], aspect: Double, color: (Int, Int) -> (Int, Int, Int),
                         size: () -> (Int, Int)) -> [ScreenTranslation.Item] {
        let (frameWidth, frameHeight) = size()
        var result = items
        for i in items.indices where takesPart(items[i]) {
            let item = items[i], box = item.box
            let lineX = item.lineHeight / aspect
            let gap = gapLines * lineX
            let background = item.style.flatMap { SpeakerColors.rgb($0.background) }
                .map { (Int($0.red * 255), Int($0.green * 255), Int($0.blue * 255)) }
            // Zemin bilinmiyorsa yandaki simge aranamaz: kenar payı da kutunun içinde kalır.
            let edgeX = background == nil ? 0 : edgeLines * lineX
            var left = max(0, box.left - edgeX), right = min(1, box.right + edgeX)
            // Aynı satırdaki komşu öğeyle arası ortadan bölünür: iki kutunun kenar payı birbirine binmez.
            for (j, other) in items.enumerated() where j != i && rowOverlap(box, other.box) >= 0.3 {
                if other.box.left >= box.right - 1e-9 { right = min(right, (box.right + other.box.left) / 2) }
                if other.box.right <= box.left + 1e-9 { left = max(left, (other.box.right + box.left) / 2) }
            }
            if let background {
                let y0 = Int(((box.top + 0.2 * height(box)) * Double(frameHeight)).rounded())
                let y1 = Int(((box.bottom - 0.2 * height(box)) * Double(frameHeight)).rounded())
                let rows = stride(from: y0, through: max(y0, y1), by: max(1, (y1 - y0) / 6)).map { min(frameHeight - 1, max(0, $0)) }
                func scan(from start: Double, to end: Double) -> Double? {
                    let a = Int((start * Double(frameWidth)).rounded()), b = Int((end * Double(frameWidth)).rounded())
                    guard a != b else { return nil }
                    let step = b > a ? 1 : -1
                    var ground = background
                    for x in stride(from: a, to: b, by: step) where x >= 0 && x < frameWidth {
                        var far = 0
                        var sum = (0, 0, 0)
                        for y in rows {
                            let c = color(x, y)
                            far = max(far, abs(c.0 - ground.0), abs(c.1 - ground.1), abs(c.2 - ground.2))
                            sum = (sum.0 + c.0, sum.1 + c.1, sum.2 + c.2)
                        }
                        if far > inkDistance { return Double(x) / Double(frameWidth) }
                        // Degrade zeminde (yarı saydam şerit, harita) zemin rengi yavaşça izlenir.
                        let n = rows.count
                        ground = ((ground.0 * 7 + sum.0 / n) / 8, (ground.1 * 7 + sum.1 / n) / 8, (ground.2 * 7 + sum.2 / n) / 8)
                    }
                    return nil
                }
                // Tarama kutunun iki piksel dışından başlar: yazı tanıma kutusu harfin kenarında biter.
                let edge = 2.0 / Double(frameWidth)
                // Simgeyle arada `gap` kalsın diye tarama kenar payından `gap` kadar öteye gider.
                if let ink = scan(from: box.right + edge, to: min(1, right + gap)) { right = min(right, ink - gap) }
                if let ink = scan(from: box.left - edge, to: max(0, left - gap)) { left = max(left, ink + gap) }
            }
            result[i].room = TextBox(left: min(box.left, left), top: box.top, right: max(box.right, right), bottom: box.bottom)
        }
        return result
    }
    // MARK: - Yerinde birebir çizim (TV fitExact ile aynı sıra; `TextPaint` gelen öğeler)

    /// Birebir çizilecek bir öğe (piksel, çizilen ekranda). `left/top/right/bottom`: örtü kutusu; `growLeft`/`growRight`:
    /// kutunun yana uzayabileceği sınırlar (uzayamıyorsa örtünün kenarı); `line`: özgün satır yüksekliği; `pitch`: özgün
    /// satır aralığı.
    public struct ExactInput: Equatable, Sendable {
        public var text: String
        public var left: Double, top: Double, right: Double, bottom: Double
        public var growLeft: Double, growRight: Double
        public var line: Double
        public var pitch: Double
        public var rows: Int
        public var align: TextLook.Align
        public var group: Int?

        public init(text: String, left: Double, top: Double, right: Double, bottom: Double, growLeft: Double? = nil,
                    growRight: Double? = nil, line: Double, pitch: Double? = nil, rows: Int = 1, align: TextLook.Align = .left,
                    group: Int? = nil) {
            self.text = text
            self.left = left
            self.top = top
            self.right = right
            self.bottom = bottom
            self.growLeft = min(left, growLeft ?? left)
            self.growRight = max(right, growRight ?? right)
            self.line = line
            self.pitch = pitch ?? line
            self.rows = rows
            self.align = align
            self.group = group
        }

        /// Ekrana oranlı öğeden (`Item.paint` olmalı) `width` x `height` piksellik çizim alanına. Örtmeyen kipte
        /// (`TextPaint.mode`) yazı `spot`'a, `spotRoom` içinde dizilir; ikizde yazı boyu `scale` katında. Yanına yazılan
        /// Türkçe özgüne yaslanır (solundaysa sağa, sağındaysa sola).
        public init?(_ item: ScreenTranslation.Item, width: Double, height: Double) {
            guard let paint = item.paint else { return nil }
            let free = paint.mode != .cover ? paint.spot : nil
            let box = free ?? paint.cover
            let room = free != nil ? paint.spotRoom : paint.grow
            let scale = paint.mode == .twin ? paint.scale : 1
            var align = item.look?.align ?? .left
            if paint.mode == .beside {
                if box.right <= paint.cover.left { align = .right } else if box.left >= paint.cover.right { align = .left }
            }
            self.init(text: item.translation, left: box.left * width, top: box.top * height, right: box.right * width,
                      bottom: box.bottom * height, growLeft: room.map { $0.left * width }, growRight: room.map { $0.right * width },
                      line: max(1, item.lineHeight * height * scale), pitch: max(1, paint.pitch * height * scale),
                      rows: item.paragraphs ? max(2, item.rows) : item.rows, align: align,
                      group: paint.mode == .cover ? paint.group : nil)
        }
    }

    /// Bir öğenin çizimi: kutu (piksel), yazı boyu, satırlar ve satır aralığı. Kutu opak, köşesiz, gölgesiz çizilir;
    /// satırlar `lineHeight` aralıkla, hizaya göre; tek satır kutunun dikey ortasında.
    public struct ExactPlacement: Equatable, Sendable {
        public var left: Double, top: Double, width: Double, height: Double
        public var fontSize: Double
        public var lines: [String]
        /// Satırların aralığı: k. satır `top + k * lineHeight`'tan başlar.
        public var lineHeight: Double
        /// Bir satırın yüksekliği: satır bu yüksekliğin dikey ortasında (özgün satırın yerinde) çizilir.
        public var rowHeight: Double
    }

    /// Yazı boyu özgün satır yüksekliğinin bu katı (TV, Mac, Windows, iPhone, Android aynı).
    public static let exactFont = 0.95
    /// Sığmayan etiket (ve grubu) yazı boyunda en çok bu orana kadar küçülür; sonra satır kırılır.
    public static let exactGroupMin = 0.7
    /// Çok satırlı yazı en çok bu orana kadar küçülür; sonra kutu aşağı uzar.
    public static let exactParagraphMin = 0.8
    /// Satır kırılan etiketin satır aralığı, yazı boyunun katı.
    public static let exactWrapGap = 1.2

    /// Birebir yerleşim. Sırasıyla: (1) grubun (aynı listedeki etiketler) yazı boyu üyelerinin özgün boyunun ortancası;
    /// (2) sığmayan etiket hizasının açık tarafındaki boş alana uzar, yazı boyu sabit; (3) boş alan da yetmezse grubun
    /// tamamı birlikte küçülür (en çok `exactGroupMin`); (4) yine sığmayan etiketin satırı kırılır, kutu aşağı uzar; tek
    /// sözcük yine sığmıyorsa yalnız o küçülür. Çok satırlı yazı özgün genişlik ve satır aralığında kalır; sığmazsa
    /// `exactParagraphMin`'e kadar küçülür, sonra aşağı uzar. Yazı hiçbir zaman "…" ile kesilmez. `measure(text, size)`:
    /// yazının çizicinin kendi yazı tipiyle genişliği.
    public static func exact(_ items: [ExactInput], measure: (String, Double) -> Double) -> [ExactPlacement] {
        var base = items.map { exactFont * $0.line }
        var members: [Int: [Int]] = [:]
        for (i, item) in items.enumerated() { if let g = item.group { members[g, default: []].append(i) } }
        for list in members.values where list.count >= 2 {
            let sizes = list.map { base[$0] }.sorted()
            let median = sizes[sizes.count / 2]
            for i in list { base[i] = median }
        }
        func isLabel(_ item: ExactInput) -> Bool { item.rows <= 1 && !item.text.contains("\n") }
        let natural = items.indices.map { i in isLabel(items[i]) ? measure(items[i].text, base[i]) : 0 }
        var scale = items.indices.map { i -> Double in
            guard isLabel(items[i]), natural[i] > 0 else { return 1 }
            return max(exactGroupMin, min(1, (items[i].growRight - items[i].growLeft) / natural[i]))
        }
        for list in members.values where list.count >= 2 {
            let least = list.map { scale[$0] }.min() ?? 1
            for i in list { scale[i] = least }
        }
        return items.indices.map { i in
            let item = items[i]
            let coverWidth = item.right - item.left, coverHeight = item.bottom - item.top
            guard isLabel(item) else { return exactParagraph(item, base: base[i], measure: measure) }
            var font = base[i] * scale[i]
            let avail = item.growRight - item.growLeft
            var width = natural[i] * scale[i]
            var lines = [item.text]
            var gap = coverHeight
            if width > avail + 0.5 {
                let words = item.text.split(whereSeparator: \.isWhitespace).map(String.init)
                let widestWord = words.map { measure($0, font) }.max() ?? width
                if words.count >= 2 {
                    // Satır kırılır; satıra sığmayan sözcük varsa yazı yalnız bu öğede küçülür (yana taşmaz).
                    if widestWord > avail + 0.5 { font *= avail / widestWord }
                    lines = exactWrap(words, limit: avail) { measure($0, font) }
                } else {
                    font *= avail / max(1e-9, width)
                }
                width = lines.map { measure($0, font) }.max() ?? avail
                if lines.count > 1 { gap = max(coverHeight / Double(lines.count), font * exactWrapGap) }
            }
            let boxWidth = max(coverWidth, min(avail, width))
            var left: Double
            switch item.align {
            case .right: left = item.right - boxWidth
            case .left: left = item.left
            case .center: left = item.left - (boxWidth - coverWidth) / 2
            }
            left = min(max(left, item.growLeft), item.growRight - boxWidth)
            return ExactPlacement(left: left, top: item.top, width: boxWidth,
                                  height: max(coverHeight, Double(lines.count) * gap), fontSize: font, lines: lines,
                                  lineHeight: gap, rowHeight: gap)
        }
    }

    /// Çok satırlı yazı: özgün genişlik ve satır aralığı; sığmazsa `exactParagraphMin`'e kadar küçülür, sonra aşağı uzar.
    private static func exactParagraph(_ item: ExactInput, base: Double,
                                       measure: (String, Double) -> Double) -> ExactPlacement {
        let coverWidth = item.right - item.left, coverHeight = item.bottom - item.top
        var factor = 1.0
        // Özgün bir satırın yüksekliği (kenar payıyla): son satır tam aralık değil, bu kadar yer kaplar.
        let row = max(base * 1.05, coverHeight - Double(max(1, item.rows) - 1) * item.pitch)
        func layout() -> (font: Double, lines: [String], gap: Double) {
            let font = base * factor
            let gap = max(item.pitch, base * 1.05) * factor
            let lines = item.text.components(separatedBy: "\n").flatMap { paragraph -> [String] in
                let words = paragraph.split(whereSeparator: \.isWhitespace).map(String.init)
                return words.isEmpty ? [""] : exactWrap(words, limit: coverWidth) { measure($0, font) }
            }
            return (font, lines, gap)
        }
        var laid = layout()
        func tall(_ laid: (font: Double, lines: [String], gap: Double)) -> Double {
            Double(laid.lines.count - 1) * laid.gap + row * factor
        }
        while tall(laid) > coverHeight + 1, factor > exactParagraphMin + 1e-6 {
            factor = max(exactParagraphMin, ((factor - 0.05) * 100).rounded() / 100)
            laid = layout()
        }
        // Satıra sığmayan tek sözcük: yazı küçülür (yana taşmaz).
        let widest = laid.lines.map { measure($0, laid.font) }.max() ?? 0
        if widest > coverWidth + 0.5 {
            factor *= coverWidth / widest
            laid = layout()
        }
        return ExactPlacement(left: item.left, top: item.top, width: coverWidth, height: max(coverHeight, tall(laid)),
                              fontSize: laid.font, lines: laid.lines, lineHeight: laid.gap, rowHeight: row * factor)
    }

    /// Sözcükler satırlara: her satır `limit`'e kadar dolar.
    static func exactWrap(_ words: [String], limit: Double, measure: (String) -> Double) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in words {
            let next = current.isEmpty ? word : current + " " + word
            if !current.isEmpty, measure(next) > limit + 0.5 {
                lines.append(current)
                current = word
            } else {
                current = next
            }
        }
        if !current.isEmpty || lines.isEmpty { lines.append(current) }
        return lines
    }

    // MARK: - Çizicilerin ortak satır yerleşimi (TV fitStyled ile aynı sıra)

    /// Bir çevirinin çizimi: satırları, yazı boyunun ölçeği ve yatay sıkıştırması. Yazının alanı her zaman özgün yazının
    /// kutusudur: yana hiç genişlemez.
    public struct Lines: Equatable, Sendable {
        public var lines: [String]
        /// Yalnız yatay ölçek (1 = sıkıştırma yok; yalnız en çok iki sözcüklük etikette, en az `firstSqueeze`).
        public var squeeze: Double
        /// Yazı boyunun ölçeği (1 = özgün satır yüksekliğinden gelen boy). Ekran yazısı alt sınırının (`floorShare`) altına
        /// inmez; kısa özgün satırda 1'den büyük olabilir.
        public var scale: Double
    }

    /// Yatay sıkıştırma yalnız en çok iki sözcüklük tek satırlık etikette (menü sekmesi, düğme) ve en çok %10. Daha uzun
    /// cümle hiç sıkışmaz: önceden %15'e kadar sıkışıyor, kısa cümleler "dar ve basık" görünüyordu.
    public static let firstSqueeze = 0.9
    /// Sığmayan çok satırlı yazı (açıklama, paragraf) önce bu orana kadar küçülür, sonra satır eklenir.
    public static let minScale = 0.6
    /// Sığmayan tek satırlık etiket bu orana kadar küçülür, sonra satır kırılır (menüde alttaki satırın üstüne binmesin);
    /// satır kırılsa da sığmayan tek sözcük de en çok bu orana kadar küçülür.
    public static let lastScale = 0.5
    /// Ekran yazısının en küçük boyu, konuşma altyazısının (öntanımlı `subtitleFont`, 1080 satırlık ekranda) bu kadarı;
    /// ekranla ölçeklenir. Kısa özgün satırın boyuna kilitlenmez: gerekirse kutu aşağı büyür.
    public static let floorShare = 0.6
    public static let subtitleFont = 46.0

    /// Ekran yazısı alt sınırının özgün yazı boyuna oranı (`lines`'ın `floor`'u): `fontSize` özgün satırdan gelen boy,
    /// `screenHeight` çizilen ekranın yüksekliği (aynı birimde).
    public static func floor(fontSize: Double, screenHeight: Double) -> Double {
        fontSize > 0 ? floorShare * subtitleFont * screenHeight / 1080 / fontSize : 0
    }

    /// Çeviriyi özgün yazının alanına (genişliği `width`, piksel) yerleştirir; alan yana hiç genişlemez. `measure`: yazının
    /// çizicinin kendi yazı tipiyle, özgün yazı boyunda genişliği (piksel). `rows`: özgün satır sayısı; çok satırlı yazı o
    /// kadar satıra bölünür. `floor`: yazı boyunun en küçük ölçeği (`floor(fontSize:screenHeight:)`). Sığmazsa sırasıyla:
    /// en çok iki sözcüklük etikette yatayda en çok %10 sıkıştırma, yazı boyunun küçülmesi (tek satırlık etiket `lastScale`'e,
    /// çok satırlı yazı `minScale`'e kadar, alt sınırın altına inmeden), satır kırma (kutu aşağı uzar), tek sözcük yine
    /// sığmıyorsa `lastScale`'e kadar küçülme.
    public static func lines(_ text: String, width: Double, rows: Int, floor floorScale: Double = 0,
                             measure: (String) -> Double) -> Lines {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var lines = text.components(separatedBy: "\n")
        let count = max(rows, lines.count)
        let squeezable = count <= 1 && words.count <= 2
        // Alt sınır yalnız cümlede (en az üç sözcük ya da çok satırlı yazı): kısa etiket simgeye taşmasın diye küçülebilir.
        let floor = squeezable ? 0 : floorScale
        let limit = squeezable ? width / firstSqueeze : width
        if lines.count == 1, count > 1 {
            // Sözcükler eşit uzunlukta satırlara, en çok özgün satır sayısı kadar.
            let target = max(limit, measure(text) / Double(count))
            lines = wrapped(words, limit: target, cap: count, measure: measure)
        }
        var widest = lines.map(measure).max() ?? 0
        let start = max(1, floor)
        var scale = start
        if widest * start > limit {
            let least = max(floor, count > 1 ? minScale : lastScale)
            if widest * least > limit, words.count >= 2 {
                lines = lines.flatMap { line in
                    wrapped(line.split(whereSeparator: \.isWhitespace).map(String.init), limit: limit / least, cap: .max,
                            measure: measure)
                }
                widest = lines.map(measure).max() ?? 0
            }
            // Satıra sığmayan tek sözcük alt sınırın da altına küçülür: yana taşmamak önce gelir.
            scale = max(lastScale, min(start, limit / max(1e-9, widest)))
        }
        let squeeze = squeezable && widest > 0 ? max(firstSqueeze, min(1, width / (widest * scale))) : 1
        return Lines(lines: lines, squeeze: squeeze, scale: scale)
    }

    /// Sözcükler satırlara: her satır `limit`'e kadar dolar, en çok `cap` satır (sonuncusu kalanı alır).
    private static func wrapped(_ words: [String], limit: Double, cap: Int, measure: (String) -> Double) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in words {
            let next = current.isEmpty ? word : current + " " + word
            if !current.isEmpty, measure(next) > limit, lines.count < cap - 1 { lines.append(current); current = word }
            else { current = next }
        }
        if !current.isEmpty || lines.isEmpty { lines.append(current) }
        return lines
    }

    /// Kutunun sol ve sağ kenar payı (piksel): en çok `pad`, kenar payı alanının (`Item.room`) dışına çıkmadan. Alan
    /// bilinmiyorsa kenar payı yoktur: yandaki simgenin yeri bilinmez.
    public static func pads(left: Double, width: Double, room: (left: Double, right: Double)?, pad: Double)
        -> (left: Double, right: Double) {
        guard let room else { return (0, 0) }
        return (min(pad, max(0, left - room.left)), min(pad, max(0, room.right - (left + width))))
    }
    /// Mac ve iPhone çizicilerinin ölçüsü: sistem yazı tipiyle (SwiftUI `.system`) yazının genişliği. Kalın değilse
    /// çiziciler yarı kalın çizer; düz yazı tipiyle ölçülüp %4 pay bırakılır.
    public static func textWidth(_ text: String, size: CGFloat, bold: Bool) -> CGFloat {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) * (bold ? 1 : 1.04)
    }
}
