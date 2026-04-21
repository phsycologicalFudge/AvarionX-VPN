import 'package:latlong2/latlong.dart';

class FullVpnServerLocation {
  final String id;
  final String label;
  final String countryCode;
  final String? city;
  final LatLng point;

  const FullVpnServerLocation({
    required this.id,
    required this.label,
    required this.countryCode,
    this.city,
    required this.point,
  });

  factory FullVpnServerLocation.fromJson(Map<String, dynamic> json) {
    final lat = (json["lat"] as num?)?.toDouble();
    final lng = (json["lng"] as num?)?.toDouble();
    return FullVpnServerLocation(
      id: (json["id"] as String?) ?? "",
      label: (json["label"] as String?) ?? "",
      countryCode: ((json["countryCode"] as String?) ?? "").toUpperCase(),
      city: json["city"] as String?,
      point: lat != null && lng != null ? LatLng(lat, lng) : const LatLng(0, 0),
    );
  }
}