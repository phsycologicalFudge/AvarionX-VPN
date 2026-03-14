package com.colourswift.avarionxvpn.vpn.hysteria.tun

data class Ipv4Packet(
    val version: Int,
    val ihl: Int,
    val totalLength: Int,
    val protocol: Int,
    val srcIp: Int,
    val dstIp: Int,
    val ttl: Int,
    val identification: Int,
    val flagsFragment: Int,
    val headerChecksum: Int,
    val payloadOffset: Int
) {
    companion object {
        fun parse(raw: ByteArray, length: Int): Ipv4Packet? {
            if (length < 20) return null

            val version = (raw[0].toInt() ushr 4) and 0x0F
            val ihl = (raw[0].toInt() and 0x0F) * 4
            if (version != 4 || ihl < 20 || length < ihl) return null

            val totalLength = ((raw[2].toInt() and 0xFF) shl 8) or (raw[3].toInt() and 0xFF)
            if (totalLength < ihl || totalLength > length) return null

            val identification = ((raw[4].toInt() and 0xFF) shl 8) or (raw[5].toInt() and 0xFF)
            val flagsFragment = ((raw[6].toInt() and 0xFF) shl 8) or (raw[7].toInt() and 0xFF)
            val ttl = raw[8].toInt() and 0xFF
            val protocol = raw[9].toInt() and 0xFF
            val headerChecksum = ((raw[10].toInt() and 0xFF) shl 8) or (raw[11].toInt() and 0xFF)

            val srcIp = readInt(raw, 12)
            val dstIp = readInt(raw, 16)

            return Ipv4Packet(
                version = version,
                ihl = ihl,
                totalLength = totalLength,
                protocol = protocol,
                srcIp = srcIp,
                dstIp = dstIp,
                ttl = ttl,
                identification = identification,
                flagsFragment = flagsFragment,
                headerChecksum = headerChecksum,
                payloadOffset = ihl
            )
        }

        private fun readInt(raw: ByteArray, offset: Int): Int {
            return ((raw[offset].toInt() and 0xFF) shl 24) or
                    ((raw[offset + 1].toInt() and 0xFF) shl 16) or
                    ((raw[offset + 2].toInt() and 0xFF) shl 8) or
                    (raw[offset + 3].toInt() and 0xFF)
        }
    }
}