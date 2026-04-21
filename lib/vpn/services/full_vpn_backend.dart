library full_vpn_controller;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:colourswift_av/vpn/services/sound_controller/vpn_sound_controller.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/purchase_service.dart';
import '../../../services/service_manager.dart';
import 'full_vpn_server_locations.dart';

part 'parts/full_vpn_controller_storage.dart';
part 'parts/full_vpn_controller_network.dart';


class FullVpnController extends ChangeNotifier {
  static const vpnChannel = MethodChannel("cs_vpn_control");

  static const kAuthToken = "cs_auth_token";
  static const kWgPriv = "cs_wg_private_key_b64";
  static const kWgPub = "cs_wg_public_key_b64";
  static const kDeviceId = "cs_device_id";
  static const kVpnMode = "cs_vpn_mode";
  static const kVpnTransport = "cs_vpn_transport";
  static const kDnsBlocklistsJson = "cs_dns_blocklists_json";
  static const kWgConfigLast = "cs_wg_config_last";
  static const kSelectedServerId = "cs_vpn_selected_region";
  static const kLocationsVersion = "cs_vpn_locations_version";
  static const kLocationsJson = "cs_vpn_locations_json";
  static const kLastLat = "cs_vpn_last_lat";
  static const kLastLon = "cs_vpn_last_lon";
  static const kAnonymousDeviceKeyFallback = "cs_anonymous_device_key_fallback";
  static const kShowFlagMarkers = "cs_vpn_show_flag_markers";
  static const int kStandaloneSoftLimitBytes = 10 * 1024 * 1024 * 1024;

  final String apiBase;
  final String loginUrl;
  final String deepLinkPrefix;

  FullVpnController({
    required this.apiBase,
    required this.loginUrl,
    required this.deepLinkPrefix,
  });

  Timer? _usageTimer;
  Timer? _runtimeSyncTimer;
  Timer? _serverStatusTimer;
  Timer? _probeTimer;
  Timer? _statsTimer;
  Timer? _locationsTimer;
  final VpnSoundController soundController = VpnSoundController();

  Map<String, dynamic> _serverStatusByRegion = {};
  bool _serverStatusEverLoaded = false;

  List<FullVpnServerLocation> _servers = [];
  String _locationsVersion = "";
  bool _locationsEverLoaded = false;

  bool _busy = false;
  String _status = "";
  String _token = "";
  Map<String, dynamic>? _me;
  bool _connected = false;
  bool _disposed = false;
  bool _connectingUi = false;
  DateTime? _connectStartedAt;

  bool _showFlagMarkers = false;

  dynamic _loc;
  DateTime? _locFetchedAt;
  DateTime? _connectedAt;

  final List<String> _netLog = [];

  double? _lastLat;
  double? _lastLon;

  int _usedBytes = 0;
  int _limitBytes = 0;
  bool _unlimited = false;

  bool _usageSyncing = false;
  bool _usageEverLoaded = false;

  int _rxBytes = 0;
  int _txBytes = 0;
  DateTime? _lastStatsAt;
  double _downloadSpeedBps = 0;
  double _uploadSpeedBps = 0;

  String _selectedServerId = "de-nuremberg";
  String _vpnTransport = "wireguard";

  final Map<String, bool> blocklists = {
    "ads": true,
    "trackers": true,
    "malware": true,
    "adult": false,
    "gambling": false,
    "social": false,
    "crypto": false,
  };

  int get effectiveUiLimitBytes {
    if (_unlimited) return 0;
    if (_limitBytes <= 0) return kStandaloneSoftLimitBytes;
    return _limitBytes;
  }

  bool get softCapReached {
    if (_unlimited) return false;
    final lim = effectiveUiLimitBytes;
    if (lim <= 0) return false;
    return _usedBytes >= lim;
  }

  bool get busy => _busy;
  String get status => _status;
  String get token => _token;
  Map<String, dynamic>? get me => _me;
  bool get connected => _connected;
  bool get connectingUi => _connectingUi;
  dynamic get loc => _loc;
  int get usedBytes => _usedBytes;
  int get limitBytes => _limitBytes;
  bool get unlimited => _unlimited;
  bool get usageSyncing => _usageSyncing;
  bool get usageEverLoaded => _usageEverLoaded;
  String get selectedServerId => _selectedServerId;
  List<String> get netLog => List.unmodifiable(_netLog);
  double? get lastLat => _lastLat;
  double? get lastLon => _lastLon;
  bool get serverStatusEverLoaded => _serverStatusEverLoaded;
  bool get showFlagMarkers => _showFlagMarkers;
  double get downloadSpeedBps => _downloadSpeedBps;
  double get uploadSpeedBps => _uploadSpeedBps;

  List<FullVpnServerLocation> get servers => _servers;
  bool get locationsEverLoaded => _locationsEverLoaded;

  FullVpnServerLocation get selectedServer {
    if (_servers.isEmpty) {
      return const FullVpnServerLocation(
        id: "",
        label: "",
        countryCode: "",
        point: LatLng(0, 0),
      );
    }
    return _servers.firstWhere(
          (s) => s.id == _selectedServerId,
      orElse: () => _servers.first,
    );
  }

  bool get hasPremiumAccess {
    final serverPlan = (_me?["plan"] ?? "").toString().trim().toLowerCase();
    return PurchaseService.isPro || serverPlan == "pro";
  }

  FullVpnServerLocation get _defaultFreeServer {
    if (_servers.isEmpty) return selectedServer;
    return _servers.firstWhere(
          (s) {
        final id = s.id.toLowerCase();
        return !id.startsWith("awg-") && !id.startsWith("hy-");
      },
      orElse: () => _servers.first,
    );
  }

  FullVpnServerLocation get effectiveConnectServer {
    if (!hasPremiumAccess) {
      final id = _selectedServerId.toLowerCase();
      if (id.startsWith("awg-") || id.startsWith("hy-")) {
        return _defaultFreeServer;
      }
    }
    return selectedServer;
  }

  String get selectedServerCountryCode => selectedServer.countryCode;

  String get selectedRegionKey {
    return effectiveConnectServer.id.toLowerCase();
  }

  String get _selectedProvisionRegion {
    if (!hasPremiumAccess) {
      return "de";
    }
    return effectiveConnectServer.id.toLowerCase();
  }

  int? get selectedServerConnectedNow {
    final s = _serverStatusByRegion[selectedRegionKey];
    if (s is! Map) return null;
    final v = s["connectedNow"];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  int? get selectedServerCap {
    final s = _serverStatusByRegion[selectedRegionKey];
    if (s is! Map) return null;
    final v = s["cap"];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  bool get vpnLocationFresh {
    if (!_connected) return false;
    if (_connectedAt == null || _locFetchedAt == null) return false;
    return _locFetchedAt!.isAfter(_connectedAt!.add(const Duration(milliseconds: 900)));
  }

  String get uiCountry {
    if (!_connected) return "";
    if (vpnLocationFresh) {
      final l = _loc;
      if (l is Map) {
        final ip = (l["ip"] ?? "").toString();
        final c = (l["country"] ?? "").toString();
        if (ip.isNotEmpty && c.isNotEmpty) return c;
      } else {
        final d = l as dynamic;
        final ip = d == null ? "" : ((d.ip)?.toString() ?? "");
        final c = d == null ? "" : ((d.country)?.toString() ?? "");
        if (ip.isNotEmpty && c.isNotEmpty) return c;
      }
    }
    return selectedServerCountryCode;
  }

  String get uiCity {
    if (!_connected) return "";
    if (!vpnLocationFresh) return "";
    final l = _loc;
    if (l is Map) {
      final ip = (l["ip"] ?? "").toString();
      if (ip.isEmpty) return "";
      return (l["city"] ?? "").toString();
    }
    final d = l as dynamic;
    final ip = d == null ? "" : ((d.ip)?.toString() ?? "");
    if (ip.isEmpty) return "";
    return d == null ? "" : ((d.city)?.toString() ?? "");
  }

  String get uiIp {
    if (!_connected) return "";
    if (!vpnLocationFresh) return "";
    final l = _loc;
    if (l is Map) {
      return (l["ip"] ?? "").toString();
    }
    final d = l as dynamic;
    return d == null ? "" : ((d.ip)?.toString() ?? "");
  }

  bool get _selectedServerIsAwg {
    final id = effectiveConnectServer.id.toLowerCase();
    final parts = id.split("-").where((e) => e.isNotEmpty).toList();
    return parts.isNotEmpty && parts.first == "awg";
  }

  bool get _selectedServerIsHysteria {
    final id = effectiveConnectServer.id.toLowerCase();
    final parts = id.split("-").where((e) => e.isNotEmpty).toList();
    return parts.isNotEmpty && parts.first == "hy";
  }

  String get vpnTransport {
    if (!hasPremiumAccess) return "wireguard";
    if (_selectedServerIsHysteria) return "hysteria";
    if (_selectedServerIsAwg) return "amnezia";
    return _vpnTransport;
  }

  bool get isAmneziaTransport => vpnTransport == "amnezia";
  bool get isHysteriaTransport => vpnTransport == "hysteria";

  String get transportLabel {
    if (isHysteriaTransport) return "Hysteria";
    if (isAmneziaTransport) return "AmneziaWG";
    return "WireGuard";
  }

  void _net(String msg) {
    final line = "${DateTime.now().toIso8601String()} $msg";
    _netLog.add(line);
    if (_netLog.length > 250) _netLog.removeAt(0);
    if (kDebugMode) {
      print(line);
    }
  }

  Future<void> startLoginInBrowser() async {
    final u = Uri.parse(loginUrl);
    final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
    if (!ok) {
      _status = "Failed to open browser.";
      notifyListeners();
    }
  }

  Future<void> refreshMe() => _refreshMeImpl();

  Future<void> fetchUsage({bool showSync = true}) =>
      _fetchUsageImpl(showSync: showSync);

  Future<void> fetchLocations() => _fetchLocationsImpl();

  Future<void> setVpnTransport(String value) => _setVpnTransportImpl(value);

  Future<void> setShowFlagMarkers(bool value) async {
    _showFlagMarkers = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kShowFlagMarkers, value);
    notifyListeners();
  }

  Future<void> init() async {
    await soundController.init();
    await _loadCachedLocations();
    await _loadBlocklists();
    await _loadSelectedServer();
    await _loadVpnTransport();
    _showFlagMarkers = (await SharedPreferences.getInstance()).getBool(kShowFlagMarkers) ?? false;
    await _loadToken();
    await _loadLastLocation();
    await _syncWithRuntime();
    _startRuntimeSync();
    unawaited(fetchLocations());
    _startLocationsPolling();

    if (_token.isEmpty) {
      await PurchaseService.clearServerAccountEntitlement();
      _me = null;
      _serverStatusTimer?.cancel();
      _serverStatusTimer = null;
      _serverStatusByRegion = {};
      _serverStatusEverLoaded = false;
      await fetchUsage(showSync: true);
      if (_connected) {
        await refreshLocation(force: true);
      }
      _startUsagePolling();
      notifyListeners();
      return;
    }

    await refreshMe();
    await refreshLocation(force: true);
    await fetchServerStatus();
    await fetchUsage(showSync: true);
    await fetchServerStatus();
    _startUsagePolling();
    _startServerStatusPolling();
  }

  Future<void> onResumed() async {
    await _syncWithRuntime();
    await _loadToken();
    unawaited(fetchLocations());
    if (_locationsTimer == null) _startLocationsPolling();

    if (_token.isEmpty) {
      await PurchaseService.clearServerAccountEntitlement();
      _me = null;
      await fetchUsage(showSync: !_usageEverLoaded);
      if (_connected) {
        await refreshLocation(force: false);
      }
      if (_usageTimer == null) _startUsagePolling();
      notifyListeners();
      return;
    }

    await refreshMe();
    await refreshLocation(force: false);
    await fetchUsage(showSync: !_usageEverLoaded);
    await fetchServerStatus();
    if (_usageTimer == null) _startUsagePolling();
    if (_serverStatusTimer == null) _startServerStatusPolling();

    if (_connected) {
      unawaited(_probeHttps("https://www.royalroad.com"));
      unawaited(_probeHttps("https://api.ipify.org"));
    }
  }

  Future<void> setTokenFromLogin(String t) async {
    await _saveToken(t);
    await refreshMe();
    await _syncAccountEntitlementToLocalPro();
    await refreshLocation(force: true);
    await fetchUsage(showSync: true);
    await fetchServerStatus();
    _startUsagePolling();
    _startServerStatusPolling();
    _status = "Signed in.";
    notifyListeners();
  }

  Future<void> signOut() async {
    await disconnect();
    await _clearSession();
    await fetchUsage(showSync: true);
    _startUsagePolling();
    _status = "Signed out.";
    notifyListeners();
  }

  Future<void> connect() async {
    if (softCapReached) {
      _status = _token.isEmpty
          ? "Trial limit reached. Sign in or upgrade to continue using Full VPN."
          : "Free limit reached. Upgrade to continue using Full VPN.";
      notifyListeners();
      return;
    }

    await _runBusy(() async {
      await _connectInternal();
    });
  }

  Future<void> disconnect() async {
    await _runBusy(() async {
      _connectingUi = false;
      _connectedAt = null;
      _status = "Disconnecting...";
      notifyListeners();

      try {
        _net("disconnect invoking ${_stopMethodName()}");
        await vpnChannel.invokeMethod(_stopMethodName());
      } catch (e) {
        _net("disconnect stop invoke error=$e");
      }

      await _setGlobalModeOff();
      _stopUsagePolling();
      _stopStatsPolling();

      await _syncWithRuntime();
      await refreshLocation(force: true);

      _status = "Disconnected.";
      notifyListeners();
    });
  }

  Future<void> switchServer(FullVpnServerLocation s) async {
    if (_busy) return;

    final wasConnected = _connected;
    final previousServerId = _selectedServerId;

    String previousTransport() {
      final id = previousServerId.toLowerCase();
      final parts = id.split("-").where((e) => e.isNotEmpty).toList();

      if (parts.isNotEmpty && parts.first == "hy") {
        return "hysteria";
      }

      if (parts.isNotEmpty && parts.first == "awg") {
        return "amnezia";
      }

      return _vpnTransport;
    }

    final prevTransport = previousTransport();

    _selectedServerId = s.id;
    _status = "Selected ${s.label}";
    notifyListeners();

    await _persistSelectedServer();
    await _syncWithRuntime();
    await fetchServerStatus();

    if (!wasConnected) return;

    await _runBusy(() async {
      _connectingUi = true;
      _status = "Switching to ${s.label}...";
      notifyListeners();

      try {
        if (prevTransport == "hysteria") {
          _net("switchServer invoking stopHysteria");
          await vpnChannel.invokeMethod("stopHysteria");
        } else if (prevTransport == "amnezia") {
          _net("switchServer invoking stopAmneziaWireGuard");
          await vpnChannel.invokeMethod("stopAmneziaWireGuard");
        } else {
          _net("switchServer invoking stopWireGuard");
          await vpnChannel.invokeMethod("stopWireGuard");
        }
      } catch (e) {
        _net("switchServer stop invoke error=$e");
      }

      await _setGlobalModeOff();
      await _syncWithRuntime();
      await refreshLocation(force: true);
      await _connectInternal();
    });
  }

  void selectServerPreview(FullVpnServerLocation s) {
    if (_connected || _connectingUi) return;
    if (s.id == _selectedServerId) return;

    _selectedServerId = s.id;
    _status = "Selected ${s.label}";
    notifyListeners();
  }

  Future<void> persistBlocklists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kDnsBlocklistsJson, jsonEncode(blocklists));
  }

  Future<void> saveDnsSettings() async {
    if (_token.isEmpty) {
      _status = "Sign in first.";
      notifyListeners();
      return;
    }

    await _runBusy(() async {
      final prefs = await SharedPreferences.getInstance();
      final pub = prefs.getString(kWgPub) ?? "";

      if (pub.isEmpty) {
        _status = "VPN key not found.";
        notifyListeners();
        return;
      }

      final enabled = blocklists.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      final settingsJson = jsonEncode({
        "enabled_lists": enabled,
      });

      final settingsB64 = base64Encode(utf8.encode(settingsJson));

      final res = await http.post(
        Uri.parse("$apiBase/vpn/update-dns"),
        headers: {
          "authorization": "Bearer $_token",
          "content-type": "application/json",
        },
        body: jsonEncode({
          "publicKey": pub,
          "settingsB64": settingsB64,
        }),
      );

      if (res.statusCode == 200) {
        await persistBlocklists();
        _status = "DNS settings updated.";
        notifyListeners();
      } else if (res.statusCode == 401) {
        await _clearSession();
        _status = "Session expired.";
        notifyListeners();
      } else {
        _status = "Failed (${res.statusCode}).";
        notifyListeners();
      }
    });
  }

  String formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const units = ["B", "KB", "MB", "GB", "TB"];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return "${size.toStringAsFixed(2)} ${units[unit]}";
  }

  String formatSpeed(double bps) {
    if (bps < 1024) return "${bps.toStringAsFixed(0)} B/s";
    if (bps < 1024 * 1024) return "${(bps / 1024).toStringAsFixed(1)} KB/s";
    return "${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s";
  }

  double? locLat() {
    final l = _loc;
    if (l == null) return null;
    final d = l as dynamic;

    dynamic tryRead(dynamic Function() fn) {
      try {
        return fn();
      } catch (_) {
        return null;
      }
    }

    final a = tryRead(() => d.lat);
    if (a is num) return a.toDouble();

    final b = tryRead(() => d.latitude);
    if (b is num) return b.toDouble();

    final c = tryRead(() => d.locationLat);
    if (c is num) return c.toDouble();

    if (d is Map) {
      final v = d["lat"] ?? d["latitude"] ?? d["locationLat"];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
    }

    return null;
  }

  double? locLon() {
    final l = _loc;
    if (l == null) return null;
    final d = l as dynamic;

    dynamic tryRead(dynamic Function() fn) {
      try {
        return fn();
      } catch (_) {
        return null;
      }
    }

    final a = tryRead(() => d.lon);
    if (a is num) return a.toDouble();

    final b = tryRead(() => d.lng);
    if (b is num) return b.toDouble();

    final c = tryRead(() => d.longitude);
    if (c is num) return c.toDouble();

    final e = tryRead(() => d.locationLon);
    if (e is num) return e.toDouble();

    if (d is Map) {
      final v = d["lon"] ?? d["lng"] ?? d["longitude"] ?? d["locationLon"];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
    }

    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _usageTimer?.cancel();
    _runtimeSyncTimer?.cancel();
    _serverStatusTimer?.cancel();
    _probeTimer?.cancel();
    _statsTimer?.cancel();
    _locationsTimer?.cancel();
    soundController.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  Future<void> _fetchLocationsImpl() async {
    if (_disposed) return;
    try {
      final res = await http
          .get(Uri.parse("$apiBase/vpn/locations"))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final version = (j["version"] ?? "").toString();
      final list = j["locations"];
      if (list is! List) return;

      if (version.isNotEmpty && version == _locationsVersion) return;

      final parsed = <FullVpnServerLocation>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final loc = FullVpnServerLocation.fromJson(item);
        if (loc.id.isEmpty) continue;
        parsed.add(loc);
      }

      if (parsed.isEmpty) return;

      _servers = parsed;
      _locationsVersion = version;
      _locationsEverLoaded = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kLocationsVersion, version);
      await prefs.setString(kLocationsJson, jsonEncode(list));

      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadCachedLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(kLocationsJson);
      if (cached == null || cached.isEmpty) return;
      final list = jsonDecode(cached);
      if (list is! List) return;
      final parsed = <FullVpnServerLocation>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final loc = FullVpnServerLocation.fromJson(item);
        if (loc.id.isEmpty) continue;
        parsed.add(loc);
      }
      if (parsed.isEmpty) return;
      _servers = parsed;
      _locationsVersion = prefs.getString(kLocationsVersion) ?? "";
      _locationsEverLoaded = true;
    } catch (_) {}
  }

  void _startLocationsPolling() {
    _locationsTimer?.cancel();
    _locationsTimer = Timer.periodic(
      const Duration(hours: 1),
          (_) async {
        if (_disposed) return;
        await fetchLocations();
      },
    );
  }

  void _stopLocationsPolling() {
    _locationsTimer?.cancel();
    _locationsTimer = null;
  }

  Future<void> _connectInternal() async {
    if (_disposed) return;

    _connectingUi = true;
    _connectStartedAt = DateTime.now();
    _status = "Connecting...";
    notifyListeners();

    final notifStatus = await Permission.notification.status;
    if (_disposed) return;

    if (!notifStatus.isGranted) {
      final notif = await Permission.notification.request();
      if (_disposed) return;

      if (!notif.isGranted) {
        _connectingUi = false;
        _status = "Notifications permission required.";
        notifyListeners();
        return;
      }
    }

    final ok = await _requestVpnPermission();
    if (_disposed) return;

    if (!ok) {
      _connectingUi = false;
      _status = "VPN permission not granted.";
      notifyListeners();
      return;
    }

    final conflict = await _isAnotherVpnActive();
    if (_disposed) return;

    if (conflict) {
      _connectingUi = false;
      _status = "Another VPN is active. Disable it first.";
      notifyListeners();
      return;
    }

    if (_token.isNotEmpty) {
      await refreshMe();
      if (_disposed) return;
    }

    final deviceId = _token.isNotEmpty ? await _getOrCreateDeviceId() : "";
    if (_disposed) return;

    final anonymousDeviceKey = _token.isEmpty ? await _getOrCreateAnonymousDeviceKey() : "";
    if (_disposed) return;

    if (_token.isEmpty && anonymousDeviceKey.isEmpty) {
      _connectingUi = false;
      _status = "Failed to create device key.";
      notifyListeners();
      return;
    }

    final kp = await _getOrCreateKeypair();
    if (_disposed) return;

    if (!hasPremiumAccess && (_selectedServerIsAwg || _selectedServerIsHysteria)) {
      _net("free_user_forcing_standard_pool selected=$_selectedServerId effective=${effectiveConnectServer.id}");
    }

    final peer = await _provision(
      deviceId,
      "Android",
      kp["public"]!,
      anonymousDeviceKey: anonymousDeviceKey,
      region: _selectedProvisionRegion,
    );

    if (_disposed) return;

    if (peer == null) {
      _connectingUi = false;
      notifyListeners();
      return;
    }

    final endpoint = (peer["endpoint"] ?? "").toString();
    final dns = (peer["dns"] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final assignedIp = (peer["assignedIp"] ?? "").toString();
    final serverPublicKey = (peer["serverPublicKey"] ?? "").toString();
    final allowed = (peer["allowedIps"] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final awg = peer["awg"] is Map ? Map<String, dynamic>.from(peer["awg"] as Map) : null;

    String cfg = "";
    Map<String, dynamic>? hysteriaArgs;

    if (isHysteriaTransport) {
      hysteriaArgs = _buildHysteriaArgs(peer);
    } else {
      if (assignedIp.isEmpty || endpoint.isEmpty || serverPublicKey.isEmpty || allowed.isEmpty) {
        _connectingUi = false;
        _status = "Provision returned incomplete settings.";
        notifyListeners();
        return;
      }

      cfg = _buildWgConfig(
        privateKeyB64: kp["private"]!,
        address: assignedIp,
        serverPublicKeyB64: serverPublicKey,
        endpoint: endpoint,
        allowedIps: allowed,
        dns: dns,
        awg: awg,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kWgConfigLast, cfg);

      if (kDebugMode) {
        final exported = prefs.getString(kWgConfigLast) ?? "";
        print("HAS_AWG_S1=${exported.contains("S1 = ")} HAS_AWG_H1=${exported.contains("H1 = ")} HAS_AWG_JC=${exported.contains("Jc = ")} HAS_STEALTH=${exported.contains("CS_Stealth = 1")} HAS_STEALTH_PORT=${exported.contains("CS_StealthPort = ")}");
        print("=== VPN EXPORT BEGIN ===");
        print(exported);
        print("=== VPN EXPORT END ===");
      }
    }

    if (_disposed) return;

    try {
      await AvServiceManager.stopVpn();
    } catch (_) {}

    try {
      _status = "Starting $transportLabel...";
      notifyListeners();

      final sw = Stopwatch()..start();

      if (isHysteriaTransport) {
        final server = (hysteriaArgs?["server"] ?? "").toString();
        _status = "HY server=$server";
      } else if (isAmneziaTransport) {
        _status = "AWG cfg len=${cfg.length} hasMTU=${cfg.contains("MTU = ")}";
      } else {
        _status = "WG cfg len=${cfg.length} hasMTU=${cfg.contains("MTU = ")}";
      }
      notifyListeners();

      if (isHysteriaTransport) {
        _net("hy_start begin region=${_selectedServerId} server=${(hysteriaArgs?["server"] ?? "").toString()}");
      } else if (isAmneziaTransport) {
        _net("awg_start begin region=${_selectedServerId} endpoint=$endpoint assignedIp=$assignedIp allowed=${allowed.length} dns=${dns.length} cfgLen=${cfg.length}");
      } else {
        _net("wg_start begin region=${_selectedServerId} endpoint=$endpoint assignedIp=$assignedIp allowed=${allowed.length} dns=${dns.length} cfgLen=${cfg.length}");
      }

      final r = await vpnChannel.invokeMethod(
        _startMethodName(),
        isHysteriaTransport
            ? hysteriaArgs
            : {
          "config": cfg,
        },
      );

      sw.stop();

      if (isHysteriaTransport) {
        _net("hy_start ok in ${sw.elapsedMilliseconds}ms result=${r?.toString() ?? ""}");
      } else if (isAmneziaTransport) {
        _net("awg_start ok in ${sw.elapsedMilliseconds}ms result=${r?.toString() ?? ""}");
      } else {
        _net("wg_start ok in ${sw.elapsedMilliseconds}ms result=${r?.toString() ?? ""}");
      }

      if (_disposed) return;

      _status = "$transportLabel start returned in ${sw.elapsedMilliseconds}ms";
      notifyListeners();

      await _setGlobalModeFull();
      if (_disposed) return;

      _status = "Securing connection...";
      notifyListeners();

      await _syncWithRuntime();
      if (_disposed) return;

      if (_connected) {
        await fetchUsage(showSync: !_usageEverLoaded);
        _startUsagePolling();
      }

      final start = DateTime.now();
      while (!_disposed && DateTime.now().difference(start).inMilliseconds < 2500) {
        final running = await _isTunnelRunning();
        if (running) break;
        await Future.delayed(const Duration(milliseconds: 120));
      }

      await refreshLocation(force: true);
      if (_disposed) return;

      unawaited(_probeHttps("https://api.ipify.org"));
      unawaited(_probeHttps("https://www.royalroad.com"));
      unawaited(_probeHttps("https://cloudflare.com"));

      _status = "Securing connection...";
      notifyListeners();

      unawaited(refreshLocation(force: true));
    } on PlatformException catch (e) {
      _connectingUi = false;

      if (isHysteriaTransport) {
        _net("hy_start error $e");
      } else if (isAmneziaTransport) {
        _net("awg_start error $e");
      } else {
        _net("wg_start error $e");
      }

      _status = "Failed to start $transportLabel (${e.code}).";
      notifyListeners();
      await _syncWithRuntime();
    } catch (e) {
      if (_disposed) return;

      _connectingUi = false;

      if (isHysteriaTransport) {
        _net("hy_start error $e");
      } else if (isAmneziaTransport) {
        _net("awg_start error $e");
      } else {
        _net("wg_start error $e");
      }

      _status = "Failed to start $transportLabel ($e).";
      notifyListeners();
      await _syncWithRuntime();
    }
  }

  void _startUsagePolling() {
    _usageTimer?.cancel();
    _usageTimer = Timer.periodic(
      const Duration(seconds: 30),
          (_) async {
        await fetchUsage(showSync: false);
      },
    );
  }

  void _stopUsagePolling() {
    _usageTimer?.cancel();
    _usageTimer = null;
  }

  void _startServerStatusPolling() {
    _serverStatusTimer?.cancel();

    if (_token.isEmpty) return;

    fetchServerStatus();

    _serverStatusTimer = Timer.periodic(
      const Duration(seconds: 8),
          (_) async {
        if (_token.isEmpty || _disposed) return;
        await fetchServerStatus();
      },
    );
  }

  void _startProbePolling() {
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(const Duration(seconds: 12), (_) async {
      if (_disposed || !_connected) return;
      await _probeHttps("https://www.royalroad.com");
    });
  }

  void _stopProbePolling() {
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  Future<void> _pollTunnelStats() async {
    if (!_connected) {
      if (_downloadSpeedBps != 0 || _uploadSpeedBps != 0) {
        _downloadSpeedBps = 0;
        _uploadSpeedBps = 0;
        notifyListeners();
      }
      _lastStatsAt = null;
      return;
    }
    try {
      final result = await vpnChannel.invokeMethod<Map>('getTunnelStats');
      if (result == null) return;
      final rx = (result['rxBytes'] as num?)?.toInt() ?? 0;
      final tx = (result['txBytes'] as num?)?.toInt() ?? 0;
      final now = DateTime.now();
      if (_lastStatsAt != null) {
        final dt = now.difference(_lastStatsAt!).inMilliseconds / 1000.0;
        if (dt > 0) {
          _downloadSpeedBps = ((rx - _rxBytes) / dt).clamp(0, double.infinity);
          _uploadSpeedBps = ((tx - _txBytes) / dt).clamp(0, double.infinity);
        }
      }
      _rxBytes = rx;
      _txBytes = tx;
      _lastStatsAt = now;
      notifyListeners();
    } catch (_) {}
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollTunnelStats());
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _rxBytes = 0;
    _txBytes = 0;
    _lastStatsAt = null;
    _downloadSpeedBps = 0;
    _uploadSpeedBps = 0;
  }

  Future<void> _startRuntimeSync() async {
    _runtimeSyncTimer?.cancel();
    _runtimeSyncTimer = Timer.periodic(
      const Duration(seconds: 1),
          (_) => _syncWithRuntime(),
    );
  }

  Future<void> _postConnectRefresh() async {
    for (int i = 0; i < 8; i++) {
      if (_disposed) return;

      if (_token.isNotEmpty) {
        try {
          final res = await http
              .get(
            Uri.parse("$apiBase/me"),
            headers: {"authorization": "Bearer $_token"},
          )
              .timeout(const Duration(seconds: 4));

          if (res.statusCode == 200) {
            final j = jsonDecode(res.body) as Map<String, dynamic>;
            _me = (j["user"] as Map?)?.cast<String, dynamic>();
            notifyListeners();
          } else if (res.statusCode == 401) {
            await _clearSession();
            _status = "Session expired. Sign in again.";
            _connectingUi = false;
            notifyListeners();
            return;
          }
        } catch (_) {}
      }

      try {
        await fetchUsage(showSync: !_usageEverLoaded);
      } catch (_) {}

      try {
        await refreshLocation(force: true);
      } catch (_) {}

      if (!_connected) {
        _connectingUi = false;
        notifyListeners();
        return;
      }

      if (vpnLocationFresh && uiIp.isNotEmpty) {
        _status = "Connected.";
        _connectingUi = false;
        notifyListeners();
        return;
      }

      _status = "Securing connection...";
      notifyListeners();

      await Future.delayed(Duration(milliseconds: 350 + (i * 250)));
    }

    if (_connected) {
      _status = "Connected.";
    }
    _connectingUi = false;
    notifyListeners();
  }

  Future<void> _syncWithRuntime() async {
    final running = await _isTunnelRunning();
    final changed = _connected != running;

    _connected = running;

    if (changed && _connected) {
      _connectedAt = DateTime.now();
      _loc = null;
      _locFetchedAt = null;
      _connectingUi = true;
      _status = "Securing connection...";
      notifyListeners();
      unawaited(soundController.playConnect());
      await _postConnectRefresh();
      return;
    }

    if (changed && !_connected) {
      _connectedAt = null;
      unawaited(soundController.playDisconnect());
      notifyListeners();
      return;
    }

    if (!_connected && _connectingUi && !_busy) {
      final started = _connectStartedAt;
      if (started == null) {
        _connectingUi = false;
      } else {
        final ageMs = DateTime.now().difference(started).inMilliseconds;
        if (ageMs > 9000) {
          _connectingUi = false;
          _connectStartedAt = null;
        }
      }
    }

    if (_connected) {
      if (_usageTimer == null) _startUsagePolling();
      if (_probeTimer == null) _startProbePolling();
      if (_statsTimer == null) _startStatsPolling();
    } else {
      if (_usageTimer != null) _stopUsagePolling();
      if (_probeTimer != null) _stopProbePolling();
      if (_statsTimer != null) _stopStatsPolling();
    }

    if (changed) notifyListeners();
  }

  Future<bool> _requestVpnPermission() async {
    const chan = MethodChannel("cs_vpn_permission");
    try {
      return await chan.invokeMethod<bool>("prepareVpn") == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isAnotherVpnActive() async {
    const chan = MethodChannel("cs_vpn_state");
    try {
      return await chan.invokeMethod<bool>("isAnotherVpnActive") ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isTunnelRunning() async {
    try {
      return await vpnChannel.invokeMethod<bool>(_isRunningMethodName()) == true;
    } catch (_) {
      return false;
    }
  }

  String _startMethodName() {
    if (isHysteriaTransport) return "startHysteria";
    if (isAmneziaTransport) return "startAmneziaWireGuard";
    return "startWireGuard";
  }

  String _stopMethodName() {
    if (isHysteriaTransport) return "stopHysteria";
    if (isAmneziaTransport) return "stopAmneziaWireGuard";
    return "stopWireGuard";
  }

  String _isRunningMethodName() {
    if (isHysteriaTransport) return "isHysteriaRunning";
    if (isAmneziaTransport) return "isAmneziaWireGuardRunning";
    return "isWireGuardRunning";
  }

  Map<String, dynamic> _buildHysteriaArgs(Map<String, dynamic> peer) {
    final endpoint = (peer["endpoint"] ?? "").toString().trim();
    final auth = (peer["auth"] ?? "").toString().trim();
    final sni = (peer["sni"] ?? "").toString().trim();
    final dns = (peer["dns"] as List?)?.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() ?? const <String>[];

    if (endpoint.isEmpty || auth.isEmpty || sni.isEmpty) {
      throw Exception("Provision returned incomplete Hysteria settings.");
    }

    return {
      "server": endpoint,
      "auth": auth,
      "sni": sni,
      "dns": dns.isNotEmpty ? dns.first : "10.8.50.1",
    };
  }

  String _buildWgConfig({
    required String privateKeyB64,
    required String address,
    required String serverPublicKeyB64,
    required String endpoint,
    required List<String> allowedIps,
    required List<String> dns,
    Map<String, dynamic>? awg,
  }) {
    String fixCidr(String a) {
      final parts = a.split(",").map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final out = <String>[];
      for (final p in parts) {
        if (p.contains("/")) {
          out.add(p);
          continue;
        }
        if (p.contains(":")) {
          out.add("$p/128");
        } else {
          out.add("$p/32");
        }
      }
      return out.join(", ");
    }

    void writeField(StringBuffer b, String key, dynamic value) {
      final s = (value ?? "").toString().trim();
      if (s.isNotEmpty) {
        b.writeln("$key = $s");
      }
    }

    bool asBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        return s == "1" || s == "true" || s == "yes";
      }
      return false;
    }

    int asInt(dynamic v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? fallback;
      return fallback;
    }

    final mtu = 1280;
    final stealth = asBool(awg?["stealth"]);
    final stealthPort = asInt(awg?["stealthPort"], 443);

    final b = StringBuffer();
    b.writeln("[Interface]");
    b.writeln("PrivateKey = $privateKeyB64");
    b.writeln("Address = ${fixCidr(address)}");
    b.writeln("MTU = $mtu");
    if (dns.isNotEmpty) {
      b.writeln("DNS = ${dns.join(", ")}");
    }

    if (stealth) {
      b.writeln("CS_Stealth = 1");
      b.writeln("CS_StealthPort = $stealthPort");
    }

    if (awg != null) {
      writeField(b, "S1", awg["S1"]);
      writeField(b, "S2", awg["S2"]);
      writeField(b, "S3", awg["S3"]);
      writeField(b, "S4", awg["S4"]);
      writeField(b, "H1", awg["H1"]);
      writeField(b, "H2", awg["H2"]);
      writeField(b, "H3", awg["H3"]);
      writeField(b, "H4", awg["H4"]);
      writeField(b, "Jc", awg["Jc"]);
      writeField(b, "Jmin", awg["Jmin"]);
      writeField(b, "Jmax", awg["Jmax"]);
      writeField(b, "I1", awg["I1"]);
      writeField(b, "I2", awg["I2"]);
      writeField(b, "I3", awg["I3"]);
      writeField(b, "I4", awg["I4"]);
      writeField(b, "I5", awg["I5"]);
    }

    b.writeln("");
    b.writeln("[Peer]");
    b.writeln("PublicKey = $serverPublicKeyB64");
    b.writeln("Endpoint = $endpoint");
    b.writeln("AllowedIPs = ${allowedIps.join(", ")}");
    b.writeln("PersistentKeepalive = 25");
    return b.toString();
  }

  Future<void> _probeHttps(String url) async {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      if (host.isEmpty) return;

      final swDns = Stopwatch()..start();
      final addrs = await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
      swDns.stop();
      _net("probe dns ok host=$host ms=${swDns.elapsedMilliseconds} addrs=${addrs.map((e) => e.address).take(3).join(",")}");

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final swConn = Stopwatch()..start();
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      final resp = await req.close().timeout(const Duration(seconds: 8));
      swConn.stop();

      _net("probe ok url=$url ms=${swConn.elapsedMilliseconds} status=${resp.statusCode}");

      try {
        await resp.drain();
      } catch (_) {}

      client.close(force: true);
    } on HandshakeException catch (e) {
      _net("probe tls_fail url=$url err=$e");
    } on SocketException catch (e) {
      _net("probe sock_fail url=$url osError=${e.osError?.message ?? ""} err=$e");
    } on TimeoutException catch (e) {
      _net("probe timeout url=$url err=$e");
    } catch (e) {
      _net("probe error url=$url err=$e");
    }
  }

  Future<void> _runBusy(Future<void> Function() fn) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await fn();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}