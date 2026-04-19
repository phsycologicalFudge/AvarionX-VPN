part of '../full_vpn_backend.dart';

extension _FullVpnControllerStorage on FullVpnController {
  Future<void> _loadLastLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final a = prefs.getDouble(FullVpnController.kLastLat);
    final b = prefs.getDouble(FullVpnController.kLastLon);
    _lastLat = a;
    _lastLon = b;
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(FullVpnController.kAuthToken) ?? "";
    if (t != _token) {
      _token = t;
      notifyListeners();
    }
  }

  Future<void> _saveToken(String t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(FullVpnController.kAuthToken, t);
    _token = t;
    notifyListeners();
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(FullVpnController.kAuthToken);
    await prefs.remove(FullVpnController.kDnsBlocklistsJson);
    await prefs.remove(FullVpnController.kWgConfigLast);

    await PurchaseService.clearServerAccountEntitlement();

    _serverStatusTimer?.cancel();
    _serverStatusTimer = null;
    _serverStatusByRegion = {};
    _serverStatusEverLoaded = false;

    _token = "";
    _me = null;
    _connected = false;
    _usedBytes = 0;
    _limitBytes = 0;
    _unlimited = false;
    _usageSyncing = false;
    _usageEverLoaded = false;

    notifyListeners();
  }

  Future<void> _loadBlocklists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(FullVpnController.kDnsBlocklistsJson) ?? "";
    if (raw.isEmpty) return;

    try {
      final j = jsonDecode(raw);
      if (j is! Map) return;

      for (final k in blocklists.keys) {
        final v = j[k];
        if (v is bool) {
          blocklists[k] = v;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadSelectedServer() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(FullVpnController.kSelectedServerId) ?? "";
    if (saved.isEmpty) return;
    final ok = servers.any((s) => s.id == saved);
    if (!ok) return;
    _selectedServerId = saved;
    notifyListeners();
  }

  Future<void> _loadVpnTransport() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(FullVpnController.kVpnTransport) ?? "").trim().toLowerCase();
    if (saved == "amnezia" || saved == "wireguard" || saved == "hysteria") {
      _vpnTransport = saved;
      notifyListeners();
    }
  }

  Future<void> _setVpnTransportImpl(String value) async {
    final next = value.trim().toLowerCase();
    if (next != "wireguard" && next != "amnezia" && next != "hysteria") return;

    if (_selectedServerIsAwg && next != "amnezia") {
      return;
    }

    if (_selectedServerIsHysteria && next != "hysteria") {
      return;
    }

    if (next == _vpnTransport) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(FullVpnController.kVpnTransport, next);
    _vpnTransport = next;
    notifyListeners();
  }

  Future<void> _persistSelectedServer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(FullVpnController.kSelectedServerId, _selectedServerId);
  }

  Future<void> _setGlobalModeFull() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(FullVpnController.kVpnMode, "full");
    await prefs.setBool("protectionEnabled", true);
    await prefs.setBool("networkProtectionEnabled", false);
    await prefs.setString("networkProtectionMode", "full");
  }

  Future<void> _setGlobalModeOff() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(FullVpnController.kVpnMode, "off");
    await prefs.setBool("networkProtectionEnabled", false);
    await prefs.setString("networkProtectionMode", "off");
  }

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(FullVpnController.kDeviceId) ?? "";
    if (existing.isNotEmpty) return existing;

    final now = DateTime.now().millisecondsSinceEpoch;
    final r = base64Url.encode(List<int>.generate(24, (i) => (now + i * 997) & 0xff));
    final id = "android_$r";
    await prefs.setString(FullVpnController.kDeviceId, id);
    return id;
  }

  String _randomOpaqueId() {
    final r = Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll("=", "");
  }

  Future<String> _getOrCreateAnonymousDeviceKey() async {
    try {
      const path = "/storage/emulated/0/Documents/avarionx/deviceKey/devicekey.txt";
      final file = File(path);

      if (await file.exists()) {
        final existing = (await file.readAsString()).trim();
        if (existing.isNotEmpty) return existing;
      }

      final created = _randomOpaqueId();
      await file.parent.create(recursive: true);
      await file.writeAsString(created, flush: true);

      final saved = (await file.readAsString()).trim();
      if (saved.isNotEmpty) return saved;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final existing = (prefs.getString(FullVpnController.kAnonymousDeviceKeyFallback) ?? "").trim();
    if (existing.isNotEmpty) return existing;

    final created = _randomOpaqueId();
    await prefs.setString(FullVpnController.kAnonymousDeviceKeyFallback, created);
    return created;
  }

  Future<Map<String, String>> _getOrCreateKeypair() async {
    final prefs = await SharedPreferences.getInstance();
    final priv = prefs.getString(FullVpnController.kWgPriv) ?? "";
    final pub = prefs.getString(FullVpnController.kWgPub) ?? "";

    if (priv.isNotEmpty && pub.isNotEmpty) {
      return {"private": priv, "public": pub};
    }

    final algo = X25519();
    final kp = await algo.newKeyPair();
    final pubKey = await kp.extractPublicKey();
    final privBytes = await kp.extractPrivateKeyBytes();

    final privB64 = base64Encode(privBytes);
    final pubB64 = base64Encode(pubKey.bytes);

    await prefs.setString(FullVpnController.kWgPriv, privB64);
    await prefs.setString(FullVpnController.kWgPub, pubB64);

    return {"private": privB64, "public": pubB64};
  }

  Future<void> _syncAccountEntitlementToLocalPro() async {
    final rawExpiry = _me?["planExpiresAt"];
    final planExpiresAt = rawExpiry is num
        ? rawExpiry.toInt()
        : int.tryParse((rawExpiry ?? "").toString());

    await PurchaseService.applyServerAccountEntitlement(
      signedIn: _token.isNotEmpty && _me != null,
      plan: (_me?["plan"] ?? "").toString(),
      planExpiresAt: planExpiresAt,
    );
  }
}