import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AnimatedConnectingRouteLayer extends StatelessWidget {
  final LatLng from;
  final LatLng to;
  final bool animate;

  const AnimatedConnectingRouteLayer({
    super.key,
    required this.from,
    required this.to,
    required this.animate,
  });

  static const int _steps = 80;

  List<LatLng> _line(LatLng a, LatLng b) {
    return List.generate(
      _steps,
          (i) {
        final t = _steps <= 1 ? 1.0 : i / (_steps - 1);
        return LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final pts = _line(from, to);

    final opacity = animate ? 0.28 : 0.18;
    final width = animate ? 5.0 : 4.0;

    return PolylineLayer(
      polylines: [
        Polyline(
          points: pts,
          strokeWidth: width,
          color: scheme.primary.withOpacity(opacity),
        ),
      ],
    );
  }
}