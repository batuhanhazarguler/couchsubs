// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

/**
 * TV'nin kalıcı kimliği: SSDP yanıtındaki USN, cihaz tanımındaki UDN, Samsung'un 8001 yanıtındaki `id`/`wifiMac`, Android
 * TV'de Google Cast cihaz tanımının UDN'si (Mac/iPhone `TVIdentity`, Windows `TvIdentity` ile aynı kural). Adres değişir,
 * ad değiştirilebilir ve aynı evde aynı adlı iki TV olabilir; kimlik değişmez.
 */
object TvIdentity {
    /** Kayıtlı TV'nin taramada nasıl tanındığı (günlükte parantez içinde). */
    enum class Match(val text: String) { UUID("UUID ile"), MAC("MAC ile"), NAME("ad ile"), ONLY_ONE("ağdaki tek TV") }

    /** "uuid:ABC-123::urn:..." → "abc-123". Boşsa null. */
    fun normalizedUuid(raw: String?): String? {
        var text = raw?.trim().orEmpty()
        if (text.isEmpty()) return null
        text = text.substringBefore("::")
        if (text.startsWith("uuid:", ignoreCase = true)) text = text.substring(5)
        return text.trim().lowercase().ifEmpty { null }
    }

    /** "AA-BB-CC-DD-EE-FF" / "aabbccddeeff" → "aa:bb:cc:dd:ee:ff". 12 onaltılık hane değilse ya da sıfırsa null. */
    fun normalizedMac(raw: String?): String? {
        raw ?: return null
        val isHex = { c: Char -> c in '0'..'9' || c.lowercaseChar() in 'a'..'f' }
        val hex = raw.filter(isHex).lowercase()
        val separators = raw.filter { !isHex(it) && !it.isWhitespace() }
        if (hex.length != 12 || separators.any { it != ':' && it != '-' && it != '.' } || hex == "000000000000" || hex == "ffffffffffff") return null
        return hex.chunked(2).joinToString(":")
    }

    /** SSDP yanıtındaki USN başlığından kimlik; yoksa null. */
    fun uuidFromSsdp(response: String): String? {
        for (line in response.split("\r\n")) {
            val colon = line.indexOf(':')
            if (colon < 0 || !line.substring(0, colon).trim().equals("USN", ignoreCase = true)) continue
            return normalizedUuid(line.substring(colon + 1))
        }
        return null
    }

    /** UPnP cihaz tanımındaki ilk `<UDN>` (kök cihaz); yoksa null. */
    fun uuidFromDescription(xml: String?): String? {
        xml ?: return null
        val start = xml.indexOf("<UDN>", ignoreCase = true)
        val end = if (start < 0) -1 else xml.indexOf("</UDN>", start, ignoreCase = true)
        return if (end < 0) null else normalizedUuid(xml.substring(start + 5, end))
    }

    /** Samsung 8001 `/api/v2/` yanıtındaki kimlik: (`device.id` ya da `id`, `device.wifiMac`). */
    fun samsungIdentity(json: String?): Pair<String?, String?> {
        val root = json?.let { runCatching { org.json.JSONObject(it) }.getOrNull() } ?: return null to null
        val device = root.optJSONObject("device")
        val uuid = normalizedUuid(device?.optString("id")) ?: normalizedUuid(root.optString("id"))
        return uuid to normalizedMac(device?.optString("wifiMac"))
    }

    fun hasIdentity(tv: FoundTv) = normalizedUuid(tv.uuid) != null || normalizedMac(tv.mac) != null

    /** İki kayıt aynı cihaz mı: ikisinde de uuid varsa uuid, yoksa ikisinde de mac varsa mac; kıyaslanamazsa null. */
    fun sameDevice(a: FoundTv, b: FoundTv): Boolean? {
        val x = normalizedUuid(a.uuid)
        val y = normalizedUuid(b.uuid)
        if (x != null && y != null) return x == y
        val m = normalizedMac(a.mac)
        val n = normalizedMac(b.mac)
        if (m != null && n != null) return m == n
        return null
    }

    /** Bilinmeyen kimlik alanları [other]'dan tamamlanır (ad, adres ve marka bu kaydınki kalır). */
    fun identified(tv: FoundTv, other: FoundTv) = tv.copy(
        uuid = normalizedUuid(tv.uuid) ?: normalizedUuid(other.uuid),
        mac = normalizedMac(tv.mac) ?: normalizedMac(other.mac),
    )

    /**
     * Bulunanlar içinde kayıtlı TV (kayıtlı adreste de olabilir) ve nasıl tanındığı (Mac `TVLocator.locate` ile aynı).
     * Kimlik önce gelir: kayıtta uuid ya da mac varsa aynı kimlikli TV seçilir; kimliği farklı TV (adı aynı olsa da, kayıtlı
     * adreste olsa da) asla seçilmez. Kimlikle bulunamazsa kimliği bilinmeyenler arasında eski kural: kayıtlı adres, aynı
     * marka ve aynı ad tekse o, değilse markada tek TV varsa o. Dönen kayıtta kimlik kayıttakinden tamamlanır.
     */
    fun locate(saved: FoundTv, all: List<FoundTv>): Pair<FoundTv, Match>? {
        val found = all.filter { it.brand == saved.brand }
        if (hasIdentity(saved)) {
            val same = found.filter { sameDevice(saved, it) == true }
            val hit = same.firstOrNull { it.host == saved.host } ?: same.firstOrNull()
            if (hit != null) {
                val byUuid = normalizedUuid(saved.uuid) != null && normalizedUuid(hit.uuid) != null
                return identified(hit, saved) to if (byUuid) Match.UUID else Match.MAC
            }
        }
        val unknown = found.filter { sameDevice(saved, it) == null }
        unknown.firstOrNull { it.host == saved.host }?.let { return identified(it, saved) to Match.NAME }
        val sameName = unknown.filter { it.name == saved.name }
        if (sameName.size == 1) return identified(sameName[0], saved) to Match.NAME
        if (found.size == 1 && unknown.size == 1) return identified(unknown[0], saved) to Match.ONLY_ONE
        return null
    }

    /** Kimliği bilinmeyen eski kayıt: TV kayıtlı adreste kimliğiyle bulunduysa kimlik eklenmiş kayıt; değilse null. */
    fun learned(saved: FoundTv, all: List<FoundTv>): FoundTv? {
        if (hasIdentity(saved)) return null
        val (hit, _) = locate(saved, all) ?: return null
        if (hit.host != saved.host || !hasIdentity(hit)) return null
        return identified(saved, hit)
    }

    /** "TV yeni adreste bulundu: eski → yeni (UUID ile)". */
    fun movedLine(old: String, new: String, how: Match) = "TV yeni adreste bulundu: $old → $new (${how.text})"

    fun learnedLine(tv: FoundTv): String {
        val id = normalizedUuid(tv.uuid)?.let { "UUID $it" } ?: normalizedMac(tv.mac)?.let { "MAC $it" } ?: "-"
        return "TV kimliği kayda yazıldı: ${tv.host} ($id)"
    }
}
