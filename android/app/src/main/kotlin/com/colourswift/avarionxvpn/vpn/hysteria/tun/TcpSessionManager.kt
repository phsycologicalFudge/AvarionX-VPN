package com.colourswift.avarionxvpn.vpn.hysteria.tun

import android.content.Context
import com.colourswift.avarionxvpn.vpn.hysteria.HyLog
import com.colourswift.avarionxvpn.vpn.hysteria.HysteriaVpnStats
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

class TcpSessionManager(
    val context: Context,
    private val natTable: NatTable,
    private val socksTunnel: SocksTunnel,
    private val packetWriter: PacketWriter,
    private val stats: HysteriaVpnStats
) {
    private val sessions = ConcurrentHashMap<SessionKey, TcpSessionState>()
    private val sessionReaders = ConcurrentHashMap<SessionKey, Future<*>>()
    private val readerExecutor = Executors.newCachedThreadPool()
    private val housekeepingExecutor = Executors.newSingleThreadScheduledExecutor()

    private val synReceivedTimeoutMs = 8000L
    private val idleTimeoutMs = 45000L
    private val lastAckTimeoutMs = 15000L

    init {
        housekeepingExecutor.scheduleAtFixedRate({
            try {
                sweepSessions()
            } catch (_: Throwable) {
            }
        }, 5, 5, TimeUnit.SECONDS)
    }

    fun handlePacket(ip: Ipv4Packet, tcp: TcpPacket) {
        val now = System.currentTimeMillis()

        val flow = FlowKey(
            srcIp = ip.srcIp,
            srcPort = tcp.srcPort,
            dstIp = ip.dstIp,
            dstPort = tcp.dstPort,
            protocol = 6
        )

        val existingSessionKey = natTable.get(flow)
        if (existingSessionKey == null) {
            if ((tcp.flags and TcpPacket.FLAG_SYN) == 0) {
                HyLog.write(context, "tcp ignore non-syn new flow dst=${ip.dstIp}:${tcp.dstPort}")
                return
            }

            HyLog.write(context, "tcp new syn dst=${ip.dstIp}:${tcp.dstPort} seq=${tcp.seq}")

            val sessionKey = natTable.put(flow)

            val channel = try {
                socksTunnel.openTcpTunnel(
                    dstIp = ip.dstIp,
                    dstPort = tcp.dstPort
                )
            } catch (t: Throwable) {
                HyLog.write(context, "tcp openTcpTunnel failed dst=${ip.dstIp}:${tcp.dstPort} error=${t.message ?: "unknown"}")
                natTable.remove(flow)
                return
            }

            HyLog.write(context, "tcp openTcpTunnel ok dst=${ip.dstIp}:${tcp.dstPort}")

            val state = TcpSessionState(
                sessionKey = sessionKey,
                flowKey = flow,
                clientSeq = tcp.seq,
                clientAck = tcp.ack,
                serverSeq = 1L,
                serverAck = tcp.seq + 1,
                tcpState = TcpState.SYN_RECEIVED,
                channel = channel,
                createdAtMs = now,
                lastActivityAtMs = now
            )

            sessions[sessionKey] = state
            stats.setActiveTcpSessions(sessions.size)
            packetWriter.writeSynAck(state)
            HyLog.write(context, "tcp synack written dst=${ip.dstIp}:${tcp.dstPort}")
            startReaderLoop(state)
            return
        }

        val state = sessions[existingSessionKey] ?: run {
            natTable.remove(flow)
            return
        }

        synchronized(state) {
            state.lastActivityAtMs = now

            if ((tcp.flags and TcpPacket.FLAG_RST) != 0) {
                HyLog.write(context, "tcp rst from client dst=${ip.dstIp}:${tcp.dstPort}")
                closeSessionLocked(state)
                return
            }

            if ((tcp.flags and TcpPacket.FLAG_SYN) != 0) {
                if (state.tcpState == TcpState.SYN_RECEIVED) {
                    HyLog.write(context, "tcp duplicate syn, resend synack dst=${ip.dstIp}:${tcp.dstPort}")
                    state.clientSeq = tcp.seq
                    state.clientAck = tcp.ack
                    state.serverAck = tcp.seq + 1
                    packetWriter.writeSynAckRetransmit(state)
                    return
                }

                if (state.tcpState == TcpState.ESTABLISHED || state.tcpState == TcpState.CLOSE_WAIT || state.tcpState == TcpState.LAST_ACK) {
                    HyLog.write(context, "tcp duplicate syn on existing flow, ack only dst=${ip.dstIp}:${tcp.dstPort}")
                    packetWriter.writeAck(state)
                    return
                }
            }

            if ((tcp.flags and TcpPacket.FLAG_ACK) != 0 && state.tcpState == TcpState.SYN_RECEIVED) {
                if (tcp.ack == state.serverSeq) {
                    state.tcpState = TcpState.ESTABLISHED
                    state.clientSeq = tcp.seq
                    state.clientAck = tcp.ack
                    state.serverAck = tcp.seq
                    HyLog.write(context, "tcp established dst=${ip.dstIp}:${tcp.dstPort}")
                } else {
                    HyLog.write(context, "tcp bad ack during handshake dst=${ip.dstIp}:${tcp.dstPort} ack=${tcp.ack} expected=${state.serverSeq}")
                    packetWriter.writeSynAckRetransmit(state)
                    return
                }
            }

            if ((tcp.flags and TcpPacket.FLAG_ACK) != 0 && state.tcpState == TcpState.LAST_ACK) {
                state.clientSeq = tcp.seq
                state.clientAck = tcp.ack
                if (state.serverFinSent && tcp.ack >= state.serverSeq) {
                    HyLog.write(context, "tcp final ack received dst=${ip.dstIp}:${tcp.dstPort}")
                    closeSessionLocked(state)
                }
                return
            }

            if (state.tcpState == TcpState.ESTABLISHED && tcp.payload.isNotEmpty()) {
                val expectedSeq = state.serverAck

                if (tcp.seq > expectedSeq) {
                    HyLog.write(context, "tcp future client seq dst=${ip.dstIp}:${tcp.dstPort} seq=${tcp.seq} expected=$expectedSeq")
                    packetWriter.writeAck(state)
                    return
                }

                var payloadToWrite = tcp.payload
                var acceptedSeq = tcp.seq

                if (tcp.seq < expectedSeq) {
                    val overlap = (expectedSeq - tcp.seq).toInt()

                    if (overlap >= tcp.payload.size) {
                        HyLog.write(context, "tcp duplicate client payload dst=${ip.dstIp}:${tcp.dstPort} seq=${tcp.seq} expected=$expectedSeq bytes=${tcp.payload.size}")
                        packetWriter.writeAck(state)
                        return
                    }

                    payloadToWrite = tcp.payload.copyOfRange(overlap, tcp.payload.size)
                    acceptedSeq = tcp.seq + overlap
                    HyLog.write(context, "tcp partial retransmit dst=${ip.dstIp}:${tcp.dstPort} seq=${tcp.seq} expected=$expectedSeq trimmed=$overlap remain=${payloadToWrite.size}")
                }

                HyLog.write(context, "tcp client payload dst=${ip.dstIp}:${tcp.dstPort} bytes=${payloadToWrite.size}")
                state.channel.write(payloadToWrite)
                state.clientSeq = acceptedSeq
                state.clientAck = tcp.ack
                state.serverAck = acceptedSeq + payloadToWrite.size.toLong()
                packetWriter.writeAck(state)
                return
            }

            if (state.tcpState == TcpState.ESTABLISHED && (tcp.flags and TcpPacket.FLAG_ACK) != 0) {
                state.clientSeq = tcp.seq
                state.clientAck = tcp.ack
            }

            if ((tcp.flags and TcpPacket.FLAG_FIN) != 0) {
                HyLog.write(context, "tcp fin from client dst=${ip.dstIp}:${tcp.dstPort}")
                state.clientSeq = tcp.seq
                state.clientAck = tcp.ack
                state.serverAck = tcp.seq + 1
                packetWriter.writeAck(state)

                if (state.tcpState == TcpState.ESTABLISHED) {
                    state.tcpState = TcpState.CLOSE_WAIT
                } else if (state.tcpState == TcpState.LAST_ACK && state.serverFinSent && tcp.ack >= state.serverSeq) {
                    closeSessionLocked(state)
                }
                return
            }
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
                state.channel.close()
            } catch (_: Throwable) {
            }
        }

        sessions.clear()
        natTable.clear()
        stats.setActiveTcpSessions(0)
        housekeepingExecutor.shutdownNow()
        readerExecutor.shutdownNow()
    }

    private fun startReaderLoop(state: TcpSessionState) {
        val future = readerExecutor.submit {
            val buffer = ByteArray(16384)

            try {
                while (true) {
                    val shouldStop = synchronized(state) {
                        state.tcpState == TcpState.CLOSED
                    }
                    if (shouldStop) {
                        break
                    }

                    val read = state.channel.read(buffer)
                    if (read <= 0) {
                        var sendFin = false

                        synchronized(state) {
                            if (state.tcpState == TcpState.CLOSED) {
                                return@submit
                            }

                            state.lastActivityAtMs = System.currentTimeMillis()

                            if (!state.serverFinSent) {
                                state.tcpState = TcpState.LAST_ACK
                                state.serverFinSent = true
                                sendFin = true
                            }
                        }

                        if (sendFin) {
                            HyLog.write(context, "tcp server eof dst=${state.flowKey.dstIp}:${state.flowKey.dstPort}")
                            packetWriter.writeServerFin(state)
                        }

                        return@submit
                    }

                    val payload = buffer.copyOf(read)

                    synchronized(state) {
                        state.lastActivityAtMs = System.currentTimeMillis()

                        if (state.tcpState == TcpState.CLOSED || state.tcpState == TcpState.SYN_RECEIVED || state.serverFinSent) {
                            return@synchronized
                        }

                        HyLog.write(context, "tcp server payload dst=${state.flowKey.dstIp}:${state.flowKey.dstPort} bytes=$read")
                        packetWriter.writeServerData(state, payload)
                    }
                }
            } catch (t: Throwable) {
                HyLog.write(context, "tcp reader error dst=${state.flowKey.dstIp}:${state.flowKey.dstPort} error=${t.message ?: "unknown"}")
                val shouldRst = synchronized(state) {
                    state.tcpState != TcpState.CLOSED
                }
                if (shouldRst) {
                    packetWriter.writeRst(state)
                    closeSession(state)
                }
            }
        }

        sessionReaders[state.sessionKey] = future
    }

    private fun sweepSessions() {
        val now = System.currentTimeMillis()
        val snapshot = sessions.values.toList()

        for (state in snapshot) {
            var shouldClose = false
            var reason = ""

            synchronized(state) {
                if (state.tcpState == TcpState.CLOSED) {
                    shouldClose = true
                    reason = "already_closed"
                } else if (state.tcpState == TcpState.SYN_RECEIVED && now - state.createdAtMs > synReceivedTimeoutMs) {
                    shouldClose = true
                    reason = "syn_timeout"
                } else if (state.tcpState == TcpState.LAST_ACK && now - state.lastActivityAtMs > lastAckTimeoutMs) {
                    shouldClose = true
                    reason = "last_ack_timeout"
                } else if (now - state.lastActivityAtMs > idleTimeoutMs) {
                    shouldClose = true
                    reason = "idle_timeout"
                }
            }

            if (shouldClose) {
                HyLog.write(context, "tcp sweep close dst=${state.flowKey.dstIp}:${state.flowKey.dstPort} reason=$reason")
                closeSession(state)
            }
        }
    }

    private fun closeSession(state: TcpSessionState) {
        synchronized(state) {
            closeSessionLocked(state)
        }
    }

    private fun closeSessionLocked(state: TcpSessionState) {
        if (state.tcpState == TcpState.CLOSED) {
            return
        }

        HyLog.write(context, "tcp closeSession dst=${state.flowKey.dstIp}:${state.flowKey.dstPort}")

        state.tcpState = TcpState.CLOSED

        try {
            state.channel.close()
        } catch (_: Throwable) {
        }

        natTable.remove(state.flowKey)
        sessions.remove(state.sessionKey)

        val future = sessionReaders.remove(state.sessionKey)
        if (future != null && !future.isDone) {
            try {
                future.cancel(true)
            } catch (_: Throwable) {
            }
        }

        stats.setActiveTcpSessions(sessions.size)
    }
}

data class TcpSessionState(
    val sessionKey: SessionKey,
    val flowKey: FlowKey,
    var clientSeq: Long,
    var clientAck: Long,
    var serverSeq: Long,
    var serverAck: Long,
    var tcpState: TcpState,
    val channel: SocksTcpChannel,
    val createdAtMs: Long,
    var lastActivityAtMs: Long,
    var serverFinSent: Boolean = false
)

enum class TcpState {
    SYN_RECEIVED,
    ESTABLISHED,
    CLOSE_WAIT,
    LAST_ACK,
    CLOSED
}