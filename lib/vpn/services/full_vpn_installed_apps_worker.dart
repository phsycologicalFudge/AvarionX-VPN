import 'package:device_apps/device_apps.dart';

class FullVpnInstalledApp {
  final String packageName;
  final String name;

  const FullVpnInstalledApp({
    required this.packageName,
    required this.name,
  });
}

class FullVpnInstalledAppsWorker {
  static Future<List<FullVpnInstalledApp>> listLaunchableApps() async {
    final apps = await DeviceApps.getInstalledApplications(
      includeSystemApps: true,
      includeAppIcons: false,
      onlyAppsWithLaunchIntent: true,
    );

    final out = <FullVpnInstalledApp>[];

    for (final a in apps) {
      final pkg = a.packageName.trim();
      final name = a.appName.trim();
      if (pkg.isEmpty || name.isEmpty) continue;
      out.add(FullVpnInstalledApp(packageName: pkg, name: name));
    }

    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static Future<List<int>?> loadIconBytes(String packageName) async {
    final app = await DeviceApps.getApp(packageName, true);
    if (app is ApplicationWithIcon) return app.icon;
    return null;
  }
}