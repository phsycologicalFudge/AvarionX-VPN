library full_vpn_controller;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:colourswift_av/vpn/services/sound_controller/vpn_sound_controller.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
part 'parts/full_vpn_controller_runtime.dart';


class FullVpnController extends ChangeNotifier {
  static const vpnChannel = MethodChannel("cs_vpn_control");

  static const kAuthToken = "cs_auth_token";
  static const kPkceVerifier = "cs_pkce_verifier";
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
  static const kSplitExcludedPkgs = "cs_vpn_split_excluded_pkgs";
  static const int kStandaloneSoftLimitBytes = 10 * 1024 * 1024 * 1024;

  final String apiBase;
  final String loginUrl;

  FullVpnController({
    required this.apiBase,
    required this.loginUrl,
  });

  Timer? _usageTimer;
  Timer? _serverStatusTimer;
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
  StreamSubscription? _runtimeSub;
  bool _connectingUi = false;
  DateTime? _connectStartedAt;

  bool _wantsConnected = false;
  bool _reconnecting = false;
  int _reconnectAttempt = 0;
  int _lastHandshakeMs = 0;
  DateTime? _lastProbeSuccessAt;

  static const Duration _initialHealthGrace = Duration(seconds: 20);
  static const Duration _recentProbeSuccessWindow = Duration(seconds: 45);
  static const int _probeFailuresBeforeReconnect = 3;

  static const List<int> _reconnectBackoffsMs = [2000, 5000, 10000, 20000, 30000];

  bool _showFlagMarkers = false;

  dynamic _loc;
  DateTime? _locFetchedAt;
  DateTime? _connectedAt;
  bool _locationFetching = false;
  String _expectedExitIp = "";

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
  int _latencyMs = 0;
  DateTime? _lastStatsAt;
  double _downloadSpeedBps = 0;
  double _uploadSpeedBps = 0;


  String _selectedServerId = "de";
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
  bool get reconnecting => _reconnecting;
  dynamic get loc => _loc;
  int get usedBytes => _usedBytes;
  int get limitBytes => _limitBytes;
  int get latencyMs => _latencyMs;
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
    return _locFetchedAt!.isAfter(_connectedAt!);
  }

  bool get vpnLocationFetching => _connected && _locationFetching;

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
    final challenge = await _generateAndStorePkceChallenge();

    final u = Uri.parse(loginUrl).replace(queryParameters: {
      ...Uri.parse(loginUrl).queryParameters,
      "flow": "v2",
      "code_challenge": challenge,
      "code_challenge_method": "S256",
    });

    final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
    if (!ok) {
      _status = "Failed to open browser.";
      notifyListeners();
    }
  }

  Future<void> completePkceLogin(String code) async {
    final verifier = await _takeStoredPkceVerifier();
    if (verifier.isEmpty || code.isEmpty) {
      _status = "Sign in failed. Please try again.";
      notifyListeners();
      return;
    }

    try {
      final res = await http.post(
        Uri.parse("$apiBase/auth/exchange"),
        headers: {"content-type": "application/json"},
        body: jsonEncode({"code": code, "codeVerifier": verifier}),
      );

      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final token = (j["token"] ?? "").toString();
        if (token.isNotEmpty) {
          await setTokenFromLogin(token);
          return;
        }
      }

      _net("POST $apiBase/auth/exchange status=${res.statusCode} bodyLen=${res.body.length}");
      _status = "Sign in failed. Please try again.";
      notifyListeners();
    } catch (e) {
      _net("POST $apiBase/auth/exchange exception=$e");
      _status = "Sign in failed ($e).";
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

    await _startRuntimeBridgeImpl();
    await _refreshRuntimeOnceImpl();
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
    await _refreshRuntimeOnceImpl();
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cs_private_dns_hostname');
    await prefs.remove(kWgPriv);
    await prefs.remove(kWgPub);
    await prefs.remove(kDeviceId);
    await prefs.remove(kWgConfigLast);
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

    await _connectManagedImpl();
  }

  Future<void> disconnect() async {
    await _disconnectManagedImpl();
    await _setGlobalModeOff();
    _stopUsagePolling();
    await refreshLocation(force: true);
    notifyListeners();
  }

  Future<void> switchServer(FullVpnServerLocation s, {String? transport}) async {
    if (_busy) return;

    if (transport != null) {
      _vpnTransport = transport.trim().toLowerCase();
    }

    _status = "Selected ${s.label}";
    notifyListeners();

    await fetchServerStatus();

    if (_wantsConnected) {
      _status = "Switching to ${s.label}...";
      notifyListeners();
    }

    await _switchServerManagedImpl(s);

    if (_wantsConnected) {
      await refreshLocation(force: true);
    }
  }

  String _correctedTransportForServerId(String id, String currentTransport) {
    final normalized = id.trim().toLowerCase();
    if (normalized.startsWith("hy-")) return "hysteria";
    if (normalized.startsWith("awg-")) return "amnezia";
    if (currentTransport == "hysteria") return "wireguard";
    return currentTransport;
  }

  void selectServerPreview(FullVpnServerLocation s) {
    if (_connected || _connectingUi) return;
    if (s.id == _selectedServerId) return;

    _selectedServerId = s.id;
    _vpnTransport = _correctedTransportForServerId(s.id, _vpnTransport);
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
    _serverStatusTimer?.cancel();
    _locationsTimer?.cancel();
    unawaited(_stopRuntimeBridgeImpl());
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
      const Duration(seconds: 30),
          (_) async {
        if (_token.isEmpty || _disposed) return;
        await fetchServerStatus();
      },
    );
  }







  Future<void> _postConnectRefresh() async {
    if (_disposed || !_wantsConnected || !_connected) {
      _connectingUi = false;
      notifyListeners();
      return;
    }
    _status = "Connected.";
    _connectingUi = false;
    _connectStartedAt = null;
    notifyListeners();

    unawaited(_refreshConnectedMetadata());
  }

  Future<void> _refreshConnectedMetadata() async {
    if (_disposed || !_connected) return;

    if (_token.isNotEmpty) {
      try {
        await refreshMe();
      } catch (_) {}
    }

    if (_disposed || !_connected) return;
    try {
      await fetchUsage(showSync: !_usageEverLoaded);
    } catch (_) {}
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