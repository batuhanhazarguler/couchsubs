// SPDX-License-Identifier: AGPL-3.0-only
// RTCDefaultVideoDecoderFactory'yi sarar (#1252): teklif edilen kodekler ve çözücüler aynı kalır, yalnız kurulan
// çözücünün adı tanı satırının "çözücü" alanına yazılır (getStats'ın decoderImplementation'ı ilk kare çözülene kadar
// boştur). Android'deki XboxDecoderFactory + XboxDecoderNote ile aynı biçim.

import Foundation
import WebRTC

final class XboxDecoderFactory: NSObject, RTCVideoDecoderFactory, @unchecked Sendable {
    private let inner = RTCDefaultVideoDecoderFactory()
    private let lock = NSLock()
    private var current: String?

    /// "H264 VideoToolbox (donanım)"; libwebrtc çözücüyü ilk görüntü karesi gelince kurar, kurulmadıysa nil.
    var note: String? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Yeni bağlantıdan önce: önceki bağlantının çözücüsü tanıya karışmaz.
    func reset() {
        lock.lock()
        current = nil
        lock.unlock()
    }

    func createDecoder(_ info: RTCVideoCodecInfo) -> RTCVideoDecoder? {
        let decoder = inner.createDecoder(info)
        let text = decoder.map { Self.describe(codec: info.name, implementation: $0.implementationName()) }
            ?? "\(info.name) bu cihazda çözücü yok"
        lock.lock()
        current = text
        lock.unlock()
        return decoder
    }

    func supportedCodecs() -> [RTCVideoCodecInfo] { inner.supportedCodecs() }

    static func describe(codec: String, implementation: String) -> String {
        "\(codec) \(implementation) (\(implementation.localizedCaseInsensitiveContains("VideoToolbox") ? "donanım" : "yazılım"))"
    }
}
