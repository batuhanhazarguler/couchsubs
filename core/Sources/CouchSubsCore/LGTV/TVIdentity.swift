// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// TV'nin kalıcı kimliği: SSDP yanıtındaki USN, cihaz tanımındaki UDN, Samsung'un 8001 yanıtındaki `id`/`wifiMac`
/// (Windows `TvIdentity`, Android `TvIdentity` ile aynı kural). Adres değişir, ad kullanıcı tarafından değiştirilebilir ve
/// aynı evde aynı adlı iki TV olabilir; kimlik değişmez.
public enum TVIdentity {
    /// "uuid:ABC-123::urn:..." → "abc-123". Boşsa nil.
    public static func normalizedUUID(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let range = text.range(of: "::") { text = String(text[..<range.lowerBound]) }
        if text.lowercased().hasPrefix("uuid:") { text = String(text.dropFirst(5)) }
        text = text.trimmingCharacters(in: .whitespaces).lowercased()
        return text.isEmpty ? nil : text
    }

    /// "AA-BB-CC-DD-EE-FF" / "aabbccddeeff" → "aa:bb:cc:dd:ee:ff". 12 onaltılık hane değilse ya da sıfırsa nil.
    public static func normalizedMAC(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let hex = raw.lowercased().filter { $0.isHexDigit }
        let separators = raw.filter { !$0.isHexDigit && !$0.isWhitespace }
        guard hex.count == 12, separators.allSatisfy({ $0 == ":" || $0 == "-" || $0 == "." }),
              hex != "000000000000", hex != "ffffffffffff" else { return nil }
        var pairs: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            pairs.append(String(hex[index..<next]))
            index = next
        }
        return pairs.joined(separator: ":")
    }

    /// SSDP yanıtındaki USN başlığından kimlik ("USN: uuid:...::urn:..."); yoksa nil.
    public static func uuid(fromSSDPResponse response: String) -> String? {
        for line in response.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0].uppercased() == "USN" else { continue }
            return normalizedUUID(parts[1])
        }
        return nil
    }

    /// UPnP cihaz tanımındaki ilk `<UDN>` (kök cihaz); yoksa nil.
    public static func uuid(fromDescription xml: String) -> String? {
        guard let start = xml.range(of: "<UDN>", options: .caseInsensitive),
              let end = xml.range(of: "</UDN>", options: .caseInsensitive, range: start.upperBound..<xml.endIndex) else { return nil }
        return normalizedUUID(String(xml[start.upperBound..<end.lowerBound]))
    }

    /// İki kayıt aynı cihaz mı: ikisinde de uuid varsa uuid, yoksa ikisinde de mac varsa mac karşılaştırılır. Kıyaslanacak
    /// kimlik yoksa nil (bilinmiyor; eski ad ve marka kuralına düşülür).
    public static func sameDevice(_ a: LGTV, _ b: LGTV) -> Bool? {
        if let x = a.uuid, let y = b.uuid { return x == y }
        if let x = a.mac, let y = b.mac { return x == y }
        return nil
    }

    /// Yeniden bulmanın günlük satırı: "TV yeni adreste bulundu: eski → yeni (UUID ile)".
    public static func movedLine(from old: String, to new: String, how: Match) -> String {
        "TV yeni adreste bulundu: \(old) → \(new) (\(how.rawValue))"
    }

    /// Eski kayda kimlik yazıldı: "TV kimliği kayda yazıldı: 192.168.1.5 (UUID abcd…)".
    public static func learnedLine(_ tv: LGTV) -> String {
        let id = tv.uuid.map { "UUID \($0)" } ?? tv.mac.map { "MAC \($0)" } ?? "-"
        return "TV kimliği kayda yazıldı: \(tv.host) (\(id))"
    }

    /// Kayıtlı TV'nin taramada nasıl tanındığı.
    public enum Match: String, Sendable {
        case uuid = "UUID ile"
        case mac = "MAC ile"
        case name = "ad ile"
        case onlyOne = "ağdaki tek TV"
    }
}
