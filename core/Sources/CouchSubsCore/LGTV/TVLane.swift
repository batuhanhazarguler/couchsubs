// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// TV adresi başına tek kanal: aynı TV'ye giden geliştirici bağlantıları (Samsung sdb, Android TV ADB) sırayla çalışır.
/// Windows'taki TvLane ve Android telefondaki TvLane ile aynı kural.
///
/// #1223 (Windows beta.93, Samsung): çeviri başlarken bekçinin açma denemesi (sdb `was_execute`) ile sürüm denetimi /
/// kurulum aynı saniyede aynı TV'ye ayrı sdb oturumları açıyordu; TV bağlantıyı zorla kapatıyor, kurulum "TV bu cihazı
/// kabul etmedi" diye bitiyordu. "Güncelle"ye arka arkaya basılınca aynı TV'ye birden çok kurulum başlıyordu. Artık:
/// - Aynı TV'deki işlemler sırayla çalışır; kurulum sürerken bekçinin açma denemesi kurulumun bitmesini bekler. Takılan bir
///   işlem kanalı sonsuza dek tutmasın diye en çok `defaultMaxWait` beklenir, sonra beklemeden sürülür ve günlüğe yazılır.
/// - Aynı TV için kurulum sürerken gelen ikinci kurulum isteği yeni kurulum başlatmaz; sürenin sonucunu bekler.
///
/// iPhone'un kurucuları bloklayan (`run`, `install`), Mac'in yardımcı çağrıları async (`runAsync`, `installAsync`) yolu
/// kullanır; ikisi aynı kanaldan geçer. Aynı iş parçacığında iç içe çağrı (kanalı tutan işlemin aynı TV'ye yeniden girmesi)
/// beklemeden çalışır.
public final class TVLane: @unchecked Sendable {
    /// Kanalı tutan işlem en çok bu kadar beklenir (kurulumun her adımının ayrıca süre sınırı var, bkz. TVStall).
    public static let defaultMaxWait: TimeInterval = 300

    /// Uygulamanın ortak kanalı.
    public static let shared = TVLane()

    private let maxWait: TimeInterval
    private let lock = NSLock()
    private var gates: [String: DispatchSemaphore] = [:]
    private var busy: Set<String> = []
    private var installs: [String: Install] = [:]
    /// Bu iş parçacığının tuttuğu kanallar (yalnız bloklayan yol).
    private static let heldKey = "CouchSubs.TVLane.held"

    public init(maxWait: TimeInterval = TVLane.defaultMaxWait) {
        self.maxWait = maxWait
    }

    /// Kanalın anahtarı: adres, boşluksuz ve küçük harfle.
    public static func key(_ host: String) -> String { host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// Bu TV'de şu an bir işlem sürüyor mu.
    public func isBusy(_ host: String) -> Bool { lock.withLock { busy.contains(Self.key(host)) } }

    /// Bu TV'de şu an kurulum sürüyor mu.
    public func isInstalling(_ host: String) -> Bool { lock.withLock { installs[Self.key(host)] != nil } }

    private func gate(_ key: String) -> DispatchSemaphore {
        lock.withLock {
            if let gate = gates[key] { return gate }
            let gate = DispatchSemaphore(value: 1)
            gates[key] = gate
            return gate
        }
    }

    private var held: Set<String> {
        get { Thread.current.threadDictionary[Self.heldKey] as? Set<String> ?? [] }
        set { Thread.current.threadDictionary[Self.heldKey] = newValue }
    }

    /// Kanala girer; girildiyse true (süre dolduysa false: beklemeden sürülür). Bloklar.
    private func enter(_ host: String, _ key: String, _ what: String, _ log: (String) -> Void) -> Bool {
        let gate = gate(key)
        var entered = gate.wait(timeout: .now()) == .success
        if !entered {
            log("TV \(host): aynı TV'de başka bir işlem sürüyor; \(what) sırasını bekliyor (aynı anda iki bağlantıyı TV kapatıyor)")
            entered = gate.wait(timeout: .now() + maxWait) == .success
            if !entered {
                log("TV \(host): önceki işlem \(Int(maxWait / 60)) dk'da bitmedi; \(what) beklemeden başlıyor")
            }
        }
        lock.withLock { _ = busy.insert(key) }
        return entered
    }

    private func leave(_ key: String, entered: Bool) {
        lock.withLock { _ = busy.remove(key) }
        if entered { gate(key).signal() }
    }

    /// `work`'ü bu TV'nin kanalında çalıştırır: aynı TV'deki başka işlem bitene kadar bekler. Bloklar.
    public func run<T>(host: String, _ what: String, log: (String) -> Void = { _ in }, _ work: () throws -> T) rethrows -> T {
        let key = Self.key(host)
        if key.isEmpty || held.contains(key) { return try work() }
        let entered = enter(host, key, what, log)
        let before = held
        held = before.union([key])
        defer {
            held = before
            leave(key, entered: entered)
        }
        return try work()
    }

    /// `work`'ü bu TV'nin kanalında çalıştırır (async; beklerken iş parçacığı havuzunu tıkamaz).
    public func runAsync<T: Sendable>(host: String, _ what: String, log: @escaping @Sendable (String) -> Void = { _ in },
                                      _ work: @Sendable () async throws -> T) async rethrows -> T {
        let key = Self.key(host)
        if key.isEmpty { return try await work() }
        let entered: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.enter(host, key, what, log))
            }
        }
        defer { leave(key, entered: entered) }
        return try await work()
    }

    /// Süren bir kurulum: bitince `done` sinyallenir, sonucu bekleyenlere dağıtılır (her bekleyen sinyali sonrakine aktarır).
    private final class Install: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        var result: Result<Any, Error>?

        /// Bitene kadar bloklar.
        func wait() -> Result<Any, Error>? {
            done.wait()
            done.signal()
            return result
        }
    }

    /// Bu TV'nin süren kurulumu varsa onu (katılan), yoksa yenisini (sahibi) döndürür.
    private func claim(_ key: String) -> (Install, owner: Bool) {
        lock.withLock {
            if let running = installs[key] { return (running, false) }
            let mine = Install()
            installs[key] = mine
            return (mine, true)
        }
    }

    private func finish(_ key: String, _ install: Install, _ result: Result<Any, Error>) {
        install.result = result
        lock.withLock { installs[key] = nil }
        install.done.signal()
    }

    private static func joinedLine(_ host: String) -> String {
        "TV \(host): kurulum zaten sürüyor; yeni kurulum başlatılmadı, sürenin bitmesi bekleniyor"
    }

    /// Kurulumu bu TV'nin kanalında çalıştırır. Aynı TV'de kurulum zaten sürüyorsa yenisi başlatılmaz: sürenin sonucu (ya da
    /// hatası) döner. Bloklar.
    public func install<T>(host: String, log: (String) -> Void = { _ in }, _ work: () throws -> T) throws -> T {
        let key = Self.key(host)
        if key.isEmpty || held.contains(key) { return try work() }
        let (install, owner) = claim(key)
        if !owner {
            log(Self.joinedLine(host))
            return try Self.value(install.wait(), or: work)
        }
        do {
            let value = try run(host: host, "kurulum", log: log, work)
            finish(key, install, .success(value))
            return value
        } catch {
            finish(key, install, .failure(error))
            throw error
        }
    }

    /// Kurulumu bu TV'nin kanalında çalıştırır (async). Aynı TV'de kurulum zaten sürüyorsa yenisi başlatılmaz.
    public func installAsync<T: Sendable>(host: String, log: @escaping @Sendable (String) -> Void = { _ in },
                                          _ work: @Sendable () async throws -> T) async throws -> T {
        let key = Self.key(host)
        if key.isEmpty { return try await work() }
        let (install, owner) = claim(key)
        if !owner {
            log(Self.joinedLine(host))
            // Bitmesi bir iş parçacığında beklenir (havuz tıkanmasın).
            let result: Result<Any, Error>? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async { continuation.resume(returning: install.wait()) }
            }
            return try await Self.value(result, or: work)
        }
        do {
            let value = try await runAsync(host: host, "kurulum", log: log, work)
            finish(key, install, .success(value))
            return value
        } catch {
            finish(key, install, .failure(error))
            throw error
        }
    }

    /// Bekleyenin sonucu; tür tutmazsa (olmamalı) kendi işini çalıştırır.
    private static func value<T>(_ result: Result<Any, Error>?, or work: () throws -> T) throws -> T {
        switch result {
        case .success(let value as T): return value
        case .failure(let error): throw error
        default: return try work()
        }
    }

    private static func value<T>(_ result: Result<Any, Error>?, or work: () async throws -> T) async throws -> T {
        switch result {
        case .success(let value as T): return value
        case .failure(let error): throw error
        default: return try await work()
        }
    }
}
