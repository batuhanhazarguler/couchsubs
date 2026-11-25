// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import ImageIO
import SwiftUI

/// Yerinde birebir çizim (Mac yayın penceresi ve iPhone önizlemesi ortak; TV placeExact, Windows ScreenTextCanvas ve Android
/// PhoneSubtitleActivity ile aynı yerleşim: `ScreenFit.exact`). Kip (`TextPaint.mode`):
/// - örtme: kareden ölçülen örtü kutusu tam sınırında, opak, köşesiz ve gölgesiz; zemin düz renk ya da degrade.
/// - yanına yazma: kutu yok; Türkçe özgün yazının yanında, özgün renk ve stilde, okunurluk için yumuşak konturla.
/// - ikiz: özgün panel örtülmez; aynı zemin, köşe, kuyruk ve kişi resmiyle küçük bir ikiz panel, genişliği içeriğe göre.
/// Türkçe özgün renk, kalınlık, hiza ve satır aralığıyla. Grup aynı boyda, uzun çeviri boş tarafa uzar; yazı kesilmez.
/// `items`: `paint`'i olan öğeler.
struct ExactScreenText: View {
    let items: [ScreenTranslation.Item]
    let size: CGSize

    var body: some View {
        let shown = items.filter { $0.paint != nil }
        let inputs = shown.compactMap { ScreenFit.ExactInput($0, width: size.width, height: size.height) }
        // Ölçü sistem yazı tipiyle; grupta kalın öğe varsa kalın ölçülür (geniş ölçü yazıyı hiç taşırmaz).
        let bold = shown.contains { $0.look?.bold == true }
        let placed = ScreenFit.exact(inputs) { text, fontSize in
            Double(ScreenFit.textWidth(text, size: CGFloat(fontSize), bold: bold))
        }
        let twins = Self.twins(shown, placed, size: size)
        ZStack(alignment: .topLeading) {
            ForEach(Array(twins.enumerated()), id: \.offset) { _, twin in
                Self.panel(twin)
            }
            ForEach(Array(zip(shown.indices, placed)), id: \.0) { index, place in
                Self.block(shown[index], place)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// İkiz panel (piksel): kutusu, köşe yarıçapı, zemini, kuyruğu ve kişi resmi.
    struct Twin {
        var frame: CGRect
        var radius: CGFloat
        var fill: Color
        var tail: String?
        var portrait: (image: CGImage, frame: CGRect)?
    }

    /// Aynı ikiz kutusunu paylaşan öğeler tek panel: genişliği içeriğe göre (en sağdaki yazı ya da resim + sol iç boşluk),
    /// yüksekliği ikizinki.
    static func twins(_ items: [ScreenTranslation.Item], _ placed: [ScreenFit.ExactPlacement], size: CGSize) -> [Twin] {
        var result: [Twin] = []
        var seen: [TextBox] = []
        for (i, item) in items.enumerated() where i < placed.count {
            guard let paint = item.paint, paint.mode == .twin, let box = paint.twin, !seen.contains(box) else { continue }
            seen.append(box)
            let members = items.indices.filter { $0 < placed.count && items[$0].paint?.twin == box }
            let left = box.left * size.width
            let pad = max(0, (members.map { placed[$0].left }.min() ?? left) - left)
            var right = members.map { placed[$0].left + placed[$0].width }.max() ?? box.right * size.width
            var portrait: (image: CGImage, frame: CGRect)?
            if let at = paint.portraitTwin, let image = image(paint.portraitImage) {
                let frame = CGRect(x: at.left * size.width, y: at.top * size.height, width: (at.right - at.left) * size.width,
                                   height: (at.bottom - at.top) * size.height)
                portrait = (image, frame)
                right = max(right, frame.maxX)
            }
            let frame = CGRect(x: left, y: box.top * size.height, width: max(1, right + pad - left),
                               height: (box.bottom - box.top) * size.height)
            result.append(Twin(frame: frame, radius: paint.radius * size.height, fill: color(paint.background) ?? .white,
                               tail: paint.tail, portrait: portrait))
        }
        return result
    }

    @ViewBuilder
    static func panel(_ twin: Twin) -> some View {
        let r = twin.radius
        ZStack(alignment: .topLeading) {
            Bubble(radius: r, tail: twin.tail)
                .fill(twin.fill)
                .frame(width: twin.frame.width, height: twin.frame.height)
            if let tail = twin.tail {
                Tail(right: tail == "right", size: r)
                    .fill(twin.fill)
                    .frame(width: twin.frame.width, height: twin.frame.height + 0.6 * r)
            }
            if let portrait = twin.portrait {
                Image(decorative: portrait.image, scale: 1)
                    .resizable()
                    .frame(width: portrait.frame.width, height: portrait.frame.height)
                    .clipShape(Ellipse())
                    .offset(x: portrait.frame.minX - twin.frame.minX, y: portrait.frame.minY - twin.frame.minY)
            }
        }
        .offset(x: twin.frame.minX, y: twin.frame.minY)
    }

    /// Yuvarlak köşeli panel; kuyruklu alt köşe köşeli (macOS 13 / iOS 16: UnevenRoundedRectangle yok).
    struct Bubble: Shape {
        let radius: CGFloat
        let tail: String?

        func path(in rect: CGRect) -> Path {
            let r = min(radius, rect.width / 2, rect.height / 2)
            let bl = tail == "left" ? 0 : r, br = tail == "right" ? 0 : r
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90),
                        endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
            if br > 0 {
                path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0),
                            endAngle: .degrees(90), clockwise: false)
            }
            path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
            if bl > 0 {
                path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90),
                            endAngle: .degrees(180), clockwise: false)
            }
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180),
                        endAngle: .degrees(270), clockwise: false)
            path.closeSubpath()
            return path
        }
    }

    /// Balonun kuyruğu: alt köşeden aşağı küçük üçgen.
    struct Tail: Shape {
        let right: Bool
        let size: CGFloat

        func path(in rect: CGRect) -> Path {
            let bottom = rect.maxY - 0.6 * size
            let x = right ? rect.maxX : rect.minX, inward: CGFloat = right ? -size : size
            var path = Path()
            path.move(to: CGPoint(x: x, y: bottom - 1))
            path.addLine(to: CGPoint(x: x + inward, y: bottom - 1))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    @ViewBuilder
    static func block(_ item: ScreenTranslation.Item, _ place: ScreenFit.ExactPlacement) -> some View {
        let mode = item.paint?.mode ?? .cover
        let alignment: Alignment = switch mode == .beside ? besideAlign(item) : item.look?.align {
        case .center: .center
        case .right: .trailing
        default: .leading
        }
        let foreground = color(item.style?.foreground) ?? .white
        let halo = outline(item.style?.foreground)
        ZStack(alignment: .topLeading) {
            ForEach(Array(place.lines.enumerated()), id: \.offset) { k, text in
                Text(verbatim: text)
                    .font(.system(size: place.fontSize, weight: item.look?.bold == true ? .bold : .regular)
                        .width(item.look?.condensed == true ? .condensed : .standard))
                    .foregroundStyle(foreground)
                    .shadow(color: mode == .beside ? halo : .clear, radius: mode == .beside ? max(1, place.fontSize * 0.08) : 0)
                    .shadow(color: mode == .beside ? halo : .clear, radius: 0, x: 0, y: mode == .beside ? 1 : 0)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: place.width, height: place.rowHeight, alignment: alignment)
                    .offset(y: CGFloat(k) * place.lineHeight)
            }
        }
        .frame(width: place.width, height: place.height, alignment: .topLeading)
        .background(mode == .cover ? fill(item) : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
        .offset(x: place.left, y: place.top)
    }

    /// Yanına yazılan Türkçe özgüne yaslanır (ScreenFit.ExactInput ile aynı).
    static func besideAlign(_ item: ScreenTranslation.Item) -> TextLook.Align? {
        guard let paint = item.paint, let spot = paint.spot else { return item.look?.align }
        if spot.right <= paint.cover.left { return .right }
        if spot.left >= paint.cover.right { return .left }
        return item.look?.align
    }

    /// Yanına yazmada okunurluk konturu: açık yazıda koyu, koyu yazıda açık.
    static func outline(_ hex: String?) -> Color {
        guard let hex, let rgb = SpeakerColors.rgb(hex) else { return .black.opacity(0.85) }
        return 0.299 * rgb.red + 0.587 * rgb.green + 0.114 * rgb.blue > 0.5 ? .black.opacity(0.85) : .white.opacity(0.85)
    }

    /// Zemin: düz renk ya da iki uçlu doğrusal degrade (sol→sağ ya da üst→alt).
    static func fill(_ item: ScreenTranslation.Item) -> LinearGradient {
        let first = color(item.paint?.background) ?? .black
        guard let paint = item.paint, let second = color(paint.background2), let direction = paint.direction else {
            return LinearGradient(colors: [first, first], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [first, second], startPoint: direction == .horizontal ? .leading : .top,
                              endPoint: direction == .horizontal ? .trailing : .bottom)
    }

    static func color(_ hex: String?) -> Color? {
        guard let hex, let rgb = SpeakerColors.rgb(hex) else { return nil }
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// PNG data: adresinden görüntü.
    static func image(_ url: String?) -> CGImage? {
        guard let url, let comma = url.firstIndex(of: ","), let data = Data(base64Encoded: String(url[url.index(after: comma)...])),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
