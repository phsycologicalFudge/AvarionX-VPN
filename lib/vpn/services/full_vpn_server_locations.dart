import 'package:latlong2/latlong.dart';

class FullVpnServerLocation {
  final String id;
  final String label;
  final String countryCode;
  final LatLng point;

  const FullVpnServerLocation({
    required this.id,
    required this.label,
    required this.countryCode,
    required this.point,
  });
}

const List<FullVpnServerLocation> kFullVpnServers = [
  FullVpnServerLocation(
    id: "de-nuremberg",
    label: "Nürnberg",
    countryCode: "DE",
    point: LatLng(49.4521, 11.0767),
  ),
  FullVpnServerLocation(
    id: "us-ashburn",
    label: "Ashburn",
    countryCode: "US",
    point: LatLng(39.0438, -77.4874),
  ),
  FullVpnServerLocation(
    id: "fl-finland",
    label: "Finland",
    countryCode: "FI",
    point: LatLng(60.1699, 24.9384),
  ),
  FullVpnServerLocation(
    id: "sg-singapore",
    label: "Singapore",
    countryCode: "SG",
    point: LatLng(1.3521, 103.8198),
  ),
  FullVpnServerLocation(
    id: "uk-portsmouth",
    label: "Portsmouth",
    countryCode: "GB",
    point: LatLng(50.8198, -1.0880),
  ),
  FullVpnServerLocation(
    id: "hy-jp",
    label: "Tokyo",
    countryCode: "JP",
    point: LatLng(35.6762, 139.6503),
  ),
  FullVpnServerLocation(
    id: "awg-us",
    label: "Oregon",
    countryCode: "US",
    point: LatLng(45.5152, -122.6784),
  ),
  FullVpnServerLocation(
    id: "pl",
    label: "Poland",
    countryCode: "PL",
    point: LatLng(52.2297, 21.0122),
  ),
];