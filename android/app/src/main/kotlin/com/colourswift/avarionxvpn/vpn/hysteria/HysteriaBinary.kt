package com.colourswift.avarionxvpn.vpn.hysteria

import android.content.Context
import java.io.File

object HysteriaBinary {
    private const val LIB_NAME = "libhysteria.so"

    fun installIfMissing(context: Context): File {
        val libDir = File(context.applicationInfo.nativeLibraryDir)
        val outFile = File(libDir, LIB_NAME)

        HyLog.write(context, "HysteriaBinary.nativeLibraryDir=${libDir.absolutePath}")
        HyLog.write(context, "HysteriaBinary.selectedLib=${outFile.absolutePath}")
        HyLog.write(context, "HysteriaBinary.libExists=${outFile.exists()} size=${if (outFile.exists()) outFile.length() else 0}")

        if (!outFile.exists()) {
            throw IllegalStateException("Missing native library: ${outFile.absolutePath}")
        }

        if (!outFile.canExecute()) {
            HyLog.write(context, "HysteriaBinary.libNotMarkedExecutable path=${outFile.absolutePath}")
        }

        return outFile
    }
}
