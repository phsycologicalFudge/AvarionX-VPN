import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:colourswift_av/vpn/services/twoDmapLighting/D/N_cycle.dart';

import 'full_vpn_server_locations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';

import 'animated_connecting_route_layer.dart';

const _displayPointOverrides = <String, LatLng>{
  'uk': LatLng(51.5074, -0.1278),
};

class FullVpnLocationMapCard extends StatefulWidget {
  final double? lat;
  final double? lon;
  final bool connected;
  final bool isConnecting;
  final String headerText;
  final List<FullVpnServerLocation> servers;
  final String? selectedServerId;
  final ValueChanged<FullVpnServerLocation>? onServerTap;
  final bool showFlagMarkers;

  const FullVpnLocationMapCard({
    super.key,
    required this.lat,
    required this.lon,
    required this.connected,
    required this.isConnecting,
    required this.headerText,
    this.servers = const [],
    this.selectedServerId,
    this.onServerTap,
    this.showFlagMarkers = false,
  });

  @override
  State<FullVpnLocationMapCard> createState() => _FullVpnLocationMapCardState();
}

class _FullVpnLocationMapCardState extends State<FullVpnLocationMapCard>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _pulseCtrl;
  late final AnimationController _focusCtrl;

  final GlobalKey _mapRepaintKey = GlobalKey();

  Uint8List? _snapshotPng;
  bool _snapshotVisible = false;
  Timer? _snapshotTimer;
  bool _snapshotInFlight = false;
  int _lastSnapshotMs = 0;

  late final FMTCStore _tileStore;
  late final FMTCTileProvider _tileProvider;
  bool _tileStoreReady = false;

  LatLng? _fromCenter;
  LatLng? _toCenter;
  double _fromZoom = 2.0;
  double _toZoom = 2.0;

  static const double _minZoom = 2.2;
  static const double _maxZoom = 6.2;

  static final LatLngBounds _worldBounds = LatLngBounds(
    const LatLng(-85.0, -180.0),
    const LatLng(85.0, 180.0),
  );

  bool _focusQueued = false;
  double _devicePixelRatio = 1.0;
  int _lastMoveMs = 0;
  LatLng? _lastMovedCenter;
  double _lastMovedZoom = -1;
  double _mapZoom = 2.0;
  String? _previewSelectedId;
  bool _userTouching = false;
  int _userTouchBlockUntilMs = 0;
  bool _forcedFocus = false;

  bool get _hasIpPoint {
    final la = widget.lat;
    final lo = widget.lon;
    if (la == null || lo == null) return false;
    if (!la.isFinite || !lo.isFinite) return false;
    return true;
  }

  LatLng _fallbackCenter() => const LatLng(20, 0);
  LatLng _ipCenter() => LatLng(widget.lat!, widget.lon!);

  String? get _effectiveSelectedId {
    final p = _previewSelectedId;
    if (p != null && p.isNotEmpty) return p;
    final w = widget.selectedServerId;
    if (w != null && w.isNotEmpty) return w;
    return null;
  }

  FullVpnServerLocation? _selectedServer() {
    final id = _effectiveSelectedId;
    if (id == null || id.isEmpty) return null;
    for (final s in widget.servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  FullVpnServerLocation? _nearestServer(LatLng p) {
    if (widget.servers.isEmpty) return null;
    const d = Distance();
    FullVpnServerLocation? best;
    double bestM = double.infinity;
    for (final s in widget.servers) {
      final m = d(p, s.point);
      if (m < bestM) {
        bestM = m;
        best = s;
      }
    }
    if (bestM <= 220000) return best;
    return null;
  }

  LatLng _midpoint(LatLng a, LatLng b) {
    final lat = (a.latitude + b.latitude) / 2.0;
    var diff = (b.longitude - a.longitude + 540.0) % 360.0 - 180.0;
    var lon = a.longitude + diff / 2.0;
    if (lon > 180.0) lon -= 360.0;
    if (lon < -180.0) lon += 360.0;
    return LatLng(lat, lon);
  }

  static const double _panelOffsetPx = 220.0;

  LatLng _applyPanelOffset(LatLng center, double zoom) {
    final latRad = center.latitude * math.pi / 180.0;
    final metersPerPx = (156543.03392 * math.cos(latRad)) / math.pow(2, zoom);
    const earthCircumference = 2 * math.pi * 6378137.0;
    final degreesPerPx = metersPerPx * (360.0 / earthCircumference);
    final latShift = _panelOffsetPx * degreesPerPx;
    final newLat = (center.latitude - latShift).clamp(-85.0, 85.0);
    return LatLng(newLat, center.longitude);
  }

  LatLng _focusCenter() {
    final s = _selectedServer();
    final zoom = _focusZoom();
    LatLng raw;
    if (!widget.connected && s != null) {
      raw = s.point;
    } else if (widget.isConnecting && _hasIpPoint && s != null) {
      raw = _midpoint(_ipCenter(), s.point);
    } else if (widget.connected && s != null) {
      raw = s.point;
    } else if (_hasIpPoint) {
      raw = _ipCenter();
    } else {
      raw = _fallbackCenter();
    }
    return _applyPanelOffset(raw, zoom);
  }

  double _focusZoom() {
    final s = _selectedServer();
    if (!widget.connected && s != null) return 4.8;
    if (widget.isConnecting && _hasIpPoint && s != null) return 2.8;
    if (widget.connected && s != null) return 5.6;
    if (_hasIpPoint) return 3.4;
    return 1.6;
  }

  @override
  void initState() {
    super.initState();
    _mapZoom = _clampZoom(_focusZoom());
    _mapController = MapController();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _focusCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..addListener(_tickFocus);
    _tileStore = const FMTCStore('cs_dark_cartodb');
    _tileProvider = FMTCTileProvider(
      stores: const {'cs_dark_cartodb': BrowseStoreStrategy.readUpdateCreate},
      loadingStrategy: BrowseLoadingStrategy.cacheFirst,
    );
    _initTileStore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _queueFocus(force: true);
      _captureSnapshotForABit(msVisible: 0);
    });
  }

  Future<void> _initTileStore() async {
    try {
      final ready = await _tileStore.manage.ready;
      if (!ready) await _tileStore.manage.create();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _tileStoreReady = true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
  }

  @override
  void dispose() {
    _snapshotTimer?.cancel();
    _focusCtrl.removeListener(_tickFocus);
    _focusCtrl.dispose();
    _pulseCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  double _clampZoom(double z) {
    if (z < _minZoom) return _minZoom;
    if (z > _maxZoom) return _maxZoom;
    return z;
  }

  LatLng _clampCenterToWorld(LatLng c) {
    final lat = c.latitude.clamp(-85.0, 85.0);
    final lon = c.longitude.clamp(-180.0, 180.0);
    return LatLng(lat, lon);
  }

  LatLng _safeCenter(LatLng c) {
    final lat = c.latitude.isFinite ? c.latitude : 20.0;
    final lon = c.longitude.isFinite ? c.longitude : 0.0;
    return _clampCenterToWorld(LatLng(lat, lon));
  }

  bool _closeEnough(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 0.00005 &&
        (a.longitude - b.longitude).abs() < 0.00005;
  }

  bool _userInteractionBlocked() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_userTouching) return true;
    return now < _userTouchBlockUntilMs;
  }

  void _tickFocus() {
    if (_fromCenter == null || _toCenter == null) return;
    if (!_forcedFocus && _userInteractionBlocked()) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastMoveMs < 16) return;
    final t = Curves.easeInOutCubic.transform(_focusCtrl.value);
    final lat = _lerp(_fromCenter!.latitude, _toCenter!.latitude, t);
    final lon = _lerp(_fromCenter!.longitude, _toCenter!.longitude, t);
    final z = _clampZoom(_lerp(_fromZoom, _toZoom, t));
    final nextCenter = _safeCenter(LatLng(lat, lon));
    final lastC = _lastMovedCenter;
    final lastZ = _lastMovedZoom;
    if (lastC != null) {
      if (_closeEnough(lastC, nextCenter) && (lastZ - z).abs() < 0.002) return;
    }
    _lastMoveMs = nowMs;
    _lastMovedCenter = nextCenter;
    _lastMovedZoom = z;
    try { _mapController.move(nextCenter, z); } catch (_) {}
    if (_focusCtrl.isCompleted) _forcedFocus = false;
  }

  void _queueFocus({bool force = false}) {
    if (!force && _userInteractionBlocked()) return;
    if (_focusQueued) return;
    _focusQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusQueued = false;
      if (!mounted) return;
      _animateFocus(force: force);
    });
  }

  void _animateFocus({bool force = false}) {
    if (!force && _userInteractionBlocked()) return;
    final toC = _safeCenter(_focusCenter());
    final toZ = _clampZoom(_focusZoom());
    MapCamera cam;
    try {
      cam = _mapController.camera;
    } catch (_) {
      return;
    }
    final fromC = _safeCenter(cam.center);
    final fromZ = _clampZoom(cam.zoom);
    if (_closeEnough(fromC, toC) && (fromZ - toZ).abs() < 0.002) return;
    _fromCenter = fromC;
    _toCenter = toC;
    _fromZoom = fromZ;
    _toZoom = toZ;
    _lastMoveMs = 0;
    _forcedFocus = force;
    _focusCtrl.stop();
    _focusCtrl.value = 0;
    _focusCtrl.forward();
  }

  void _zoomBy(double delta) {
    final cam = _mapController.camera;
    final zoom = _clampZoom(cam.zoom + delta);
    _mapController.move(cam.center, zoom);
    if ((_mapZoom - zoom).abs() > 0.05) {
      setState(() => _mapZoom = zoom);
    }
  }

  void _recenter() {
    _focusCtrl.stop();
    _previewSelectedId = null;
    _queueFocus(force: true);
  }

  Widget _mapControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget btn(IconData icon, VoidCallback onTap) {
      return Material(
        color: const Color(0xFF0B2545).withOpacity(0.78),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: scheme.onSurface.withOpacity(0.95), size: 20),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.add_rounded, () => _zoomBy(0.7)),
        const SizedBox(height: 10),
        btn(Icons.remove_rounded, () => _zoomBy(-0.7)),
        const SizedBox(height: 10),
        btn(Icons.my_location_rounded, _recenter),
      ],
    );
  }

  bool _changedDouble(double? a, double? b) {
    if (a == null || b == null) return a != b;
    return (a - b).abs() > 0.002;
  }

  Future<void> _captureSnapshotForABit({required int msVisible}) async {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSnapshotMs < 500) return;
    if (_snapshotInFlight) return;
    _snapshotInFlight = true;
    _lastSnapshotMs = now;
    try {
      final ctx = _mapRepaintKey.currentContext;
      if (ctx == null) { _snapshotInFlight = false; return; }
      final ro = ctx.findRenderObject();
      if (ro is! RenderRepaintBoundary) { _snapshotInFlight = false; return; }
      final img = await ro.toImage(pixelRatio: _devicePixelRatio);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (bd == null || !mounted) { _snapshotInFlight = false; return; }
      final bytes = bd.buffer.asUint8List();
      if (bytes.isEmpty) { _snapshotInFlight = false; return; }
      setState(() {
        _snapshotPng = bytes;
        _snapshotVisible = msVisible > 0;
      });
      _snapshotTimer?.cancel();
      if (msVisible > 0) {
        _snapshotTimer = Timer(Duration(milliseconds: msVisible), () {
          if (!mounted) return;
          setState(() => _snapshotVisible = false);
          Timer(const Duration(milliseconds: 220), () {
            if (!mounted) return;
            if (!_snapshotVisible) setState(() => _snapshotPng = null);
          });
        });
      }
    } catch (_) {
      if (mounted) setState(() { _snapshotVisible = false; _snapshotPng = null; });
    } finally {
      _snapshotInFlight = false;
    }
  }

  @override
  void didUpdateWidget(covariant FullVpnLocationMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final parentSelectedChanged = oldWidget.selectedServerId != widget.selectedServerId;
    if (parentSelectedChanged) {
      _previewSelectedId = null;
    } else {
      final p = _previewSelectedId;
      if (p != null && p.isNotEmpty) {
        final stillExists = widget.servers.any((s) => s.id == p);
        if (!stillExists) _previewSelectedId = null;
      }
    }
    final latChanged = _changedDouble(oldWidget.lat, widget.lat);
    final lonChanged = _changedDouble(oldWidget.lon, widget.lon);
    final connChanged = oldWidget.connected != widget.connected;
    final connectingChanged = oldWidget.isConnecting != widget.isConnecting;
    if (connChanged || connectingChanged) _captureSnapshotForABit(msVisible: 2400);
    if (latChanged || lonChanged || parentSelectedChanged) _queueFocus(force: parentSelectedChanged);
  }

  void _tapServer(FullVpnServerLocation s) {
    if (widget.onServerTap == null) return;
    _focusCtrl.stop();
    setState(() => _previewSelectedId = s.id);
    widget.onServerTap?.call(s);
    _queueFocus(force: true);
  }

  static String _countryCodeToEmoji(String code) {
    return code.toUpperCase().runes
        .map((r) => String.fromCharCode(r + 127397))
        .join();
  }

  LatLng _displayPoint(FullVpnServerLocation s) =>
      _displayPointOverrides[s.id] ?? s.point;

  List<_VisibleServerMarker> _visibleServerMarkers(String? selectedId) {
    if (_mapZoom >= 4.2) {
      final deduped = <_VisibleServerMarker>[];
      for (final s in widget.servers) {
        final dp = _displayPoint(s);
        final isDupe = deduped.any((m) =>
        m.countryCode == s.countryCode &&
            (m.point.latitude - dp.latitude).abs() < 0.5 &&
            (m.point.longitude - dp.longitude).abs() < 0.5,
        );
        if (isDupe) {
          if (s.id == selectedId) {
            deduped.removeWhere((m) =>
            m.countryCode == s.countryCode &&
                (m.point.latitude - dp.latitude).abs() < 0.5 &&
                (m.point.longitude - dp.longitude).abs() < 0.5,
            );
            deduped.add(_VisibleServerMarker(
              point: dp,
              countryCode: s.countryCode,
              selected: true,
              server: s,
            ));
          }
          continue;
        }
        deduped.add(_VisibleServerMarker(
          point: dp,
          countryCode: s.countryCode,
          selected: s.id == selectedId,
          server: s,
        ));
      }
      return deduped;
    }

    final byCountry = <String, List<FullVpnServerLocation>>{};
    for (final s in widget.servers) {
      final key = s.countryCode.toUpperCase();
      byCountry.putIfAbsent(key, () => []).add(s);
    }

    final visible = <_VisibleServerMarker>[];

    for (final entry in byCountry.entries) {
      final servers = entry.value;
      FullVpnServerLocation? selectedServer;

      for (final s in servers) {
        if (s.id == selectedId) {
          selectedServer = s;
          break;
        }
      }

      final target = selectedServer ?? servers.first;

      double lat = 0;
      double lonX = 0;
      double lonY = 0;

      for (final s in servers) {
        final p = _displayPoint(s);
        lat += p.latitude;
        final rad = p.longitude * math.pi / 180.0;
        lonX += math.cos(rad);
        lonY += math.sin(rad);
      }

      lat /= servers.length;
      final lon = math.atan2(lonY / servers.length, lonX / servers.length) * 180.0 / math.pi;

      visible.add(
        _VisibleServerMarker(
          point: LatLng(lat, lon),
          countryCode: target.countryCode,
          selected: selectedServer != null,
          server: target,
        ),
      );
    }

    return visible;
  }

  Widget _serverPin({
    required ColorScheme scheme,
    required bool selected,
    required bool connected,
    required VoidCallback? onTapDown,
    required String countryCode,
    required bool showFlag,
  }) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        final pulse = 0.5 + 0.5 * math.sin(_pulseCtrl.value * math.pi * 2);
        final pinColor = selected
            ? (connected ? const Color(0xFF4ADE80) : scheme.primary)
            : scheme.primary.withOpacity(0.65);
        final glowOpacity = selected ? (0.22 + 0.18 * pulse) : (0.08 + 0.07 * pulse);
        final glowSize = selected ? (44.0 + 8.0 * pulse) : (28.0 + 4.0 * pulse);
        final circleSize = selected ? 28.0 : 22.0;

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => onTapDown?.call(),
          child: SizedBox(
            width: 54,
            height: 60,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: glowSize,
                      height: glowSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: pinColor.withOpacity(glowOpacity),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: math.max(0, (glowSize - circleSize) / 2 - 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: circleSize,
                        height: circleSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pinColor,
                          border: Border.all(
                            color: Colors.white.withOpacity(selected ? 0.9 : 0.55),
                            width: selected ? 2.0 : 1.5,
                          ),
                          boxShadow: selected
                              ? [BoxShadow(color: pinColor.withOpacity(0.5), blurRadius: 10, spreadRadius: 1)]
                              : [],
                        ),
                        child: showFlag
                            ? Center(
                          child: Text(
                            _countryCodeToEmoji(countryCode),
                            style: TextStyle(fontSize: selected ? 13 : 10, height: 1),
                          ),
                        )
                            : null,
                      ),
                      CustomPaint(
                        size: Size(selected ? 8.0 : 6.0, selected ? 7.0 : 5.0),
                        painter: _TrianglePainter(color: pinColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectedId = _effectiveSelectedId;

    final markers = <Marker>[];
    final visibleServers = _visibleServerMarkers(selectedId);

    for (final s in visibleServers) {
      markers.add(
        Marker(
          point: s.point,
          width: 54,
          height: 60,
          alignment: Alignment.bottomCenter,
          child: _serverPin(
            scheme: scheme,
            selected: s.selected,
            connected: widget.connected,
            onTapDown: () => _tapServer(s.server),
            countryCode: s.countryCode,
            showFlag: widget.showFlagMarkers,
          ),
        ),
      );
    }

    final sel = _selectedServer();
    final showRoute = _hasIpPoint && sel != null && (widget.isConnecting || widget.connected);
    final tileProvider = _tileStoreReady ? _tileProvider : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          if (_snapshotPng != null)
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: _snapshotVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: Image.memory(
                  _snapshotPng!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                ),
              ),
            ),
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                _userTouching = true;
                _userTouchBlockUntilMs = DateTime.now().millisecondsSinceEpoch + 900;
              },
              onPointerUp: (_) {
                _userTouching = false;
                _userTouchBlockUntilMs = DateTime.now().millisecondsSinceEpoch + 650;
              },
              onPointerCancel: (_) {
                _userTouching = false;
                _userTouchBlockUntilMs = DateTime.now().millisecondsSinceEpoch + 650;
              },
              child: RepaintBoundary(
                key: _mapRepaintKey,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _safeCenter(_focusCenter()),
                    initialZoom: _clampZoom(_focusZoom()),
                    minZoom: _minZoom,
                    maxZoom: _maxZoom,
                    backgroundColor: const Color(0xFF0B1626),
                    cameraConstraint: CameraConstraint.contain(bounds: _worldBounds),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom,
                    ),
                    onMapEvent: (e) {
                      final zoom = e.camera.zoom;
                      if ((_mapZoom - zoom).abs() > 0.05) {
                        setState(() => _mapZoom = zoom);
                      }

                      if (e is MapEventMoveEnd) {
                        if (_snapshotVisible) {
                          setState(() => _snapshotVisible = false);
                          Timer(const Duration(milliseconds: 220), () {
                            if (!mounted) return;
                            if (!_snapshotVisible) setState(() => _snapshotPng = null);
                          });
                        }
                      }
                    },
                    onTap: (_, p) {
                      final s = _nearestServer(p);
                      if (s == null) return;
                      _tapServer(s);
                    },
                  ),
                  children: [
                    ColorFiltered(
                      colorFilter: ColorFilter.matrix([
                        0.38, 0.00, 0.00, 0,  8,
                        0.00, 0.42, 0.00, 0, 14,
                        0.00, 0.00, 0.88, 0, 26,
                        0.00, 0.00, 0.00, 1,  0,
                      ]),
                      child: TileLayer(
                        urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png',
                        subdomains: const ['a', 'b', 'c', 'd'],
                        userAgentPackageName: 'com.colourswift.avarionxvpn',
                        maxZoom: _maxZoom,
                        maxNativeZoom: 6,
                        keepBuffer: 6,
                        tileProvider: tileProvider,
                        tileDisplay: const TileDisplay.instantaneous(),
                      ),
                    ),
                    const VpnDayNightLayer(),
                    if (showRoute)
                      AnimatedConnectingRouteLayer(
                        from: _ipCenter(),
                        to: sel!.point,
                        animate: widget.isConnecting,
                      ),
                    if (markers.isNotEmpty) MarkerLayer(markers: markers),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0B1626).withOpacity(0.52),
                      const Color(0xFF0B1626).withOpacity(0.06),
                      const Color(0xFF0B1626).withOpacity(0.52),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: SafeArea(
              child: _mapControls(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisibleServerMarker {
  final LatLng point;
  final String countryCode;
  final bool selected;
  final FullVpnServerLocation server;

  const _VisibleServerMarker({
    required this.point,
    required this.countryCode,
    required this.selected,
    required this.server,
  });
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}