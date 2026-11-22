// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import SwiftUI
import UniformTypeIdentifiers

/// Geçmiş (tuval 16): arama kutusu ve kaynak seçici (Tümü / Paket / Çeviri); tabloda Saat, Türkçe, İngilizce, Kaynak;
/// altta oyun · gün · satır sayısı, Dışa Aktar ve Hatalı Çeviriyi Bildir. Satıra tıklanınca seçilir (bildirim o satırla
/// açılır), sağ tıkla kopyalanır. Eski Geçmiş sayfasındaki Tümünü Kopyala ve Temizle de buradadır.
struct HistoryPage: View {
    enum Filter: Hashable { case all, pack, engine }

    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var filter = Filter.all
    @State private var selected: Int?
    @State private var confirmClear = false
    @State private var copiedAll = false

    var body: some View {
        let rows = filtered
        VStack(spacing: DS.space("m")) {
            HStack(spacing: DS.space("s")) {
                DSFieldChrome {
                    HStack(spacing: DS.space("s")) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.dsMuted).accessibilityHidden(true)
                        TextField("Search History", text: $query).textFieldStyle(.plain)
                    }
                }
                DSTabs(selection: $filter, items: [(.all, "All"), (.pack, "Pack"), (.engine, "Translation")], fill: true)
                    .frame(width: 360)
            }
            VStack(spacing: 0) {
                header
                if rows.isEmpty {
                    Text(model.history.entries.isEmpty ? "No subtitles yet. Lines translated while you play appear here." : "No lines match this search.")
                        .dsMuted(.dsBody)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(DS.space("xxl"))
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(rows, id: \.id) { entry in row(entry) }
                        }
                    }
                }
                DSDivider()
                footer(count: rows.count)
            }
            .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: DS.radius("card"), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.radius("card"), style: .continuous).strokeBorder(Color.dsBorder))
            .clipShape(RoundedRectangle(cornerRadius: DS.radius("card"), style: .continuous))
        }
        .padding(DS.space("l"))
        .confirmationDialog("Clear the history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { model.clearHistory() }
        } message: {
            Text("All saved lines are removed from this computer.")
        }
    }

    private var filtered: [SubtitleHistory.Entry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased(with: Locale(identifier: "tr"))
        return model.history.entries.filter { entry in
            switch filter {
            case .all: break
            case .pack: guard entry.origin == .pack else { return false }
            case .engine: guard entry.origin == .engine else { return false }
            }
            guard !needle.isEmpty else { return true }
            return (entry.translation + " " + entry.source).lowercased(with: Locale(identifier: "tr")).contains(needle)
        }
    }

    private static let columns: (time: CGFloat, source: CGFloat) = (72, 96)

    private var header: some View {
        HStack(spacing: DS.space("m")) {
            DSMonoLabel("Time").frame(width: Self.columns.time, alignment: .leading)
            DSMonoLabel("Turkish").frame(maxWidth: .infinity, alignment: .leading)
            DSMonoLabel("English").frame(maxWidth: .infinity, alignment: .leading)
            DSMonoLabel("Source").frame(width: Self.columns.source, alignment: .leading)
        }
        .padding(.horizontal, DS.space("l"))
        .padding(.vertical, DS.space("m"))
        .overlay(alignment: .bottom) { DSDivider() }
    }

    private func row(_ entry: SubtitleHistory.Entry) -> some View {
        let isSelected = selected == entry.id
        return HStack(alignment: .center, spacing: DS.space("m")) {
            Text(verbatim: entry.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.dsMuted)
                .frame(width: Self.columns.time, alignment: .leading)
            Text(verbatim: entry.translation).font(.system(size: 14, weight: .medium)).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: entry.source).font(.dsSmall).foregroundStyle(Color.dsMuted).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                DSBadge(text: entry.origin == .pack ? "Pack" : "Translation", tone: entry.origin == .pack ? .amber : .unknown)
                Spacer(minLength: 0)
            }
            .frame(width: Self.columns.source)
        }
        .padding(.horizontal, DS.space("l"))
        .padding(.vertical, DS.space("s"))
        .background(isSelected ? Color.dsAmberSoft : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.dsTileBorder).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { selected = isSelected ? nil : entry.id }
        .contextMenu {
            Button("Copy") { copy("\(entry.translation)\n\(entry.source)") }
            Button("Report a Wrong Translation") { report(entry) }
        }
        .textSelection(.enabled)
    }

    private func footer(count: Int) -> some View {
        HStack(spacing: DS.space("xs")) {
            Text(verbatim: summary(count)).font(.dsSmall).foregroundStyle(Color.dsMuted).lineLimit(1)
            Spacer(minLength: DS.space("s"))
            Button(copiedAll ? "Copied" : "Copy All") {
                copy(SubtitleHistory.plainText(model.history.entries))
                copiedAll = true
            }
            .disabled(model.history.entries.isEmpty)
            .resetsAfterDelay($copiedAll)
            Button("Export") { export() }.disabled(model.history.entries.isEmpty)
            Button("Report a Wrong Translation") { report(model.history.entries.first { $0.id == selected } ?? model.history.entries.first) }
                .disabled(model.history.entries.isEmpty)
            Button("Clear History") { confirmClear = true }.disabled(model.history.entries.isEmpty)
        }
        .buttonStyle(SmallSecondary())
        .padding(.horizontal, DS.space("l"))
        .padding(.vertical, DS.space("s"))
    }

    private func summary(_ count: Int) -> String {
        if let game = model.gameChoice.game?.name {
            return String(format: String(localized: "%@ · Today · %lld Lines"), game, count)
        }
        return String(format: String(localized: "Today · %lld Lines"), count)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Geçmişi düz metin olarak kaydeder (Tümünü Kopyala ile aynı biçim).
    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "CouchSubs-\(Date().formatted(.iso8601.year().month().day())).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? SubtitleHistory.plainText(model.history.entries).write(to: url, atomically: true, encoding: .utf8)
    }

    /// GitHub'da hazır doldurulmuş bir sorun bildirimi açar: satırın İngilizcesi, Türkçesi, kaynağı ve oyun. Hiçbir şey
    /// kendiliğinden gönderilmez; kullanıcı tarayıcıda düzeltip gönderir.
    private func report(_ entry: SubtitleHistory.Entry?) {
        guard let entry else { return }
        let game = model.gameChoice.game?.name ?? "-"
        let body = """
        **Oyun / Game:** \(game)
        **İngilizce / English:** \(entry.source)
        **Çeviri / Translation:** \(entry.translation)
        **Kaynak / Source:** \(entry.origin == .pack ? "pack" : model.settings.translationEngine.rawValue)
        **Doğrusu / Correct translation:**\u{20}
        """
        var components = URLComponents(url: AppIdentity.sourceURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "title", value: "Hatalı çeviri: \(entry.source.prefix(60))"),
                                  URLQueryItem(name: "body", value: body)]
        if let url = components?.url { NSWorkspace.shared.open(url) }
    }
}

/// Geçmiş altındaki küçük ikincil düğmeler (40 yükseklik, 13 pt).
private struct SmallSecondary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SmallBody(configuration: configuration)
    }

    private struct SmallBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.dsText)
                .lineLimit(1)
                .padding(.horizontal, DS.space("m"))
                .frame(height: DS.size("tab"))
                .background(hovering || configuration.isPressed ? Color.dsField : Color.dsSurface, in: Capsule(style: .circular))
                .overlay(Capsule(style: .circular).strokeBorder(Color.dsBorder))
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Capsule(style: .circular))
                .onHover { hovering = $0 }
        }
    }
}
