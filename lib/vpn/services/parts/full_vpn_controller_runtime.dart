part of '../full_vpn_backend.dart';

class VpnRuntimeSnapshot {
  final String state;
  final String transport;
  final String region;
  final bool wantsConnected;
  final bool pausedByUser;
  final int reconnectAttempt;
  final int lastHandshakeMs;
  final int rxBytes;
  final int txBytes;
  final String detail;
  final double downloadBps;
  final double uploadBps;
  final int latencyMs;
  final String expectedIp;

  const VpnRuntimeSnapshot({
    required this.state,
    required this.transport,
    required this.region,
    required this.wantsConnected,
    required this.pausedByUser,
    required this.reconnectAttempt,
    required this.lastHandshakeMs,
    required this.rxBytes,
    required this.txBytes,
    required this.detail,
    required this.downloadBps,
    required this.uploadBps,
    required this.latencyMs,
    required this.expectedIp,
  });

  factory VpnRuntimeSnapshot.fromMap(Map<dynamic, dynamic> m) {
    double asDouble(Object? v) {
      if (v is num) return v.toDouble();
      return double.tryParse("${v ?? ""}") ?? 0.0;
    }

    int asInt(Object? v) {
      if (v is num) return v.toInt();
      return int.tryParse("${v ?? ""}") ?? 0;
    }

    bool asBool(Object? v) {
      if (v is bool) return v;
      final s = "${v ?? ""}".toLowerCase();
      return s == "1" || s == "true";
    }

    return VpnRuntimeSnapshot(
      state: "${m["state"] ?? "disconnected"}".toLowerCase(),
      transport: "${m["transport"] ?? "wireguard"}".toLowerCase(),
      region: "${m["region"] ?? ""}",
      wantsConnected: asBool(m["wantsConnected"]),
      pausedByUser: asBool(m["pausedByUser"]),
      reconnectAttempt: asInt(m["reconnectAttempt"]),
      lastHandshakeMs: asInt(m["lastHandshakeMs"]),
      rxBytes: asInt(m["rxBytes"]),
      txBytes: asInt(m["txBytes"]),
      detail: "${m["detail"] ?? ""}",
      downloadBps: asDouble(m["downloadBps"]),
      uploadBps: asDouble(m["uploadBps"]),
      latencyMs: asInt(m["latencyMs"]),
      expectedIp: "${m["expectedIp"] ?? ""}",
    );
  }

  bool get isConnected => state == "connected";

  bool get isConnecting => state == "connecting";

  bool get isReconnecting => state == "reconnecting";

  bool get isPaused => state == "paused";
}

extension _FullVpnControllerRuntime on FullVpnController {
  static const EventChannel _statusChannel = EventChannel("cs_vpn_status");
  static const MethodChannel _managedChannel = MethodChannel("cs_fullvpn");

  Future<void> _startRuntimeBridgeImpl() async {
    await _runtimeSub?.cancel();

    try {
      _runtimeSub = _statusChannel.receiveBroadcastStream().listen(
            (event) {
          if (event is! Map) return;
          _applyRuntimeSnapshot(VpnRuntimeSnapshot.fromMap(event));
        },
        onError: (Object e) {
          _net("runtime_bridge_error $e");
        },
        cancelOnError: false,
      );
    } catch (e) {
      _net("runtime_bridge_unavailable $e");
    }
  }

  Future<void> _stopRuntimeBridgeImpl() async {
    await _runtimeSub?.cancel();
    _runtimeSub = null;
  }

  static const Duration _fastLocationTimeout = Duration(milliseconds: 900);

  static const List<Duration> _backgroundLocationTimeouts = [
    Duration(milliseconds: 1200),
    Duration(milliseconds: 1200),
    Duration(milliseconds: 1500),
    Duration(milliseconds: 1500),
    Duration(milliseconds: 2000),
  ];

  void _applyRuntimeSnapshot(VpnRuntimeSnapshot s) {
    if (_disposed) return;

    final wasConnected = _connected;
    final justConnected = !wasConnected && s.isConnected;

    _reconnecting = s.isReconnecting;
    _wantsConnected = s.wantsConnected;
    _reconnectAttempt = s.reconnectAttempt;
    _lastHandshakeMs = s.lastHandshakeMs;
    _rxBytes = s.rxBytes;
    _txBytes = s.txBytes;
    _downloadSpeedBps = s.downloadBps;
    _uploadSpeedBps = s.uploadBps;
    _latencyMs = s.latencyMs;
    _vpnTransport = s.transport;
    _status = s.detail;
    _expectedExitIp = s.expectedIp;

    if (justConnected) {
      unawaited(_settleNewConnection());
      return;
    }

    _connected = s.isConnected;
    _connectingUi = s.isConnecting;
    notifyListeners();

    if (wasConnected && !_connected) {
      _onRuntimeDisconnected();
    }
  }

  Future<void> _settleNewConnection() async {
    if (_disposed) return;

    _connectedAt = DateTime.now();
    _locationFetching = true;

    final expectedIp = _expectedExitIp;
    final gotFast = await _fetchLocationOnce(
      timeout: _fastLocationTimeout,
      expectedIp: expectedIp,
    );

    if (_disposed) return;

    _connected = true;
    _connectingUi = false;
    _locationFetching = !gotFast;
    notifyListeners();

    unawaited(soundController.playConnect());
    unawaited(_postConnectRefresh());

    if (!gotFast) {
      unawaited(_backgroundLocationRetry(expectedIp));
    }
  }

  Future<void> _backgroundLocationRetry(String expectedIp) async {
    for (final timeout in _backgroundLocationTimeouts) {
      if (_disposed || !_connected) return;

      await Future.delayed(const Duration(milliseconds: 500));
      if (_disposed || !_connected) return;

      final ok = await _fetchLocationOnce(timeout: timeout, expectedIp: expectedIp);
      if (ok) {
        if (_disposed || !_connected) return;
        _locationFetching = false;
        notifyListeners();
        return;
      }
    }

    if (_disposed || !_connected) return;
    _locationFetching = false;
    notifyListeners();
  }

  void _onRuntimeDisconnected() {
    _connectedAt = null;
    _locationFetching = false;
    _expectedExitIp = "";
    unawaited(soundController.playDisconnect());

    _rxBytes = 0;
    _txBytes = 0;
    _downloadSpeedBps = 0;
    _uploadSpeedBps = 0;
    _latencyMs = 0;
    notifyListeners();
  }

  Future<void> _connectManagedImpl() async {
    if (_busy) return;

    final notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted) {
      final notif = await Permission.notification.request();
      if (!notif.isGranted) {
        _status = "Notifications permission required.";
        notifyListeners();
        return;
      }
    }

    final granted = await _requestVpnPermission();
    if (!granted) {
      _status = "VPN permission denied";
      notifyListeners();
      return;
    }

    if (await _isAnotherVpnActive()) {
      _status = "Another VPN is active";
      notifyListeners();
      return;
    }

    await _persistConnectSelection();

    try {
      await AvServiceManager.stopVpn();
    } catch (_) {}

    try {
      await _managedChannel.invokeMethod("connectManaged", {
        "premium": hasPremiumAccess,
      });
    } catch (e) {
      _status = "Unable to connect";
      _net("connect_managed_failed $e");
      notifyListeners();
    }
  }

  Future<void> _disconnectManagedImpl() async {
    try {
      await _managedChannel.invokeMethod("disconnectManaged");
    } catch (e) {
      _net("disconnect_failed $e");
    }
  }

  Future<void> _switchServerManagedImpl(FullVpnServerLocation s) async {
    _selectedServerId = s.id;
    await _persistConnectSelection();

    if (!_wantsConnected) {
      notifyListeners();
      return;
    }

    try {
      await _managedChannel.invokeMethod("switchServerManaged", {
        "premium": hasPremiumAccess,
      });
    } catch (e) {
      _status = "Unable to switch server";
      _net("switch_server_failed $e");
      notifyListeners();
    }
  }

  Future<void> _persistConnectSelection() async {
    _vpnTransport = _correctedTransportForServerId(_selectedServerId, _vpnTransport);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      FullVpnController.kSelectedServerId,
      _selectedServerId,
    );
    await prefs.setString(
      FullVpnController.kVpnTransport,
      _vpnTransport,
    );
  }

  Future<void> _refreshRuntimeOnceImpl() async {
    try {
      final raw = await _managedChannel.invokeMethod("runtimeSnapshot");
      if (raw is Map) {
        _applyRuntimeSnapshot(VpnRuntimeSnapshot.fromMap(raw));
      }
    } catch (e) {
      _net("runtime_snapshot_failed $e");
    }
  }
}