package com.colourswift.avarionxvpn.vpn

import java.util.concurrent.ConcurrentHashMap

object DnsCache {
    private const val MIN_TTL_SECONDS = 5L
    private const val MAX_TTL_SECONDS = 300L
    private const val MAX_ENTRIES = 4096

    private data class Entry(val reply: ByteArray, val expiresAtMs: Long)

    private val store = ConcurrentHashMap<String, Entry>()

    fun key(query: ByteArray): String? {
        if (query.size < 12) return null
        val qdcount = ((query[4].toInt() and 0xFF) shl 8) or (query[5].toInt() and 0xFF)
        if (qdcount != 1) return null

        var off = 12
        val name = StringBuilder()
        while (off < query.size) {
            val len = query[off].toInt() and 0xFF
            if (len == 0) {
                off += 1
                break
            }
            if ((len and 0xC0) != 0) return null
            if (off + 1 + len > query.size) return null
            for (i in 0 until len) {
                val c = query[off + 1 + i].toInt() and 0xFF
                name.append(if (c in 0x41..0x5A) (c + 0x20).toChar() else c.toChar())
            }
            name.append('.')
            off += 1 + len
        }

        if (off + 4 > query.size) return null
        val qtype = ((query[off].toInt() and 0xFF) shl 8) or (query[off + 1].toInt() and 0xFF)
        val qclass = ((query[off + 2].toInt() and 0xFF) shl 8) or (query[off + 3].toInt() and 0xFF)

        return "$name|$qtype|$qclass"
    }

    fun get(key: String, query: ByteArray): ByteArray? {
        val entry = store[key] ?: return null
        if (System.currentTimeMillis() >= entry.expiresAtMs) {
            store.remove(key)
            return null
        }

        val copy = entry.reply.copyOf()
        val qEnd = questionEnd(query) ?: return null
        if (qEnd > copy.size || qEnd > query.size) return null

        System.arraycopy(query, 0, copy, 0, 2)
        System.arraycopy(query, 12, copy, 12, qEnd - 12)
        return copy
    }

    private fun questionEnd(query: ByteArray): Int? {
        if (query.size < 12) return null
        var off = 12
        while (off < query.size) {
            val len = query[off].toInt() and 0xFF
            if (len == 0) {
                off += 1
                break
            }
            if ((len and 0xC0) != 0) return null
            off += 1 + len
        }
        val end = off + 4
        return if (end <= query.size) end else null
    }

    fun put(key: String, reply: ByteArray) {
        if (reply.size < 12) return

        val rcode = reply[3].toInt() and 0x0F
        if (rcode != 0) return

        val ancount = ((reply[6].toInt() and 0xFF) shl 8) or (reply[7].toInt() and 0xFF)
        if (ancount <= 0) return

        val minTtl = minAnswerTtl(reply, ancount) ?: return
        val ttl = minTtl.coerceIn(MIN_TTL_SECONDS, MAX_TTL_SECONDS)

        if (store.size >= MAX_ENTRIES) sweep()
        if (store.size >= MAX_ENTRIES) return

        store[key] = Entry(reply.copyOf(), System.currentTimeMillis() + ttl * 1000L)
    }

    fun clear() {
        store.clear()
    }

    private fun minAnswerTtl(reply: ByteArray, ancount: Int): Long? {
        var off = skipQuestions(reply) ?: return null
        var min = Long.MAX_VALUE

        for (i in 0 until ancount) {
            off = skipName(reply, off) ?: return null
            if (off + 10 > reply.size) return null

            val ttl = ((reply[off + 4].toLong() and 0xFF) shl 24) or
                    ((reply[off + 5].toLong() and 0xFF) shl 16) or
                    ((reply[off + 6].toLong() and 0xFF) shl 8) or
                    (reply[off + 7].toLong() and 0xFF)

            val rdlength = ((reply[off + 8].toInt() and 0xFF) shl 8) or (reply[off + 9].toInt() and 0xFF)
            if (ttl < min) min = ttl
            off += 10 + rdlength
            if (off > reply.size) return null
        }

        return if (min == Long.MAX_VALUE) null else min
    }

    private fun skipQuestions(reply: ByteArray): Int? {
        val qdcount = ((reply[4].toInt() and 0xFF) shl 8) or (reply[5].toInt() and 0xFF)
        var off = 12
        for (i in 0 until qdcount) {
            off = skipName(reply, off) ?: return null
            off += 4
            if (off > reply.size) return null
        }
        return off
    }

    private fun skipName(reply: ByteArray, start: Int): Int? {
        var off = start
        while (off < reply.size) {
            val len = reply[off].toInt() and 0xFF
            if (len == 0) return off + 1
            if ((len and 0xC0) == 0xC0) return off + 2
            off += 1 + len
        }
        return null
    }

    private fun sweep() {
        val now = System.currentTimeMillis()
        val it = store.entries.iterator()
        while (it.hasNext()) {
            if (now >= it.next().value.expiresAtMs) it.remove()
        }
    }
}