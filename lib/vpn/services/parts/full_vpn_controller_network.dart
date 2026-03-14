part of '../full_vpn_backend.dart';

extension _FullVpnControllerNetwork on FullVpnController {
  Future<void> _refreshMeImpl() async {
    if (_token.isEmpty) return;

    try {
      final res = await http.get(
        Uri.parse("$apiBase/me"),
        headers: {"authorization": "Bearer $_token"},
      );

      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        _me = (j["user"] as Map?)?.cast<String, dynamic>();
        await _syncAccountEntitlementToLocalPro();
        _status = "";
        notifyListeners();
        return;
      }

      if (res.statusCode == 401) {
        await _clearSession();
        _status = "Session expired. Sign in again.";
        notifyListeners();
        return;
      }

      _status = "Failed to load account (${res.statusCode}).";
      _net("GET $apiBase/me status=${res.statusCode} bodyLen=${res.body.length}");
      notifyListeners();
    } catch (e) {
      _net("GET $apiBase/me exception=$e");
      _status = "Failed to load account ($e).";
      notifyListeners();
    }
  }

  Future<void> fetchServerStatus() async {
    if (_token.isEmpty) return;

    try {
      final res = await http.get(
        Uri.parse("$apiBase/vpn/servers"),
        headers: {"authorization": "Bearer $_token"},
      );

      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        final list = (j as Map?)?["servers"];
        if (list is List) {
          final next = <String, dynamic>{};
          for (final item in list) {
            if (item is! Map) continue;
            final region = (item["region"] ?? "").toString().trim().toLowerCase();
            if (region.isEmpty) continue;

            next[region] = {
              "connectedNow": item["connectedNow"],
              "cap": item["cap"],
              "lastSeenAt": item["lastSeenAt"],
              "vpsName": item["vpsName"],
            };
          }
          _serverStatusByRegion = next;
          _serverStatusEverLoaded = true;
          notifyListeners();
        }
        return;
      }

      if (res.statusCode == 401) {
        await _clearSession();
        notifyListeners();
        return;
      }

      _net("GET $apiBase/vpn/servers status=${res.statusCode} bodyLen=${res.body.length}");
    } catch (e) {
      _net("GET $apiBase/vpn/servers exception=$e");
    }
  }

  Future<void> refreshLocation({bool force = false}) async {
    final hasAuth = _token.isNotEmpty;
    final anonymousDeviceKey = hasAuth ? "" : await _getOrCreateAnonymousDeviceKey();

    if (!hasAuth && anonymousDeviceKey.isEmpty) return;

    final now = DateTime.now();
    if (!force && _locFetchedAt != null) {
      final age = now.difference(_locFetchedAt!);
      if (age.inSeconds < 10) return;
    }

    try {
      final uri = hasAuth
          ? Uri.parse("$apiBase/vpn/my-ip")
          : Uri.parse("$apiBase/vpn/my-ip").replace(
        queryParameters: {
          "anonymousDeviceKey": anonymousDeviceKey,
        },
      );

      final headers = <String, String>{};
      if (hasAuth) {
        headers["authorization"] = "Bearer $_token";
      }

      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        _loc = j;
        _locFetchedAt = DateTime.now();

        final a = locLat();
        final b = locLon();
        if (a != null && b != null) {
          _lastLat = a;
          _lastLon = b;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble(FullVpnController.kLastLat, a);
          await prefs.setDouble(FullVpnController.kLastLon, b);
        }

        notifyListeners();
        return;
      }

      if (res.statusCode == 401 && hasAuth) {
        await _clearSession();
        _status = "Session expired. Sign in again.";
        notifyListeners();
      }
    } catch (e) {
      _net("GET $apiBase/vpn/my-ip exception=$e");
    }
  }

  Future<void> _fetchUsageImpl({bool showSync = true}) async {
    final hasAuth = _token.isNotEmpty;
    final anonymousDeviceKey = hasAuth ? "" : await _getOrCreateAnonymousDeviceKey();

    if (!hasAuth && anonymousDeviceKey.isEmpty) return;

    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    bool asBool(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == "true";
      if (v is num) return v != 0;
      return false;
    }

    final prevSync = _usageSyncing;
    if (showSync && !_usageSyncing) {
      _usageSyncing = true;
      notifyListeners();
    }

    try {
      final uri = hasAuth
          ? Uri.parse("$apiBase/vpn/usage")
          : Uri.parse("$apiBase/vpn/usage").replace(
        queryParameters: {
          "anonymousDeviceKey": anonymousDeviceKey,
        },
      );

      final headers = <String, String>{};
      if (hasAuth) {
        headers["authorization"] = "Bearer $_token";
      }

      final res = await http.get(uri, headers: headers);

      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        final nextUsed = asInt((j as Map?)?["usedBytes"]);
        final nextLimit = asInt((j as Map?)?["limitBytes"]);
        final nextUnlimited = asBool((j as Map?)?["unlimited"]);

        final firstLoad = !_usageEverLoaded;

        final changed = nextUsed != _usedBytes ||
            nextLimit != _limitBytes ||
            nextUnlimited != _unlimited;

        _usedBytes = nextUsed;
        _limitBytes = nextLimit;
        _unlimited = nextUnlimited;

        _usageEverLoaded = true;
        _usageSyncing = false;

        if (firstLoad || changed || prevSync != _usageSyncing) {
          notifyListeners();
        }
        return;
      }

      if (res.statusCode == 401 && hasAuth) {
        await _clearSession();
        _usageSyncing = false;
        notifyListeners();
        return;
      }

      _net("GET $apiBase/vpn/usage status=${res.statusCode} bodyLen=${res.body.length}");
      if (_usageSyncing) {
        _usageSyncing = false;
        notifyListeners();
      }
    } catch (e) {
      _net("GET $apiBase/vpn/usage exception=$e");
      if (_usageSyncing) {
        _usageSyncing = false;
        notifyListeners();
      }
    }
  }

  Future<Map<String, dynamic>?> _provision(
      String deviceId,
      String deviceName,
      String publicKeyB64, {
        required String region,
        String anonymousDeviceKey = "",
      }) async {
    try {
      final headers = <String, String>{
        "content-type": "application/json; charset=utf-8",
      };
      if (_token.isNotEmpty) {
        headers["authorization"] = "Bearer $_token";
      }

      final body = <String, dynamic>{
        "deviceName": deviceName,
        "publicKey": publicKeyB64,
        "region": region,
      };

      if (_token.isNotEmpty) {
        body["deviceId"] = deviceId;
      } else {
        body["anonymousDeviceKey"] = anonymousDeviceKey;
      }

      final res = await http
          .post(
        Uri.parse("$apiBase/vpn/provision"),
        headers: headers,
        body: jsonEncode(body),
      )
          .timeout(const Duration(seconds: 8));
      _net("POST $apiBase/vpn/provision status=${res.statusCode} bodyLen=${res.body.length}");

      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        return (j["peer"] as Map?)?.cast<String, dynamic>();
      }

      if (res.statusCode == 401 && _token.isNotEmpty) {
        await _clearSession();
        _status = "Session expired. Sign in again.";
        notifyListeners();
        return null;
      }

      if (res.statusCode == 403) {
        _status = _token.isEmpty
            ? "Trial limit reached. Sign in or upgrade to continue."
            : "Your plan is not allowed to use Full VPN.";
        notifyListeners();
        return null;
      }

      final bodyText = res.body.trim();
      _status = bodyText.isEmpty
          ? "Provision failed (${res.statusCode})."
          : "Provision failed (${res.statusCode}): $bodyText";
      notifyListeners();
      return null;
    } on TimeoutException {
      _status = "Provision timed out. Try again.";
      notifyListeners();
      return null;
    } catch (e) {
      _net("POST $apiBase/vpn/provision exception=$e");
      _status = "Provision error ($e).";
      notifyListeners();
      return null;
    }
  }
}