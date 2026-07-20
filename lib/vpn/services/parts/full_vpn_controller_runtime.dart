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

  void _applyRuntimeSnapshot(VpnRuntimeSnapshot s) {
    if (_disposed) return;

    final wasConnected = _connected;

    _connected = s.isConnected;
    _connectingUi = s.isConnecting;
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

    notifyListeners();

    if (!wasConnected && _connected) {
      _onRuntimeConnected();
      return;
    }

    if (wasConnected && !_connected) {
      _onRuntimeDisconnected();
    }
  }

  void _onRuntimeConnected() {
    _connectedAt = DateTime.now();
    unawaited(soundController.playConnect());
    unawaited(_postConnectRefresh());
  }

  void _onRuntimeDisconnected() {
    _connectedAt = null;
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
