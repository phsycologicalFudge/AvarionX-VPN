package com.colourswift.avarionxvpn.vpn.amnezia

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.colourswift.avarionxvpn.R
import com.colourswift.avarionxvpn.vpn.VpnNotificationActionReceiver
import org.amnezia.awg.backend.GoBackend
import org.amnezia.awg.backend.Tunnel
import org.amnezia.awg.config.Config
import java.util.concurrent.Executors

class CSAmneziaWireGuardService : VpnService() {

    companion object {
        @Volatile var isRunning: Boolean = false
        const val ACTION_START = "com.colourswift.avarionxvpn.AWG_START"
        const val ACTION_STOP = "com.colourswift.avarionxvpn.AWG_STOP"
        const val ACTION_UPDATE_USAGE = "com.colourswift.avarionxvpn.AWG_UPDATE_USAGE"
        const val EXTRA_AWG_CONFIG = "awg_config"
        const val EXTRA_EXCLUDED_APPS_JSON = "excluded_apps_json"
        const val EXTRA_USAGE_TEXT = "usage_text"
        private const val NOTIF_ID = 231
        private const val NOTIF_CHANNEL = "cs_awg_status"
        private const val RC_DISCONNECT = 231001
        private const val RC_PAUSE_5 = 231005
        private const val RC_PAUSE_15 = 231015
        private const val RC_PAUSE_30 = 231030

        @Volatile private var instance: CSAmneziaWireGuardService? = null

        fun snapshotStats(): Map<String, Long>? {
            val svc = instance ?: return null
            val b = svc.backend ?: return null
            return try {
                val stats = b.getStatistics(svc.tunnel)
                mapOf("rxBytes" to stats.totalRx(), "txBytes" to stats.totalTx())
            } catch (_: Throwable) {
                null
            }
        }
    }

    private var backend: GoBackend? = null

    private val tunnel = object : Tunnel {
        override fun getName(): String = "cs_awg"
        override fun onStateChange(newState: Tunnel.State) {}
    }

    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var starting = false
    @Volatile private var up = false
    @Volatile private var statusText: String = "Disconnected"
    @Volatile private var usageText: String = ""

    private var lastConfigRaw: String? = null
    private var lastExcludedAppsJson: String? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val i = intent ?: return START_NOT_STICKY
        val action = i.action ?: ""

        if (action == ACTION_UPDATE_USAGE) {
            val text = i.getStringExtra(EXTRA_USAGE_TEXT)?.trim().orEmpty()
            usageText = text
            if (isRunning) updateNotif(statusText)
            return START_STICKY
        }

        if (action == ACTION_STOP) {
            worker.execute {
                stopBackendOnly()
                stopForegroundSafe()
                isRunning = false
                starting = false
                up = false
                statusText = "Disconnected"
                stopSelf()
            }
            return START_NOT_STICKY
        }

        if (action == ACTION_START) {
            val raw = i.getStringExtra(EXTRA_AWG_CONFIG) ?: ""
            val excludedJson = i.getStringExtra(EXTRA_EXCLUDED_APPS_JSON)
            val excludedPkgs = parseExcludedApps(excludedJson)

            lastConfigRaw = raw
            lastExcludedAppsJson = excludedJson

            if (raw.isBlank()) {
                isRunning = false
                starting = false
                up = false
                statusText = "Failed to connect"
                stopSelf()
                return START_NOT_STICKY
            }

            if (starting) {
                statusText = "Connecting"
                updateNotif(statusText)
                return START_STICKY
            }

            starting = true
            statusText = "Connecting"
            startForegroundCompat(statusText)

            worker.execute {
                try {
                    stopBackendOnly()

                    val cfgText0 = withExcludedApps(raw, excludedPkgs)
                    val cfgText = withIpv6Support(cfgText0)

                    val parseStart = System.nanoTime()
                    val cfg = Config.parse(cfgText.byteInputStream())
                    val parseMs = (System.nanoTime() - parseStart) / 1_000_000

                    logConfigSummary(cfg, excludedPkgs.size, parseMs)
                    logNetState("pre_up")

                    val upStart = System.nanoTime()
                    ensureBackend().setState(tunnel, Tunnel.State.UP, cfg)
                    val upMs = (System.nanoTime() - upStart) / 1_000_000

                    up = true
                    isRunning = true
                    statusText = "Connected"
                    updateNotif(statusText)

                    Log.i("CSAWG", "AWG UP ok ms=$upMs")
                    logNetState("post_up")

                    worker.execute {
                        try {
                            Thread.sleep(1500)
                        } catch (_: Throwable) {
                        }
                        logNetState("post_up_1500ms")
                    }
                } catch (t: Throwable) {
                    Log.e("CSAWG", "Failed to start AWG", t)
                    up = false
                    isRunning = false
                    statusText = "Failed to connect"
                    updateNotif(statusText)
                    stopBackendOnly()
                    stopForegroundSafe()
                    stopSelf()
                } finally {
                    starting = false
                }
            }

            return START_STICKY
        }

        return START_STICKY
    }

    private fun disconnectPendingIntent(): PendingIntent {
        val intent = Intent(this, VpnNotificationActionReceiver::class.java)
            .setAction(VpnNotificationActionReceiver.ACTION_DISCONNECT)
            .putExtra(VpnNotificationActionReceiver.EXTRA_MODE, VpnNotificationActionReceiver.MODE_AWG)

        return PendingIntent.getBroadcast(
            this,
            RC_DISCONNECT,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun pausePendingIntent(minutes: Int): PendingIntent {
        val requestCode = when (minutes) {
            5 -> RC_PAUSE_5
            15 -> RC_PAUSE_15
            30 -> RC_PAUSE_30
            else -> 231100 + minutes
        }

        val intent = Intent(this, VpnNotificationActionReceiver::class.java)
            .setAction(VpnNotificationActionReceiver.ACTION_PAUSE)
            .putExtra(VpnNotificationActionReceiver.EXTRA_MODE, VpnNotificationActionReceiver.MODE_AWG)
            .putExtra(VpnNotificationActionReceiver.EXTRA_MINUTES, minutes)
            .putExtra(VpnNotificationActionReceiver.EXTRA_AWG_CONFIG, lastConfigRaw)
            .putExtra(VpnNotificationActionReceiver.EXTRA_EXCLUDED_APPS_JSON, lastExcludedAppsJson)

        return PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun buildServiceNotification(status: String) =
        NotificationCompat.Builder(this, NOTIF_CHANNEL)
            .setContentTitle("Secure VPN")
            .setContentText(composeNotifText(status))
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setAutoCancel(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .addAction(0, "Disconnect", disconnectPendingIntent())
            .addAction(0, "Pause 5m", pausePendingIntent(5))
            .addAction(0, "Pause 15m", pausePendingIntent(15))
            .addAction(0, "Pause 30m", pausePendingIntent(30))
            .build()

    private fun startForegroundCompat(status: String) {
        try {
            val mgr = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && mgr != null) {
                val ch = NotificationChannel(
                    NOTIF_CHANNEL,
                    "Secure VPN",
                    NotificationManager.IMPORTANCE_LOW
                )
                ch.setShowBadge(false)
                mgr.createNotificationChannel(ch)
            }
            startForeground(NOTIF_ID, buildServiceNotification(status))
        } catch (t: Throwable) {
            Log.e("CSAWG", "startForegroundCompat failed", t)
        }
    }

    private fun updateNotif(status: String) {
        try {
            val mgr = getSystemService(NotificationManager::class.java) ?: return
            mgr.notify(NOTIF_ID, buildServiceNotification(status))
        } catch (_: Throwable) {
        }
    }

    private fun composeNotifText(status: String): String {
        val usage = usageText.trim()
        return if (usage.isNotEmpty()) usage else status
    }

    private fun ensureBackend(): GoBackend {
        val b = backend
        if (b != null) return b
        val nb = GoBackend(this)
        backend = nb
        return nb
    }

    private fun parseExcludedApps(json: String?): List<String> {
        if (json.isNullOrBlank()) return emptyList()

        return try {
            val arr = org.json.JSONArray(json)
            val out = mutableListOf<String>()
            for (i in 0 until arr.length()) {
                val s = arr.optString(i).trim()
                if (s.isNotEmpty()) out.add(s)
            }
            out.distinct()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun withExcludedApps(raw: String, excludedPkgs: List<String>): String {
        val pkgs = excludedPkgs.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        if (pkgs.isEmpty()) return raw

        val line = "ExcludedApplications = " + pkgs.joinToString(", ")

        val lines = raw.replace("\r\n", "\n").split("\n").toMutableList()
        val ifaceStart = lines.indexOfFirst { it.trim().equals("[Interface]", ignoreCase = true) }
        if (ifaceStart == -1) return raw

        val nextSection = (ifaceStart + 1 until lines.size).firstOrNull { lines[it].trim().startsWith("[") } ?: lines.size
        val existing = (ifaceStart + 1 until nextSection).firstOrNull {
            lines[it].trim().startsWith("ExcludedApplications", ignoreCase = true)
        }

        if (existing != null) {
            lines[existing] = line
        } else {
            lines.add(ifaceStart + 1, line)
        }

        return lines.joinToString("\n")
    }

    private fun withIpv6Support(raw: String): String {
        val lines = raw.replace("\r\n", "\n").split("\n").toMutableList()
        var inPeer = false

        for (idx in lines.indices) {
            val t = lines[idx].trim()

            if (t.startsWith("[") && t.endsWith("]")) {
                inPeer = t.equals("[Peer]", ignoreCase = true)
                continue
            }

            if (!inPeer) continue

            if (t.startsWith("AllowedIPs", ignoreCase = true)) {
                val parts = lines[idx].split("=", limit = 2)
                if (parts.size != 2) continue

                val key = parts[0].trim()
                val rhs = parts[1].trim()
                if (rhs.isEmpty()) continue

                val items = rhs.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toMutableList()
                val hasV4Default = items.any { it.equals("0.0.0.0/0", ignoreCase = true) }
                val hasV6Default = items.any { it.equals("::/0", ignoreCase = true) }

                if (hasV4Default && !hasV6Default) {
                    items.add("::/0")
                    lines[idx] = "$key = " + items.joinToString(", ")
                }
            }
        }

        return lines.joinToString("\n")
    }

    private fun stopBackendOnly() {
        try {
            backend?.setState(tunnel, Tunnel.State.DOWN, null)
        } catch (_: Throwable) {
        }
        up = false
    }

    private fun stopForegroundSafe() {
        try {
            stopForeground(true)
        } catch (_: Throwable) {
        }
    }

    override fun onRevoke() {
        worker.execute {
            stopBackendOnly()
            stopForegroundSafe()
            isRunning = false
            starting = false
            up = false
            statusText = "Disconnected"
        }
        super.onRevoke()
    }

    override fun onDestroy() {
        instance = null
        try {
            worker.execute {
                stopBackendOnly()
                stopForegroundSafe()
                isRunning = false
                starting = false
                up = false
                statusText = "Disconnected"
            }
        } catch (_: Throwable) {
        }
        worker.shutdownNow()
        isRunning = false
        super.onDestroy()
    }

    private fun logConfigSummary(cfg: Config, excludedCount: Int, parseMs: Long) {
        try {
            val iface = cfg.getInterface()
            val addrs = iface.getAddresses().map { it.toString() }.joinToString(", ")
            val dns = iface.getDnsServers().map { it.toString() }.joinToString(", ")
            val peers = cfg.getPeers()

            val endpoints = peers.mapNotNull { p ->
                try {
                    p.getEndpoint().orElse(null)?.toString()
                } catch (_: Throwable) {
                    null
                }
            }.joinToString(", ")

            val allowed = peers.flatMap { p ->
                try {
                    p.getAllowedIps().map { it.toString() }
                } catch (_: Throwable) {
                    emptyList()
                }
            }.distinct().joinToString(", ")

            Log.i(
                "CSAWG",
                "cfg parseMs=$parseMs excluded=$excludedCount addrs=[$addrs] dns=[$dns] endpoints=[$endpoints] allowed=[$allowed]"
            )
        } catch (t: Throwable) {
            Log.e("CSAWG", "logConfigSummary failed", t)
        }
    }

    private fun logNetState(phase: String) {
        try {
            val cm = getSystemService(ConnectivityManager::class.java)
            if (cm == null) {
                Log.i("CSAWG", "net $phase cm=null")
                return
            }

            val an = cm.activeNetwork
            val anc = if (an != null) cm.getNetworkCapabilities(an) else null
            val anlp = if (an != null) cm.getLinkProperties(an) else null

            Log.i(
                "CSAWG",
                "net $phase active=${an != null} caps=${capsToStr(anc)} if=${anlp?.interfaceName ?: ""} dns=${anlp?.dnsServers?.joinToString(",") ?: ""} routes=${anlp?.routes?.size ?: 0}"
            )

            val vpnNet = findVpnNetwork(cm)
            val vpnc = if (vpnNet != null) cm.getNetworkCapabilities(vpnNet) else null
            val vpnlp = if (vpnNet != null) cm.getLinkProperties(vpnNet) else null

            Log.i(
                "CSAWG",
                "net $phase vpn=${vpnNet != null} caps=${capsToStr(vpnc)} if=${vpnlp?.interfaceName ?: ""} dns=${vpnlp?.dnsServers?.joinToString(",") ?: ""} routes=${vpnlp?.routes?.joinToString(";") { it.toString() } ?: ""}"
            )
        } catch (t: Throwable) {
            Log.e("CSAWG", "logNetState failed phase=$phase", t)
        }
    }

    private fun findVpnNetwork(cm: ConnectivityManager): Network? {
        return try {
            cm.allNetworks.firstOrNull { n ->
                val c = cm.getNetworkCapabilities(n)
                c != null && c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun capsToStr(c: NetworkCapabilities?): String {
        if (c == null) return ""
        val out = mutableListOf<String>()
        if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) out.add("VPN")
        if (c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) out.add("WIFI")
        if (c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) out.add("CELL")
        if (c.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) out.add("ETH")
        if (c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) out.add("INTERNET")
        if (c.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) out.add("VALIDATED")
        if (c.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)) out.add("UNMETERED")
        return out.joinToString("|")
    }
}