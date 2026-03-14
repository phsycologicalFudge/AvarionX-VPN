package com.colourswift.avarionxvpn.vpn.hysteria

import android.content.Context
import java.io.File

object HysteriaConfig {
    fun writeClientConfig(
        context: Context,
        serverIpPort: String,
        auth: String,
        sni: String,
        fdSocketPath: String,
        socksPort: Int = 1080
    ): File {
        val outFile = File(context.filesDir, "hysteria_client.yaml")
        val text = """
server: $serverIpPort
auth: $auth

tls:
  sni: $sni
  insecure: false

quic:
  sockopts:
    fdControlUnixSocket: $fdSocketPath

socks5:
  listen: 127.0.0.1:$socksPort
""".trimIndent()

        outFile.writeText(text)
        outFile.setReadable(true, true)
        outFile.setWritable(true, true)
        return outFile
    }
}