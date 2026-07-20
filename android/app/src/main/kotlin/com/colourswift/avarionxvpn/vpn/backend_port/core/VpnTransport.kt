package com.colourswift.avarionxvpn.vpn.backend_port.core

enum class VpnTransport(val wire: String, val label: String) {
    WIREGUARD("wireguard", "WireGuard"),
    AMNEZIA("amnezia", "AmneziaWG"),
    HYSTERIA("hysteria", "Hysteria");

    companion object {
        fun fromWire(value: String?): VpnTransport {
            return when (value?.trim()?.lowercase()) {
                "hysteria" -> HYSTERIA
                "amnezia" -> AMNEZIA
                else -> WIREGUARD
            }
        }
    }
}

data class ConnectPlan(
    val region: String,
    val transport: VpnTransport,
    val premium: Boolean
)

object VpnPlanResolver {

    private const val FREE_REGION = "de"

    fun serverPrefix(serverId: String): String {
        return serverId.trim().lowercase()
            .split("-")
            .firstOrNull { it.isNotEmpty() }
            .orEmpty()
    }

    fun isAwgServer(serverId: String): Boolean = serverPrefix(serverId) == "awg"

    fun isHysteriaServer(serverId: String): Boolean = serverPrefix(serverId) == "hy"

    fun resolve(selectedServerId: String, storedTransport: String, premium: Boolean): ConnectPlan {
        if (!premium) {
            return ConnectPlan(
                region = FREE_REGION,
                transport = VpnTransport.WIREGUARD,
                premium = false
            )
        }

        val transport = when {
            isHysteriaServer(selectedServerId) -> VpnTransport.HYSTERIA
            isAwgServer(selectedServerId) -> VpnTransport.AMNEZIA
            else -> VpnTransport.fromWire(storedTransport)
        }

        return ConnectPlan(
            region = selectedServerId.trim().lowercase(),
            transport = transport,
            premium = true
        )
    }
}
