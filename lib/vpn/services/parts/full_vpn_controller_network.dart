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

  static final RegExp _ipv4Pattern = RegExp(
    r'^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$',
  );

  bool _isValidIpv4(dynamic v) {
    final s = (v ?? "").toString().trim();
    if (s.isEmpty) return false;
    return _ipv4Pattern.hasMatch(s);
  }

  Future<bool> _fetchLocationOnce({
    required Duration timeout,
    String expectedIp = "",
  }) async {
    final hasAuth = _token.isNotEmpty;
    final anonymousDeviceKey = hasAuth ? "" : await _getOrCreateAnonymousDeviceKey();

    if (!hasAuth && anonymousDeviceKey.isEmpty) return false;

    final queryParams = <String, String>{};
    if (!hasAuth) {
      queryParams["anonymousDeviceKey"] = anonymousDeviceKey;
    }
    if (expectedIp.isNotEmpty) {
      queryParams["expectedIp"] = expectedIp;
    }

    final uri = Uri.parse("$apiBase/vpn/my-ip").replace(
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );

    final headers = <String, String>{};
    if (hasAuth) {
      headers["authorization"] = "Bearer $_token";
    }

    try {
      final res = await http.get(uri, headers: headers).timeout(timeout);

      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;

        if (expectedIp.isNotEmpty) {
          if (j["confirmed"] != true) {
            _net("GET $apiBase/vpn/my-ip not_confirmed expectedIp=$expectedIp");
            return false;
          }
          j["ip"] = expectedIp;
        } else if (!_isValidIpv4(j["ip"])) {
          _net("GET $apiBase/vpn/my-ip non_ipv4_ip value=${j["ip"]}");
          return false;
        }

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

        return true;
      }

      if (res.statusCode == 401 && hasAuth) {
        await _clearSession();
        _status = "Session expired. Sign in again.";
        notifyListeners();
        return false;
      }

      _net("GET $apiBase/vpn/my-ip status=${res.statusCode}");
      return false;
    } catch (e) {
      _net("GET $apiBase/vpn/my-ip exception=$e");
      return false;
    }
  }

  Future<void> refreshLocation({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _locFetchedAt != null) {
      final age = now.difference(_locFetchedAt!);
      if (age.inSeconds < 10) return;
    }

    const maxAttempts = 3;
    const attemptTimeout = Duration(milliseconds: 1500);
    const attemptGap = Duration(milliseconds: 500);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final ok = await _fetchLocationOnce(timeout: attemptTimeout, expectedIp: _expectedExitIp);
      if (ok) {
        notifyListeners();
        return;
      }
      if (attempt < maxAttempts) {
        await Future.delayed(attemptGap);
      }
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

}