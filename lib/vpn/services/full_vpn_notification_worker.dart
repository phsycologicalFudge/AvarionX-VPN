import 'package:flutter/services.dart';

class FullVpnNotificationWorker {
  static const MethodChannel _channel = MethodChannel('cs_fullvpn');
  String _lastText = '';

  Future<void> pushStatus({
    required bool connected,
    required bool connectingUi,
    required String serverLabel,
    required double downloadSpeedBps,
    required double uploadSpeedBps,
    required String Function(double bps) formatSpeed,
  }) async {
    if (!connected || connectingUi) return;

    final text = '$serverLabel  ↓${formatSpeed(downloadSpeedBps)}  ↑${formatSpeed(uploadSpeedBps)}';

    if (text == _lastText) return;
    _lastText = text;

    try {
      await _channel.invokeMethod('updateNotificationUsage', text);
    } catch (_) {}
  }

  void resetCache() {
    _lastText = '';
  }
}