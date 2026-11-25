// SPDX-License-Identifier: AGPL-3.0-only
// Masaüstündeki windows/src/CouchSubs.TvInstall/TvStall.cs ve Android'deki tv/TvStall.kt ile aynı adımlar ve süreler.

import Foundation

/// Kurulumun bir adımı süresinde bitmedi: TV yanıt vermeyi kesti, bağlantı kapatıldı.
struct TVStepTimeout: Error, CustomStringConvertible {
    /// Takılan adım ("installing", "launching" …).
    let step: String
    let limit: TimeInterval

    var description: String { "TV \"\(TVStall.name(step))\" adımında \(Int(limit)) sn yanıt vermedi" }

    /// İkinci denemede de takılınca kullanıcıya gösterilen ayrıntı.
    var gaveUp: String { "\(description); bir kez daha denendi, TV yine yanıt vermedi" }
}

/// TV uygulaması güncellemesinin bekçisi: her adımın (bağlanma, sürümü okuma, eski uygulamayı kapatma, kurulum, açma) süre
/// sınırı vardır; süre dolunca TV bağlantısı kapatılır, bekleyen okuma hatayla döner ve deneme `TVStepTimeout` ile biter.
/// Önceden yalnız soketin 120 sn'lik okuma süresi vardı, yeniden deneme yoktu: TV takılınca güncelleme dakikalarca
/// "kuruluyor"da kalıp "bağlantı koptu" diyordu.
final class TVStall: @unchecked Sendable {
    /// Adımların süre sınırı; kullanıcının bir şey yaptığı adımlarda (Samsung girişi, TV'deki Play sayfası) sınır yoktur.
    /// Android TV'de onay adımı TV'deki soruyu (en çok 90 sn) bekler.
    static func limit(for step: String) -> TimeInterval? {
        switch step {
        case "connecting": 45
        case "approve": 150
        case "pairing", "reading", "launching": 60
        case "signin", "play": nil
        case "certificate": 240
        case "closing": 30
        case "installing": 360
        default: 120
        }
    }

    /// Adımın günlükte ve hata ayrıntısında görünen adı.
    static func name(_ step: String) -> String {
        switch step {
        case "connecting": "bağlanma"
        case "approve": "TV'de onay"
        case "pairing": "eşleme"
        case "reading": "TV'deki sürümü okuma"
        case "certificate": "sertifika"
        case "signing": "paket imzalama"
        case "closing": "eski uygulamayı kapatma"
        case "installing": "paket gönderme ve kurulum"
        case "uninstalling": "eski kopyayı kaldırma"
        case "launching": "uygulamayı açma"
        default: step
        }
    }

    /// Arayüzün adımı bekçinin adımına.
    static func key(_ step: InstallStep) -> String {
        switch step {
        case .connecting: "connecting"
        case .reading: "reading"
        case .signIn: "signin"
        case .certificate: "certificate"
        case .signing: "signing"
        case .installing: "installing"
        case .uninstalling: "uninstalling"
        case .launching: "launching"
        case .pairing: "pairing"
        case .approveOnTV: "approve"
        case .key: "key"
        case .openPlay: "play"
        }
    }

    private let lock = NSLock()
    private let limits: (String) -> TimeInterval?
    private var generation = 0
    private var current = ""
    private var currentLimit: TimeInterval = 0
    private var closers: [() -> Void] = []
    private var stalledStep: String?
    private var finished = false

    init(limits: @escaping (String) -> TimeInterval? = TVStall.limit(for:)) {
        self.limits = limits
        enter("connecting")
    }

    /// Takıldı mı; takıldıysa adımın hatası.
    var timeout: TVStepTimeout? {
        lock.withLock { stalledStep.map { TVStepTimeout(step: $0, limit: currentLimit) } }
    }

    /// Yeni adıma geçildi: süre baştan başlar (sınırsız adımda süre durur).
    func enter(_ step: String) {
        let armed: (Int, TimeInterval)? = lock.withLock {
            guard stalledStep == nil, !finished else { return nil }
            generation += 1
            current = step
            guard let limit = limits(step) else { return nil }
            currentLimit = limit
            return (generation, limit)
        }
        guard case let (generation, limit)? = armed else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + limit) { [weak self] in self?.fire(generation) }
    }

    func enter(_ step: InstallStep) { enter(Self.key(step)) }

    /// Takılınca çalışacak kapatma (TV bağlantısı); bekleyen okuma böylece hatayla biter.
    func onStall(_ close: @escaping () -> Void) {
        let now = lock.withLock { () -> Bool in
            if stalledStep == nil { closers.append(close) }
            return stalledStep != nil
        }
        if now { close() }
    }

    private func fire(_ armed: Int) {
        let close: [() -> Void]? = lock.withLock {
            guard armed == generation, stalledStep == nil, !finished else { return nil }
            stalledStep = current
            return closers
        }
        close?.forEach { $0() }
    }

    /// Denemeyi bekçiyle çalıştırır. Adım takıldıysa sonuç her durumda `TVStepTimeout` olur: takılmış bağlantının yuttuğu
    /// hata ("kurulum tamam" ama uygulama açılamadı) da sessiz geçmez.
    func run<T>(_ body: () throws -> T) throws -> T {
        defer { lock.withLock { finished = true } }
        let result: T
        do {
            result = try body()
        } catch let timeout as TVStepTimeout {
            throw timeout
        } catch {
            if let timeout { throw timeout }
            throw error
        }
        if let timeout { throw timeout }
        return result
    }

    /// İlk deneme takıldıysa ya da bağlantı koptuysa (`retryable`) günlüğe yazılır ve yeni bağlantıyla bir kez daha denenir.
    /// İkinci denemenin hatası olduğu gibi yükselir.
    static func retryOnce<T>(log: InstallLog, retryable: (Error) -> Bool, _ attempt: (Int) throws -> T) throws -> T {
        do {
            return try attempt(1)
        } catch where retryable(error) {
            log.write("Takıldı: \(error); bağlantı kapatıldı, bir kez daha deneniyor.")
        }
        return try attempt(2)
    }
}
