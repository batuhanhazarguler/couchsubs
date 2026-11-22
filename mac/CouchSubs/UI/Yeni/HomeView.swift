// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import RemotePlay
import SwiftUI

/// Ana ekranın saniyede iki kez yenilenen bilgileri: son kare, kare hızı, sessizlik süresi, gecikme geçmişi. Model her
/// karede yayın yapmaz; yalnız bunu izleyen küçük görünümler yeniden çizilir.
@MainActor
final class HomeTicker: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var fps = 0
    @Published private(set) var now = Date()
    @Published private(set) var delays: [Int] = []
    private var lastCount = 0
    private var lastAt = Date()
    private var lastMetrics: LineMetrics?

    func tick(_ model: AppModel) {
        let date = Date()
        if model.lastFrame !== image { image = model.lastFrame }
        let elapsed = date.timeIntervalSince(lastAt)
        if elapsed >= 1 {
            let value = model.isRunning ? Int((Double(model.frameCount - lastCount) / elapsed).rounded()) : 0
            if value != fps { fps = max(0, value) }
            lastCount = model.frameCount
            lastAt = date
        }
        if let metrics = model.lastMetrics, metrics != lastMetrics {
            lastMetrics = metrics
            delays = Array((delays + [metrics.totalMs]).suffix(10))
        }
        if !model.isRunning, !delays.isEmpty, model.sessionHistory.isEmpty { delays = [] }
        now = date
    }
}

/// Ana ekran (tuval 09–10): üstte dört durum çipi; solda oyun görüntüsü ve üç düğme; sağda Durum ve Canlı Akış ya da
/// sorun varken sessizlik nedeni kartı. Oyun sorulunca "Hangi Oyun?" kartı ekranın üstünde açılır.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var ticker = HomeTicker()

    var body: some View {
        ZStack {
            // Sayfa kayar: sol kart (16:9 önizleme kartın iç genişliğini tam doldurur) kısa pencerede de tamamıyla görülür,
            // alttaki reklam bandının altına girmez. Sağ sütun sol kartla aynı yükseklikte.
            GeometryReader { outer in
                let gap = DS.space("l")
                let width = max(outer.size.width - 2 * gap, 0)
                let left = ((width - gap) * 2 / 3).rounded(.down)
                let height = PreviewCard.height(width: left)
                ScrollView(.vertical) {
                    VStack(spacing: gap) {
                        StatusChips(choice: model.gameChoice)
                        HStack(alignment: .top, spacing: gap) {
                            PreviewCard(ticker: ticker).frame(width: left, height: height)
                            RightColumn(ticker: ticker).frame(maxWidth: .infinity).frame(height: height)
                        }
                    }
                    .padding(gap)
                }
                .scrollIndicators(.automatic)
            }
            GamePickerOverlay(choice: model.gameChoice, areas: model.gameAreas)
        }
        .task {
            while !Task.isCancelled {
                ticker.tick(model)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

// MARK: Durum çipleri

private struct StatusChips: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var choice: GameChoice

    var body: some View {
        HStack(spacing: DS.space("xs")) {
            consoleChip
            tvChip
            StatusChip(key: "Game", value: choice.game?.name ?? String(localized: "Unknown Game"),
                       detail: gameHasPack ? String(localized: "Pack") : nil,
                       tone: choice.game == nil ? .idle : .good) { choice.ask() }
            StatusChip(key: "Translation", value: engineName, detail: languages,
                       tone: model.translatorStatus == .ready ? .good : .warning) { model.openSettings(.advanced) }
        }
        .padding(DS.space("xs"))
        .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: DS.radius("card"), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radius("card"), style: .continuous).strokeBorder(Color.dsBorder))
    }

    @ViewBuilder private var consoleChip: some View {
        let tone = model.demoMode ? StatusTone.good : AppModel.ps5Tone(model.sessionState, running: model.isRunning)
        if model.demoMode {
            StatusChip(key: "Demo Mode", value: String(localized: "Sample pictures"), detail: nil, tone: tone) { model.openSettings(.console) }
        } else if model.readsCaptureWindow {
            StatusChip(key: "Window", value: model.settings.captureWindow?.title ?? model.pictureSourceName,
                       detail: shortState, tone: tone) { model.openSettings(.console) }
        } else if model.isXbox {
            StatusChip(key: "Xbox · Beta", value: model.xboxConsole?.name ?? "Xbox", detail: shortState, tone: tone) {
                if model.needsXboxLink { model.linkXbox() } else { model.openSettings(.console) }
            }
        } else if model.settings.frameSource == .remotePlayWindow {
            StatusChip(key: "PS5", value: String(localized: "Remote Play Window on This Mac"), detail: shortState, tone: tone) {
                model.openSettings(.console)
            }
        } else {
            StatusChip(key: "PS5", value: model.console.map { $0.name.isEmpty ? "PS5" : $0.name } ?? String(localized: "Not Set Up"),
                       detail: shortState, tone: tone) { model.openSettings(.console) }
        }
    }

    @ViewBuilder private var tvChip: some View {
        if !model.settings.output.showsOnTV {
            StatusChip(key: "Computer Screen", value: model.settings.output == .obs ? String(localized: "OBS Only (Streaming)") : String(localized: "This Mac"),
                       detail: nil, tone: .good) { model.openSettings(.outputs) }
        } else if let tv = model.tv, model.hasTV {
            StatusChip(key: "TV", value: tv.name, detail: tvDetail, tone: model.tvAppOutdated != nil ? .warning
                       : AppModel.tvTone(clients: model.tvClients, running: model.isRunning)) { model.openSettings(.outputs) }
        } else {
            StatusChip(key: "TV", value: String(localized: "Not Set Up"), detail: nil, tone: .idle) { model.step = .tv }
        }
    }

    private var tvDetail: String? {
        if case .upToDate(let version) = model.tvApp { return version }
        return model.tvClients > 0 ? nil : model.tvStatusText
    }

    private var shortState: String? {
        switch model.sessionState {
        case .streaming: String(localized: "Connected")
        case .connecting: String(localized: "Connecting…")
        case .disconnected: model.isRunning ? String(localized: "Not Connected") : nil
        }
    }

    private var gameHasPack: Bool {
        guard let name = choice.game?.name else { return false }
        let key = GameName.key(name)
        return GameCatalog.packShelf(model.installedPacks).contains { item in item.titles.contains { GameName.key($0) == key } }
    }

    private var engineName: String {
        let engine = model.settings.translationEngine
        return engine == .free ? String(localized: "Free Translation") : engine.displayName
    }

    private var languages: String {
        "\(model.settings.sourceLanguage.uppercased())→\(model.settings.targetLanguage.uppercased())"
    }
}

/// Tek çip: 56 yükseklik, solda durum yuvarlağı (yeşil tik / kırmızı ünlem / gri), üstte 12 pt anahtar, altında 14 pt değer
/// ve mono ek bilgi. Tıklanınca ilgili ayara gider.
private struct StatusChip: View {
    let key: LocalizedStringKey
    let value: String
    let detail: String?
    let tone: StatusTone
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space("s")) {
                ZStack {
                    Circle().fill(tone == .good ? Color.dsSuccessSoft : tone == .warning ? Color.dsLiveSoft : Color.dsField)
                    Image(systemName: tone == .good ? "checkmark" : tone == .warning ? "exclamationmark" : "minus")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(tone == .good ? Color.dsSuccess : tone == .warning ? Color.dsLive : Color.dsFaint)
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: DS.space("line")) {
                    Text(key).font(.dsCaption).foregroundStyle(Color.dsMuted).lineLimit(1)
                    HStack(spacing: DS.space("xxs")) {
                        Text(verbatim: value).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.dsText).lineLimit(1)
                        if let detail {
                            Text(verbatim: detail).font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.dsMuted).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.space("m"))
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(hovering ? Color.dsField : Color.dsSurface, in: RoundedRectangle(cornerRadius: DS.radius("tile"), style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.radius("tile"), style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Oyun görüntüsü ve düğmeler

private struct PreviewCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var ticker: HomeTicker

    var body: some View {
        // Kart iç boşluğu her yönde 24 (ölçü sistemi); 16:9 önizleme iç genişliği tam doldurur, düğme satırı aynı genişlikte.
        DSCard(padding: Self.padding, spacing: Self.gap, scrolls: false) {
            GeometryReader { geometry in
                let width = geometry.size.width
                VStack(spacing: Self.gap) {
                    preview.frame(width: width, height: (width * 9 / 16).rounded(.down))
                    HomeButtons().frame(width: width)
                }
            }
        }
    }

    static let padding = DS.space("l")
    static let gap = DS.space("m")

    /// Kartın yüksekliği: iç boşluk + 16:9 önizleme + aralık + düğme satırı + iç boşluk.
    static func height(width: CGFloat) -> CGFloat {
        let inner = max(width - 2 * padding, 0)
        return 2 * padding + (inner * 9 / 16).rounded(.down) + gap + DS.size("button")
    }

    private var preview: some View {
        let running = model.isRunning
        return DSScreenFrame(image: ticker.image.map { NSImage(cgImage: $0, size: .zero) }) {
            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: UnitPoint(x: 0.5, y: 0.4), endPoint: .bottom)
                        .allowsHitTesting(false)
                    AreaFrame(region: model.settings.region, size: size, animated: running)
                    if running, !model.lastTranslation.isEmpty {
                        SubtitleLine(text: model.lastTranslation)
                            .frame(width: size.width * 0.7)
                            .position(x: size.width / 2, y: size.height * 0.4)
                            .id(model.lastTranslation)
                            .transition(.opacity.combined(with: .offset(y: -8)))
                    }
                    // Durum hapı sağ üstte: örnek karenin sol üstündeki görev yazısıyla çakışmasın.
                    HStack(spacing: DS.space("xs")) {
                        Spacer()
                        LivePill(running: running)
                        if running {
                            OverlayPill(text: String(format: String(localized: "%lld Frames/s"), ticker.fps), mono: true,
                                        prefix: model.isXbox ? "Xbox" : model.readsCaptureWindow ? nil : "PS5")
                        }
                    }
                    .padding(DS.space("s"))
                }
            }
        }
        .animation(DS.animation(.page, reduced: !model.settings.transitionAnimations), value: model.lastTranslation)
    }
}

/// Okunan alan: amber kesikli çerçeve ve "Okunan Alan" etiketi; çeviri sürerken yavaşça soluklaşıp parlar.
private struct AreaFrame: View {
    let region: CropRegion
    let size: CGSize
    let animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dsMotionOff) private var motionOff
    @State private var dim = false

    var body: some View {
        let rect = CGRect(x: region.left * size.width, y: region.top * size.height,
                          width: max(0, region.right - region.left) * size.width, height: max(0, region.bottom - region.top) * size.height)
        RoundedRectangle(cornerRadius: DS.radius("small"))
            .strokeBorder(Color.dsAmber, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: rect.width, height: rect.height)
            .overlay(alignment: .topLeading) {
                Text("Area Read")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.dsOnAmber)
                    .padding(.horizontal, DS.space("xs"))
                    .frame(height: 22)
                    .background(Color.dsAmber, in: Capsule(style: .circular))
                    .offset(x: DS.space("s"), y: -11)
            }
            .opacity(dim ? 0.55 : 1)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .onAppear { start() }
            .onChange(of: animated) { _ in start() }
    }

    private func start() {
        guard animated, !reduceMotion, !motionOff else { dim = false; return }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { dim = true }
    }
}

/// Önizlemedeki altyazı: koyu yarı saydam kutu, konuşanın adı amber.
private struct SubtitleLine: View {
    let text: String

    var body: some View {
        let parts = SpeakerSplit(text)
        (Text(verbatim: parts.speaker.map { $0 + " " } ?? "").foregroundColor(Color.dsAmber) + Text(verbatim: parts.line).foregroundColor(.white))
            .font(.system(size: 17, weight: .semibold))
            .lineSpacing(4)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .padding(.horizontal, DS.space("m"))
            .padding(.vertical, DS.space("s"))
            .background(Color(red: 0.063, green: 0.063, blue: 0.078).opacity(0.85), in: RoundedRectangle(cornerRadius: DS.radius("control")))
    }
}

/// "Jason: Tamam." → ("Jason:", "Tamam."); adı olmayan satır olduğu gibi.
struct SpeakerSplit {
    let speaker: String?
    let line: String

    init(_ text: String) {
        if let range = text.range(of: ": "), text.distance(from: text.startIndex, to: range.lowerBound) <= 24,
           !text[..<range.lowerBound].contains(where: { ".!?\n".contains($0) }) {
            speaker = String(text[..<range.lowerBound]) + ":"
            line = String(text[range.upperBound...])
        } else {
            speaker = nil
            line = text
        }
    }
}

private struct LivePill: View {
    let running: Bool

    var body: some View {
        HStack(spacing: DS.space("xs")) {
            if running { DSPulseDot(color: .dsLiveDot, size: 7) } else { Circle().fill(Color.white.opacity(0.6)).frame(width: 7, height: 7) }
            Text(running ? "LIVE" : "STOPPED").font(.system(size: 11, weight: .semibold)).tracking(0.66)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DS.space("s"))
        .frame(height: 28)
        .background(Color.black.opacity(0.45), in: Capsule(style: .circular))
    }
}

private struct OverlayPill: View {
    let text: String
    var mono = false
    var prefix: String?

    var body: some View {
        Text(verbatim: [prefix, text].compactMap { $0 }.joined(separator: " · "))
            .font(.system(size: 11, weight: .medium, design: mono ? .monospaced : .default))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.space("s"))
            .frame(height: 28)
            .background(Color.black.opacity(0.45), in: Capsule(style: .circular))
    }
}

/// Çeviriyi Başlat/Durdur (1.3 pay), Ekranı Çevir, TV'de Dene (1'er pay); 12 aralık.
private struct HomeButtons: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { geometry in
            let gap = DS.space("s")
            let unit = (geometry.size.width - 2 * gap) / 3.3
            HStack(spacing: gap) {
                mainButton.frame(width: unit * 1.3)
                Button("Translate the Screen") { model.translateScreen() }
                    .buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: true))
                    .frame(width: unit)
                    .disabled(!model.isRunning)
                    .help(Text(HotkeyText.title(model.settings, .screen, String(localized: "Translate the screen (%@)"))))
                testButton.frame(width: unit)
            }
        }
        .frame(height: DS.size("button"))
    }

    @ViewBuilder private var mainButton: some View {
        if model.demoMode {
            Button("Exit Demo Mode") { model.exitDemo() }
                .buttonStyle(DSButtonStyle(kind: .stop, fullWidth: true))
                .accessibilityIdentifier("demoModeExit")
        } else if model.isRunning {
            Button("Stop Translating") { model.stop() }
                .buttonStyle(DSButtonStyle(kind: .stop, fullWidth: true))
                .keyboardShortcut(.defaultAction)
        } else {
            Button(model.isStarting ? "Starting…" : "Start Translating") { Task { await model.start() } }
                .buttonStyle(DSButtonStyle(kind: .primary, fullWidth: true))
                .disabled(model.isStarting || !model.canStart)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var testButton: some View {
        let onTV = model.settings.output.showsOnTV
        return Button(model.openingTVAppForTest ? "Opening the App on the TV…" : onTV ? "Try on TV" : "Try on Screen") {
            Task { await model.testSubtitle() }
        }
        .buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: true))
        .disabled((onTV && !model.hasTV && !model.settings.output.showsOnComputer) || model.openingTVAppForTest)
        .help(Text(onTV ? "Sends a sample subtitle to the TV." : "Shows a sample subtitle on this computer's screen."))
    }
}

// MARK: Sağ sütun

private struct RightColumn: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var ticker: HomeTicker

    var body: some View {
        VStack(spacing: DS.space("l")) {
            HomeNotices()
            if let problem = HomeProblem.current(model) {
                ProblemCard(problem: problem, ticker: ticker)
            } else {
                StatusCard(ticker: ticker)
                LiveFeedCard()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Durum kartı: başlık ("Altyazı Akıyor"/"Çeviri Durdu") ve üç karo: satır sayısı + dakikalık hız çizgisi, paketten
/// gelen oran halkası, ortalama gecikme çubukları.
private struct StatusCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var ticker: HomeTicker

    var body: some View {
        let entries = model.isRunning ? model.sessionHistory : []
        let packCount = entries.filter { $0.origin == .pack }.count
        let percent = entries.isEmpty ? 0 : Int((Double(packCount) / Double(entries.count) * 100).rounded())
        let perMinute = entries.filter { ticker.now.timeIntervalSince($0.date) <= 60 }.count
        DSCard(scrolls: false) {
            DSCardHeader("Status")
            Text(model.isRunning ? (entries.isEmpty ? "Waiting for Subtitles" : "Subtitles Flowing") : "Translation Stopped")
                .font(.dsH3)
            HStack(spacing: DS.space("xs")) {
                MetricTile(delay: 0) {
                    Text(verbatim: "\(entries.count)").font(.dsMonoValue)
                } graphic: {
                    Sparkline(values: Self.buckets(entries, now: ticker.now))
                } caption: {
                    Text(String(format: String(localized: "Lines · %lld/min"), perMinute))
                }
                MetricTile(delay: 1.2) {
                    HStack {
                        Text(verbatim: "\(packCount)").font(.dsMonoValue)
                        Spacer(minLength: 0)
                        Ring(fraction: Double(percent) / 100)
                    }
                } graphic: {
                    EmptyView()
                } caption: {
                    Text(String(format: String(localized: "From Pack · %lld%%"), percent))
                }
                MetricTile(delay: 2.4) {
                    Text(verbatim: ticker.delays.isEmpty ? "–" : "\(ticker.delays.reduce(0, +) / ticker.delays.count) ms").font(.dsMonoValue)
                } graphic: {
                    DelayBars(values: ticker.delays)
                } caption: {
                    Text("Average Delay")
                }
                .help(Text(verbatim: model.lastMetrics?.summary ?? ""))
            }
        }
    }

    /// Son 6 dakikanın 30 sn'lik dilimlerindeki satır sayısı (12 değer).
    static func buckets(_ entries: [SubtitleHistory.Entry], now: Date) -> [Double] {
        var counts = Array(repeating: 0.0, count: 12)
        for entry in entries {
            let age = now.timeIntervalSince(entry.date)
            guard age >= 0, age < 360 else { continue }
            counts[11 - Int(age / 30)] += 1
        }
        return counts
    }
}

private struct MetricTile<Value: View, Graphic: View, Caption: View>: View {
    let delay: Double
    @ViewBuilder var value: Value
    @ViewBuilder var graphic: Graphic
    @ViewBuilder var caption: Caption
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.radius("tile"), style: .continuous)
        VStack(alignment: .leading, spacing: DS.space("xxs")) {
            value.frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            graphic.frame(height: 28)
            caption.font(.dsCaption).foregroundStyle(Color.dsMuted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(DS.space("s"))
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(LinearGradient(colors: [Color.dsField, Color.dsSurface], startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
        .overlay(Sheen(delay: delay).clipShape(shape))
        .overlay(shape.strokeBorder(Color.dsTileBorder))
        .offset(y: hovering ? -2 : 0)
        .shadow(color: Color.black.opacity(hovering ? 0.08 : 0), radius: 8, y: 6)
        .onHover { value in withAnimation(DS.animation(.medium, reduced: false)) { hovering = value } }
    }
}

/// Karo üzerinden 6 sn'de bir geçen ince parıltı (hareket azaltılınca yok).
private struct Sheen: View {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dsMotionOff) private var motionOff
    @State private var phase: CGFloat = -1.2

    var body: some View {
        GeometryReader { geometry in
            if !reduceMotion && !motionOff {
                LinearGradient(colors: [.clear, Color.white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: phase * geometry.size.width)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.8).delay(delay + 4.2).repeatForever(autoreverses: false)) { phase = 1.6 }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            let top = max(values.max() ?? 0, 1)
            let points = values.enumerated().map { index, value in
                CGPoint(x: geometry.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                        y: geometry.size.height - geometry.size.height * 0.85 * CGFloat(value / top) - 2)
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last!.x, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.dsAmber.opacity(0.35), Color.dsAmber.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(Color.dsAmberLine, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle().fill(Color.dsAmberLine).frame(width: 5, height: 5).position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Ring: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.dsBorder, lineWidth: 5)
            Circle().trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(Color.dsAmberLine, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 32, height: 32)
        .animation(DS.enter(600), value: fraction)
        .accessibilityHidden(true)
    }
}

private struct DelayBars: View {
    let values: [Int]

    var body: some View {
        let shown = values.isEmpty ? Array(repeating: 0, count: 10) : Array((Array(repeating: 0, count: 10) + values).suffix(10))
        let top = max(shown.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, value in
                UnevenBar()
                    .fill(index == shown.count - 1 && !values.isEmpty ? Color.dsCharcoal : Color.dsScrollThumb)
                    .frame(height: 4 + 24 * CGFloat(value) / CGFloat(top))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .animation(DS.enter(400), value: values)
        .accessibilityHidden(true)
    }

    private struct UnevenBar: Shape {
        func path(in rect: CGRect) -> Path { Path(roundedRect: rect, cornerRadius: 2) }
    }
}

/// Canlı Akış: bu oturumun son satırları (Türkçe üstte, İngilizcesi altta gri); "Geçmiş →" Geçmiş sekmesini açar.
private struct LiveFeedCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let entries = Array(model.sessionHistory.prefix(30))
        DSCard(spacing: DS.space("xs"), scrolls: false) {
            DSCardHeader("Live feed") {
                Button("History →") { model.showHistory = true }
                    .buttonStyle(.plain)
                    .font(.dsSmall)
                    .foregroundStyle(Color.dsMuted)
            }
            if entries.isEmpty {
                Text("Subtitles will appear here while you play.").dsMuted()
                if model.showsSubtitleOffTip {
                    Text("CouchSubs reads the English subtitles on screen, not the audio. Turn on the game's own subtitles.").dsMuted()
                }
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries, id: \.id) { entry in
                            VStack(alignment: .leading, spacing: DS.space("line")) {
                                Text(verbatim: entry.translation).font(.system(size: 14, weight: .medium)).lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(verbatim: entry.source).font(.dsCaption).foregroundStyle(Color.dsMuted).lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, DS.space("xs"))
                            .overlay(alignment: .bottom) { DSDivider() }
                            .transition(.opacity.combined(with: .offset(y: -8)))
                        }
                    }
                }
                .animation(DS.animation(.page, reduced: !model.settings.transitionAnimations), value: entries.first?.id)
            }
        }
        .frame(maxHeight: .infinity)
    }
}
