// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections

/**
 * Telefonun ev ağındaki adresi değişti mi (Mac/iPhone `SenderAddressWatcher`, Windows `SenderAddressWatcher` ile aynı
 * kural). Modem yeniden başlayınca ya da telefon başka Wi-Fi'a geçince yeni adres alır; TV uygulaması eski adrese
 * bağlanmaya çalışıp ağı taramaya düşüyordu. Ağ değişince (ConnectivityManager'ın varsayılan ağ bildirimi) adresler
 * yeniden okunur; ev ağı adresi değiştiyse [onChange] çağrılır ve TV'ye yeni adres hemen bildirilir.
 */
class SenderAddressWatcher(
    private val read: () -> List<String> = ::homeAddresses,
    private val onChange: (old: List<String>, new: List<String>) -> Unit,
) {
    @Volatile private var last: List<String> = read()
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var manager: ConnectivityManager? = null

    fun start(context: Context) {
        val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return
        val watch = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = check()
            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) = check()
            override fun onLost(network: Network) = check()
        }
        runCatching { connectivity.registerDefaultNetworkCallback(watch) }.onSuccess {
            manager = connectivity
            callback = watch
        }
    }

    fun stop() {
        val watch = callback ?: return
        runCatching { manager?.unregisterNetworkCallback(watch) }
        callback = null
        manager = null
    }

    /** Adresleri yeniden okur; değiştiyse bildirir. Testler doğrudan çağırır. */
    @Synchronized fun check() {
        val now = runCatching(read).getOrDefault(emptyList())
        val old = last
        last = now
        if (changed(old, now)) runCatching { onChange(old, now) }
    }

    companion object {
        /** Bildirilecek değişiklik mi: yeni liste boş değil ve eskisinden farklı (sıra önemsiz). */
        fun changed(old: List<String>, new: List<String>) = new.isNotEmpty() && old.toSet() != new.toSet()

        fun line(old: List<String>, new: List<String>) =
            "Bu cihazın adresi değişti: ${if (old.isEmpty()) "-" else old.joinToString(", ")} → ${new.joinToString(", ")}; TV'ye yeni adres bildiriliyor."

        /** Açık bağdaştırıcıların özel (ev ağı) IPv4 adresleri; hücresel (rmnet, ccmni) ve VPN (tun) sayılmaz. */
        fun homeAddresses(): List<String> = Collections.list(NetworkInterface.getNetworkInterfaces())
            .filter { it.isUp && !it.isLoopback && !it.name.startsWith("rmnet") && !it.name.startsWith("ccmni") && !it.name.startsWith("tun") }
            .flatMap { Collections.list(it.inetAddresses) }
            .filter { it is Inet4Address && it.isSiteLocalAddress }
            .mapNotNull { it.hostAddress }
            .sorted()
    }
}
