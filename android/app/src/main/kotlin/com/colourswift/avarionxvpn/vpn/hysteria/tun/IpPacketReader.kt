package com.colourswift.avarionxvpn.vpn.hysteria.tun

class IpPacketReader {
    fun parse(buffer: ByteArray, length: Int): ParsedPacket? {
        val ipv4 = Ipv4Packet.parse(buffer, length) ?: return null

        return when (ipv4.protocol) {
            6 -> {
                val tcp = TcpPacket.parse(ipv4, buffer, length) ?: return null
                ParsedPacket.ParsedTcpPacket(ipv4, tcp)
            }
            17 -> {
                val udp = UdpPacket.parse(ipv4, buffer, length) ?: return null
                ParsedPacket.ParsedUdpPacket(ipv4, udp)
            }
            else -> null
        }
    }
}

sealed class ParsedPacket {
    data class ParsedTcpPacket(
        val ipv4: Ipv4Packet,
        val tcp: TcpPacket
    ) : ParsedPacket()

    data class ParsedUdpPacket(
        val ipv4: Ipv4Packet,
        val udp: UdpPacket
    ) : ParsedPacket()
}