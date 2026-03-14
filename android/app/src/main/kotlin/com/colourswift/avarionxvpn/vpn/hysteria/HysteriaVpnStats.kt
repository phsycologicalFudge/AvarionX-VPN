package com.colourswift.avarionxvpn.vpn.hysteria

import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

class HysteriaVpnStats {
    private val packetsIn = AtomicLong(0)
    private val packetsOut = AtomicLong(0)
    private val bytesIn = AtomicLong(0)
    private val bytesOut = AtomicLong(0)
    private val activeTcpSessions = AtomicInteger(0)
    private val activeUdpSessions = AtomicInteger(0)
    private val fdControlSuccessCount = AtomicLong(0)
    private val fdControlFailureCount = AtomicLong(0)

    @Volatile
    private var hysteriaAlive: Boolean = false

    @Volatile
    private var lastError: String? = null

    @Volatile
    private var lastProcessLog: String? = null

    fun incPacketsIn(count: Long = 1) {
        packetsIn.addAndGet(count)
    }

    fun incPacketsOut(count: Long = 1) {
        packetsOut.addAndGet(count)
    }

    fun addBytesIn(count: Long) {
        bytesIn.addAndGet(count)
    }

    fun addBytesOut(count: Long) {
        bytesOut.addAndGet(count)
    }

    fun setActiveTcpSessions(count: Int) {
        activeTcpSessions.set(count)
    }

    fun setActiveUdpSessions(count: Int) {
        activeUdpSessions.set(count)
    }

    fun incFdControlSuccess() {
        fdControlSuccessCount.incrementAndGet()
    }

    fun incFdControlFailure() {
        fdControlFailureCount.incrementAndGet()
    }

    fun setHysteriaAlive(value: Boolean) {
        hysteriaAlive = value
    }

    fun setLastError(value: String?) {
        lastError = value
    }

    fun appendProcessLog(line: String) {
        lastProcessLog = line
    }
}