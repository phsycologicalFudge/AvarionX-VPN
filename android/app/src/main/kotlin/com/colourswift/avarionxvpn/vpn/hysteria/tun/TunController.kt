package com.colourswift.avarionxvpn.vpn.hysteria.tun

import android.os.ParcelFileDescriptor
import com.colourswift.avarionxvpn.vpn.hysteria.HyLog
import com.colourswift.avarionxvpn.vpn.hysteria.HysteriaVpnStats
import java.io.InputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class TunController(
    private val tunFd: ParcelFileDescriptor,
    private val packetReader: IpPacketReader,
    private val tcpSessionManager: TcpSessionManager,
    private val udpSessionManager: UdpSessionManager,
    private val stats: HysteriaVpnStats
) {
    private val running = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor()

    private var tunInput: InputStream? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return

        tunInput = ParcelFileDescriptor.AutoCloseInputStream(tunFd)

        executor.execute {
            readLoop()
        }
    }

    fun stop() {
        running.set(false)

        try {
            tunInput?.close()
        } catch (_: Throwable) {
        }

        executor.shutdownNow()
    }

    fun isRunning(): Boolean {
        return running.get()
    }

    private fun readLoop() {
        val input = tunInput ?: return
        val buffer = ByteArray(32767)

        while (running.get()) {
            val read = try {
                input.read(buffer)
            } catch (_: Throwable) {
                break
            }

            if (read <= 0) continue

            stats.incPacketsIn()
            stats.addBytesIn(read.toLong())

            val packet = packetReader.parse(buffer, read) ?: continue

            when (packet) {
                is ParsedPacket.ParsedTcpPacket -> {
                    HyLog.write(
                        tcpSessionManager.context,
                        "tun tcp src=${packet.ipv4.srcIp}:${packet.tcp.srcPort} dst=${packet.ipv4.dstIp}:${packet.tcp.dstPort} flags=${packet.tcp.flags} payload=${packet.tcp.payload.size}"
                    )
                    tcpSessionManager.handlePacket(packet.ipv4, packet.tcp)
                }
                is ParsedPacket.ParsedUdpPacket -> {
                    HyLog.write(
                        tcpSessionManager.context,
                        "tun udp src=${packet.ipv4.srcIp}:${packet.udp.srcPort} dst=${packet.ipv4.dstIp}:${packet.udp.dstPort} payload=${packet.udp.payload.size}"
                    )
                    udpSessionManager.handlePacket(packet.ipv4, packet.udp)
                }
            }
        }
    }
}