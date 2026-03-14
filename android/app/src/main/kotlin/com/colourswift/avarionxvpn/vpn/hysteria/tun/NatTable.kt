package com.colourswift.avarionxvpn.vpn.hysteria.tun

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

class NatTable {
    private val flowToSession = ConcurrentHashMap<FlowKey, SessionKey>()
    private val nextSessionId = AtomicLong(1)

    fun get(flow: FlowKey): SessionKey? {
        return flowToSession[flow]
    }

    fun put(flow: FlowKey): SessionKey {
        val session = SessionKey(nextSessionId.getAndIncrement())
        flowToSession[flow] = session
        return session
    }

    fun put(flow: FlowKey, session: SessionKey) {
        flowToSession[flow] = session
    }

    fun remove(flow: FlowKey) {
        flowToSession.remove(flow)
    }

    fun clear() {
        flowToSession.clear()
    }
}

data class FlowKey(
    val srcIp: Int,
    val srcPort: Int,
    val dstIp: Int,
    val dstPort: Int,
    val protocol: Int
)

data class SessionKey(
    val id: Long
)