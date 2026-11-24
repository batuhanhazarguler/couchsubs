// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Ağdaki Android TV / Google TV'ler ve kimlikleri (Windows `AndroidTvDiscovery`, Android telefon `TvIdentity` ile aynı
/// kural). Android TV'ler Google Cast'in cihaz tanımını (8008 `/ssdp/device-desc.xml`) yayınlar: adı (friendlyName) ve
/// kalıcı kimliği (UDN) oradadır. Cast vermeyen ama ADB'si (5555) açık TV kimliksiz "Android TV" olarak listelenir.
public enum AndroidTVDiscovery {
    /// Google Cast cihaz tanımının adresi.
    static func descriptionURL(host: String) -> URL? { URL(string: "http://\(host):8008/ssdp/device-desc.xml") }

    /// Cihaz tanımından TV kaydı: kimlik (UDN) yoksa nil.
    static func tv(host: String, description xml: String) -> LGTV? {
        guard let uuid = TVIdentity.uuid(fromDescription: xml) else { return nil }
        return LGTV(name: LGDiscovery.friendlyName(fromDescription: xml) ?? "Android TV", host: host, brand: .androidTV, uuid: uuid)
    }

    /// Adresteki Android TV'nin kaydı (Cast cihaz tanımı okunabilirse kimlikli); okunamazsa nil.
    public static func identify(host: String) async -> LGTV? {
        guard !host.isEmpty, let url = descriptionURL(host: host),
              let (data, _) = try? await LocalNetwork.probeSession.data(from: url) else { return nil }
        return tv(host: host, description: String(decoding: data, as: UTF8.self))
    }

    /// Ev ağında (/24) Android TV'ler: Cast cihaz tanımını verenler kimlikli, yalnız ADB portu açık olanlar kimliksiz.
    public static func search(adbPort: UInt16 = 5555) async -> [LGTV] {
        await LocalNetwork.probeAll { host -> LGTV? in
            if let tv = await identify(host: host) { return tv }
            guard await DevModeInstaller.isPortOpen(host: host, port: adbPort, timeout: .milliseconds(800)) else { return nil }
            return LGTV(name: "Android TV", host: host, brand: .androidTV)
        }.map(\.value)
    }
}

/// Android TV bekçisinin yeniden bulucusu (LG ve Samsung'daki `TVLocator`'ın Android TV karşılığı; Mac, iPhone ve
/// Windows'ta aynı kural). Açma denemesi TV'ye ulaşamayınca ve kayıtlı adres hiç yanıt vermiyorsa ağ aranır (ilk
/// başarısızlıkta hemen, sonra en çok `searchInterval`'da bir); aynı TV (önce kimlikle, sonra ad ve marka kuralıyla)
/// bulunursa kayıt güncellenir ve bekçi yeni adresle hemen yeniden dener. Kimliği bilinmeyen eski kayıt, TV ilk kez
/// açıldığında kimliğini öğrenir.
public final class AndroidTVLocator: @unchecked Sendable {
    private let lock = NSLock()
    private var tv: LGTV
    private let search: @Sendable () async -> [LGTV]
    private let identify: @Sendable (String) async -> LGTV?
    private let responds: @Sendable (String) async -> Bool
    private let onMoved: @Sendable (LGTV) -> Void
    private let log: @Sendable (String) -> Void
    private let searchInterval: Duration
    private var lastSearch: ContinuousClock.Instant?
    private var identityChecked = false

    public init(tv: LGTV,
                search: @escaping @Sendable () async -> [LGTV] = { await AndroidTVDiscovery.search() },
                identify: @escaping @Sendable (String) async -> LGTV? = { await AndroidTVDiscovery.identify(host: $0) },
                responds: @escaping @Sendable (String) async -> Bool = { await TVReach.responds(host: $0, brand: .androidTV) },
                onMoved: @escaping @Sendable (LGTV) -> Void, log: @escaping @Sendable (String) -> Void = { _ in },
                searchInterval: Duration = .seconds(30)) {
        self.tv = tv
        self.search = search
        self.identify = identify
        self.responds = responds
        self.onMoved = onMoved
        self.log = log
        self.searchInterval = searchInterval
    }

    /// Şu anki adres.
    public var host: String { lock.withLock { tv.host } }

    /// Açma TV'ye ulaşamadı: kayıtlı adres sessizse ağ aranır; TV yeni adreste bulunursa kayıt güncellenir ve yeni adres
    /// döner. Adres yanıt veriyorsa, arama zamanı gelmediyse ya da TV bulunamadıysa nil.
    public func relocate() async -> String? {
        let saved = lock.withLock { tv }
        guard !saved.host.isEmpty, !(await responds(saved.host)) else { return nil }
        let now = ContinuousClock.now
        let due: Bool = lock.withLock {
            if let lastSearch, lastSearch.duration(to: now) < searchInterval { return false }
            lastSearch = now
            return true
        }
        guard due else { return nil }
        guard let (moved, how) = TVLocator.locate(saved, among: await search()), moved.host != saved.host else { return nil }
        lock.withLock { tv = moved }
        log(TVIdentity.movedLine(from: saved.host, to: moved.host, how: how))
        onMoved(moved)
        return moved.host
    }

    /// Açma başarılı: kayıtta kimlik yoksa adresteki TV'nin kimliği bir kez okunur ve kayda yazılır.
    public func learnIdentity() async {
        let saved: LGTV? = lock.withLock {
            guard !identityChecked, !tv.hasIdentity, !tv.host.isEmpty else { return nil }
            identityChecked = true
            return tv
        }
        guard let saved, let found = await identify(saved.host), found.hasIdentity else { return }
        let learned = saved.identified(from: found)
        lock.withLock { tv = learned }
        log(TVIdentity.learnedLine(learned))
        onMoved(learned)
    }
}
