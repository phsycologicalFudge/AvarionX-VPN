package com.colourswift.avarionxvpn.vpn

import java.io.File

object ProcNetUid {
    private val procFiles = listOf("/proc/net/udp", "/proc/net/udp6")

    fun lookupUdpUid(localPort: Int): Int? {
        val hexPort = localPort.coerceIn(0, 65535).toString(16).uppercase().padStart(4, '0')

        for (path in procFiles) {
            val uid = scan(File(path), hexPort)
            if (uid != null) return uid
        }
        return null
    }

    private fun scan(file: File, hexPort: String): Int? {
        if (!file.exists()) return null
        return try {
            file.bufferedReader().useLines { lines ->
                lines.drop(1)
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                    .firstNotNullOfOrNull { line ->
                        val parts = line.split(Regex("\\s+"))
                        if (parts.size < 8) return@firstNotNullOfOrNull null
                        val local = parts[1]
                        val idx = local.indexOf(':')
                        if (idx <= 0) return@firstNotNullOfOrNull null
                        if (local.substring(idx + 1).uppercase() != hexPort) return@firstNotNullOfOrNull null
                        parts[7].toIntOrNull()
                    }
            }
        } catch (_: Exception) {
            null
        }
    }
}