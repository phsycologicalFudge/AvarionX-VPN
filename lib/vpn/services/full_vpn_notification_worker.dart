import 'package:flutter/services.dart';

class FullVpnNotificationWorker {
  static const MethodChannel _channel = MethodChannel('cs_fullvpn');
  String _lastUsageText = '';

  Future<void> pushUsage({
    required bool connected,
    required bool connectingUi,
    required bool unlimited,
    required int usedBytes,
    required int uiLimitBytes,
    required String Function(int bytes) formatBytes,
  }) async {
    if (!connected || connectingUi) return;

    String text;
    if (unlimited) {
      text = "${formatBytes(usedBytes)} used";
    } else {
      if (uiLimitBytes <= 0) return;
      text = "${formatBytes(usedBytes)} / ${formatBytes(uiLimitBytes)}";
    }

    if (text == _lastUsageText) return;
    _lastUsageText = text;

    try {
      await _channel.invokeMethod('updateNotificationUsage', text);
    } catch (_) {}
  }

  void resetCache() {
    _lastUsageText = '';
  }
}