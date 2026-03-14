package com.colourswift.avarionxvpn.vpn

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.colourswift.avarionxvpn.vpn.amnezia.CSAmneziaWireGuardService
import com.colourswift.avarionxvpn.vpn.hysteria.CSHysteriaService
import com.colourswift.avarionxvpn.vpn.wireguard.CSWireGuardService

class VpnNotificationActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_DISCONNECT = "com.colourswift.avarionxvpn.NOTIF_DISCONNECT"
        const val ACTION_PAUSE = "com.colourswift.avarionxvpn.NOTIF_PAUSE"
        const val ACTION_RESUME = "com.colourswift.avarionxvpn.NOTIF_RESUME"

        const val EXTRA_MODE = "mode"
        const val EXTRA_MINUTES = "minutes"

        const val MODE_WG = "wg"
        const val MODE_AWG = "awg"
        const val MODE_HY = "hy"

        const val EXTRA_WG_CONFIG = "wg_config"
        const val EXTRA_AWG_CONFIG = "awg_config"
        const val EXTRA_EXCLUDED_APPS_JSON = "excluded_apps_json"
        const val EXTRA_SERVER = "server"
        const val EXTRA_AUTH = "auth"
        const val EXTRA_SNI = "sni"
        const val EXTRA_DNS = "dns"

        private const val RC_RESUME_WG = 4101
        private const val RC_RESUME_AWG = 4102
        private const val RC_RESUME_HY = 4103
        private const val RC_RESUME_FALLBACK = 4199
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_DISCONNECT -> {
                val mode = intent.getStringExtra(EXTRA_MODE).orEmpty()
                cancelResume(context, mode)
                stopVpn(context, mode)
            }

            ACTION_PAUSE -> {
                val mode = intent.getStringExtra(EXTRA_MODE).orEmpty()
                val minutes = intent.getIntExtra(EXTRA_MINUTES, 5).coerceAtLeast(1)

                cancelResume(context, mode)
                stopVpn(context, mode)
                scheduleResume(context, intent, mode, minutes)
            }

            ACTION_RESUME -> {
                resumeVpn(context, intent)
            }
        }
    }

    private fun stopVpn(context: Context, mode: String) {
        val intent = when (mode) {
            MODE_WG -> Intent(context, CSWireGuardService::class.java)
                .setAction(CSWireGuardService.ACTION_STOP)

            MODE_AWG -> Intent(context, CSAmneziaWireGuardService::class.java)
                .setAction(CSAmneziaWireGuardService.ACTION_STOP)

            MODE_HY -> Intent(context, CSHysteriaService::class.java)
                .setAction(CSHysteriaService.ACTION_STOP)

            else -> null
        } ?: return

        startServiceCompat(context, intent)
    }

    private fun resumeVpn(context: Context, sourceIntent: Intent) {
        val mode = sourceIntent.getStringExtra(EXTRA_MODE).orEmpty()

        val intent = when (mode) {
            MODE_WG -> {
                Intent(context, CSWireGuardService::class.java)
                    .setAction(CSWireGuardService.ACTION_START)
                    .putExtra(CSWireGuardService.EXTRA_WG_CONFIG, sourceIntent.getStringExtra(EXTRA_WG_CONFIG))
                    .putExtra(CSWireGuardService.EXTRA_EXCLUDED_APPS_JSON, sourceIntent.getStringExtra(EXTRA_EXCLUDED_APPS_JSON))
            }

            MODE_AWG -> {
                Intent(context, CSAmneziaWireGuardService::class.java)
                    .setAction(CSAmneziaWireGuardService.ACTION_START)
                    .putExtra(CSAmneziaWireGuardService.EXTRA_AWG_CONFIG, sourceIntent.getStringExtra(EXTRA_AWG_CONFIG))
                    .putExtra(CSAmneziaWireGuardService.EXTRA_EXCLUDED_APPS_JSON, sourceIntent.getStringExtra(EXTRA_EXCLUDED_APPS_JSON))
            }

            MODE_HY -> {
                Intent(context, CSHysteriaService::class.java)
                    .setAction(CSHysteriaService.ACTION_START)
                    .putExtra(CSHysteriaService.EXTRA_SERVER, sourceIntent.getStringExtra(EXTRA_SERVER))
                    .putExtra(CSHysteriaService.EXTRA_AUTH, sourceIntent.getStringExtra(EXTRA_AUTH))
                    .putExtra(CSHysteriaService.EXTRA_SNI, sourceIntent.getStringExtra(EXTRA_SNI))
                    .putExtra(CSHysteriaService.EXTRA_DNS, sourceIntent.getStringExtra(EXTRA_DNS))
            }

            else -> null
        } ?: return

        try {
            android.util.Log.i("VPN_NOTIF", "resumeVpn mode=$mode")
            startServiceCompat(context, intent)
        } catch (t: Throwable) {
            android.util.Log.e("VPN_NOTIF", "resumeVpn failed mode=$mode", t)
        }
    }

    private fun scheduleResume(context: Context, sourceIntent: Intent, mode: String, minutes: Int) {
        val resumeIntent = Intent(context, VpnNotificationActionReceiver::class.java)
            .setAction(ACTION_RESUME)
            .putExtra(EXTRA_MODE, mode)

        when (mode) {
            MODE_WG -> {
                resumeIntent.putExtra(EXTRA_WG_CONFIG, sourceIntent.getStringExtra(EXTRA_WG_CONFIG))
                resumeIntent.putExtra(EXTRA_EXCLUDED_APPS_JSON, sourceIntent.getStringExtra(EXTRA_EXCLUDED_APPS_JSON))
            }

            MODE_AWG -> {
                resumeIntent.putExtra(EXTRA_AWG_CONFIG, sourceIntent.getStringExtra(EXTRA_AWG_CONFIG))
                resumeIntent.putExtra(EXTRA_EXCLUDED_APPS_JSON, sourceIntent.getStringExtra(EXTRA_EXCLUDED_APPS_JSON))
            }

            MODE_HY -> {
                resumeIntent.putExtra(EXTRA_SERVER, sourceIntent.getStringExtra(EXTRA_SERVER))
                resumeIntent.putExtra(EXTRA_AUTH, sourceIntent.getStringExtra(EXTRA_AUTH))
                resumeIntent.putExtra(EXTRA_SNI, sourceIntent.getStringExtra(EXTRA_SNI))
                resumeIntent.putExtra(EXTRA_DNS, sourceIntent.getStringExtra(EXTRA_DNS))
            }
        }

        val requestCode = when (mode) {
            MODE_WG -> 4101
            MODE_AWG -> 4102
            MODE_HY -> 4103
            else -> 4199
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            resumeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val triggerAt = System.currentTimeMillis() + minutes * 60_000L
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val canExact = alarmManager.canScheduleExactAlarms()
                android.util.Log.i(
                    "VPN_NOTIF",
                    "scheduleResume mode=$mode minutes=$minutes canExact=$canExact triggerAt=$triggerAt"
                )

                if (canExact) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        pendingIntent
                    )
                } else {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        pendingIntent
                    )
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent
                )
            }
        } catch (t: Throwable) {
            android.util.Log.e("VPN_NOTIF", "scheduleResume failed mode=$mode minutes=$minutes", t)
        }
    }

    private fun cancelResume(context: Context, mode: String) {
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            resumeRequestCode(mode),
            Intent(context, VpnNotificationActionReceiver::class.java).setAction(ACTION_RESUME),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun resumeRequestCode(mode: String): Int {
        return when (mode) {
            MODE_WG -> RC_RESUME_WG
            MODE_AWG -> RC_RESUME_AWG
            MODE_HY -> RC_RESUME_HY
            else -> RC_RESUME_FALLBACK
        }
    }

    private fun startServiceCompat(context: Context, intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }
}