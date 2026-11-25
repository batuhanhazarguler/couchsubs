// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import CoreText
import Foundation

/// Ekran yazısının dar-kalın BÜYÜK HARF görünüşü için gömülü yazı tipi: Barlow Condensed (SIL Open Font License 1.1,
/// Resources/fonts/OFL.txt). Oyunun kendi yazı tipi telifli; özgün yazı dar (`TextLook.condensed`) olunca menü ve kutu
/// çiziminde kullanılır (Mac yayın penceresi, iPhone önizlemesi; TV style.css, Windows ve Android aynı dosyalar). Konuşma
/// satırı hiçbir zaman dar aile almaz (#1297, `ScreenFit.isDialogue`).
public enum EmbeddedFonts {
    /// PostScript adları: 400 → Medium (oyunun ince yazısı bile Regular'dan dolgun), 700 → Bold.
    public static let regular = "BarlowCondensed-Medium"
    public static let bold = "BarlowCondensed-Bold"

    private static let registered: Bool = {
        guard let folder = Bundle.module.url(forResource: "fonts", withExtension: nil) else { return false }
        var ok = true
        for name in ["BarlowCondensed-Medium.ttf", "BarlowCondensed-Bold.ttf"] {
            let url = folder.appendingPathComponent(name)
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Zaten kayıtlıysa (ikinci kayıt) hata döner; ad çözülebiliyorsa sorun yok.
                ok = ok && CTFontCreateWithName(bold as CFString, 12, nil).postScriptName == bold
            }
        }
        return ok
    }()

    /// Yazı tipleri sürece kayıtlı mı (ilk çağrıda kaydeder).
    @discardableResult
    public static func register() -> Bool { registered }

    /// Dar yazı tipinin PostScript adı (kayıt başarısızsa nil: çizici sistemin dar genişliğine döner).
    public static func condensedName(bold isBold: Bool) -> String? {
        register() ? (isBold ? bold : regular) : nil
    }

    /// Dar yazı tipiyle yazının genişliği (çizici aynı yazı tipiyle ölçer).
    public static func width(_ text: String, size: CGFloat, bold isBold: Bool) -> CGFloat? {
        guard let name = condensedName(bold: isBold) else { return nil }
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}

private extension CTFont {
    var postScriptName: String { CTFontCopyPostScriptName(self) as String }
}
