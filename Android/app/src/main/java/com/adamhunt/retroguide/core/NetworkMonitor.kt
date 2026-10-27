package com.adamhunt.retroguide.core

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities

/**
 * Tells the app when the network changes (the Apple app's `NetworkChangeMonitor`),
 * so servers are rechecked at once rather than when a stream fails, and whether
 * a VPN is up (servers reached over it are preferred then).
 */
class NetworkMonitor(context: Context) {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private var callback: ConnectivityManager.NetworkCallback? = null

    val isVPNActive: Boolean
        get() = connectivity.getNetworkCapabilities(connectivity.activeNetwork)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true

    fun start(onChange: () -> Unit) {
        if (callback != null) return
        var current: Network? = connectivity.activeNetwork
        val watcher = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (network != current) {
                    current = network
                    onChange()
                }
            }
        }
        callback = watcher
        connectivity.registerDefaultNetworkCallback(watcher)
    }
}
