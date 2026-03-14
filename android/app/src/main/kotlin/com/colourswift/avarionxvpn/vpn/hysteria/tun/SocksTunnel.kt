package com.colourswift.avarionxvpn.vpn.hysteria.tun

import android.content.Context
import com.colourswift.avarionxvpn.vpn.hysteria.HyLog
import com.colourswift.avarionxvpn.vpn.hysteria.HysteriaVpnStats
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

class SocksTunnel(
    private val context: Context,
    private val proxyHost: String,
    private val proxyPort: Int,
    private val protectSocketIfNeeded: (Socket) -> Boolean,
    private val stats: HysteriaVpnStats
) {
    fun openTcpTunnel(dstIp: Int, dstPort: Int): SocksTcpChannel {
        val socket = Socket()
        protectSocketIfNeeded(socket)
        socket.connect(InetSocketAddress(proxyHost, proxyPort))
        HyLog.write(context, "socks connected proxy=$proxyHost:$proxyPort dst=$dstIp:$dstPort")

        val out = socket.getOutputStream()
        val input = socket.getInputStream()

        out.write(byteArrayOf(0x05, 0x01, 0x00))
        out.flush()

        val authReply = ByteArray(2)
        input.readFully(authReply)
        HyLog.write(context, "socks auth reply ver=${authReply[0].toInt() and 0xFF} method=${authReply[1].toInt() and 0xFF}")

        if ((authReply[0].toInt() and 0xFF) != 0x05 || (authReply[1].toInt() and 0xFF) == 0xFF) {
            throw IllegalStateException("SOCKS auth negotiation failed")
        }

        val ipBytes = byteArrayOf(
            ((dstIp ushr 24) and 0xFF).toByte(),
            ((dstIp ushr 16) and 0xFF).toByte(),
            ((dstIp ushr 8) and 0xFF).toByte(),
            (dstIp and 0xFF).toByte()
        )

        val req = byteArrayOf(
            0x05,
            0x01,
            0x00,
            0x01,
            ipBytes[0],
            ipBytes[1],
            ipBytes[2],
            ipBytes[3],
            ((dstPort ushr 8) and 0xFF).toByte(),
            (dstPort and 0xFF).toByte()
        )

        out.write(req)
        out.flush()

        val replyHead = ByteArray(4)
        input.readFully(replyHead)

        val rep = replyHead[1].toInt() and 0xFF
        val atyp = replyHead[3].toInt() and 0xFF

        when (atyp) {
            0x01 -> input.readFully(ByteArray(6))
            0x03 -> {
                val len = input.read()
                if (len > 0) {
                    input.readFully(ByteArray(len + 2))
                }
            }
            0x04 -> input.readFully(ByteArray(18))
        }

        HyLog.write(context, "socks connect reply rep=$rep atyp=$atyp dst=$dstIp:$dstPort")

        if (rep != 0x00) {
            throw IllegalStateException("SOCKS connect failed rep=$rep")
        }

        return DefaultSocksTcpChannel(
            socket = socket,
            input = input,
            output = out
        )
    }

    fun close() {
    }

    private fun InputStream.readFully(buffer: ByteArray) {
        var offset = 0
        while (offset < buffer.size) {
            val read = read(buffer, offset, buffer.size - offset)
            if (read <= 0) throw IllegalStateException("Unexpected EOF")
            offset += read
        }
    }
}

interface SocksTcpChannel {
    fun write(data: ByteArray)
    fun read(buffer: ByteArray): Int
    fun close()
}

class DefaultSocksTcpChannel(
    private val socket: Socket,
    private val input: InputStream,
    private val output: OutputStream
) : SocksTcpChannel {
    override fun write(data: ByteArray) {
        output.write(data)
        output.flush()
    }

    override fun read(buffer: ByteArray): Int {
        return input.read(buffer)
    }

    override fun close() {
        try {
            socket.close()
        } catch (_: Throwable) {
        }
    }
}