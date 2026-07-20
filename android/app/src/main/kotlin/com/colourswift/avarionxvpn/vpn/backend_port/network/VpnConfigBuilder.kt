package com.colourswift.avarionxvpn.vpn.backend_port.network

import org.json.JSONArray
import org.json.JSONObject

object VpnConfigBuilder {

    private const val MTU = 1280
    private const val DEFAULT_HYSTERIA_DNS = "10.8.50.1"

    private val AWG_FIELDS = listOf(
        "S1", "S2", "S3", "S4",
        "H1", "H2", "H3", "H4",
        "Jc", "Jmin", "Jmax",
        "I1", "I2", "I3", "I4", "I5"
    )

    data class HysteriaArgs(
        val server: String,
        val auth: String,
        val sni: String,
        val dns: String
    )

    fun str(json: JSONObject?, key: String): String {
        if (json == null || json.isNull(key)) return ""
        return json.optString(key, "").trim()
    }

    fun strList(json: JSONObject?, key: String): List<String> {
        if (json == null || json.isNull(key)) return emptyList()
        val arr: JSONArray = json.optJSONArray(key) ?: return emptyList()
        val out = ArrayList<String>(arr.length())
        for (i in 0 until arr.length()) {
            if (arr.isNull(i)) continue
            val v = arr.optString(i, "").trim()
            if (v.isNotEmpty()) out.add(v)
        }
        return out
    }

    fun buildHysteriaArgs(peer: JSONObject): HysteriaArgs {
        val endpoint = str(peer, "endpoint")
        val auth = str(peer, "auth")
        val sni = str(peer, "sni")
        val dns = strList(peer, "dns")

        if (endpoint.isEmpty() || auth.isEmpty() || sni.isEmpty()) {
            throw IllegalStateException("Provision returned incomplete Hysteria settings.")
        }

        return HysteriaArgs(
            server = endpoint,
            auth = auth,
            sni = sni,
            dns = dns.firstOrNull() ?: DEFAULT_HYSTERIA_DNS
        )
    }

    fun buildWgConfig(
        privateKeyB64: String,
        address: String,
        serverPublicKeyB64: String,
        endpoint: String,
        allowedIps: List<String>,
        dns: List<String>,
        awg: JSONObject?
    ): String {
        val stealth = asBool(awg, "stealth")
        val stealthPort = asInt(awg, "stealthPort", 443)

        val b = StringBuilder()
        b.appendLine("[Interface]")
        b.appendLine("PrivateKey = $privateKeyB64")
        b.appendLine("Address = ${fixCidr(address)}")
        b.appendLine("MTU = $MTU")
        if (dns.isNotEmpty()) {
            b.appendLine("DNS = ${dns.joinToString(", ")}")
        }

        if (stealth) {
            b.appendLine("CS_Stealth = 1")
            b.appendLine("CS_StealthPort = $stealthPort")
        }

        if (awg != null) {
            for (field in AWG_FIELDS) {
                writeField(b, field, str(awg, field))
            }
        }

        b.appendLine("")
        b.appendLine("[Peer]")
        b.appendLine("PublicKey = $serverPublicKeyB64")
        b.appendLine("Endpoint = $endpoint")
        b.appendLine("AllowedIPs = ${allowedIps.joinToString(", ")}")
        b.appendLine("PersistentKeepalive = 25")
        return b.toString()
    }

    private fun writeField(b: StringBuilder, key: String, value: String) {
        val s = value.trim()
        if (s.isNotEmpty()) {
            b.appendLine("$key = $s")
        }
    }

    private fun fixCidr(address: String): String {
        val parts = address.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        val out = ArrayList<String>(parts.size)
        for (p in parts) {
            when {
                p.contains("/") -> out.add(p)
                p.contains(":") -> out.add("$p/128")
                else -> out.add("$p/32")
            }
        }
        return out.joinToString(", ")
    }

    private fun asBool(json: JSONObject?, key: String): Boolean {
        if (json == null || json.isNull(key)) return false
        val v = json.opt(key) ?: return false
        if (v is Boolean) return v
        if (v is Number) return v.toInt() != 0
        val s = v.toString().trim().lowercase()
        return s == "1" || s == "true" || s == "yes"
    }

    private fun asInt(json: JSONObject?, key: String, fallback: Int): Int {
        if (json == null || json.isNull(key)) return fallback
        val v = json.opt(key) ?: return fallback
        if (v is Number) return v.toInt()
        return v.toString().trim().toIntOrNull() ?: fallback
    }
}
