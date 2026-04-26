//maaan this some buushii
//whoever invented maths should square up

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';

class VpnDayNightLayer extends StatefulWidget {
  const VpnDayNightLayer({super.key});

  @override
  State<VpnDayNightLayer> createState() => _VpnDayNightLayerState();
}

class _VpnDayNightLayerState extends State<VpnDayNightLayer> {
  late DateTime _utcNow;
  late Timer _timer;
  ui.FragmentShader? _shader;
  ui.Image? _nightLights;

  @override
  void initState() {
    super.initState();
    _utcNow = DateTime.now().toUtc();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      setState(() => _utcNow = DateTime.now().toUtc());
    });
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    try {
      final results = await Future.wait([
        ui.FragmentProgram.fromAsset('assets/shaders/day_night.frag'),
        _loadImage('assets/images/night_lights.jpg'),
      ]);
      if (!mounted) return;
      setState(() {
        _shader = (results[0] as ui.FragmentProgram).fragmentShader();
        _nightLights = results[1] as ui.Image;
      });
    } catch (e) {
      debugPrint('VpnDayNightLayer: asset load failed: $e');
    }
  }

  Future<ui.Image> _loadImage(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  void dispose() {
    _timer.cancel();
    _nightLights?.dispose();
    super.dispose();
  }

  ({double lat, double lon}) _subsolarPoint(DateTime utc) {
    final dayOfYear =
        utc.difference(DateTime.utc(utc.year, 1, 1)).inDays + 1;
    final decl = -23.45 *
        math.cos(2 * math.pi * (dayOfYear + 10) / 365.0) *
        math.pi /
        180.0;
    final utcHours = utc.hour + utc.minute / 60.0 + utc.second / 3600.0;
    final sunLon = -(utcHours - 12.0) * 15.0;
    return (lat: decl * 180.0 / math.pi, lon: sunLon);
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    final nightLights = _nightLights;
    if (shader == null || nightLights == null) return const SizedBox.shrink();

    final sun = _subsolarPoint(_utcNow);

    return Builder(
      builder: (ctx) {
        final camera = MapCamera.of(ctx);
        final scale =
            256.0 * math.pow(2.0, camera.zoom) / (2.0 * math.pi);

        return SizedBox.expand(
          child: CustomPaint(
            painter: _DayNightPainter(
              shader: shader,
              nightLights: nightLights,
              sunLatRad: sun.lat * math.pi / 180.0,
              sunLonRad: sun.lon * math.pi / 180.0,
              centerLatRad: camera.center.latitude * math.pi / 180.0,
              centerLonRad: camera.center.longitude * math.pi / 180.0,
              scale: scale.toDouble(),
            ),
          ),
        );
      },
    );
  }
}

class _DayNightPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image nightLights;
  final double sunLatRad;
  final double sunLonRad;
  final double centerLatRad;
  final double centerLonRad;
  final double scale;

  const _DayNightPainter({
    required this.shader,
    required this.nightLights,
    required this.sunLatRad,
    required this.sunLonRad,
    required this.centerLatRad,
    required this.centerLonRad,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, sunLatRad);
    shader.setFloat(3, sunLonRad);
    shader.setFloat(4, centerLatRad);
    shader.setFloat(5, centerLonRad);
    shader.setFloat(6, scale);
    shader.setImageSampler(0, nightLights);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_DayNightPainter old) =>
      old.sunLatRad != sunLatRad ||
          old.sunLonRad != sunLonRad ||
          old.centerLatRad != centerLatRad ||
          old.centerLonRad != centerLonRad ||
          old.scale != scale;
}