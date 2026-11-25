// SPDX-License-Identifier: AGPL-3.0-only
// SDP'deki görüntü kodekleri (#1252): teklif edilenler ve Xbox'ın yanıtta seçtiği günlüğe yazılır, tanı satırının
// "kodek" alanı ilk kare gelmeden de dolar (getStats kodeği ilk kareye kadar boştur). Android'deki XboxSdp
// (XboxCodecs.kt) ve Windows'taki XboxSdp (CouchSubs.Shell) ile aynı biçim.

import Foundation

public enum XboxSdp {
    private static let skipped: Set<String> = ["rtx", "red", "ulpfec", "flexfec-03"]

    /// `m=video` bölümündeki kodekler m= satırındaki sırayla: "H264 640c1f", "VP8". Bölüm yoksa ya da reddedildiyse boş.
    public static func videoCodecs(_ sdp: String) -> [String] {
        // Swift'te "\r\n" tek karakterdir; satırlar Foundation'la (UTF-16) bölünür.
        let lines = sdp.components(separatedBy: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        guard let start = lines.firstIndex(where: { $0.hasPrefix("m=video ") }) else { return [] }
        let media = lines[start].split(separator: " ").map(String.init)
        if media.count > 1, media[1] == "0" { return [] }
        var names: [String: String] = [:]
        var formats: [String: String] = [:]
        for line in lines[(start + 1)...] {
            if line.hasPrefix("m=") { break }
            if line.hasPrefix("a=rtpmap:") {
                let rest = line.dropFirst("a=rtpmap:".count)
                let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                names[parts[0]] = String(parts[1].split(separator: "/", maxSplits: 1).first ?? "")
            } else if line.hasPrefix("a=fmtp:") {
                let rest = line.dropFirst("a=fmtp:".count)
                let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
                formats[parts[0]] = parts.count == 2 ? parts[1] : ""
            }
        }
        var result: [String] = []
        for type in media.dropFirst(3) {
            guard let name = names[type], !skipped.contains(name.lowercased()) else { continue }
            let profile = formats[type]?.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.lowercased().hasPrefix("profile-level-id=") }
                .map { String($0.split(separator: "=", maxSplits: 1).last ?? "").lowercased() }
            let entry = name.uppercased() == "H264" && profile != nil ? "\(name) \(profile!)" : name
            if !result.contains(entry) { result.append(entry) }
        }
        return result
    }

    /// Xbox'ın yanıtta seçtiği görüntü kodeği (ilk kodek); yoksa nil.
    public static func negotiated(_ answer: String) -> String? { videoCodecs(answer).first }

    /// "SDP görüntü kodekleri: teklif H264 640c1f, H264 42e01f, VP8; Xbox yanıtı H264 640c1f"
    public static func summary(offer: String, answer: String) -> String {
        let offered = videoCodecs(offer)
        let chosen = videoCodecs(answer)
        return "SDP görüntü kodekleri: teklif \(offered.isEmpty ? "yok" : offered.joined(separator: ", ")); "
            + "Xbox yanıtı \(chosen.isEmpty ? "görüntü yok" : chosen.joined(separator: ", "))"
    }
}
