// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import UIKit

// Yeni arayüzün ortak bileşenleri, iPhone karşılığı (Mac: mac/CouchSubs/UI/Yeni/DSComponents.swift; aynı adlar, aynı
// ölçüler). Telefonda üzerine gelme yok; yükseklikler Dinamik Yazı büyüdüğünde kesilmesin diye en az değer olarak verilir.

// MARK: Düğmeler

/// Düğme türleri: ana (amber, ekranda tek), ikincil (yüzey, ince halka), durdur/tehlikeli (kırmızı tonlu), hayalet (amber
/// yazılı düz). Hepsi tam yuvarlak, en az 48 yükseklik, alt çizgisiz. İşlem sürerken çağıran `.disabled(true)` verir.
struct DSButtonStyle: ButtonStyle {
    enum Kind { case primary, dark, secondary, stop, danger, ghost }
    var kind: Kind = .secondary
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        DSButtonBody(configuration: configuration, kind: kind, fullWidth: fullWidth)
    }
}

private struct DSButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: DSButtonStyle.Kind
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Ayarlar › Geçiş Animasyonları kapalıyken de yalnız kısa solma.
    @Environment(\.dsMotionOff) private var motionOff
    private var reduceMotion: Bool { systemReduceMotion || motionOff }

    var body: some View {
        let pressed = configuration.isPressed
        HStack(spacing: DS.space("xs")) {
            configuration.label
                .labelStyle(.titleAndIcon)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .font(kind == .secondary || kind == .ghost ? .dsButtonSecondary : .dsButton)
        .foregroundStyle(foreground)
        .padding(.horizontal, kind == .ghost ? DS.space("s") : DS.space("l"))
        .padding(.vertical, DS.space("xs"))
        .frame(maxWidth: fullWidth && kind != .ghost ? .infinity : nil)
        .frame(minHeight: kind == .ghost ? 44 : DS.size("button"))
        .background(background(pressed: pressed), in: Capsule())
        .overlay { ring }
        .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
        .opacity(isEnabled ? 1 : 0.55)
        .contentShape(Capsule())
        .animation(DS.animation(.short, reduced: reduceMotion), value: pressed)
    }

    @ViewBuilder private var ring: some View {
        switch kind {
        case .secondary: Capsule().strokeBorder(Color.dsBorder)
        case .stop, .danger: Capsule().strokeBorder(Color.dsLiveRing)
        default: EmptyView()
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .dsOnAmber
        case .dark: .dsOnCharcoal
        case .secondary: .dsText
        case .stop, .danger: .dsLiveText
        case .ghost: .dsAmberText
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: pressed ? .dsAmberHover : .dsAmber
        case .dark: .dsCharcoal
        case .secondary: pressed ? .dsField : .dsSurface
        case .stop, .danger: pressed ? Color.dsLive.opacity(0.18) : .dsLiveSoft
        case .ghost: pressed ? .dsField : .clear
        }
    }
}

/// Başarı durumu (Eşleşti, Onaylandı, Kaydedildi): açık yeşil zemin, yeşil yazı, tik, küçük oturma animasyonu.
struct DSSuccessBadge: View {
    let text: LocalizedStringKey
    var fullWidth = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Ayarlar › Geçiş Animasyonları kapalıyken de yalnız kısa solma.
    @Environment(\.dsMotionOff) private var motionOff
    private var reduceMotion: Bool { systemReduceMotion || motionOff }
    @State private var seated = false

    var body: some View {
        HStack(spacing: DS.space("xs")) {
            Image(systemName: "checkmark").font(.footnote.weight(.heavy)).accessibilityHidden(true)
            Text(text).lineLimit(1)
        }
        .font(.dsButton)
        .foregroundStyle(Color.dsSuccessText)
        .padding(.horizontal, DS.space("l"))
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .frame(minHeight: DS.size("button"))
        .background(Color.dsSuccessSoft, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.dsSuccessRing))
        .scaleEffect(seated || reduceMotion ? 1 : 0.94)
        .onAppear { withAnimation(DS.animation(.medium, reduced: reduceMotion)) { seated = true } }
        .accessibilityElement(children: .combine)
    }
}

/// Atan nokta (canlı/çalışıyor). Azaltılmış harekette sabit.
struct DSPulseDot: View {
    var color: Color = .dsLive
    var size: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Ayarlar › Geçiş Animasyonları kapalıyken de yalnız kısa solma.
    @Environment(\.dsMotionOff) private var motionOff
    private var reduceMotion: Bool { systemReduceMotion || motionOff }
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

// MARK: Sekme seçici

/// Tek seçimli seçici (her yerde aynı): bej iz (alan rengi, kapsül, ince halka), seçili sekme yüzey rengi + hafif gölge +
/// halka ve kayarak geçer. Sekmeler genişliği eşit paylaşır.
struct DSTabs<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: LocalizedStringKey
        var id: Value { value }
    }

    @Binding var selection: Value
    let items: [Item]
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Ayarlar › Geçiş Animasyonları kapalıyken de yalnız kısa solma.
    @Environment(\.dsMotionOff) private var motionOff
    private var reduceMotion: Bool { systemReduceMotion || motionOff }
    @Namespace private var namespace

    init(selection: Binding<Value>, items: [(Value, LocalizedStringKey)]) {
        _selection = selection
        self.items = items.map { Item(value: $0.0, title: $0.1) }
    }

    var body: some View {
        HStack(spacing: DS.space("xxs")) {
            ForEach(items) { item in
                let on = item.value == selection
                Button {
                    withAnimation(DS.animation(.medium, reduced: reduceMotion)) { selection = item.value }
                } label: {
                    Text(item.title)
                        .font(.dsTab)
                        .foregroundStyle(on ? Color.dsText : Color.dsMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, DS.space("xs"))
                        .frame(maxWidth: .infinity, minHeight: DS.size("tab"))
                        .background {
                            if on {
                                Capsule().fill(Color.dsSurface)
                                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                                    .overlay(Capsule().strokeBorder(Color.dsBorder))
                                    .matchedGeometryEffect(id: "tab", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .selectionFeedback(trigger: on)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(DS.space("xxs"))
        .background(Color.dsField, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.dsBorder))
    }
}

// MARK: Anahtar

/// Anahtar: 44 × 26, açıkken amber (yeşil değil), beyaz gölgeli düğmecik.
struct DSSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Ayarlar › Geçiş Animasyonları kapalıyken de yalnız kısa solma.
    @Environment(\.dsMotionOff) private var motionOff
    private var reduceMotion: Bool { systemReduceMotion || motionOff }

    var body: some View {
        let width = DS.size("switchWidth"), height = DS.size("switchHeight"), knob = DS.size("switchKnob")
        Capsule()
            .fill(isOn ? Color.dsAmber : Color.dsSwitchOff)
            .frame(width: width, height: height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .padding(.horizontal, 3)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .animation(DS.animation(.medium, reduced: reduceMotion), value: isOn)
            .accessibilityHidden(true)
    }
}

/// Bütün anahtarlar (Toggle) bu biçimde: anahtar satırın başında, yazının solunda; satırın tamamı dokunulabilir.
struct DSToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: DS.space("m")) {
                DSSwitch(isOn: configuration.$isOn)
                configuration.label
                    .foregroundStyle(Color.dsText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

// MARK: Radyo ve seçenek kartı

/// Radyo yuvarlağı: seçiliyken 6 pt amber halka, değilken 2 pt gri.
struct DSRadio: View {
    let on: Bool

    var body: some View {
        Circle()
            .strokeBorder(on ? Color.dsAmber : Color.dsSwitchOff, lineWidth: on ? 6 : 2)
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}

/// Seçenek kartı: tıklanabilir olduğu belli: 1 pt ince halka; seçiliyken amber halka ve hafif amber dolgu; solda radyo.
struct DSOptionStyle: ButtonStyle {
    var selected: Bool
    var radio = true

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius("tile"), style: .continuous)
        return HStack(spacing: DS.space("m")) {
            if radio { DSRadio(on: selected) }
            configuration.label.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.space("m"))
        .padding(.vertical, DS.space("s"))
        .frame(maxWidth: .infinity, minHeight: DS.size("option"), alignment: .leading)
        .background(selected ? Color.dsAmber.opacity(0.08) : configuration.isPressed ? Color.dsField : Color.dsSurface, in: shape)
        .overlay(shape.strokeBorder(selected ? Color.dsAmber : Color.dsBorder, lineWidth: selected ? 1.5 : 1))
        .contentShape(shape)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: Giriş kutusu

/// Giriş kutusu: tam yuvarlak, en az 48, alan zemini, ince halka; odakta amber halka. `trailing` kutunun içinde sağda.
struct DSFieldChrome<Field: View, Trailing: View>: View {
    var mono = false
    @ViewBuilder var field: Field
    @ViewBuilder var trailing: Trailing
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: DS.space("xs")) {
            field
                .focused($focused)
                .font(mono ? .system(.footnote, design: .monospaced) : .dsBody)
                .foregroundStyle(Color.dsText)
                .tint(Color.dsAmberText)
            trailing
        }
        .padding(.leading, DS.space("m") + 4)
        .padding(.trailing, Trailing.self == EmptyView.self ? DS.space("m") + 4 : DS.space("xxs"))
        .frame(minHeight: DS.size("input"))
        .background(Color.dsField, in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? Color.dsAmber : Color.dsBorder, lineWidth: focused ? 2 : 1))
    }
}

extension DSFieldChrome where Trailing == EmptyView {
    init(mono: Bool = false, @ViewBuilder field: () -> Field) {
        self.mono = mono
        self.field = field()
        self.trailing = EmptyView()
    }
}

/// Kutunun içinde sağdaki yuvarlak simge düğmesi (kopyala, kaldır): 40 pt dokunma hedefi.
struct DSFieldIconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var tint: Color = .dsMuted
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// Seçilebilir adres kutusu: yazı mono, sağda kutunun içinde kopyala simgesi; kopyalanınca yeşil tik.
struct DSCopyField: View {
    let text: String
    @State private var copied = false

    var body: some View {
        DSFieldChrome(mono: true) {
            Text(verbatim: text)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } trailing: {
            DSFieldIconButton(symbol: copied ? "checkmark" : "doc.on.doc", label: copied ? "Copied" : "Copy",
                              tint: copied ? .dsSuccessText : .dsMuted) {
                UIPasteboard.general.string = text
                copied = true
            }
        }
        .resetsAfterDelay($copied)
    }
}

/// Kutu içi metin alanı (TextField / SecureField): `textFieldStyle(DSTextFieldStyle())`.
struct DSTextFieldStyle: TextFieldStyle {
    var mono = false

    func _body(configuration: TextField<Self._Label>) -> some View {
        DSFieldChrome(mono: mono) { configuration }
    }
}

// MARK: Rozet

/// Rozet: 24 yükseklik, tam yuvarlak. ok: yeşil, warn: kırmızı, unknown: gri, amber: paket/öneri.
struct DSBadge: View {
    enum Tone { case ok, warn, unknown, amber }
    let text: String
    var tone: Tone = .unknown

    var body: some View {
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(minHeight: DS.size("badge"))
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .ok: .dsSuccessText
        case .warn: .dsLiveText
        case .unknown: .dsMuted
        case .amber: .dsAmberText
        }
    }

    private var background: Color {
        switch tone {
        case .ok: .dsSuccessSoft
        case .warn: .dsLiveSoft
        case .unknown: .dsField
        case .amber: .dsAmberSoft
        }
    }
}

// MARK: Kaydırıcı

/// Kaydırıcı: 4 pt ince iz (kapalı anahtar rengi), dolu kısmı amber, 24 pt beyaz gölgeli düğmecik; nokta (tick) yok.
/// İz düğmeciğin yarıçapı kadar içeriden başlar; değer yazıları iz uçlarına hizalanacaksa `DSSlider.inset` kullanılır.
struct DSSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var onEditingChanged: (Bool) -> Void = { _ in }
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Ayarlar › Geçiş Animasyonları kapalıyken de yalnız kısa solma.
    @Environment(\.dsMotionOff) private var motionOff
    private var reduceMotion: Bool { systemReduceMotion || motionOff }
    @State private var dragging = false

    static let knob: CGFloat = 24
    static var inset: CGFloat { knob / 2 }
    private static let track: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let knob = Self.knob
            let travel = max(geometry.size.width - knob, 1)
            let offset = travel * fraction
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsSwitchOff)
                    .frame(width: travel, height: Self.track)
                    .offset(x: knob / 2)
                Capsule().fill(Color.dsAmber)
                    .frame(width: offset, height: Self.track)
                    .offset(x: knob / 2)
                Circle().fill(Color.white)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.06)))
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .scaleEffect(dragging && !reduceMotion ? 1.08 : 1)
                    .offset(x: offset)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !dragging {
                            dragging = true
                            onEditingChanged(true)
                        }
                        set(fraction: (gesture.location.x - knob / 2) / travel)
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 32)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(DS.animation(.short, reduced: reduceMotion), value: dragging)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: value.formatted(.number.precision(.fractionLength(step.map { $0 < 1 ? 1 : 0 } ?? 0)))))
        .accessibilityAdjustableAction { direction in
            let delta = step ?? (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = clamp(value + delta)
            case .decrement: value = clamp(value - delta)
            @unknown default: break
            }
            onEditingChanged(false)
        }
    }

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((clamp(value) - range.lowerBound) / span)
    }

    private func set(fraction: CGFloat) {
        let raw = range.lowerBound + Double(min(max(fraction, 0), 1)) * (range.upperBound - range.lowerBound)
        let snapped = step.map { (raw / $0).rounded() * $0 } ?? raw
        let next = clamp(snapped)
        if next != value {
            value = next
            if step != nil { UISelectionFeedbackGenerator().selectionChanged() }
        }
    }

    private func clamp(_ x: Double) -> Double { min(max(x, range.lowerBound), range.upperBound) }
}

/// Kaydırıcı satırı: başlık solda, değer sağda (mono); altında tam genişlikte kaydırıcı, en altta isteğe bağlı açıklama.
struct DSSliderRow: View {
    let title: LocalizedStringKey
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var hint: LocalizedStringKey?
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space("xs")) {
            HStack(alignment: .firstTextBaseline, spacing: DS.space("s")) {
                Text(title).font(.dsBodyStrong).foregroundStyle(Color.dsText).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.space("s"))
                Text(verbatim: valueText)
                    .font(.system(.footnote, design: .monospaced).weight(.medium).monospacedDigit())
                    .foregroundStyle(Color.dsText)
            }
            DSSlider(value: $value, range: range, step: step, onEditingChanged: onEditingChanged)
                .accessibilityLabel(Text(title))
            if let hint { Text(hint).dsMuted() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Açılır seçim kutusu

/// Açılır seçim kutusu: yüzey zemini, ince halka, 12 köşe, koyu yazı, sağda tek küçük aşağı ok; dokununca sistemin menüsü
/// açılır, seçili satır tikli.
struct DSSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius("control"), style: .continuous)
        Menu {
            Picker(selection: $selection) {
                ForEach(options, id: \.0) { option in Text(verbatim: option.1).tag(option.0) }
            } label: { EmptyView() }
        } label: {
            HStack(spacing: DS.space("xs")) {
                Text(verbatim: options.first { $0.0 == selection }?.1 ?? "")
                    .font(.dsBody)
                    .foregroundStyle(Color.dsText)
                    .lineLimit(1)
                Spacer(minLength: DS.space("xs"))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.dsMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.dsSurface, in: shape)
            .overlay(shape.strokeBorder(Color.dsBorder))
            .contentShape(shape)
        }
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityValue(Text(verbatim: options.first { $0.0 == selection }?.1 ?? ""))
    }
}

// MARK: Logo

/// CouchSubs logosu, arka plansız: yalnız kanepe ve iki amber altyazı çubuğu (design/logo.svg ile aynı geometri, 640 × 464).
struct DSLogoMark: View {
    var height: CGFloat = 26

    var body: some View {
        let scale = height / 464
        ZStack(alignment: .topLeading) {
            rect(282, 290, 460, 320, 52, .dsLogoBack, scale)
            bar(367, 362, 290, 50, scale)
            bar(414, 436, 196, 50, scale)
            rect(262, 690, 40, 44, 12, .dsLogoSeat, scale)
            rect(722, 690, 40, 44, 12, .dsLogoSeat, scale)
            rect(202, 446, 112, 254, 56, .dsLogoSeat, scale)
            rect(710, 446, 112, 254, 56, .dsLogoSeat, scale)
            rect(202, 574, 620, 126, 56, .dsLogoSeat, scale)
        }
        .frame(width: 640 * scale, height: height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ color: Color, _ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: r * s, style: .continuous)
            .fill(color)
            .frame(width: w * s, height: h * s)
            .offset(x: (x - 192) * s, y: (y - 280) * s)
    }

    private func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ s: CGFloat) -> some View {
        Capsule()
            .fill(Color.dsAmber)
            .frame(width: w * s, height: h * s)
            .offset(x: (x - 192) * s, y: (y - 280) * s)
    }
}

/// Logo + "CouchSubs" (ana ekranın üst satırı).
struct DSBrand: View {
    var body: some View {
        HStack(spacing: DS.space("s")) {
            DSLogoMark(height: 24)
            Text(verbatim: "CouchSubs").font(.system(.subheadline, weight: .bold)).foregroundStyle(Color.dsText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "CouchSubs"))
    }
}
