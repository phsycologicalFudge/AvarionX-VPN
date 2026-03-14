package com.colourswift.avarionxvpn.vpn.hysteria.tun

data class TcpPacket(
    val srcPort: Int,
    val dstPort: Int,
    val seq: Long,
    val ack: Long,
    val dataOffset: Int,
    val flags: Int,
    val windowSize: Int,
    val checksum: Int,
    val urgentPointer: Int,
    val payload: ByteArray
) {
    companion object {
        const val FLAG_FIN = 0x01
        const val FLAG_SYN = 0x02
        const val FLAG_RST = 0x04
        const val FLAG_PSH = 0x08
        const val FLAG_ACK = 0x10

        fun parse(ip: Ipv4Packet, raw: ByteArray, length: Int): TcpPacket? {
            val packetLength = minOf(length, ip.totalLength)
            val offset = ip.payloadOffset
            if (packetLength < offset + 20) return null

            val srcPort = ((raw[offset].toInt() and 0xFF) shl 8) or (raw[offset + 1].toInt() and 0xFF)
            val dstPort = ((raw[offset + 2].toInt() and 0xFF) shl 8) or (raw[offset + 3].toInt() and 0xFF)

            val seq = readUnsignedInt(raw, offset + 4)
            val ack = readUnsignedInt(raw, offset + 8)

            val dataOffset = ((raw[offset + 12].toInt() ushr 4) and 0x0F) * 4
            if (dataOffset < 20) return null

            val flags = raw[offset + 13].toInt() and 0xFF
            val windowSize = ((raw[offset + 14].toInt() and 0xFF) shl 8) or (raw[offset + 15].toInt() and 0xFF)
            val checksum = ((raw[offset + 16].toInt() and 0xFF) shl 8) or (raw[offset + 17].toInt() and 0xFF)
            val urgentPointer = ((raw[offset + 18].toInt() and 0xFF) shl 8) or (raw[offset + 19].toInt() and 0xFF)

            val payloadOffset = offset + dataOffset
            if (payloadOffset > packetLength) return null

            val payload = raw.copyOfRange(payloadOffset, packetLength)

            return TcpPacket(
                srcPort = srcPort,
                dstPort = dstPort,
                seq = seq,
                ack = ack,
                dataOffset = dataOffset,
                flags = flags,
                windowSize = windowSize,
                checksum = checksum,
                urgentPointer = urgentPointer,
                payload = payload
            )
        }

        private fun readUnsignedInt(raw: ByteArray, offset: Int): Long {
            return (
                    ((raw[offset].toLong() and 0xFF) shl 24) or
                            ((raw[offset + 1].toLong() and 0xFF) shl 16) or
                            ((raw[offset + 2].toLong() and 0xFF) shl 8) or
                            (raw[offset + 3].toLong() and 0xFF)
                    ) and 0xFFFFFFFFL
        }
    }
}