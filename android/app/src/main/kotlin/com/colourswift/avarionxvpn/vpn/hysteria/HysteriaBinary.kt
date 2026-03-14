package com.colourswift.avarionxvpn.vpn.hysteria

import android.content.Context
import android.os.Build
import java.io.File

object HysteriaBinary {
    private const val LIB_ARM64 = "libhysteria.so"
    private const val LIB_ARMV7 = "libhysteria.so"

    fun install(context: Context): File {
        return installIfMissing(context)
    }

    fun installIfMissing(context: Context): File {
        val libDir = File(context.applicationInfo.nativeLibraryDir)
        val libName = pickLibraryName()
        val outFile = File(libDir, libName)

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

    private fun pickLibraryName(): String {
        val abis = Build.SUPPORTED_ABIS?.toList().orEmpty()

        if (abis.any { it.equals("arm64-v8a", ignoreCase = true) }) {
            return LIB_ARM64
        }

        if (abis.any { it.equals("armeabi-v7a", ignoreCase = true) }) {
            return LIB_ARMV7
        }

        throw IllegalStateException("Unsupported ABI: $abis")
    }
}