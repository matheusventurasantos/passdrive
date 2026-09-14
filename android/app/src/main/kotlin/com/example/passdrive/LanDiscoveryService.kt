package com.example.passdrive

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.MulticastSocket
import java.net.NetworkInterface
import java.net.SocketTimeoutException
import java.util.Collections

/** Discovery only: never opens the vault, stores codes or accepts credentials. */
class LanDiscoveryService : Service() {
    @Volatile private var running = false
    private var socket: MulticastSocket? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private val seen = LinkedHashSet<String>()
    private var lastNotification = 0L
    private val manager by lazy { getSystemService(NotificationManager::class.java) }
    private val prefs by lazy { getSharedPreferences("passdrive_sync", MODE_PRIVATE) }
    override fun onBind(intent: Intent?): IBinder? = null
    private fun builder(channel: String): Notification.Builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channel) else Notification.Builder(this)
    private fun openIntent(id: String = ""): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (id.isNotEmpty()) intent.putExtra("passdrive_sync_request", id)
        return PendingIntent.getActivity(this, if (id.isEmpty()) 5100 else 5101, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel("passdrive_lan", "Conexões locais", NotificationManager.IMPORTANCE_LOW))
            manager.createNotificationChannel(NotificationChannel("passdrive_pairing", "Pedidos de conexão", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val notification = builder("passdrive_lan").setSmallIcon(R.drawable.ic_sync_devices)
            .setContentTitle("PassDrive disponível na rede local")
            .setContentText("Toque para abrir. Desative nas opções de sincronização.")
            .setContentIntent(openIntent()).setOngoing(true).setVisibility(Notification.VISIBILITY_PRIVATE).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(5100, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        else startForeground(5100, notification)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!running) {
            running = true
            Thread({ discover() }, "PassDrive LAN discovery").start()
        }
        return START_STICKY
    }
    @Suppress("DEPRECATION")
    private fun discover() {
        try {
            multicastLock = (applicationContext.getSystemService(WIFI_SERVICE) as WifiManager).createMulticastLock("passdrive_lan").apply { setReferenceCounted(false); acquire() }
            val s = MulticastSocket(null).apply { reuseAddress = true; bind(InetSocketAddress(47777)); soTimeout = 1000; timeToLive = 1; broadcast = true }
            socket = s
            val group = InetAddress.getByName("239.255.77.77")
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces()).filter { it.isUp && !it.isLoopback && it.supportsMulticast() }
            for (network in interfaces) try { s.joinGroup(InetSocketAddress(group, 47777), network) } catch (_: Exception) { }
            var advertised = 0L
            while (running) {
                val id = prefs.getString("id", "") ?: ""
                if (id.isEmpty()) break
                val now = System.currentTimeMillis()
                if (now - advertised >= 2000) {
                    advertised = now
                    val data = JSONObject().put("app", "passdrive-lan").put("v", 1).put("id", id).put("name", prefs.getString("name", "Celular")).put("role", "phone").put("port", 0).toString().toByteArray(Charsets.UTF_8)
                    for (network in interfaces) try { s.networkInterface = network; s.send(DatagramPacket(data, data.size, group, 47777)) } catch (_: Exception) { }
                }
                val packet = DatagramPacket(ByteArray(2049), 2049)
                try { s.receive(packet) } catch (_: SocketTimeoutException) { continue }
                if (packet.length > 2048 || packet.address !is Inet4Address || !(packet.address.isSiteLocalAddress || packet.address.isLinkLocalAddress || packet.address.isLoopbackAddress)) continue
                try {
                    val data = JSONObject(String(packet.data, 0, packet.length, Charsets.UTF_8))
                    if (data.optString("app") != "passdrive-lan" || data.optInt("v") != 1 || data.optString("role") != "desktop" || data.optString("target") != id) continue
                    val desktop = data.optString("id")
                    val ticket = data.optString("ticket")
                    if (!Regex("[A-Za-z0-9_-]{22}").matches(desktop) || !Regex("[A-Za-z0-9_-]{22}").matches(ticket)) continue
                    val key = "$desktop:$ticket"
                    if (key in seen || now - lastNotification < 15000) continue
                    seen.add(key); if (seen.size > 128) seen.remove(seen.first())
                    lastNotification = now
                    manager.notify(5101, builder("passdrive_pairing").setSmallIcon(R.drawable.ic_sync_devices)
                        .setContentTitle("Pedido de conexão com o PassDrive")
                        .setContentText("Desbloqueie o cofre e confira o código no computador.")
                        .setContentIntent(openIntent(desktop)).setAutoCancel(true).apply { if (Build.VERSION.SDK_INT >= 26) setTimeoutAfter(120000) }
                        .setVisibility(Notification.VISIBILITY_PRIVATE).build())
                } catch (_: Exception) { /* Ignore unauthenticated malformed beacons. */ }
            }
        } catch (_: Exception) { /* No authorization occurs in this service. */ }
        finally { socket?.close(); socket = null; if (multicastLock?.isHeld == true) multicastLock?.release(); running = false; stopSelf() }
    }
    override fun onDestroy() {
        running = false; socket?.close()
        if (multicastLock?.isHeld == true) multicastLock?.release()
        super.onDestroy()
    }
}
