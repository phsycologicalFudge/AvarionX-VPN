package com.colourswift.avarionxvpn.vpn.hysteria

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object HyLog {
    private const val FILE_NAME = "hysteria_debug.log"

    private fun logFile(context: Context): File {
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        return File(base, FILE_NAME)
    }

    fun write(context: Context, message: String) {
        try {
            val ts = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
            logFile(context).appendText("$ts $message\n")
        } catch (_: Throwable) {
        }
    }

    fun clear(context: Context) {
        try {
            logFile(context).delete()
        } catch (_: Throwable) {
        }
    }
}