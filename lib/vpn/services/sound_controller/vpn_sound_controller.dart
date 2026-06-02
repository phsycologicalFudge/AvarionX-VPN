import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VpnSoundOption {
  final String key;
  final String label;
  final String? assetPath;
  final String? filePath;
  final bool isCustom;

  const VpnSoundOption({
    required this.key,
    required this.label,
    this.assetPath,
    this.filePath,
    this.isCustom = false,
  });

  bool get isAsset => assetPath != null;

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'filePath': filePath,
    'isCustom': isCustom,
  };

  factory VpnSoundOption.fromJson(Map<String, dynamic> json) => VpnSoundOption(
    key: json['key'] as String,
    label: json['label'] as String,
    filePath: json['filePath'] as String?,
    isCustom: json['isCustom'] as bool? ?? true,
  );
}

enum SoundImportError {
  cancelled,
  tooLong,
  longButAllowed,
  unreadable,
  copyFailed,
}

class VpnSoundController extends ChangeNotifier {
  static const String _kSelectedConnectKey = 'cs_vpn_selected_connect_sound';
  static const String _kSelectedDisconnectKey = 'cs_vpn_selected_disconnect_sound';
  static const String _kSoundsEnabledKey = 'cs_vpn_connection_sounds_enabled';
  static const String _kCustomSoundsKey = 'cs_vpn_custom_sounds';
  static const double _recommendedDurationSeconds = 5.0;
  static const double _maxDurationSeconds = 300.0;

  final AudioPlayer _player = AudioPlayer();
  bool _disposed = false;

  static const List<VpnSoundOption> _bundledSounds = [
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
    VpnSoundOption(
      key: 'wah_wah_sad_trombone',
      label: 'Sad Trombone',
      assetPath: 'assets/sound_effects/wah-wah-sad-trombone.mp3',
    ),
    VpnSoundOption(
      key: 'watch_yo_jet',
      label: 'Watch Yo Jet',
      assetPath: 'assets/sound_effects/watch_yo_jet.mp3',
    ),
    VpnSoundOption(
      key: 'fart',
      label: 'Fart',
      assetPath: 'assets/sound_effects/fart.mp3',
    ),
    VpnSoundOption(
      key: 'explosion',
      label: 'Explosion',
      assetPath: 'assets/sound_effects/explosion.mp3',
    ),
  ];

  List<VpnSoundOption> _customSounds = [];

  List<VpnSoundOption> get sounds => [..._bundledSounds, ..._customSounds];

  String _selectedConnectKey = 'ethereal_startup';
  String _selectedDisconnectKey = 'connection_pop';
  bool _enabled = true;

  bool get enabled => _enabled;
  String get selectedConnectKey => _selectedConnectKey;
  String get selectedDisconnectKey => _selectedDisconnectKey;

  VpnSoundOption? get selectedConnectSound => _findByKey(_selectedConnectKey);
  VpnSoundOption? get selectedDisconnectSound => _findByKey(_selectedDisconnectKey);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    _enabled = prefs.getBool(_kSoundsEnabledKey) ?? true;

    final rawCustom = prefs.getString(_kCustomSoundsKey);
    if (rawCustom != null) {
      try {
        final list = jsonDecode(rawCustom) as List<dynamic>;
        _customSounds = list
            .map((e) => VpnSoundOption.fromJson(e as Map<String, dynamic>))
            .where((s) => s.filePath != null && File(s.filePath!).existsSync())
            .toList();
      } catch (_) {
        _customSounds = [];
      }
    }

    final savedConnect = prefs.getString(_kSelectedConnectKey);
    final savedDisconnect = prefs.getString(_kSelectedDisconnectKey);

    _selectedConnectKey = _findByKey(savedConnect) != null
        ? savedConnect!
        : 'ethereal_startup';

    _selectedDisconnectKey = _findByKey(savedDisconnect) != null
        ? savedDisconnect!
        : 'connection_pop';

    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSoundsEnabledKey, value);
    notifyListeners();
  }

  Future<void> setSelectedConnectKey(String key) async {
    if (_findByKey(key) == null) return;
    _selectedConnectKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelectedConnectKey, key);
    notifyListeners();
  }

  Future<void> setSelectedDisconnectKey(String key) async {
    if (_findByKey(key) == null) return;
    _selectedDisconnectKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelectedDisconnectKey, key);
    notifyListeners();
  }

  Future<void> playConnect() async {
    if (!_enabled) return;
    final sound = selectedConnectSound;
    if (sound == null) return;
    await _playOption(sound);
  }

  Future<void> playDisconnect() async {
    if (!_enabled) return;
    final sound = selectedDisconnectSound;
    if (sound == null) return;
    await _playOption(sound);
  }

  Future<void> previewSound(VpnSoundOption option) async {
    await _playOption(option);
  }

  Future<({SoundImportError? error, VpnSoundOption? sound, String? pendingPath})> importSound() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
    } catch (_) {
      return (error: SoundImportError.unreadable, sound: null, pendingPath: null);
    }

    if (result == null || result.files.isEmpty) {
      return (error: SoundImportError.cancelled, sound: null, pendingPath: null);
    }

    final sourcePath = result.files.first.path;
    if (sourcePath == null) {
      return (error: SoundImportError.unreadable, sound: null, pendingPath: null);
    }

    final duration = await _probeDuration(sourcePath);
    if (duration == null) {
      return (error: SoundImportError.unreadable, sound: null, pendingPath: null);
    }
    if (duration > _maxDurationSeconds) {
      return (error: SoundImportError.tooLong, sound: null, pendingPath: null);
    }
    if (duration > _recommendedDurationSeconds) {
      return (error: SoundImportError.longButAllowed, sound: null, pendingPath: sourcePath);
    }

    final committed = await _commitImport(sourcePath);
    return (error: committed.error, sound: committed.sound, pendingPath: null);
  }

  Future<({SoundImportError? error, VpnSoundOption? sound})> importSoundFromPath(String sourcePath) async {
    return _commitImport(sourcePath);
  }

  Future<({SoundImportError? error, VpnSoundOption? sound})> _commitImport(String sourcePath) async {
    final dir = await _soundsDir();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourcePath)}';
    final destPath = p.join(dir.path, fileName);

    try {
      await File(sourcePath).copy(destPath);
    } catch (_) {
      return (error: SoundImportError.copyFailed, sound: null);
    }

    final rawName = p.basenameWithoutExtension(sourcePath)
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .trim();
    final label = rawName[0].toUpperCase() + rawName.substring(1);
    final key = 'custom_${DateTime.now().millisecondsSinceEpoch}';

    final option = VpnSoundOption(
      key: key,
      label: label,
      filePath: destPath,
      isCustom: true,
    );

    _customSounds.add(option);
    await _persistCustomSounds();
    notifyListeners();

    return (error: null, sound: option);
  }

  Future<void> deleteCustomSound(String key) async {
    final index = _customSounds.indexWhere((s) => s.key == key);
    if (index == -1) return;

    final sound = _customSounds[index];
    if (sound.filePath != null) {
      try {
        await File(sound.filePath!).delete();
      } catch (_) {}
    }

    _customSounds.removeAt(index);

    if (_selectedConnectKey == key) {
      _selectedConnectKey = _bundledSounds.first.key;
    }
    if (_selectedDisconnectKey == key) {
      _selectedDisconnectKey = _bundledSounds.first.key;
    }

    await _persistCustomSounds();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelectedConnectKey, _selectedConnectKey);
    await prefs.setString(_kSelectedDisconnectKey, _selectedDisconnectKey);

    notifyListeners();
  }

  Future<void> _persistCustomSounds() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_customSounds.map((s) => s.toJson()).toList());
    await prefs.setString(_kCustomSoundsKey, encoded);
  }

  Future<double?> _probeDuration(String filePath) async {
    final probe = AudioPlayer();
    try {
      final completer = probe.onDurationChanged.first;
      await probe.setSource(DeviceFileSource(filePath));
      final duration = await completer.timeout(const Duration(seconds: 5));
      return duration.inMilliseconds / 1000.0;
    } catch (_) {
      return null;
    } finally {
      await probe.dispose();
    }
  }

  Future<Directory> _soundsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'vpn_sounds'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  VpnSoundOption? _findByKey(String? key) {
    if (key == null) return null;
    for (final s in sounds) {
      if (s.key == key) return s;
    }
    return null;
  }

  Future<void> _playOption(VpnSoundOption option) async {
    try {
      await _player.stop();
      if (option.isAsset) {
        await _player.play(
          AssetSource(option.assetPath!.replaceFirst('assets/', '')),
        );
      } else if (option.filePath != null) {
        await _player.play(DeviceFileSource(option.filePath!));
      }
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