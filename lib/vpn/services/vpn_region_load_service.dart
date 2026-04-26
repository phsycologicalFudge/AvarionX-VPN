import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class VpnRegionLoadService extends ChangeNotifier {
  final String apiBase;

  VpnRegionLoadService({required this.apiBase});

  Map<String, int> _loads = {};
  Timer? _timer;
  bool _disposed = false;
  String _activeToken = "";

  Map<String, int> get loads => Map.unmodifiable(_loads);

  int? loadForRegion(String regionId) => _loads[regionId.toLowerCase()];

  void start(String token) {
    if (token.isEmpty) {
      stop();
      return;
    }
    if (token == _activeToken && _timer != null) return;
    _activeToken = token;
    _stop();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _fetch());
  }

  void stop() {
    _activeToken = "";
    _stop();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _fetch() async {
    final token = _activeToken;
    if (_disposed || token.isEmpty) return;
    try {
      final res = await http
          .get(
        Uri.parse('$apiBase/vpn/region-loads'),
        headers: {'authorization': 'Bearer $token'},
      )
          .timeout(const Duration(seconds: 10));
      if (_disposed) return;
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = data['loads'];
      if (raw is! Map) return;

      final next = <String, int>{};
      for (final e in raw.entries) {
        final v = e.value;
        final key = e.key.toString().toLowerCase();
        if (v is int) {
          next[key] = v;
        } else if (v is num) {
          next[key] = v.toInt();
        }
      }

      if (_disposed) return;
      _loads = next;
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    super.dispose();
  }
}