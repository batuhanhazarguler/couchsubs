// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// Yerinde birebir çizim (Mac yayın penceresi ve iPhone önizlemesi ortak; TV placeExact, Windows ScreenTextCanvas ve Android
/// PhoneSubtitleActivity ile aynı yerleşim: `ScreenFit.exact`). Kareden ölçülen (`TextPaint`) örtü kutusu tam sınırında,
/// opak, köşesiz ve gölgesiz; zemin düz renk ya da degrade; Türkçe özgün renk, kalınlık, hiza ve satır aralığıyla. Grup
/// aynı boyda, uzun çeviri boş tarafa uzar; yazı kesilmez. `items`: `paint`'i olan öğeler.
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
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(shown.indices, placed)), id: \.0) { index, place in
                Self.block(shown[index], place)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    static func block(_ item: ScreenTranslation.Item, _ place: ScreenFit.ExactPlacement) -> some View {
        let alignment: Alignment = switch item.look?.align {
        case .center: .center
        case .right: .trailing
        default: .leading
        }
        ZStack(alignment: .topLeading) {
            ForEach(Array(place.lines.enumerated()), id: \.offset) { k, text in
                Text(verbatim: text)
                    .font(.system(size: place.fontSize, weight: item.look?.bold == true ? .bold : .regular)
                        .width(item.look?.condensed == true ? .condensed : .standard))
                    .foregroundStyle(color(item.style?.foreground) ?? .white)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: place.width, height: place.rowHeight, alignment: alignment)
                    .offset(y: CGFloat(k) * place.lineHeight)
            }
        }
        .frame(width: place.width, height: place.height, alignment: .topLeading)
        .background(fill(item))
        .offset(x: place.left, y: place.top)
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
}
