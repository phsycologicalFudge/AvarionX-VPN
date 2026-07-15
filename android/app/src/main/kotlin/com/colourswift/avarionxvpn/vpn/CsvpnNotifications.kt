package com.colourswift.avarionxvpn.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.ServiceCompat
import com.colourswift.avarionxvpn.MainActivity
import com.colourswift.avarionxvpn.R

object CsvpnNotifications {

    private const val PROTECTION_CHANNEL_ID = "cssecurity_realtime_v2"
    private const val GROUP_KEY = "cssecurity_protection_group"
    private const val SUMMARY_ID = 2

    private fun ensureProtectionChannel(mgr: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                PROTECTION_CHANNEL_ID,
                "Protection",
                NotificationManager.IMPORTANCE_LOW
            )
            ch.setShowBadge(false)
            mgr.createNotificationChannel(ch)
        }
    }

    private fun buildSummaryNotification(ctx: Context, pi: PendingIntent): Notification {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, PROTECTION_CHANNEL_ID)
                .setContentTitle("AVarionX")
                .setContentText("Protection active")
                .setSmallIcon(R.drawable.ic_notification)
                .setContentIntent(pi)
                .setOnlyAlertOnce(true)
                .setGroup(GROUP_KEY)
                .setGroupSummary(true)
                .build()
        } else {
            Notification.Builder(ctx)
                .setContentTitle("AVarionX")
                .setContentText("Protection active")
                .setSmallIcon(R.drawable.ic_notification)
                .setContentIntent(pi)
                .setOnlyAlertOnce(true)
                .setGroup(GROUP_KEY)
                .setGroupSummary(true)
                .build()
        }
    }

    private fun buildVpnNotification(ctx: Context, pi: PendingIntent): Notification {
        val title = "DNS Protection Active"
        val text = "Device protected"
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, PROTECTION_CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentIntent(pi)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setGroup(GROUP_KEY)
                .build()
        } else {
            Notification.Builder(ctx)
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentIntent(pi)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setGroup(GROUP_KEY)
                .build()
        }
    }

    fun startForegroundNotif(service: CSVpnService) {
        val ctx = service.applicationContext
        val mgr = service.getSystemService(NotificationManager::class.java)
        ensureProtectionChannel(mgr)

        val pi = PendingIntent.getActivity(
            service,
            0,
            Intent(service, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        mgr.notify(SUMMARY_ID, buildSummaryNotification(ctx, pi))
        val n = buildVpnNotification(ctx, pi)

        Log.i("CSVpn", "Starting foreground")
        ServiceCompat.startForeground(
            service,
            CSVpnService.NOTIF_ID,
            n,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        )
    }
}
