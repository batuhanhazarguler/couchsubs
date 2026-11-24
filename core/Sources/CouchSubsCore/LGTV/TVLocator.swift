// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Kayıtlı TV'ye ulaşılamazsa ağda yeniden arar: modem TV'ye yeni adres verdiğinde eşleşme bozulmaz.
public final class TVLocator: @unchecked Sendable {
    private var tv: LGTV
    private let connectTo: (LGTV) async throws -> TVControlling
    private let search: () async -> [LGTV]
    private let onMoved: (LGTV) -> Void
    private let log: (String) -> Void
    private let searchInterval: Duration
    private var lastSearch: ContinuousClock.Instant?

    /// `onMoved`: TV yeni adreste bulundu ya da eski kayda kimliği (uuid/mac) yazıldı; kayıt güncellenmelidir.
    public init(tv: LGTV, connect: @escaping (LGTV) async throws -> TVControlling, search: @escaping () async -> [LGTV],
                onMoved: @escaping (LGTV) -> Void, log: @escaping (String) -> Void = { _ in },
                searchInterval: Duration = .seconds(30)) {
        self.tv = tv
        connectTo = connect
        self.search = search
        self.onMoved = onMoved
        self.log = log
        self.searchInterval = searchInterval
    }

    /// Bekçinin şu an kullandığı kayıt (yeni adreste bulununca değişir).
    public var current: LGTV { tv }

    public func connect() async throws -> TVControlling {
        do {
            return try await connectTo(tv)
        } catch {
            // TV kapalıyken de buraya gelinir; ağ her denemede taranmaz.
            let now = ContinuousClock.now
            if let lastSearch, lastSearch.duration(to: now) < searchInterval { throw error }
            lastSearch = now
            let found = await search()
            if let learned = Self.learned(tv, among: found) {
                tv = learned
                log(TVIdentity.learnedLine(learned))
                onMoved(learned)
            }
            guard let (moved, how) = Self.locate(tv, among: found), moved.host != tv.host else { throw error }
            let control = try await connectTo(moved)
            log(TVIdentity.movedLine(from: tv.host, to: moved.host, how: how))
            tv = moved
            onMoved(moved)
            return control
        }
    }

    /// Bulunanlar içinde kayıtlı TV'nin yeni adresi; TV kayıtlı adresteyse ya da emin olunamazsa nil.
    static func moved(_ saved: LGTV, among all: [LGTV]) -> LGTV? {
        guard let (found, _) = locate(saved, among: all), found.host != saved.host else { return nil }
        return found
    }

    /// Bulunanlar içinde kayıtlı TV (kayıtlı adreste de olabilir) ve nasıl tanındığı. Kimlik önce gelir: kayıtta uuid ya
    /// da mac varsa aynı kimlikli TV seçilir; kimliği farklı olan TV (adı aynı olsa da, kayıtlı adreste olsa da) asla
    /// seçilmez. Kimlikle bulunamazsa kimliği bilinmeyenler arasında eski kural: kayıtlı adres, aynı marka ve aynı ad tekse
    /// o, değilse markada tek TV varsa o. Birden çok tanınmayan TV varsa tahmin edilmez (başka odadaki TV'ye geçilmez).
    /// Dönen kayıtta kimlik, bulunanda yoksa kayıttakinden tamamlanır.
    public static func locate(_ saved: LGTV, among all: [LGTV]) -> (LGTV, TVIdentity.Match)? {
        let found = all.filter { $0.brand == saved.brand }
        if saved.hasIdentity {
            let same = found.filter { TVIdentity.sameDevice(saved, $0) == true }
            if let hit = same.first(where: { $0.host == saved.host }) ?? same.first {
                return (hit.identified(from: saved), saved.uuid != nil && hit.uuid != nil ? .uuid : .mac)
            }
        }
        let unknown = found.filter { TVIdentity.sameDevice(saved, $0) == nil }
        if let here = unknown.first(where: { $0.host == saved.host }) { return (here.identified(from: saved), .name) }
        // Kayıtlı adreste kimliği farklı bir TV yanıt verdiyse kayıtlı TV oradan taşınmıştır; adı kimliği bilinmeyenler
        // arasında aranır.
        let sameName = unknown.filter { $0.name == saved.name }
        if sameName.count == 1 { return (sameName[0].identified(from: saved), .name) }
        if found.count == 1, unknown.count == 1 { return (unknown[0].identified(from: saved), .onlyOne) }
        return nil
    }

    /// Kimliği bilinmeyen eski kayıt: TV taramada kayıtlı adreste kimliğiyle bulunduysa kimlik eklenmiş kayıt; değilse nil.
    /// (TV yeni adreste bulunursa kimlik `locate`'in döndürdüğü kayıtla zaten gelir.)
    public static func learned(_ saved: LGTV, among all: [LGTV]) -> LGTV? {
        guard !saved.hasIdentity, let (found, _) = locate(saved, among: all), found.host == saved.host,
              found.hasIdentity else { return nil }
        return saved.identified(from: found)
    }
}
