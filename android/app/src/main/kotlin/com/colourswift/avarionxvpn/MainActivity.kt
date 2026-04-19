package com.colourswift.avarionxvpn

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import com.colourswift.avarionxvpn.vpn.CSVpnService
import com.colourswift.avarionxvpn.vpn.VpnModeSwitcher
import com.colourswift.avarionxvpn.vpn.amnezia.CSAmneziaWireGuardService
import com.colourswift.avarionxvpn.vpn.wireguard.CSWireGuardService
import com.colourswift.avarionxvpn.vpn.hysteria.CSHysteriaService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

object CsDnsEvents {
    private const val MAX = 800

    private val lock = Any()
    private val buffer = ArrayDeque<Map<String, Any?>>(MAX)
    private val sinks = LinkedHashSet<EventChannel.EventSink>()

    fun addSink(s: EventChannel.EventSink?) {
        if (s == null) return

        val snapshot: List<Map<String, Any?>> = synchronized(lock) {
            sinks.add(s)
            buffer.toList()
        }

        for (e in snapshot) {
            try {
                s.success(e)
            } catch (_: Exception) {
            }
        }
    }

    fun removeSink(s: EventChannel.EventSink?) {
        if (s == null) return
        synchronized(lock) {
            sinks.remove(s)
        }
    }

    fun emit(map: Map<String, Any?>) {
        val targets: List<EventChannel.EventSink>
        synchronized(lock) {
            if (buffer.size >= MAX) buffer.removeFirst()
            buffer.addLast(map)
            targets = sinks.toList()
        }

        if (targets.isEmpty()) return

        for (t in targets) {
            try {
                t.success(map)
            } catch (_: Exception) {
            }
        }
    }
}

class MainActivity : FlutterFragmentActivity() {
    private val REQ_WG_VPN = 9911
    private val REQ_DNS_VPN_PERMISSION = 777

    private var pendingWgConfig: String? = null
    private var pendingWgExcludedAppsJson: String? = null
    private var pendingVpnPermissionResult: MethodChannel.Result? = null

    private fun installCrashLogger() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()

        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                android.util.Log.e(
                    "CS_CRASH",
                    "uncaught thread=${thread.name} msg=${throwable.message ?: ""}",
                    throwable
                )
            } catch (_: Throwable) {
            }

            previous?.uncaughtException(thread, throwable)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installCrashLogger()
        super.onCreate(savedInstanceState)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQ_WG_VPN) {
            val wgCfg = pendingWgConfig
            val wgEx = pendingWgExcludedAppsJson

            pendingWgConfig = null
            pendingWgExcludedAppsJson = null

            if (resultCode == RESULT_OK) {
                if (!wgCfg.isNullOrBlank()) {
                    startWgService(wgCfg, wgEx)
                }
            }

            return
        }

        if (requestCode == REQ_DNS_VPN_PERMISSION) {
            val ok = resultCode == RESULT_OK
            pendingVpnPermissionResult?.success(ok)
            pendingVpnPermissionResult = null
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cs_vpn_control")
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "startVpn" -> {
                        val dnsMode = call.argument<String>("dns_mode") ?: "malware"
                        val intent = Intent(applicationContext, CSVpnService::class.java).apply {
                            action = CSVpnService.ACTION_START
                            putExtra("dns_mode", dnsMode)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            applicationContext.startForegroundService(intent)
                        } else {
                            applicationContext.startService(intent)
                        }
                        result.success(true)
                    }

                    "stopVpn" -> {
                        val intent = Intent(applicationContext, CSVpnService::class.java).apply {
                            action = CSVpnService.ACTION_STOP
                        }
                        applicationContext.startService(intent)
                        result.success(true)
                    }

                    "startWireGuard" -> {
                        val config = call.argument<String>("config") ?: ""
                        if (config.isBlank()) {
                            result.error("WG_CONFIG_MISSING", "WireGuard config missing", null)
                            return@setMethodCallHandler
                        }

                        val excludedAppsJson = argsToExcludedAppsJson(call.argument<List<*>>("excluded_apps"))

                        VpnModeSwitcher.stopDnsVpn(applicationContext)
                        VpnModeSwitcher.stopWireGuard(applicationContext)
                        stopAmneziaService()

                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            startWgService(config, excludedAppsJson)
                        }, 650)

                        result.success(true)
                    }

                    "stopWireGuard" -> {
                        val intent = Intent(applicationContext, CSWireGuardService::class.java).apply {
                            action = CSWireGuardService.ACTION_STOP
                        }
                        applicationContext.startService(intent)
                        result.success(true)
                    }

                    "isWireGuardRunning" -> {
                        result.success(CSWireGuardService.isRunning)
                    }

                    "startAmneziaWireGuard" -> {
                        val config = call.argument<String>("config") ?: ""
                        if (config.isBlank()) {
                            result.error("AWG_CONFIG_MISSING", "Amnezia config missing", null)
                            return@setMethodCallHandler
                        }

                        val excludedAppsJson = argsToExcludedAppsJson(call.argument<List<*>>("excluded_apps"))

                        VpnModeSwitcher.stopDnsVpn(applicationContext)
                        VpnModeSwitcher.stopWireGuard(applicationContext)
                        stopAmneziaService()

                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            startAmneziaService(config, excludedAppsJson)
                        }, 650)

                        result.success(true)
                    }

                    "stopAmneziaWireGuard" -> {
                        stopAmneziaService()
                        result.success(true)
                    }

                    "isAmneziaWireGuardRunning" -> {
                        result.success(CSAmneziaWireGuardService.isRunning)
                    }

                    "startHysteria" -> {
                        val server = call.argument<String>("server")?.trim().orEmpty()
                        val auth = call.argument<String>("auth")?.trim().orEmpty()
                        val sni = call.argument<String>("sni")?.trim().orEmpty()
                        val dns = call.argument<String>("dns")?.trim().orEmpty()

                        if (server.isBlank() || auth.isBlank() || sni.isBlank() || dns.isBlank()) {
                            result.error("HY_ARGS_MISSING", "Hysteria server/auth/sni/dns missing", null)
                            return@setMethodCallHandler
                        }

                        VpnModeSwitcher.stopDnsVpn(applicationContext)
                        VpnModeSwitcher.stopWireGuard(applicationContext)
                        stopAmneziaService()

                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            val intent = Intent(applicationContext, CSHysteriaService::class.java).apply {
                                action = CSHysteriaService.ACTION_START
                                putExtra(CSHysteriaService.EXTRA_SERVER, server)
                                putExtra(CSHysteriaService.EXTRA_AUTH, auth)
                                putExtra(CSHysteriaService.EXTRA_SNI, sni)
                                putExtra(CSHysteriaService.EXTRA_DNS, dns)
                            }

                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                applicationContext.startForegroundService(intent)
                            } else {
                                applicationContext.startService(intent)
                            }
                        }, 650)

                        result.success(true)
                    }

                    "stopHysteria" -> {
                        android.util.Log.i("CS_HY_MAIN", "stopHysteria method channel invoked")

                        val intent = Intent(applicationContext, CSHysteriaService::class.java).apply {
                            action = CSHysteriaService.ACTION_STOP
                        }
                        applicationContext.startService(intent)
                        result.success(true)
                    }

                    "isHysteriaRunning" -> {
                        result.success(CSHysteriaService.isReady)
                    }

                    "isDnsVpnRunning" -> {
                        result.success(CSVpnService.isRunning)
                    }

                    "getTunnelStats" -> {
                        val stats: Map<String, Long>? = when {
                            CSWireGuardService.isRunning -> CSWireGuardService.snapshotStats()
                            CSAmneziaWireGuardService.isRunning -> CSAmneziaWireGuardService.snapshotStats()
                            CSHysteriaService.isRunning -> mapOf(
                                "rxBytes" to CSHysteriaService.rxBytes,
                                "txBytes" to CSHysteriaService.txBytes
                            )
                            else -> null
                        }
                        result.success(stats)
                    }

                    "startXray" -> {
                        result.error("XRAY_DISABLED", "Xray is disabled in this build", null)
                    }

                    "stopXray" -> {
                        result.success(true)
                    }

                    "isXrayRunning" -> {
                        result.success(false)
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cs_vpn_permission")
            .setMethodCallHandler { call, result ->
                if (call.method == "prepareVpn") {
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        pendingVpnPermissionResult = result
                        startActivityForResult(intent, REQ_DNS_VPN_PERMISSION)
                    } else {
                        result.success(true)
                    }
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cs_vpn_state")
            .setMethodCallHandler { call, result ->
                if (call.method == "isAnotherVpnActive") {
                    val active = VpnService.prepare(applicationContext) != null
                    result.success(active)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cs_dns_settings")
            .setMethodCallHandler { call, result ->
                if (call.method != "setCloudSettings") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val args = call.arguments as? Map<*, *>
                val enabledLists = args?.get("enabled_lists") as? List<*>
                val resolver = (args?.get("resolver") as? String)?.trim().orEmpty()
                val plan = (args?.get("plan") as? String)?.trim()?.lowercase().orEmpty()
                val cloudUrl = (args?.get("cloud_url") as? String)?.trim().orEmpty()
                val clientId = (args?.get("client_id") as? String)?.trim().orEmpty()

                val prefs =
                    applicationContext.getSharedPreferences("cs_dns_cloud", Context.MODE_PRIVATE)
                val ed = prefs.edit()

                if (enabledLists != null) {
                    val arr = JSONArray()
                    enabledLists.forEach { v ->
                        val s = v?.toString()?.trim().orEmpty()
                        if (s.isNotEmpty()) arr.put(s)
                    }
                    ed.putString("enabled_lists_json", arr.toString())
                }

                if (resolver.isNotEmpty()) ed.putString("resolver", resolver)
                if (plan == "pro" || plan == "free") ed.putString("plan", plan)
                if (cloudUrl.isNotEmpty()) ed.putString("cloud_url", cloudUrl)
                if (clientId.isNotEmpty()) ed.putString("client_id", clientId)

                ed.commit()
                result.success(true)
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cs_dns_usage")
            .setMethodCallHandler { call, result ->
                if (call.method != "getUsage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val prefs =
                    applicationContext.getSharedPreferences("cs_dns_cloud", Context.MODE_PRIVATE)

                val used = prefs.getLong("usage_used", 0L).toInt()
                val limit =
                    prefs.getLong("usage_limit", -1L).toInt().let { if (it <= 0) null else it }
                val resetMs =
                    prefs.getLong("usage_reset_ms", -1L).let { if (it <= 0L) null else it }
                val plan = prefs.getString("plan", "free") ?: "free"

                val out = HashMap<String, Any?>()
                out["used"] = used
                out["limit"] = limit
                out["reset_ms"] = resetMs
                out["plan"] = plan

                result.success(out)
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cs_vpn_lockdown")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLockdownState" -> {
                        try {
                            result.success(CSVpnService.snapshotLockdownState(applicationContext))
                        } catch (_: Exception) {
                            result.success(
                                mapOf(
                                    "always_on" to false,
                                    "lockdown" to false,
                                    "always_on_pkg" to null
                                )
                            )
                        }
                    }

                    "openVpnSettings" -> {
                        try {
                            val i = Intent(Settings.ACTION_VPN_SETTINGS)
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "cs_dns_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var sink: EventChannel.EventSink? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                    CsDnsEvents.addSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    CsDnsEvents.removeSink(sink)
                    sink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cs_fullvpn")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        val cfg = call.arguments as? String ?: ""
                        if (cfg.isBlank()) {
                            result.error("bad_args", "missing config", null)
                            return@setMethodCallHandler
                        }

                        val prep = VpnService.prepare(this@MainActivity)
                        if (prep != null) {
                            pendingWgConfig = cfg
                            pendingWgExcludedAppsJson = null
                            startActivityForResult(prep, REQ_WG_VPN)
                            result.success(mapOf("permission" to true, "started" to false))
                            return@setMethodCallHandler
                        }

                        startWgService(cfg, null)
                        result.success(mapOf("permission" to false, "started" to true))
                    }

                    "connectWithOptions" -> {
                        val args = call.arguments as? Map<*, *>
                        val cfg = (args?.get("config") as? String).orEmpty()
                        if (cfg.isBlank()) {
                            result.error("bad_args", "missing config", null)
                            return@setMethodCallHandler
                        }

                        val excludedAppsJson = argsToExcludedAppsJson(args?.get("excluded_apps") as? List<*>)

                        val prep = VpnService.prepare(this@MainActivity)
                        if (prep != null) {
                            pendingWgConfig = cfg
                            pendingWgExcludedAppsJson = excludedAppsJson
                            startActivityForResult(prep, REQ_WG_VPN)
                            result.success(mapOf("permission" to true, "started" to false))
                            return@setMethodCallHandler
                        }

                        startWgService(cfg, excludedAppsJson)
                        result.success(mapOf("permission" to false, "started" to true))
                    }

                    "disconnect" -> {
                        stopWgService()
                        result.success(true)
                    }

                    "updateNotificationUsage" -> {
                        val usageText = (call.arguments as? String)?.trim().orEmpty()

                        when {
                            CSWireGuardService.isRunning -> {
                                val i = Intent(applicationContext, CSWireGuardService::class.java).apply {
                                    action = CSWireGuardService.ACTION_UPDATE_USAGE
                                    putExtra(CSWireGuardService.EXTRA_USAGE_TEXT, usageText)
                                }
                                applicationContext.startService(i)
                            }
                            CSAmneziaWireGuardService.isRunning -> {
                                val i = Intent(applicationContext, CSAmneziaWireGuardService::class.java).apply {
                                    action = CSAmneziaWireGuardService.ACTION_UPDATE_USAGE
                                    putExtra(CSAmneziaWireGuardService.EXTRA_USAGE_TEXT, usageText)
                                }
                                applicationContext.startService(i)
                            }
                            CSHysteriaService.isRunning -> {
                                val i = Intent(applicationContext, CSHysteriaService::class.java).apply {
                                    action = CSHysteriaService.ACTION_UPDATE_USAGE
                                    putExtra(CSHysteriaService.EXTRA_USAGE_TEXT, usageText)
                                }
                                applicationContext.startService(i)
                            }
                        }

                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun argsToExcludedAppsJson(list: List<*>?): String? {
        if (list == null) return null
        val arr = JSONArray()
        for (v in list) {
            val s = v?.toString()?.trim().orEmpty()
            if (s.isNotEmpty()) arr.put(s)
        }
        return if (arr.length() == 0) null else arr.toString()
    }

    private fun startWgService(cfg: String, excludedAppsJson: String?) {
        val i = Intent(this, CSWireGuardService::class.java).apply {
            action = CSWireGuardService.ACTION_START
            putExtra(CSWireGuardService.EXTRA_WG_CONFIG, cfg)
            if (!excludedAppsJson.isNullOrBlank()) {
                putExtra(CSWireGuardService.EXTRA_EXCLUDED_APPS_JSON, excludedAppsJson)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(this, i)
        } else {
            startService(i)
        }
    }

    private fun stopWgService() {
        val i = Intent(this, CSWireGuardService::class.java).apply {
            action = CSWireGuardService.ACTION_STOP
        }
        startService(i)
    }

    private fun startAmneziaService(cfg: String, excludedAppsJson: String?) {
        val i = Intent(this, CSAmneziaWireGuardService::class.java).apply {
            action = CSAmneziaWireGuardService.ACTION_START
            putExtra(CSAmneziaWireGuardService.EXTRA_AWG_CONFIG, cfg)
            if (!excludedAppsJson.isNullOrBlank()) {
                putExtra(CSAmneziaWireGuardService.EXTRA_EXCLUDED_APPS_JSON, excludedAppsJson)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(this, i)
        } else {
            startService(i)
        }
    }

    private fun stopAmneziaService() {
        val i = Intent(this, CSAmneziaWireGuardService::class.java).apply {
            action = CSAmneziaWireGuardService.ACTION_STOP
        }
        startService(i)
    }
}