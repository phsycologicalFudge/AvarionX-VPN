import 'dart:math' as math;
import 'package:colourswift_av/vpn/services/full_vpn_server_locations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_globe_3d/flutter_globe_3d.dart';
import 'full_vpn_globe_controller.dart';
import 'full_vpn_globe_markers.dart';

const _displayOverrides = <String, List<double>>{
  'uk': [51.5074, -0.1278],
};

class FullVpnGlobeCard extends StatefulWidget {
  final double? lat;
  final double? lon;
  final bool connected;
  final bool isConnecting;
  final String headerText;
  final List<FullVpnServerLocation> servers;
  final String? selectedServerId;
  final ValueChanged<FullVpnServerLocation>? onServerTap;
  final bool showFlagMarkers;

  const FullVpnGlobeCard({
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
  State<FullVpnGlobeCard> createState() => _FullVpnGlobeCardState();
}

class _FullVpnGlobeCardState extends State<FullVpnGlobeCard>
    with SingleTickerProviderStateMixin {
  late EarthController _controller;
  late final AnimationController _focusCtrl;

  static const double _panelLatOffset = 12.0;

  String? _lastAppliedFocusKey;
  String? _previewSelectedId;

  double _currentLat = 20.0;
  double _currentLon = 0.0;
  double _fromLat = 20.0;
  double _fromLon = 0.0;
  double _toLat = 20.0;
  double _toLon = 0.0;

  bool get _hasIpPoint {
    final la = widget.lat;
    final lo = widget.lon;
    if (la == null || lo == null) return false;
    if (!la.isFinite || !lo.isFinite) return false;
    return true;
  }

  double _displayLat(FullVpnServerLocation s) =>
      _displayOverrides[s.id]?[0] ?? s.point.latitude;

  double _displayLon(FullVpnServerLocation s) =>
      _displayOverrides[s.id]?[1] ?? s.point.longitude;

  String? get _effectiveSelectedId {
    final p = _previewSelectedId;
    if (p != null && p.isNotEmpty) return p;
    final id = widget.selectedServerId;
    if (id == null || id.isEmpty) return null;
    return id;
  }

  FullVpnServerLocation? get _selectedServer {
    final id = _effectiveSelectedId;
    if (id == null) return null;
    for (final server in widget.servers) {
      if (server.id == id) return server;
    }
    return null;
  }

  _GlobeFocusData get _focusData {
    final selected = _selectedServer;
    if (selected != null) {
      return _GlobeFocusData(
        'server:${selected.id}',
        _displayLat(selected) - _panelLatOffset,
        _displayLon(selected),
      );
    }
    if (_hasIpPoint) {
      return _GlobeFocusData(
        'ip:${widget.lat!.toStringAsFixed(4)}:${widget.lon!.toStringAsFixed(4)}',
        widget.lat! - _panelLatOffset,
        widget.lon!,
      );
    }
    return _GlobeFocusData('fallback', 20.0 - _panelLatOffset, 0.0);
  }

  @override
  void initState() {
    super.initState();

    final focus = _focusData;
    _currentLat = focus.latitude;
    _currentLon = focus.longitude;
    _fromLat = _currentLat;
    _fromLon = _currentLon;
    _toLat = _currentLat;
    _toLon = _currentLon;

    _controller = buildFullVpnEarthController();
    _focusCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..addListener(_tickFocus);

    _buildServerNodes(_controller, _effectiveSelectedId);
    _buildIpNode(_controller);
    _buildConnection(_controller);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.setCameraFocus(_currentLat, _currentLon);
      _lastAppliedFocusKey = _focusData.key;
    });
  }

  @override
  void dispose() {
    _focusCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FullVpnGlobeCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final selectedChanged = oldWidget.selectedServerId != widget.selectedServerId;
    final latChanged = oldWidget.lat != widget.lat;
    final lonChanged = oldWidget.lon != widget.lon;
    final serverIdsChanged = !_sameServerIds(oldWidget.servers, widget.servers);
    final connectionChanged = oldWidget.connected != widget.connected ||
        oldWidget.isConnecting != widget.isConnecting;
    final flagMarkersChanged = oldWidget.showFlagMarkers != widget.showFlagMarkers;

    final oldHadIpPoint = oldWidget.lat != null && oldWidget.lon != null &&
        oldWidget.lat!.isFinite && oldWidget.lon!.isFinite;
    final ipPresenceChanged = oldHadIpPoint != _hasIpPoint;

    if (selectedChanged) {
      _previewSelectedId = null;
    }

    if (selectedChanged || serverIdsChanged || ipPresenceChanged || connectionChanged || flagMarkersChanged) {
      _rebuildScene();
    }

    if (selectedChanged || ((latChanged || lonChanged) && _selectedServer == null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyFocus(force: true);
      });
    }
  }

  bool _sameServerIds(List<FullVpnServerLocation> a, List<FullVpnServerLocation> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _buildServerNodes(EarthController controller, String? selectedId) {
    final deduped = <_DedupeEntry>[];

    for (final s in widget.servers) {
      final dlat = _displayLat(s);
      final dlon = _displayLon(s);
      final cc = s.countryCode.toUpperCase();
      final isDupe = deduped.any((m) =>
      m.cc == cc &&
          (m.lat - dlat).abs() < 0.5 &&
          (m.lon - dlon).abs() < 0.5,
      );
      if (isDupe) {
        if (s.id == selectedId) {
          deduped.removeWhere((m) =>
          m.cc == cc &&
              (m.lat - dlat).abs() < 0.5 &&
              (m.lon - dlon).abs() < 0.5,
          );
          deduped.add(_DedupeEntry(id: s.id, cc: cc, lat: dlat, lon: dlon, server: s));
        }
        continue;
      }
      deduped.add(_DedupeEntry(id: s.id, cc: cc, lat: dlat, lon: dlon, server: s));
    }

    for (final entry in deduped) {
      controller.addNode(
        EarthNode(
          id: entry.id,
          latitude: entry.lat,
          longitude: entry.lon,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _focusServerNow(entry.server);
              widget.onServerTap?.call(entry.server);
            },
            child: FullVpnGlobeServerMarker(
              selected: entry.id == selectedId,
              connected: widget.connected,
              countryCode: entry.server.countryCode,
              showFlag: widget.showFlagMarkers,
            ),
          ),
        ),
      );
    }
  }

  void _buildIpNode(EarthController controller) {
    if (!_hasIpPoint) return;
    controller.addNode(
      EarthNode(
        id: '__user_ip__',
        latitude: widget.lat!,
        longitude: widget.lon!,
        child: const FullVpnGlobeUserMarker(),
      ),
    );
  }

  void _buildConnection(EarthController controller) {
    final selected = _selectedServer;
    if (!_hasIpPoint || selected == null) return;
    controller.connect(
      EarthConnection(
        fromId: '__user_ip__',
        toId: selected.id,
        color: widget.connected ? Colors.greenAccent : const Color(0xFF60A5FA),
        width: 1.9,
        isDashed: false,
        showArrow: false,
      ),
    );
  }

  void _rebuildScene() {
    final newController = buildFullVpnEarthController();
    _buildServerNodes(newController, _effectiveSelectedId);
    _buildIpNode(newController);
    _buildConnection(newController);

    final oldController = _controller;
    _controller = newController;
    _controller.setCameraFocus(_currentLat, _currentLon);

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      oldController.dispose();
    });
  }

  void _tickFocus() {
    final t = Curves.easeInOutCubic.transform(_focusCtrl.value);
    _currentLat = _fromLat + (_toLat - _fromLat) * t;
    _currentLon = _lerpLongitude(_fromLon, _toLon, t);
    _controller.setCameraFocus(_currentLat, _currentLon);
  }

  double _lerpLongitude(double a, double b, double t) {
    double delta = b - a;
    if (delta > 180.0) delta -= 360.0;
    if (delta < -180.0) delta += 360.0;
    double value = a + delta * t;
    while (value > 180.0) value -= 360.0;
    while (value < -180.0) value += 360.0;
    return value;
  }

  void _applyFocus({bool force = false}) {
    final focus = _focusData;
    if (!force && _lastAppliedFocusKey == focus.key) return;
    _lastAppliedFocusKey = focus.key;
    _fromLat = _currentLat;
    _fromLon = _currentLon;
    _toLat = focus.latitude;
    _toLon = focus.longitude;
    _focusCtrl.stop();
    _focusCtrl.value = 0.0;
    _focusCtrl.forward();
  }

  void _focusServerNow(FullVpnServerLocation server) {
    _previewSelectedId = server.id;
    _lastAppliedFocusKey = 'server:${server.id}';
    _fromLat = _currentLat;
    _fromLon = _currentLon;
    _toLat = _displayLat(server) - _panelLatOffset;
    _toLon = _displayLon(server);
    _focusCtrl.stop();
    _focusCtrl.value = 0.0;
    _focusCtrl.forward();
    _rebuildScene();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFF050A12))),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final diameter = math.max(constraints.maxWidth, constraints.maxHeight) * 1.3;
                return InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 1.0,
                  panEnabled: false,
                  child: OverflowBox(
                    maxWidth: diameter,
                    maxHeight: diameter,
                    alignment: Alignment.center,
                    child: Center(
                      child: Earth3D(
                        controller: _controller,
                        initialScale: 3.25,
                        initialLatitude: _currentLat,
                        initialLongitude: _currentLon,
                        texture: const AssetImage('assets/globe/earth_minimal_vpn_texture.png'),
                        size: Size(diameter, diameter),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.55),
                      Colors.transparent,
                      Colors.black.withOpacity(0.55),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobeFocusData {
  final String key;
  final double latitude;
  final double longitude;
  _GlobeFocusData(this.key, this.latitude, this.longitude);
}

class _DedupeEntry {
  final String id;
  final String cc;
  final double lat;
  final double lon;
  final FullVpnServerLocation server;

  const _DedupeEntry({
    required this.id,
    required this.cc,
    required this.lat,
    required this.lon,
    required this.server,
  });
}