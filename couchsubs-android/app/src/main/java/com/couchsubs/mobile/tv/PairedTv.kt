// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * TV'nin kendisi başlattığı eşleşme ("TV eşleşmek istiyor", kodla onay) onaylanınca TV'nin TV kaydına alınması
 * (Mac/iPhone `PairedTV`, Windows `PairedTv` ile aynı kural). Eskiden yalnız altyazı anahtarı TV'ye veriliyor, TV kaydı
 * ([InstalledTv]: adres, marka) hiç tutulmuyordu: TV bekçisi (otomatik açma) çalışmıyor, ana ekranda TV kartı çıkmıyordu.
 * Onaylanan TV, kullanıcı onu listeden seçmiş gibi kaydedilir ([TvChoice.select]).
 */
object PairedTv {
    /** Android TV / Google TV'nin açık tuttuğu portlar: ADB, Android TV uzaktan kumanda hizmeti, Google Cast (Mac/Windows ile aynı). */
    val ANDROID_PORTS = listOf(5555, 6466, 8009, 8008)

    /**
     * İsteği gönderen TV kaydedilsin mi. [host]: isteğin geldiği adres; [saved]: kayıtlı TV. Kullanıcının seçtiği başka bir
     * TV'nin yerine geçilmez (adresi bilinmeyen seçim, örneğin adsız seçilen Android TV, kayıt sayılmaz; tamamlanır).
     */
    fun shouldAdopt(host: String, saved: InstalledTv?): Boolean = host.isNotEmpty() && saved == null

    /**
     * Yoklama sonuçlarından TV: Samsung 8001'de kendini tanıtırsa Samsung; LG cihaz tanımı (1990) ya da ikinci ekran
     * sunucusu (3000) yanıt verirse LG; Android TV portlarından biri açıksa Android TV; hiçbiri değilse null (Mac'teki
     * `ManualTV.classify` ile aynı sıra; tanınmayan TV yanlış markayla kaydedilmez).
     */
    fun classify(host: String, samsungName: String?, lgName: String?, lgSeen: Boolean, androidPortOpen: Boolean): FoundTv? = when {
        samsungName != null -> FoundTv(samsungName, host, TvBrand.SAMSUNG)
        lgName != null || lgSeen -> FoundTv(lgName ?: "LG TV", host, TvBrand.LG)
        androidPortOpen -> FoundTv("Android TV", host, TvBrand.ANDROID_TV)
        else -> null
    }

    /**
     * Tanınan TV'ye kimliği eklenir: Samsung'da 8001 yanıtındaki `device.id`/`wifiMac`, LG'de cihaz tanımının UDN'si, Android
     * TV'de Google Cast cihaz tanımının (8008) UDN'si.
     */
    fun withIdentity(tv: FoundTv, samsungJson: String?, lgXml: String?, castXml: String?): FoundTv = when (tv.brand) {
        TvBrand.SAMSUNG -> TvIdentity.samsungIdentity(samsungJson).let { (uuid, mac) -> tv.copy(uuid = uuid, mac = mac) }
        TvBrand.LG -> tv.copy(uuid = TvIdentity.uuidFromDescription(lgXml))
        TvBrand.ANDROID_TV -> tv.copy(uuid = TvIdentity.uuidFromDescription(castXml))
    }

    /** Samsung 8001 `/api/v2/` yanıtındaki ad (`device.name`); Samsung değilse null. */
    fun samsungName(json: String?): String? = json?.let {
        runCatching { org.json.JSONObject(it).getJSONObject("device").getString("name").replace("&quot;", "\"") }.getOrNull()
    }?.takeIf { it.isNotBlank() }

    /** webOS cihaz tanımındaki ad; LG/webOS tanımı değilse null. */
    fun lgName(xml: String?): String? {
        val text = xml?.lowercase() ?: return null
        if ("<device" !in text || !("lg electronics" in text || "webos" in text)) return null
        return xml.substringAfter("<friendlyName>", "").substringBefore("</friendlyName>").takeIf { it.isNotBlank() } ?: "LG TV"
    }

    /** Adresteki TV'yi yoklar (bloklar, en çok birkaç saniye); hiçbir yoklama tanımazsa SSDP aramasında bu adres aranır. */
    fun identify(host: String): FoundTv? {
        val pool = Executors.newFixedThreadPool(4)
        try {
            val samsungJson = pool.submit(Callable { text("http://$host:8001/api/v2/") })
            val lgXml = pool.submit(Callable { text("http://$host:1990/") })
            val castXml = pool.submit(Callable { text("http://$host:8008/ssdp/device-desc.xml") })
            val greeting = pool.submit(Callable { text("http://$host:3000/")?.trim()?.lowercase() == "hello world" || isOpen(host, 3000) })
            val android = pool.submit(Callable { ANDROID_PORTS.any { isOpen(host, it) } })
            fun <T> take(task: java.util.concurrent.Future<T>, fallback: T): T = runCatching { task.get(8, TimeUnit.SECONDS) }.getOrDefault(fallback)
            val json = take(samsungJson, null)
            val xml = take(lgXml, null)
            val tv = classify(host, samsungName(json), lgName(xml), take(greeting, false), take(android, false))
            if (tv != null) return withIdentity(tv, json, xml, take(castXml, null))
        } finally {
            pool.shutdownNow()
        }
        return runCatching { TvDiscovery.search().firstOrNull { it.host == host } }.getOrNull()
    }

    private fun text(address: String): String? = try {
        val connection = URL(address).openConnection() as HttpURLConnection
        connection.connectTimeout = 1500
        connection.readTimeout = 1500
        try {
            if (connection.responseCode != 200) null else connection.inputStream.use { String(it.readBytes(), Charsets.UTF_8) }
        } finally {
            connection.disconnect()
        }
    } catch (error: Exception) {
        null
    }

    private fun isOpen(host: String, port: Int): Boolean = try {
        Socket().use { it.connect(InetSocketAddress(host, port), 1500); true }
    } catch (error: Exception) {
        false
    }
}
