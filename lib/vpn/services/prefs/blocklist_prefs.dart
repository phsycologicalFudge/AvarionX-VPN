/// Single source of truth for blocklist toggle state.
library;

import 'package:shared_preferences/shared_preferences.dart';

class BlocklistPrefs {
  BlocklistPrefs._();

  static const String malware  = 'dns_cloud_list_malware';
  static const String ads      = 'dns_cloud_list_ads';
  static const String trackers = 'dns_cloud_list_trackers';
  static const String adult    = 'dns_cloud_list_adult';
  static const String gambling = 'dns_cloud_list_gambling';
  static const String social   = 'dns_cloud_list_social';

  static const String recCsMalware = 'dns_cloud_rec_cs_malware';
  static const String recCsAds     = 'dns_cloud_rec_cs_ads';

  static const Map<String, String> _controllerKeyMap = {
    'malware':  malware,
    'ads':      ads,
    'trackers': trackers,
    'adult':    adult,
    'gambling': gambling,
    'social':   social,
    'romain':   recCsMalware,
    'oisd':     recCsAds,
  };

  static Future<Map<String, bool>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'malware':  prefs.getBool(malware)      ?? false,
      'ads':      prefs.getBool(ads)          ?? false,
      'trackers': prefs.getBool(trackers)     ?? false,
      'adult':    prefs.getBool(adult)        ?? false,
      'gambling': prefs.getBool(gambling)     ?? false,
      'social':   prefs.getBool(social)       ?? false,
      'romain':   prefs.getBool(recCsMalware) ?? false,
      'oisd':     prefs.getBool(recCsAds)     ?? false,
    };
  }

  static Future<void> save(Map<String, bool> values) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in values.entries) {
      final key = _controllerKeyMap[entry.key];
      if (key != null) await prefs.setBool(key, entry.value);
    }
  }

  static Future<void> set(String controllerKey, bool value) async {
    final prefKey = _controllerKeyMap[controllerKey];
    if (prefKey == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, value);
  }
}