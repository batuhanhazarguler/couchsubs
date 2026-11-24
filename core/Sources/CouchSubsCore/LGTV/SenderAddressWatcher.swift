// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Network

/// Bu cihazın (gönderici: Mac ya da iPhone) ev ağındaki adresi değişti mi (Windows `SenderAddressWatcher`, Android
/// `SenderAddressWatcher` ile aynı kural). Modem yeniden başlayınca ya da cihaz başka Wi-Fi'a geçince gönderici yeni adres
/// alır; TV uygulaması eski adrese bağlanmaya çalışıp ağı taramaya düşüyordu. Ağ değişince (`NWPathMonitor`) adresler
/// yeniden okunur; gerçek ev ağı adresi değiştiyse `onChange` çağrılır ve uygulama TV'ye yeni adresi hemen bildirir (LG ve
/// Samsung'da bekçinin açma komutu, Android TV'de adres komutu).
public final class SenderAddressWatcher: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "couchsubs.sender-address")
    private let read: @Sendable () -> [String]
    private let onChange: @Sendable (_ old: [String], _ new: [String]) -> Void
    private let settle: TimeInterval
    private var last: [String]
    private var generation = 0

    /// `read`: ev ağı adresleri (varsayılanı VPN, sanal ve hücresel bağdaştırıcılar dışındaki IPv4 adresleri).
    /// `settle`: ağ değişikliğinden sonra adreslerin oturması için beklenen süre.
    public init(read: @escaping @Sendable () -> [String] = SenderAddressWatcher.homeAddresses, settle: TimeInterval = 2,
                onChange: @escaping @Sendable (_ old: [String], _ new: [String]) -> Void) {
        self.read = read
        self.onChange = onChange
        self.settle = settle
        last = read()
    }

    public static let homeAddresses: @Sendable () -> [String] = {
        NetworkAddress.candidates().filter { !NetworkAddress.isVirtual($0) }.map(\.address)
    }

    public func start() {
        monitor.pathUpdateHandler = { [weak self] _ in self?.pathChanged() }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.pathUpdateHandler = nil
        monitor.cancel()
    }

    deinit { monitor.cancel() }

    private func pathChanged() {
        generation += 1
        let current = generation
        queue.asyncAfter(deadline: .now() + settle) { [weak self] in
            guard let self, self.generation == current else { return }
            self.check()
        }
    }

    /// Adresleri yeniden okur; değiştiyse (ve yeni bir adres varsa) bildirir. Testler doğrudan çağırır.
    func check() {
        let now = read()
        let old = last
        last = now
        if Self.changed(from: old, to: now) { onChange(old, now) }
    }

    /// Bildirilecek değişiklik mi: yeni adres listesi boş değil ve eskisinden farklı (sıra önemsiz). Ağ tümüyle gidince
    /// (boş) bildirilmez; adres geri gelince bildirilir.
    public static func changed(from old: [String], to new: [String]) -> Bool {
        !new.isEmpty && Set(old) != Set(new)
    }

    /// Günlük satırı.
    public static func line(old: [String], new: [String]) -> String {
        "Bu cihazın adresi değişti: \(old.isEmpty ? "-" : old.joined(separator: ", ")) → \(new.joined(separator: ", ")); TV'ye yeni adres bildiriliyor."
    }
}
