package com.colourswift.avarionxvpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.colourswift.avarionxvpn.vpn.CSVpnService

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {

            Handler(Looper.getMainLooper()).postDelayed({
                if (vpnAutoStartEnabled(context)) {
                    try {
                        val vpn = Intent(context, CSVpnService::class.java).apply {
                            action = CSVpnService.ACTION_START
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(vpn)
                        } else {
                            context.startService(vpn)
                        }
                    } catch (_: Exception) {
                    }
                }
            }, 7000)
        }
    }

    private fun vpnAutoStartEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences("cs_dns_cloud", Context.MODE_PRIVATE)
        return prefs.getBoolean("vpn_autostart_enabled", false)
    }
}
