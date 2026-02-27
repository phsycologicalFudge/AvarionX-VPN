package com.colourswift.avarionxvpn.vpn.wireguard

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.colourswift.avarionxvpn.R
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import java.util.concurrent.Executors

class CSWireGuardService : VpnService() {

    companion object {
        @Volatile var isRunning: Boolean = false
        const val ACTION_START = "com.colourswift.avarionxvpn.WG_START"
        const val ACTION_STOP = "com.colourswift.avarionxvpn.WG_STOP"
        const val ACTION_UPDATE_USAGE = "com.colourswift.avarionxvpn.WG_UPDATE_USAGE"
        const val EXTRA_EXCLUDED_APPS_JSON = "excluded_apps_json"
        const val EXTRA_WG_CONFIG = "wg_config"
        const val EXTRA_USAGE_TEXT = "usage_text"
        private const val NOTIF_ID = 230
        private const val NOTIF_CHANNEL = "cs_wg_status"
    }

    private var backend: GoBackend? = null

    private val tunnel = object : Tunnel {
        override fun getName(): String = "cs_wg"
        override fun onStateChange(newState: Tunnel.State) {}
    }

    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var starting = false
    @Volatile private var up = false
    @Volatile private var statusText: String = "Disconnected"
    @Volatile private var usageText: String = ""

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
            val raw = i.getStringExtra(EXTRA_WG_CONFIG) ?: ""
            val excludedJson = i.getStringExtra(EXTRA_EXCLUDED_APPS_JSON)
            val excludedPkgs = parseExcludedApps(excludedJson)
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
                    val cfgText = withExcludedApps(raw, excludedPkgs)
                    val cfg = Config.parse(cfgText.byteInputStream())
                    ensureBackend().setState(tunnel, Tunnel.State.UP, cfg)
                    up = true
                    isRunning = true
                    statusText = "Connected"
                    updateNotif(statusText)
                } catch (t: Throwable) {
                    Log.e("CSWG", "Failed to start WG", t)
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

            val n = NotificationCompat.Builder(this, NOTIF_CHANNEL)
                .setContentTitle("Secure VPN")
                .setContentText(composeNotifText(status))
                .setSmallIcon(R.drawable.ic_notification)
                .setOngoing(true)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()

            startForeground(NOTIF_ID, n)
        } catch (t: Throwable) {
            Log.e("CSWG", "startForegroundCompat failed", t)
            try {
                val n2 = NotificationCompat.Builder(this)
                    .setContentTitle("Secure VPN")
                    .setContentText("Starting...")
                    .setSmallIcon(android.R.drawable.stat_sys_warning)
                    .setOngoing(true)
                    .setCategory(NotificationCompat.CATEGORY_SERVICE)
                    .setPriority(NotificationCompat.PRIORITY_LOW)
                    .build()
                startForeground(NOTIF_ID, n2)
            } catch (t2: Throwable) {
                Log.e("CSWG", "fallback startForeground failed", t2)
            }
        }
    }

    private fun updateNotif(status: String) {
        try {
            val mgr = getSystemService(NotificationManager::class.java) ?: return
            val n = NotificationCompat.Builder(this, NOTIF_CHANNEL)
                .setContentTitle("Secure VPN")
                .setContentText(composeNotifText(status))
                .setSmallIcon(R.drawable.ic_notification)
                .setOngoing(true)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()
            mgr.notify(NOTIF_ID, n)
        } catch (_: Throwable) {}
    }

    private fun composeNotifText(status: String): String {
        val usage = usageText.trim()
        return if (usage.isNotEmpty()) "$status • $usage" else status
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
        val existing = (ifaceStart + 1 until nextSection).firstOrNull { lines[it].trim().startsWith("ExcludedApplications", ignoreCase = true) }

        if (existing != null) {
            lines[existing] = line
        } else {
            lines.add(ifaceStart + 1, line)
        }

        return lines.joinToString("\n")
    }

    private fun stopBackendOnly() {
        try {
            backend?.setState(tunnel, Tunnel.State.DOWN, null)
        } catch (_: Throwable) {}
        up = false
    }

    private fun stopForegroundSafe() {
        try {
            stopForeground(true)
        } catch (_: Throwable) {}
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
        try {
            worker.execute {
                stopBackendOnly()
                stopForegroundSafe()
                isRunning = false
                starting = false
                up = false
                statusText = "Disconnected"
            }
        } catch (_: Throwable) {}
        worker.shutdownNow()
        isRunning = false
        super.onDestroy()
    }
}