package com.colourswift.avarionxvpn.vpn.hysteria

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import com.colourswift.avarionxvpn.R
import com.colourswift.avarionxvpn.vpn.VpnNotificationActionReceiver
import com.colourswift.avarionxvpn.vpn.hysteria.tun.Tun2SocksBridge
import java.io.File
import java.util.concurrent.Executors

class CSHysteriaService : VpnService() {
    companion object {
        @Volatile var isRunning: Boolean = false
        @Volatile var isReady: Boolean = false

        const val ACTION_START = "com.colourswift.avarionxvpn.HY_START"
        const val ACTION_STOP = "com.colourswift.avarionxvpn.HY_STOP"

        const val EXTRA_SERVER = "server"
        const val EXTRA_AUTH = "auth"
        const val EXTRA_SNI = "sni"
        const val EXTRA_DNS = "dns"

        private const val NOTIF_ID = 232
        private const val NOTIF_CHANNEL = "cs_hy_status"
        private const val TUN_IPV4 = "198.18.0.1"
        private const val TUN_MTU = 1280
        private const val RC_DISCONNECT = 232001
        private const val RC_PAUSE_5 = 232005
        private const val RC_PAUSE_15 = 232015
        private const val RC_PAUSE_30 = 232030
    }

    private val worker = Executors.newSingleThreadExecutor()

    private var vpnInterface: ParcelFileDescriptor? = null
    private var processManager: HysteriaProcessManager? = null
    private var fdControlServer: HysteriaFdControlServer? = null

    private val stats = HysteriaVpnStats()

    private var lastServer: String? = null
    private var lastAuth: String? = null
    private var lastSni: String? = null
    private var lastDns: String? = null

    override fun onBind(intent: Intent?): IBinder? {
        return super.onBind(intent)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureNotifChannel()
        startForegroundCompat(buildNotification("Starting Hysteria"))

        val i = intent
        if (i == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        val action = i.action
        if (action == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (action == ACTION_STOP) {
            worker.execute {
                HyLog.write(this, "ACTION_STOP received")
                stopSession()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            return START_NOT_STICKY
        }

        if (action == ACTION_START) {
            val server = i.getStringExtra(EXTRA_SERVER)?.trim().orEmpty()
            val auth = i.getStringExtra(EXTRA_AUTH)?.trim().orEmpty()
            val sni = i.getStringExtra(EXTRA_SNI)?.trim().orEmpty()
            val dns = i.getStringExtra(EXTRA_DNS)?.trim().orEmpty()

            if (server.isEmpty() || auth.isEmpty() || sni.isEmpty() || dns.isEmpty()) {
                HyLog.write(this, "ACTION_START missing args server=$server sni=$sni dns=$dns authLen=${auth.length}")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }

            lastServer = server
            lastAuth = auth
            lastSni = sni
            lastDns = dns

            worker.execute {
                try {
                    HyLog.clear(this)
                    HyLog.write(this, "ACTION_START begin server=$server sni=$sni dns=$dns authLen=${auth.length}")

                    startSession(
                        serverIpPort = server,
                        auth = auth,
                        sni = sni,
                        dnsIp = dns
                    )

                    updateNotif("Protected by Stealth+")
                    HyLog.write(this, "ACTION_START success isRunning=$isRunning isReady=$isReady")
                } catch (t: Throwable) {
                    stats.setLastError(t.message ?: "unknown start error")
                    HyLog.write(this, "ACTION_START failed error=${t.message ?: "unknown"}")
                    stopSession()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }

            return START_STICKY
        }

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        return START_NOT_STICKY
    }

    private fun startSession(
        serverIpPort: String,
        auth: String,
        sni: String,
        dnsIp: String
    ) {
        HyLog.write(this, "startSession enter")
        stopSession()
        HyLog.write(this, "previous session cleared")

        vpnInterface = buildVpnInterface(dnsIp)
        HyLog.write(this, "vpnInterface established=${vpnInterface != null}")

        val fdSocketPath = File(filesDir, "hy_fd.sock").absolutePath
        fdControlServer = HysteriaFdControlServer(
            socketPath = fdSocketPath,
            protectFd = { fd -> protect(fd) },
            stats = stats
        ).also { it.start() }
        HyLog.write(this, "fdControlServer started path=$fdSocketPath")

        val config = HysteriaConfig.writeClientConfig(
            context = this,
            serverIpPort = serverIpPort,
            auth = auth,
            sni = sni,
            fdSocketPath = fdSocketPath,
            socksPort = 1080
        )
        HyLog.write(this, "config written path=${config.absolutePath}")

        processManager = HysteriaProcessManager(
            context = this,
            stats = stats
        ).also { it.start(config) }
        HyLog.write(this, "processManager start returned alive=${processManager?.isAlive() == true}")

        val processHandle = processManager?.localSocksEndpoint()
            ?: throw IllegalStateException("Missing local SOCKS endpoint")
        HyLog.write(this, "local SOCKS endpoint ${processHandle.hostString}:${processHandle.port}")

        waitForLocalSocks(processHandle.hostString, processHandle.port, 5000)
        HyLog.write(this, "local SOCKS listener ready")

        val tunnelConfig = buildTun2SocksConfig(
            socksHost = processHandle.hostString,
            socksPort = processHandle.port
        )
        HyLog.write(this, "tun2socks config:\n$tunnelConfig")

        val tunFdInt = vpnInterface!!.fd
        val startResult = Tun2SocksBridge.nativeStart(tunFdInt, tunnelConfig)
        if (startResult != 0) {
            throw IllegalStateException("Tun2Socks start failed: $startResult")
        }

        HyLog.write(this, "tun2socks started tunFd=$tunFdInt")

        isRunning = true
        isReady = processManager?.isAlive() == true
        HyLog.write(this, "flags set isRunning=$isRunning isReady=$isReady")
    }

    private fun buildTun2SocksConfig(
        socksHost: String,
        socksPort: Int
    ): String {
        return """
tunnel:
  mtu: $TUN_MTU
  ipv4: $TUN_IPV4

socks5:
  address: $socksHost
  port: $socksPort
  udp: udp

misc:
  log-file: stderr
  log-level: debug
""".trimIndent()
    }

    private fun waitForLocalSocks(host: String, port: Int, timeoutMs: Long) {
        val start = System.currentTimeMillis()

        while (System.currentTimeMillis() - start < timeoutMs) {
            try {
                java.net.Socket().use { socket ->
                    socket.connect(java.net.InetSocketAddress(host, port), 250)
                    return
                }
            } catch (_: Throwable) {
                try {
                    Thread.sleep(120)
                } catch (_: Throwable) {
                }
            }
        }

        throw IllegalStateException("Hysteria SOCKS listener did not start on $host:$port")
    }

    private fun stopSession() {
        HyLog.write(this, "stopSession begin")

        try {
            Tun2SocksBridge.nativeStop()
        } catch (_: Throwable) {
        }

        try {
            processManager?.stop()
        } catch (_: Throwable) {
        }
        processManager = null

        try {
            fdControlServer?.stop()
        } catch (_: Throwable) {
        }
        fdControlServer = null

        try {
            vpnInterface?.close()
        } catch (_: Throwable) {
        }
        vpnInterface = null

        isRunning = false
        isReady = false
        HyLog.write(this, "stopSession done")
    }

    private fun buildVpnInterface(dnsIp: String): ParcelFileDescriptor {
        val builder = Builder()
            .setSession("Secure VPN")
            .setBlocking(true)
            .setMtu(TUN_MTU)
            .addAddress(TUN_IPV4, 32)
            .addRoute("0.0.0.0", 0)
            .addDnsServer(dnsIp)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        return builder.establish() ?: throw IllegalStateException("Failed to establish VPN interface")
    }

    private fun ensureNotifChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            NOTIF_CHANNEL,
            "VPN status",
            NotificationManager.IMPORTANCE_LOW
        )
        mgr.createNotificationChannel(channel)
    }

    private fun disconnectPendingIntent(): PendingIntent {
        val intent = Intent(this, VpnNotificationActionReceiver::class.java)
            .setAction(VpnNotificationActionReceiver.ACTION_DISCONNECT)
            .putExtra(VpnNotificationActionReceiver.EXTRA_MODE, VpnNotificationActionReceiver.MODE_HY)

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
            else -> 232100 + minutes
        }

        val intent = Intent(this, VpnNotificationActionReceiver::class.java)
            .setAction(VpnNotificationActionReceiver.ACTION_PAUSE)
            .putExtra(VpnNotificationActionReceiver.EXTRA_MODE, VpnNotificationActionReceiver.MODE_HY)
            .putExtra(VpnNotificationActionReceiver.EXTRA_MINUTES, minutes)
            .putExtra(VpnNotificationActionReceiver.EXTRA_SERVER, lastServer)
            .putExtra(VpnNotificationActionReceiver.EXTRA_AUTH, lastAuth)
            .putExtra(VpnNotificationActionReceiver.EXTRA_SNI, lastSni)
            .putExtra(VpnNotificationActionReceiver.EXTRA_DNS, lastDns)

        return PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun buildNotification(status: String): Notification {
        return NotificationCompat.Builder(this, NOTIF_CHANNEL)
            .setContentTitle("Secure VPN")
            .setContentText(status)
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
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun updateNotif(status: String) {
        val mgr = getSystemService(NotificationManager::class.java) ?: return
        mgr.notify(NOTIF_ID, buildNotification(status))
    }

    override fun onDestroy() {
        HyLog.write(this, "onDestroy called")
        stopSession()
        worker.shutdownNow()
        super.onDestroy()
    }

    override fun onRevoke() {
        HyLog.write(this, "onRevoke called")
        stopSession()
        super.onRevoke()
    }
}