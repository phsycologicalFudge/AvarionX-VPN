import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VpnSoundOption {
  final String key;
  final String label;
  final String assetPath;

  const VpnSoundOption({
    required this.key,
    required this.label,
    required this.assetPath,
  });
}

class VpnSoundController extends ChangeNotifier {
  static const String kSelectedConnectSoundKey = 'cs_vpn_selected_connect_sound';
  static const String kSelectedDisconnectSoundKey = 'cs_vpn_selected_disconnect_sound';
  static const String kConnectionSoundsEnabledKey = 'cs_vpn_connection_sounds_enabled';

  final AudioPlayer _player = AudioPlayer();

  final List<VpnSoundOption> connectionSupported = const [
    VpnSoundOption(
      key: 'connection_pop',
      label: 'Connection Pop',
      assetPath: 'assets/sound_effects/connection_pop.mp3',
    ),
    VpnSoundOption(
      key: 'ethereal_startup',
      label: 'Ethereal Startup',
      assetPath: 'assets/sound_effects/ethereal_startup.mp3',
    ),
  ];

  final List<VpnSoundOption> disconnectionSupported = const [
    VpnSoundOption(
      key: 'connection_pop',
      label: 'Connection Pop',
      assetPath: 'assets/sound_effects/connection_pop.mp3',
    ),
    VpnSoundOption(
      key: 'ethereal_startup',
      label: 'Ethereal Startup',
      assetPath: 'assets/sound_effects/ethereal_startup.mp3',
    ),
  ];

  String _selectedConnectKey = 'connection_pop';
  String _selectedDisconnectKey = 'connection_pop';
  bool _enabled = true;
  bool _disposed = false;

  bool get enabled => _enabled;
  String get selectedConnectKey => _selectedConnectKey;
  String get selectedDisconnectKey => _selectedDisconnectKey;

  VpnSoundOption? get selectedConnectSound => _findByKey(
    connectionSupported,
    _selectedConnectKey,
  );

  VpnSoundOption? get selectedDisconnectSound => _findByKey(
    disconnectionSupported,
    _selectedDisconnectKey,
  );

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    _enabled = prefs.getBool(kConnectionSoundsEnabledKey) ?? true;

    final savedConnect = prefs.getString(kSelectedConnectSoundKey);
    final savedDisconnect = prefs.getString(kSelectedDisconnectSoundKey);

    if (_findByKey(connectionSupported, savedConnect) != null) {
      _selectedConnectKey = savedConnect!;
    } else if (connectionSupported.isNotEmpty) {
      _selectedConnectKey = connectionSupported.first.key;
    }

    if (_findByKey(disconnectionSupported, savedDisconnect) != null) {
      _selectedDisconnectKey = savedDisconnect!;
    } else if (disconnectionSupported.isNotEmpty) {
      _selectedDisconnectKey = disconnectionSupported.first.key;
    }

    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kConnectionSoundsEnabledKey, value);
    notifyListeners();
  }

  Future<void> setSelectedConnectKey(String key) async {
    if (_findByKey(connectionSupported, key) == null) return;
    _selectedConnectKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kSelectedConnectSoundKey, key);
    notifyListeners();
  }

  Future<void> setSelectedDisconnectKey(String key) async {
    if (_findByKey(disconnectionSupported, key) == null) return;
    _selectedDisconnectKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kSelectedDisconnectSoundKey, key);
    notifyListeners();
  }

  Future<void> playConnect() async {
    if (!_enabled) return;
    final sound = selectedConnectSound;
    if (sound == null) return;
    await _play(sound.assetPath);
  }

  Future<void> playDisconnect() async {
    if (!_enabled) return;
    final sound = selectedDisconnectSound;
    if (sound == null) return;
    await _play(sound.assetPath);
  }

  VpnSoundOption? _findByKey(List<VpnSoundOption> items, String? key) {
    if (key == null) return null;
    for (final item in items) {
      if (item.key == key) return item;
    }
    return null;
  }

  Future<void> _play(String assetPath) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(assetPath.replaceFirst('assets/', '')));
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _player.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}