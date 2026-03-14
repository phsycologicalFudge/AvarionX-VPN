package com.colourswift.avarionxvpn.vpn.hysteria.tun

import com.colourswift.avarionxvpn.vpn.hysteria.HysteriaVpnStats
import java.io.OutputStream

class PacketWriter(
    private val tunOutput: OutputStream,
    private val stats: HysteriaVpnStats
) {
    private val maxTcpPayloadSize = 1300

    fun writeSynAck(state: TcpSessionState) {
        val packet = buildTcpPacket(
            srcIp = state.flowKey.dstIp,
            dstIp = state.flowKey.srcIp,
            srcPort = state.flowKey.dstPort,
            dstPort = state.flowKey.srcPort,
            seq = state.serverSeq,
            ack = state.serverAck,
            flags = TcpPacket.FLAG_SYN or TcpPacket.FLAG_ACK,
            payload = byteArrayOf(),
            windowSize = 65535,
            options = synAckOptions()
        )
        writeRaw(packet)
        state.serverSeq += 1
    }

    fun writeSynAckRetransmit(state: TcpSessionState) {
        val seqForRetransmit = state.serverSeq - 1

        val packet = buildTcpPacket(
            srcIp = state.flowKey.dstIp,
            dstIp = state.flowKey.srcIp,
            srcPort = state.flowKey.dstPort,
            dstPort = state.flowKey.srcPort,
            seq = seqForRetransmit,
            ack = state.serverAck,
            flags = TcpPacket.FLAG_SYN or TcpPacket.FLAG_ACK,
            payload = byteArrayOf(),
            windowSize = 65535,
            options = synAckOptions()
        )
        writeRaw(packet)
    }

    fun writeAck(state: TcpSessionState) {
        val packet = buildTcpPacket(
            srcIp = state.flowKey.dstIp,
            dstIp = state.flowKey.srcIp,
            srcPort = state.flowKey.dstPort,
            dstPort = state.flowKey.srcPort,
            seq = state.serverSeq,
            ack = state.serverAck,
            flags = TcpPacket.FLAG_ACK,
            payload = byteArrayOf(),
            windowSize = 65535
        )
        writeRaw(packet)
    }

    fun writeFinAck(state: TcpSessionState) {
        val packet = buildTcpPacket(
            srcIp = state.flowKey.dstIp,
            dstIp = state.flowKey.srcIp,
            srcPort = state.flowKey.dstPort,
            dstPort = state.flowKey.srcPort,
            seq = state.serverSeq,
            ack = state.serverAck,
            flags = TcpPacket.FLAG_FIN or TcpPacket.FLAG_ACK,
            payload = byteArrayOf(),
            windowSize = 65535
        )
        writeRaw(packet)
        state.serverSeq += 1
        state.serverFinSent = true
    }

    fun writeServerData(state: TcpSessionState, payload: ByteArray) {
        if (payload.isEmpty()) return

        var offset = 0

        while (offset < payload.size) {
            val end = minOf(offset + maxTcpPayloadSize, payload.size)
            val chunk = payload.copyOfRange(offset, end)
            val flags = if (end >= payload.size) {
                TcpPacket.FLAG_ACK or TcpPacket.FLAG_PSH
            } else {
                TcpPacket.FLAG_ACK
            }

            val packet = buildTcpPacket(
                srcIp = state.flowKey.dstIp,
                dstIp = state.flowKey.srcIp,
                srcPort = state.flowKey.dstPort,
                dstPort = state.flowKey.srcPort,
                seq = state.serverSeq,
                ack = state.serverAck,
                flags = flags,
                payload = chunk,
                windowSize = 65535
            )

            writeRaw(packet)
            state.serverSeq += chunk.size.toLong()
            offset = end
        }
    }

    fun writeServerFin(state: TcpSessionState) {
        val packet = buildTcpPacket(
            srcIp = state.flowKey.dstIp,
            dstIp = state.flowKey.srcIp,
            srcPort = state.flowKey.dstPort,
            dstPort = state.flowKey.srcPort,
            seq = state.serverSeq,
            ack = state.serverAck,
            flags = TcpPacket.FLAG_FIN or TcpPacket.FLAG_ACK,
            payload = byteArrayOf(),
            windowSize = 65535
        )
        writeRaw(packet)
        state.serverFinSent = true
        state.serverSeq += 1
    }

    fun writeRst(state: TcpSessionState) {
        val packet = buildTcpPacket(
            srcIp = state.flowKey.dstIp,
            dstIp = state.flowKey.srcIp,
            srcPort = state.flowKey.dstPort,
            dstPort = state.flowKey.srcPort,
            seq = state.serverSeq,
            ack = state.serverAck,
            flags = TcpPacket.FLAG_RST or TcpPacket.FLAG_ACK,
            payload = byteArrayOf(),
            windowSize = 65535
        )
        writeRaw(packet)
    }

    fun writeUdp(
        srcIp: Int,
        dstIp: Int,
        srcPort: Int,
        dstPort: Int,
        payload: ByteArray
    ) {
        val packet = buildUdpPacket(
            srcIp = srcIp,
            dstIp = dstIp,
            srcPort = srcPort,
            dstPort = dstPort,
            payload = payload
        )
        writeRaw(packet)
    }

    fun writeRaw(packet: ByteArray) {
        tunOutput.write(packet)
        tunOutput.flush()
        stats.incPacketsOut()
        stats.addBytesOut(packet.size.toLong())
    }

    fun close() {
        try {
            tunOutput.close()
        } catch (_: Throwable) {
        }
    }

    private fun synAckOptions(): ByteArray {
        return byteArrayOf(
            2, 4, 0x05, 0xB4.toByte(),
            4, 2,
            3, 3, 7,
            1
        )
    }

    private fun buildTcpPacket(
        srcIp: Int,
        dstIp: Int,
        srcPort: Int,
        dstPort: Int,
        seq: Long,
        ack: Long,
        flags: Int,
        payload: ByteArray,
        windowSize: Int = 65535,
        options: ByteArray = byteArrayOf()
    ): ByteArray {
        val paddedOptionsLen = if (options.isEmpty()) 0 else ((options.size + 3) / 4) * 4
        val ipHeaderLen = 20
        val tcpHeaderLen = 20 + paddedOptionsLen
        val tcpHeaderWords = tcpHeaderLen / 4
        val totalLen = ipHeaderLen + tcpHeaderLen + payload.size

        val packet = ByteArray(totalLen)

        packet[0] = 0x45.toByte()
        packet[1] = 0x00.toByte()
        writeU16(packet, 2, totalLen)
        writeU16(packet, 4, 0)
        writeU16(packet, 6, 0)
        packet[8] = 64.toByte()
        packet[9] = 6.toByte()
        writeU16(packet, 10, 0)
        writeU32(packet, 12, srcIp)
        writeU32(packet, 16, dstIp)

        val ipChecksum = checksum(packet, 0, ipHeaderLen)
        writeU16(packet, 10, ipChecksum)

        writeU16(packet, 20, srcPort)
        writeU16(packet, 22, dstPort)
        writeU32(packet, 24, seq)
        writeU32(packet, 28, ack)
        packet[32] = ((tcpHeaderWords shl 4) and 0xF0).toByte()
        packet[33] = (flags and 0xFF).toByte()
        writeU16(packet, 34, windowSize)
        writeU16(packet, 36, 0)
        writeU16(packet, 38, 0)

        if (options.isNotEmpty()) {
            System.arraycopy(options, 0, packet, 40, options.size)
        }

        if (payload.isNotEmpty()) {
            System.arraycopy(payload, 0, packet, 20 + tcpHeaderLen, payload.size)
        }

        val tcpChecksum = tcpChecksum(
            srcIp = srcIp,
            dstIp = dstIp,
            tcpSegment = packet,
            offset = 20,
            length = tcpHeaderLen + payload.size
        )
        writeU16(packet, 36, tcpChecksum)

        return packet
    }

    private fun buildUdpPacket(
        srcIp: Int,
        dstIp: Int,
        srcPort: Int,
        dstPort: Int,
        payload: ByteArray
    ): ByteArray {
        val ipHeaderLen = 20
        val udpHeaderLen = 8
        val totalLen = ipHeaderLen + udpHeaderLen + payload.size
        val udpLength = udpHeaderLen + payload.size

        val packet = ByteArray(totalLen)

        packet[0] = 0x45.toByte()
        packet[1] = 0x00.toByte()
        writeU16(packet, 2, totalLen)
        writeU16(packet, 4, 0)
        writeU16(packet, 6, 0)
        packet[8] = 64.toByte()
        packet[9] = 17.toByte()
        writeU16(packet, 10, 0)
        writeU32(packet, 12, srcIp)
        writeU32(packet, 16, dstIp)

        val ipChecksum = checksum(packet, 0, ipHeaderLen)
        writeU16(packet, 10, ipChecksum)

        writeU16(packet, 20, srcPort)
        writeU16(packet, 22, dstPort)
        writeU16(packet, 24, udpLength)
        writeU16(packet, 26, 0)

        if (payload.isNotEmpty()) {
            System.arraycopy(payload, 0, packet, 28, payload.size)
        }

        val udpChecksum = udpChecksum(
            srcIp = srcIp,
            dstIp = dstIp,
            udpSegment = packet,
            offset = 20,
            length = udpLength
        )
        writeU16(packet, 26, udpChecksum)

        return packet
    }

    private fun tcpChecksum(
        srcIp: Int,
        dstIp: Int,
        tcpSegment: ByteArray,
        offset: Int,
        length: Int
    ): Int {
        val pseudo = ByteArray(12 + length)

        writeU32(pseudo, 0, srcIp)
        writeU32(pseudo, 4, dstIp)
        pseudo[8] = 0
        pseudo[9] = 6
        writeU16(pseudo, 10, length)

        System.arraycopy(tcpSegment, offset, pseudo, 12, length)

        return checksum(pseudo, 0, pseudo.size)
    }

    private fun udpChecksum(
        srcIp: Int,
        dstIp: Int,
        udpSegment: ByteArray,
        offset: Int,
        length: Int
    ): Int {
        val pseudo = ByteArray(12 + length)

        writeU32(pseudo, 0, srcIp)
        writeU32(pseudo, 4, dstIp)
        pseudo[8] = 0
        pseudo[9] = 17
        writeU16(pseudo, 10, length)

        System.arraycopy(udpSegment, offset, pseudo, 12, length)

        val value = checksum(pseudo, 0, pseudo.size)
        return if (value == 0) 0xFFFF else value
    }

    private fun checksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0L
        var i = offset
        val end = offset + length

        while (i + 1 < end) {
            val word = ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            sum += word.toLong()
            while ((sum ushr 16) != 0L) {
                sum = (sum and 0xFFFF) + (sum ushr 16)
            }
            i += 2
        }

        if (i < end) {
            val word = (data[i].toInt() and 0xFF) shl 8
            sum += word.toLong()
            while ((sum ushr 16) != 0L) {
                sum = (sum and 0xFFFF) + (sum ushr 16)
            }
        }

        return sum.inv().toInt() and 0xFFFF
    }

    private fun writeU16(buffer: ByteArray, offset: Int, value: Int) {
        buffer[offset] = ((value ushr 8) and 0xFF).toByte()
        buffer[offset + 1] = (value and 0xFF).toByte()
    }

    private fun writeU32(buffer: ByteArray, offset: Int, value: Int) {
        buffer[offset] = ((value ushr 24) and 0xFF).toByte()
        buffer[offset + 1] = ((value ushr 16) and 0xFF).toByte()
        buffer[offset + 2] = ((value ushr 8) and 0xFF).toByte()
        buffer[offset + 3] = (value and 0xFF).toByte()
    }

    private fun writeU32(buffer: ByteArray, offset: Int, value: Long) {
        buffer[offset] = ((value ushr 24) and 0xFF).toByte()
        buffer[offset + 1] = ((value ushr 16) and 0xFF).toByte()
        buffer[offset + 2] = ((value ushr 8) and 0xFF).toByte()
        buffer[offset + 3] = (value and 0xFF).toByte()
    }
}