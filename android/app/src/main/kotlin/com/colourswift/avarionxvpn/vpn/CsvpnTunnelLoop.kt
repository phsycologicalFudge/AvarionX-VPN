package com.colourswift.avarionxvpn.vpn

import android.net.VpnService
import android.os.ParcelFileDescriptor
import com.colourswift.avarionxvpn.AppWifiRules
import com.colourswift.avarionxvpn.CsDnsEvents
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.nio.channels.WritableByteChannel
import java.util.concurrent.Executors
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

object CsvpnTunnelLoop {

    private const val MAX_CONCURRENT_QUERIES = 16

    suspend fun run(
        service: VpnService,
        tun: ParcelFileDescriptor?,
        shouldStop: () -> Boolean,
        fakeDnsIp: String,
        cloudResolve: (ByteArray, String?) -> Pair<ByteArray?, Map<String, Any?>?>
    ) = coroutineScope {
        val fd = tun?.fileDescriptor ?: return@coroutineScope
        val input = FileInputStream(fd).channel
        val output = FileOutputStream(fd).channel
        val buf = ByteBuffer.allocate(65535)

        val ctx = service.applicationContext
        val writeMutex = Mutex()
        val dispatcher = Executors.newFixedThreadPool(MAX_CONCURRENT_QUERIES).asCoroutineDispatcher()

        DnsCache.clear()

        try {
            while (!shouldStop() && coroutineContext.isActive) {
                buf.clear()
                val n = try {
                    input.read(buf)
                } catch (_: Exception) {
                    break
                }

                if (n <= 0) {
                    delay(5)
                    continue
                }

                buf.flip()
                val packet = ByteArray(n)
                buf.get(packet)

                if (!DnsPacketUtils.isIpv4Udp(packet) || !DnsPacketUtils.isDnsToFakeServer(packet, fakeDnsIp)) {
                    continue
                }

                launch(dispatcher) {
                    handleQuery(service, ctx, output, writeMutex, packet, cloudResolve)
                }
            }
        } finally {
            dispatcher.close()
        }
    }

    private suspend fun handleQuery(
        service: VpnService,
        ctx: android.content.Context,
        output: WritableByteChannel,
        writeMutex: Mutex,
        packet: ByteArray,
        cloudResolve: (ByteArray, String?) -> Pair<ByteArray?, Map<String, Any?>?>
    ) {
        try {
            val dnsQuery = DnsPacketUtils.extractDnsPayload(packet) ?: return
            val domain = DnsPacketUtils.extractDomain(packet)

            if (domain != null && domain.equals("dns.colourswift.com", ignoreCase = true)) {
                val reply = resolveUpstream(service, ctx, dnsQuery)
                val payload = reply ?: DnsPacketUtils.buildNxDomain(dnsQuery) ?: return
                writeReply(output, writeMutex, packet, payload)
                return
            }

            if (AppWifiRules.hasActiveWifiBlocks(ctx)) {
                val uid = lookupUidForDnsPacket(packet)
                if (uid != null && AppWifiRules.shouldBlockUidOnWifi(ctx, uid)) {
                    val blockedReply = DnsPacketUtils.buildNxDomain(dnsQuery) ?: return
                    writeReply(output, writeMutex, packet, blockedReply)
                    emitEvent(
                        mapOf(
                            "ts_ms" to System.currentTimeMillis(),
                            "qname" to (domain ?: "unknown"),
                            "blocked" to true,
                            "plan" to CsvpnCloudPrefs.cloudPlan(ctx),
                            "upstream" to null,
                            "latency_ms" to 0,
                            "decision" to mapOf("match" to mapOf("list" to "wifi_app_block", "type" to "app_rule"))
                        )
                    )
                    return
                }
            }

            val cacheKey = DnsCache.key(dnsQuery)
            if (cacheKey != null) {
                val cached = DnsCache.get(cacheKey, dnsQuery)
                if (cached != null) {
                    writeReply(output, writeMutex, packet, cached)
                    CsvpnUsage.bumpUsageCount(ctx)
                    emitEvent(
                        mapOf(
                            "ts_ms" to System.currentTimeMillis(),
                            "qname" to (domain ?: "unknown"),
                            "blocked" to false,
                            "plan" to CsvpnCloudPrefs.cloudPlan(ctx),
                            "upstream" to "cache",
                            "latency_ms" to 0,
                            "decision" to mapOf("match" to null)
                        )
                    )
                    return
                }
            }

            CsvpnUsage.bumpUsageCount(ctx)
            val (dnsReply, meta) = cloudResolve(dnsQuery, domain)
            if (meta != null) emitEvent(meta)

            if (dnsReply != null) {
                if (cacheKey != null) DnsCache.put(cacheKey, dnsReply)
                writeReply(output, writeMutex, packet, dnsReply)
                return
            }

            val upstream = resolveUpstream(service, ctx, dnsQuery)
            val payload = upstream ?: DnsPacketUtils.buildNxDomain(dnsQuery) ?: return
            if (upstream != null && cacheKey != null) DnsCache.put(cacheKey, upstream)
            writeReply(output, writeMutex, packet, payload)
        } catch (_: Exception) {
        }
    }

    private fun resolveUpstream(service: VpnService, ctx: android.content.Context, dnsQuery: ByteArray): ByteArray? {
        var socket: DatagramSocket? = null
        return try {
            socket = DatagramSocket()
            service.protect(socket)
            socket.soTimeout = 3000

            val upstream = InetSocketAddress(CsvpnCloudPrefs.cloudResolverIp(ctx), 53)
            socket.send(DatagramPacket(dnsQuery, dnsQuery.size, upstream))

            val recv = ByteArray(4096)
            val replyPacket = DatagramPacket(recv, recv.size)
            socket.receive(replyPacket)
            replyPacket.data.copyOf(replyPacket.length)
        } catch (_: SocketTimeoutException) {
            null
        } catch (_: Exception) {
            null
        } finally {
            try {
                socket?.close()
            } catch (_: Exception) {
            }
        }
    }

    private suspend fun writeReply(
        output: WritableByteChannel,
        writeMutex: Mutex,
        original: ByteArray,
        dnsReply: ByteArray
    ) {
        val rebuilt = DnsPacketUtils.rebuildDnsReply(original, dnsReply)
        writeMutex.withLock {
            output.write(ByteBuffer.wrap(rebuilt))
        }
    }

    private fun emitEvent(meta: Map<String, Any?>) {
        try {
            CsDnsEvents.emit(meta)
        } catch (_: Exception) {
        }
    }

    private fun lookupUidForDnsPacket(ipv4UdpPacket: ByteArray): Int? {
        val ihl = DnsPacketUtils.ipHeaderLength(ipv4UdpPacket)
        if (ipv4UdpPacket.size < ihl + 8) return null
        val srcPort = ((ipv4UdpPacket[ihl].toInt() and 0xFF) shl 8) or (ipv4UdpPacket[ihl + 1].toInt() and 0xFF)
        if (srcPort <= 0) return null
        return ProcNetUid.lookupUdpUid(srcPort)
    }
}