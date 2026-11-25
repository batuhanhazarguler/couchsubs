// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation

/// Telefon listesi kartlarının (`ScreenPhoneCard.ListRow`) oyundan kesilen görüntüleri: avatar (bileşende simge), sağdaki
/// rozet ve seçili satırın çerçevesi. Sinan Bey (beta.100, 3399): kart telefondaki satırın Türkçe kopyası olsun; avatar,
/// okunmamış kırmızı nokta (avatarın köşesinde, kesilen resmin içinde kalır), rozet ve seçim çerçevesi de.
///
/// Kararlılık (#1279): aynı satırın resmi bir kez kesilir ve saklanır (anahtar: kişi adının özgün yazısı); her okumada
/// yeniden kesilen resim, sıkıştırma gürültüsüyle her gönderiyi farklı gösterip TV'de titretirdi. Rozet ve seçim ancak
/// art arda `turns` okumada aynı yeni değeri gösterirse değişir. Resimler küçük PNG'dir (en çok `avatarMax` piksel).
/// Windows (PhoneListLook.cs) ve Android (PhoneListLook.kt) aynı kuralı, aynı eşikleri kullanır.
public final class PhoneListLook: @unchecked Sendable {
    /// Avatarın ve rozetin en uzun kenarı (piksel).
    public static let avatarMax = 48, badgeMax = 32
    /// Rozet ve seçim bu kadar art arda okumada aynı yeni değeri gösterirse değişir.
    static let turns = 2
    /// En çok bu kadar satır saklanır (dolunca hepsi unutulur).
    static let capacity = 64

    struct Entry {
        var avatar: String?
        var badge: String?
        var selected: String?
        var pendingBadge: String??
        var pendingSelected: String??
        var badgeVotes = 0, selectedVotes = 0
    }
    private var entries: [String: Entry] = [:]
    private let lock = NSLock()

    public init() {}

    public func clear() { lock.withLock { entries.removeAll() } }

    /// Kare (CGImage) üzerinden.
    public func apply(_ items: [ScreenTranslation.Item], frame: CGImage) -> [ScreenTranslation.Item] {
        guard items.contains(where: { $0.listRow != nil }), let pixels = GamePhonePixels(frame) else { return items }
        return apply(items, width: pixels.width, height: pixels.height) { x, y in
            let p = pixels.offset(x, y)
            return (Int(pixels.bytes[p]), Int(pixels.bytes[p + 1]), Int(pixels.bytes[p + 2]))
        }
    }

    /// Liste kartlarına resimleri koyar. `color`: karenin (x, y) pikseli.
    public func apply(_ items: [ScreenTranslation.Item], width: Int, height: Int,
                      color: (Int, Int) -> TextPainter.RGB) -> [ScreenTranslation.Item] {
        guard width > 0, height > 0 else { return items }
        return lock.withLock {
            if entries.count > Self.capacity { entries.removeAll() }
            return items.map { item in
                guard var row = item.listRow else { return item }
                let key = (row.widget ? "w|" : "r|") + (item.source.split(separator: "\n").first.map(String.init) ?? item.source)
                var entry = entries[key] ?? Entry()
                if entry.avatar == nil, let spot = row.portraitSpot {
                    entry.avatar = TextPainter.portraitImage(spot, width: width, height: height, largest: Self.avatarMax, color: color)
                }
                if let spot = row.badgeSpot {
                    let fresh = Self.hasBadge(spot, width: width, height: height, color: color)
                        ? TextPainter.portraitImage(spot, width: width, height: height, largest: Self.badgeMax, color: color) : nil
                    Self.vote(fresh, current: &entry.badge, pending: &entry.pendingBadge, votes: &entry.badgeVotes,
                              same: { ($0 == nil) == ($1 == nil) }, first: entries[key] == nil)
                }
                if let spot = row.frameSpot {
                    let fresh = Self.frameColor(spot, width: width, height: height, color: color)
                    Self.vote(fresh, current: &entry.selected, pending: &entry.pendingSelected, votes: &entry.selectedVotes,
                              same: { ($0 == nil) == ($1 == nil) }, first: entries[key] == nil)
                }
                entries[key] = entry
                row.avatar = entry.avatar
                row.badge = entry.badge
                row.selected = entry.selected
                var placed = item
                placed.listRow = row
                return placed
            }
        }
    }

    /// Yeni değer (`same` ile aynı sayılmayan) art arda `turns` okumada gelirse geçer; ilk görülen satırda hemen geçer.
    static func vote(_ fresh: String?, current: inout String?, pending: inout String??, votes: inout Int,
                     same: (String?, String?) -> Bool, first: Bool) {
        if first {
            current = fresh
            return
        }
        if same(fresh, current) {
            votes = 0
            pending = nil
            return
        }
        if let waiting = pending, same(waiting, fresh) { votes += 1 } else {
            pending = .some(fresh)
            votes = 1
        }
        if votes >= turns {
            current = fresh
            votes = 0
            pending = nil
        }
    }

    /// Örnek ızgarası (kutunun içinde `columns`×`rows` nokta).
    static func samples(_ box: TextBox, width: Int, height: Int, columns: Int, rows: Int,
                        color: (Int, Int) -> TextPainter.RGB) -> [[TextPainter.RGB]] {
        (0..<rows).map { j in
            let y = min(height - 1, max(0, Int((box.top + (Double(j) + 0.5) / Double(rows) * (box.bottom - box.top)) * Double(height))))
            return (0..<columns).map { i in
                let x = min(width - 1, max(0, Int((box.left + (Double(i) + 0.5) / Double(columns) * (box.right - box.left)) * Double(width))))
                return color(x, y)
            }
        }
    }

    /// Belirgin mavi (seçim çerçevesi, gönder rozeti).
    static func isBlue(_ c: TextPainter.RGB) -> Bool { c.b >= 140 && c.b - (c.r + c.g) / 2 >= 45 }

    /// Satırın üstünde seçim çerçevesi var mı: kutunun bir yatay sırasındaki noktaların en az `frameShare`'i mavi. Varsa
    /// çerçevenin rengi (mavi noktaların ortalaması).
    static let frameShare = 0.6
    static func frameColor(_ box: TextBox, width: Int, height: Int, color: (Int, Int) -> TextPainter.RGB) -> String? {
        let grid = samples(box, width: width, height: height, columns: 24, rows: 12, color: color)
        for line in grid {
            let blue = line.filter(isBlue)
            if Double(blue.count) >= Double(line.count) * frameShare {
                let r = blue.reduce(0) { $0 + $1.r } / blue.count, g = blue.reduce(0) { $0 + $1.g } / blue.count
                let b = blue.reduce(0) { $0 + $1.b } / blue.count
                return String(format: "#%02X%02X%02X", r, g, b)
            }
        }
        return nil
    }

    /// Rozetin yerinde düz kart zemini değil bir simge var mı: noktaların en az `badgeShare`'i zeminden (kutunun
    /// köşelerinin ortancası) belirgin farklı ve renkli/koyu.
    static let badgeShare = 0.12
    static func hasBadge(_ box: TextBox, width: Int, height: Int, color: (Int, Int) -> TextPainter.RGB) -> Bool {
        let grid = samples(box, width: width, height: height, columns: 10, rows: 10, color: color)
        let corners = [grid[0][0], grid[0][9], grid[9][0], grid[9][9]]
        func tone(_ c: TextPainter.RGB) -> Int { (c.r + 2 * c.g + c.b) / 4 }
        let base = corners.map(tone).sorted()[1]
        let marked = grid.joined().filter { c in
            let chroma = max(c.r, c.g, c.b) - min(c.r, c.g, c.b)
            return chroma >= 60 && abs(tone(c) - base) >= 25
        }.count
        return Double(marked) >= 100 * badgeShare
    }
}
