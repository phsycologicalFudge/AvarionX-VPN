package com.colourswift.avarionxvpn.vpn.hysteria.tun

data class UdpPacket(
    val srcPort: Int,
    val dstPort: Int,
    val length: Int,
    val checksum: Int,
    val payload: ByteArray
) {
    companion object {
        fun parse(ip: Ipv4Packet, raw: ByteArray, totalLength: Int): UdpPacket? {
            val offset = ip.payloadOffset
            if (totalLength < offset + 8) return null

            val srcPort = ((raw[offset].toInt() and 0xFF) shl 8) or (raw[offset + 1].toInt() and 0xFF)
            val dstPort = ((raw[offset + 2].toInt() and 0xFF) shl 8) or (raw[offset + 3].toInt() and 0xFF)
            val length = ((raw[offset + 4].toInt() and 0xFF) shl 8) or (raw[offset + 5].toInt() and 0xFF)
            val checksum = ((raw[offset + 6].toInt() and 0xFF) shl 8) or (raw[offset + 7].toInt() and 0xFF)

            if (length < 8) return null

            val payloadStart = offset + 8
            val payloadEnd = kotlin.math.min(totalLength, offset + length)
            if (payloadEnd < payloadStart) return null

            val payload = raw.copyOfRange(payloadStart, payloadEnd)

            return UdpPacket(
                srcPort = srcPort,
                dstPort = dstPort,
                length = length,
                checksum = checksum,
                payload = payload
            )
        }
    }
}