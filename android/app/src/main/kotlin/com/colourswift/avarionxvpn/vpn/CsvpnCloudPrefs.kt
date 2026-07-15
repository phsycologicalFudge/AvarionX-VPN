package com.colourswift.avarionxvpn.vpn

import android.content.Context
import android.util.Base64
import org.json.JSONObject

object CsvpnCloudPrefs {

    private const val PREFS = "cs_dns_cloud"
    private const val PREF_CLOUD_ENABLED_LISTS = "enabled_lists_json"
    private const val PREF_CLOUD_RESOLVER = "resolver"
    private const val PREF_CLOUD_PLAN = "plan"
    private const val PREF_CLOUD_URL = "cloud_url"
    private const val PREF_CLIENT_ID = "client_id"

    private const val DEFAULT_CLOUD_URL = "https://dns.colourswift.com/resolve"

    private fun prefs(ctx: Context): android.content.SharedPreferences {
        return ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    fun cloudUrl(ctx: Context): String {
        val s = prefs(ctx).getString(PREF_CLOUD_URL, null)?.trim().orEmpty()
        return if (s.isNotEmpty()) s else DEFAULT_CLOUD_URL
    }

    fun cloudPlan(ctx: Context): String {
        val s = prefs(ctx).getString(PREF_CLOUD_PLAN, null)?.trim()?.lowercase().orEmpty()
        return if (s == "pro") "pro" else "free"
    }

    fun cloudClientId(ctx: Context): String? {
        val s = prefs(ctx).getString(PREF_CLIENT_ID, null)?.trim().orEmpty()
        return if (s.isNotEmpty()) s else null
    }

    fun cloudResolverIp(ctx: Context): String {
        val s = prefs(ctx).getString(PREF_CLOUD_RESOLVER, null)?.trim().orEmpty()
        return if (s.isNotEmpty()) s else "1.1.1.1"
    }

    fun cloudSettingsB64(ctx: Context): String? {
        val p = prefs(ctx)
        val listsJson = p.getString(PREF_CLOUD_ENABLED_LISTS, null)
        val resolver = p.getString(PREF_CLOUD_RESOLVER, null)

        val obj = JSONObject()

        if (!listsJson.isNullOrBlank()) {
            try {
                obj.put("enabled_lists", org.json.JSONArray(listsJson))
            } catch (_: Exception) {
            }
        }

        val r = resolver?.trim().orEmpty()
        if (r.isNotEmpty()) {
            obj.put("resolver", r)
        }

        if (obj.length() == 0) return null

        val raw = obj.toString().toByteArray(Charsets.UTF_8)
        return Base64.encodeToString(raw, Base64.NO_WRAP)
    }
}
