// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Kamerayla kayan yazı (plaka, tabela, dükkân adı, haritadaki yer adı) altyazı değildir. Oyunun altyazısı ekranda hep
/// aynı yerde ve aynı boyda durur; oyun dünyasındaki yazı ise kamera, araç ya da harita oynadıkça yana kayar ya da
/// yaklaşıp büyür. Kullanıcı bildirimleri (GitHub #1259, #1203, GTA 6, Mac, "Ekran yazılarını otomatik çevir" kapalı):
/// "MOTOR OIL MOTOR OIL" benzin istasyonu tabelası, "Game Base" dükkân adı, haritada "Tola Bay", teknedeki "Charters"
/// yazısı altyazı alanından okunup çevriliyor, "Charters / We're doing that tomorrow." diye konuşmanın başına
/// yapışıyordu. Bunlar kısa ve tek satır olduğu için `SceneText`'in plaka (alt alta büyük harfli satırlar) ve eğik satır
/// kurallarına takılmıyordu.
///
/// Aynı yazı (birebir aynı okunan satır) `windowMs` içinde yatay ortası karenin genişliğinin `shift` kadarı kaydıysa ya
/// da boyu `scale` katı değiştiyse kayan yazıdır; son kaydığı andan `holdMs` sonrasına dek okumadan çıkarılır (yerine
/// oturan yazı yeniden aday olur). Gerçek altyazıyı düşürmemek için:
/// - konuşan adlı satır ("Jason: …") hiç çıkarılmaz;
/// - küçük harfli ve `maxWords`'ten uzun satır (konuşma cümlesi) çıkarılmaz; yalnız kısa satır ya da küçük harfsiz yazı;
/// - yalnız yatay kayma ve boy değişimi sayılır: alttan yeni satır gelince yukarı itilen altyazı satırının yatay ortası
///   ve boyu değişmez;
/// - yalnız birebir aynı okuma karşılaştırılır: yazı yazılır gibi beliren ya da farklı okunan satır eşleşmez;
/// - önceki okumaların biriyle karşılaştırılır (aynı karede iki aynı tabela kayma sayılmaz).
/// Tek karede (ilk görüş) hiçbir şey çıkarılmaz; gerçek kare gerileme seti bu yüzden etkilenmez.
/// Windows (SceneMotion.cs) ve Android (SceneMotion.kt) aynı kuralları ve eşikleri uygular; ortak deneme dosyası
/// Tests/CouchSubsCoreTests/Fixtures/scene-motion.json.
public struct SceneMotion {
    /// Kayma bu süre içindeki ilk görüşe göre ölçülür (yavaş kayan yazı birikerek yakalanır).
    public static let windowMs = 2000
    /// Yatay ortanın en az bu kadar kayması (karenin genişliğine oranla; 1920 piksellik karede yaklaşık 38 piksel).
    /// Yazı tanımanın aynı yazıda kutu oynaması bunun çok altındadır.
    public static let shift = 0.02
    /// Satır boyu en az bu kat değişirse (yaklaşan/uzaklaşan tabela) kayan yazıdır.
    public static let scale = 1.4
    /// Son kaymadan bu kadar sonra yazı yeniden aday olur.
    public static let holdMs = 1000
    /// Küçük harfli satır en çok bu kadar sözcükse kayan yazı sayılabilir ("Charters", "Game Base", "Tola Bay").
    public static let maxWords = 3
    /// Günlükte atılma nedeni.
    public static let reason = "kayan yazı (kamerayla kayan tabela/plaka)"

    struct Anchor {
        var text: String
        var center: Double
        var height: Double
        var since: Int
        var lastSeen: Int
        var movedAt: Int?
    }

    private var anchors: [Anchor] = []
    /// Son `filter` çağrısında kayan yazı sayılıp okumadan çıkarılan satırlar (günlük için).
    public private(set) var removed: [TextLine] = []

    public init() {}

    /// Okumanın kayan yazıları çıkarılmış hali. Satır kutuları `area`'ya oranlıdır; `area` okunan alanın karedeki yeridir.
    /// `time`: milisaniye saati.
    public mutating func filter(_ reading: Reading, in area: TextBox, at time: Int) -> Reading {
        removed = []
        anchors.removeAll { time - $0.lastSeen > Self.windowMs }
        let previous = anchors.indices.filter { anchors[$0].since < time }
        var used = Set<Int>()
        var fresh: [Anchor] = []
        var kept: [TextLine] = []
        for line in reading.lines {
            guard let box = line.box?.placed(in: area), Self.eligible(line.text) else { kept.append(line); continue }
            let text = Self.key(line.text)
            let center = (box.left + box.right) / 2, height = box.bottom - box.top
            let same = previous.filter { !used.contains($0) && anchors[$0].text == text }
            guard let index = same.min(by: { abs(anchors[$0].center - center) < abs(anchors[$1].center - center) }) else {
                fresh.append(Anchor(text: text, center: center, height: height, since: time, lastSeen: time))
                kept.append(line)
                continue
            }
            used.insert(index)
            anchors[index].lastSeen = time
            if Self.moved(from: anchors[index], center: center, height: height) {
                anchors[index].movedAt = time
                anchors[index].center = center
                anchors[index].height = height
                anchors[index].since = time
            } else if time - anchors[index].since > Self.windowMs {
                // Yerinde duran yazının ölçüsü tazelenir: çok yavaş kayma (pencere başına `shift`'ten az) birikmez.
                anchors[index].center = center
                anchors[index].height = height
                anchors[index].since = time
            }
            if let moved = anchors[index].movedAt, time - moved <= Self.holdMs {
                removed.append(line)
            } else {
                kept.append(line)
            }
        }
        anchors += fresh
        return removed.isEmpty ? reading : Reading(lines: kept)
    }

    public mutating func reset() {
        anchors = []
        removed = []
    }

    /// Satır kayan yazı sayılabilir mi: konuşan adı yok, en az üç harf/rakam; küçük harf taşıyorsa en çok `maxWords`
    /// sözcük (konuşma cümlesi hiç çıkarılmaz).
    static func eligible(_ text: String) -> Bool {
        guard SpeakerPrefix.split(text) == nil, text.filter({ $0.isLetter || $0.isNumber }).count >= 3 else { return false }
        return !text.contains(where: \.isLowercase) || SceneText.wordCount(text) <= maxWords
    }

    static func key(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces).lowercased() }

    static func moved(from anchor: Anchor, center: Double, height: Double) -> Bool {
        if abs(center - anchor.center) >= shift { return true }
        guard anchor.height > 0, height > 0 else { return false }
        return max(height, anchor.height) >= scale * min(height, anchor.height)
    }
}
