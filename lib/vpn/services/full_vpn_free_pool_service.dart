import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FullVpnFreePoolService {
  static const String kFreePoolKey = "cs_vpn_free_pool";
  static const String kFreePoolFetchedAtKey = "cs_vpn_free_pool_fetched_at";

  final String apiBase;

  const FullVpnFreePoolService({
    required this.apiBase,
  });

  Future<String> getCachedPool() async {
    final prefs = await SharedPreferences.getInstance();
    final value = (prefs.getString(kFreePoolKey) ?? "").trim().toLowerCase();
    if (value == "de" || value == "us" || value == "sg") return value;
    return "";
  }

  Future<void> clearCachedPool() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kFreePoolKey);
    await prefs.remove(kFreePoolFetchedAtKey);
  }

  Future<String> refreshPool() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(kFreePoolKey);
    await prefs.remove(kFreePoolFetchedAtKey);

    try {
      final res = await http.get(
        Uri.parse("$apiBase/vpn/free-pool"),
        headers: {
          "accept": "application/json",
        },
      );

      if (res.statusCode != 200) return "";

      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) return "";

      final pool = (data["pool"] ?? "").toString().trim().toLowerCase();
      if (pool != "de" && pool != "us" && pool != "sg") return "";

      await prefs.setString(kFreePoolKey, pool);
      await prefs.setInt(
        kFreePoolFetchedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      return pool;
    } catch (_) {
      return "";
    }
  }
}