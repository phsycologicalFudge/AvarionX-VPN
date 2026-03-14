package com.colourswift.avarionxvpn.vpn.hysteria.tun

import android.content.Context
import com.colourswift.avarionxvpn.vpn.hysteria.HyLog
import com.colourswift.avarionxvpn.vpn.hysteria.HysteriaVpnStats
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

class UdpSessionManager(
    val context: Context,
    private val natTable: NatTable,
    private val packetWriter: PacketWriter,
    private val stats: HysteriaVpnStats,
    private val socksHost: String = "127.0.0.1",
    private val socksPort: Int = 1080
) {
    private val sessions = ConcurrentHashMap<SessionKey, UdpSessionState>()
    private val sessionReaders = ConcurrentHashMap<SessionKey, Future<*>>()
    private val readerExecutor = Executors.newCachedThreadPool()
    private val housekeepingExecutor = Executors.newSingleThreadScheduledExecutor()
    private val idleTimeoutMs = 45000L

    init {
        housekeepingExecutor.scheduleAtFixedRate({
            try {
                sweepSessions()
            } catch (_: Throwable) {
            }
        }, 5, 5, TimeUnit.SECONDS)
    }

    fun handlePacket(ip: Ipv4Packet, udp: UdpPacket) {
        val now = System.currentTimeMillis()

        val flow = FlowKey(
            srcIp = ip.srcIp,
            srcPort = udp.srcPort,
            dstIp = ip.dstIp,
            dstPort = udp.dstPort,
            protocol = 17
        )

        var sessionKey = natTable.get(flow)
        var state = if (sessionKey != null) sessions[sessionKey] else null

        if (state == null) {
            val created = try {
                createSession(flow, now)
            } catch (t: Throwable) {
                HyLog.write(context, "udp createSession failed dst=${ip.dstIp}:${udp.dstPort} error=${t.message ?: "unknown"}")
                natTable.remove(flow)
                return
            }

            sessionKey = created.sessionKey
            state = created
            natTable.put(flow, sessionKey)
            sessions[sessionKey] = state
            stats.setActiveUdpSessions(sessions.size)
            startReaderLoop(state)
            HyLog.write(context, "udp session created dst=${ip.dstIp}:${udp.dstPort} relay=${state.relayAddress.hostAddress}:${state.relayPort}")
        }

        synchronized(state) {
            state.lastActivityAtMs = now
        }

        try {
            sendViaSocksUdp(state, ip.dstIp, udp.dstPort, udp.payload)
            HyLog.write(context, "udp client payload dst=${ip.dstIp}:${udp.dstPort} bytes=${udp.payload.size}")
        } catch (t: Throwable) {
            HyLog.write(context, "udp send failed dst=${ip.dstIp}:${udp.dstPort} error=${t.message ?: "unknown"}")
            closeSession(state)
        }
    }

    fun closeAll() {
        sessionReaders.values.forEach { future ->
            try {
                future.cancel(true)
            } catch (_: Throwable) {
            }
        }
        sessionReaders.clear()

        sessions.values.forEach { state ->
            try {
                state.udpSocket.close()
            } catch (_: Throwable) {
            }
            try {
                state.controlSocket.close()
            } catch (_: Throwable) {
            }
        }

        sessions.clear()
        stats.setActiveUdpSessions(0)
        housekeepingExecutor.shutdownNow()
        readerExecutor.shutdownNow()
    }

    private fun createSession(flow: FlowKey, now: Long): UdpSessionState {
        val controlSocket = Socket()
        controlSocket.tcpNoDelay = true
        controlSocket.connect(InetSocketAddress(socksHost, socksPort), 10000)

        val input = BufferedInputStream(controlSocket.getInputStream())
        val output = BufferedOutputStream(controlSocket.getOutputStream())

        output.write(byteArrayOf(0x05, 0x01, 0x00))
        output.flush()

        val authReply = readExact(input, 2)
        if (authReply[0].toInt() != 0x05 || authReply[1].toInt() != 0x00) {
            controlSocket.close()
            throw IllegalStateException("SOCKS auth failed")
        }

        val request = ByteArray(10)
        request[0] = 0x05
        request[1] = 0x03
        request[2] = 0x00
        request[3] = 0x01
        request[4] = 0x00
        request[5] = 0x00
        request[6] = 0x00
        request[7] = 0x00
        request[8] = 0x00
        request[9] = 0x00

        output.write(request)
        output.flush()

        val head = readExact(input, 4)
        if (head[0].toInt() != 0x05) {
            controlSocket.close()
            throw IllegalStateException("SOCKS UDP associate invalid version")
        }
        if (head[1].toInt() != 0x00) {
            controlSocket.close()
            throw IllegalStateException("SOCKS UDP associate failed rep=${head[1].toInt() and 0xFF}")
        }

        val atyp = head[3].toInt() and 0xFF
        val relayAddress = when (atyp) {
            0x01 -> InetAddress.getByAddress(readExact(input, 4))
            0x03 -> {
                val len = readExact(input, 1)[0].toInt() and 0xFF
                InetAddress.getByName(String(readExact(input, len), Charsets.UTF_8))
            }
            0x04 -> InetAddress.getByAddress(readExact(input, 16))
            else -> {
                controlSocket.close()
                throw IllegalStateException("SOCKS UDP associate unsupported atyp=$atyp")
            }
        }

        val portBytes = readExact(input, 2)
        val relayPort = ((portBytes[0].toInt() and 0xFF) shl 8) or (portBytes[1].toInt() and 0xFF)

        val udpSocket = DatagramSocket()
        udpSocket.soTimeout = 15000
        udpSocket.connect(relayAddress, relayPort)

        val sessionKey = SessionKey(System.nanoTime())

        return UdpSessionState(
            sessionKey = sessionKey,
            flowKey = flow,
            relayAddress = relayAddress,
            relayPort = relayPort,
            controlSocket = controlSocket,
            udpSocket = udpSocket,
            createdAtMs = now,
            lastActivityAtMs = now
        )
    }

    private fun startReaderLoop(state: UdpSessionState) {
        val future = readerExecutor.submit {
            val buffer = ByteArray(65535)

            try {
                while (true) {
                    if (state.closed) break

                    val packet = DatagramPacket(buffer, buffer.size)
                    state.udpSocket.receive(packet)

                    synchronized(state) {
                        state.lastActivityAtMs = System.currentTimeMillis()
                    }

                    val decoded = parseSocksUdpResponse(packet.data, packet.length) ?: continue

                    val srcIp = inet4ToInt(decoded.dstAddress)
                    packetWriter.writeUdp(
                        srcIp = srcIp,
                        dstIp = state.flowKey.srcIp,
                        srcPort = decoded.dstPort,
                        dstPort = state.flowKey.srcPort,
                        payload = decoded.payload
                    )

                    HyLog.write(
                        context,
                        "udp server payload src=${srcIp}:${decoded.dstPort} dst=${state.flowKey.srcIp}:${state.flowKey.srcPort} bytes=${decoded.payload.size}"
                    )
                }
            } catch (t: Throwable) {
                if (!state.closed) {
                    HyLog.write(context, "udp reader error dst=${state.flowKey.dstIp}:${state.flowKey.dstPort} error=${t.message ?: "unknown"}")
                }
            } finally {
                closeSession(state)
            }
        }

        sessionReaders[state.sessionKey] = future
    }

    private fun sendViaSocksUdp(state: UdpSessionState, dstIp: Int, dstPort: Int, payload: ByteArray) {
        val addressBytes = intToIpv4Bytes(dstIp)
        val packet = ByteArray(10 + payload.size)

        packet[0] = 0x00
        packet[1] = 0x00
        packet[2] = 0x00
        packet[3] = 0x01
        System.arraycopy(addressBytes, 0, packet, 4, 4)
        packet[8] = ((dstPort ushr 8) and 0xFF).toByte()
        packet[9] = (dstPort and 0xFF).toByte()
        System.arraycopy(payload, 0, packet, 10, payload.size)

        val datagram = DatagramPacket(packet, packet.size, state.relayAddress, state.relayPort)
        state.udpSocket.send(datagram)
    }

    private fun parseSocksUdpResponse(data: ByteArray, length: Int): DecodedSocksUdpPacket? {
        if (length < 10) return null
        if ((data[0].toInt() and 0xFF) != 0x00 || (data[1].toInt() and 0xFF) != 0x00) return null
        if ((data[2].toInt() and 0xFF) != 0x00) return null

        val atyp = data[3].toInt() and 0xFF
        var offset = 4

        val address = when (atyp) {
            0x01 -> {
                if (length < offset + 4 + 2) return null
                val addr = InetAddress.getByAddress(data.copyOfRange(offset, offset + 4))
                offset += 4
                addr
            }
            0x03 -> {
                if (length < offset + 1) return null
                val len = data[offset].toInt() and 0xFF
                offset += 1
                if (length < offset + len + 2) return null
                val addr = InetAddress.getByName(String(data, offset, len, Charsets.UTF_8))
                offset += len
                addr
            }
            0x04 -> {
                if (length < offset + 16 + 2) return null
                val addr = InetAddress.getByAddress(data.copyOfRange(offset, offset + 16))
                offset += 16
                addr
            }
            else -> return null
        }

        val port = ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)
        offset += 2
        if (length < offset) return null

        val payload = data.copyOfRange(offset, length)
        return DecodedSocksUdpPacket(address, port, payload)
    }

    private fun sweepSessions() {
        val now = System.currentTimeMillis()
        val snapshot = sessions.values.toList()

        for (state in snapshot) {
            val shouldClose = synchronized(state) {
                !state.closed && now - state.lastActivityAtMs > idleTimeoutMs
            }

            if (shouldClose) {
                HyLog.write(context, "udp sweep close dst=${state.flowKey.dstIp}:${state.flowKey.dstPort} reason=idle_timeout")
                closeSession(state)
            }
        }
    }

    private fun closeSession(state: UdpSessionState) {
        synchronized(state) {
            if (state.closed) return
            state.closed = true
        }

        HyLog.write(context, "udp closeSession dst=${state.flowKey.dstIp}:${state.flowKey.dstPort}")

        natTable.remove(state.flowKey)
        sessions.remove(state.sessionKey)

        val future = sessionReaders.remove(state.sessionKey)
        if (future != null && !future.isDone) {
            try {
                future.cancel(true)
            } catch (_: Throwable) {
            }
        }

        try {
            state.udpSocket.close()
        } catch (_: Throwable) {
        }

        try {
            state.controlSocket.close()
        } catch (_: Throwable) {
        }

        stats.setActiveUdpSessions(sessions.size)
    }

    private fun readExact(input: BufferedInputStream, size: Int): ByteArray {
        val out = ByteArray(size)
        var offset = 0
        while (offset < size) {
            val read = input.read(out, offset, size - offset)
            if (read < 0) throw IllegalStateException("Unexpected EOF")
            offset += read
        }
        return out
    }

    private fun intToIpv4Bytes(value: Int): ByteArray {
        return byteArrayOf(
            ((value ushr 24) and 0xFF).toByte(),
            ((value ushr 16) and 0xFF).toByte(),
            ((value ushr 8) and 0xFF).toByte(),
            (value and 0xFF).toByte()
        )
    }

    private fun inet4ToInt(address: InetAddress): Int {
        val raw = (address as Inet4Address).address
        return ((raw[0].toInt() and 0xFF) shl 24) or
                ((raw[1].toInt() and 0xFF) shl 16) or
                ((raw[2].toInt() and 0xFF) shl 8) or
                (raw[3].toInt() and 0xFF)
    }
}

data class UdpSessionState(
    val sessionKey: SessionKey,
    val flowKey: FlowKey,
    val relayAddress: InetAddress,
    val relayPort: Int,
    val controlSocket: Socket,
    val udpSocket: DatagramSocket,
    val createdAtMs: Long,
    var lastActivityAtMs: Long,
    var closed: Boolean = false
)

data class DecodedSocksUdpPacket(
    val dstAddress: InetAddress,
    val dstPort: Int,
    val payload: ByteArray
)