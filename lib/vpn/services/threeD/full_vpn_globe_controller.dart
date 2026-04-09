import 'package:colourswift_av/vpn/services/full_vpn_server_locations.dart';
import 'package:flutter_globe_3d/flutter_globe_3d.dart';

class GlobeFocusData {
  final double latitude;
  final double longitude;
  final String key;

  const GlobeFocusData({
    required this.latitude,
    required this.longitude,
    required this.key,
  });
}

EarthController buildFullVpnEarthController() {
  final controller = EarthController();
  controller.rotateSpeed = 0;
  controller.enableAutoRotate = false;
  controller.minZoom = 0.75;
  controller.setLightMode(EarthLightMode.realTime);
  return controller;
}

GlobeFocusData buildFullVpnGlobeFocus({
  required double? userLat,
  required double? userLon,
  required bool hasUserPoint,
  required bool connected,
  required bool isConnecting,
  required FullVpnServerLocation? selectedServer,
  required String? selectedServerId,
}) {
  double focusLat;
  double focusLon;

  if (!connected && selectedServer != null) {
    focusLat = selectedServer.point.latitude;
    focusLon = selectedServer.point.longitude;
  } else if (isConnecting && hasUserPoint && selectedServer != null) {
    focusLat = midLat(userLat!, selectedServer.point.latitude);
    focusLon = midLon(userLon!, selectedServer.point.longitude);
  } else if (connected && selectedServer != null) {
    focusLat = selectedServer.point.latitude;
    focusLon = selectedServer.point.longitude;
  } else if (hasUserPoint) {
    focusLat = userLat!;
    focusLon = userLon!;
  } else {
    focusLat = 20.0;
    focusLon = 0.0;
  }

  return GlobeFocusData(
    latitude: focusLat,
    longitude: focusLon,
    key: '${focusLat.toStringAsFixed(4)}:${focusLon.toStringAsFixed(4)}:$connected:$isConnecting:${selectedServerId ?? ''}',
  );
}

bool sameServerIds(
    List<FullVpnServerLocation> a,
    List<FullVpnServerLocation> b,
    ) {
  if (a.length != b.length) return false;

  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id) return false;
  }

  return true;
}

double midLat(double a, double b) => (a + b) / 2.0;

double midLon(double a, double b) {
  var diff = (b - a + 540.0) % 360.0 - 180.0;
  var mid = a + diff / 2.0;

  if (mid > 180.0) mid -= 360.0;
  if (mid < -180.0) mid += 360.0;

  return mid;
}