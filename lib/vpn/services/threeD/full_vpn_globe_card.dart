import 'dart:math' as math;
import 'package:colourswift_av/vpn/services/full_vpn_server_locations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_globe_3d/flutter_globe_3d.dart';
import 'full_vpn_globe_controller.dart';
import 'full_vpn_globe_markers.dart';

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

  String? _lastAppliedFocusKey;

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

  String? get _effectiveSelectedId {
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
        selected.point.latitude,
        selected.point.longitude,
      );
    }
    if (_hasIpPoint) {
      return _GlobeFocusData(
        'ip:${widget.lat!.toStringAsFixed(4)}:${widget.lon!.toStringAsFixed(4)}',
        widget.lat!,
        widget.lon!,
      );
    }
    return _GlobeFocusData('fallback', 20, 0);
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

    _populateScene();

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

  void _rebuildScene() {
    final newController = buildFullVpnEarthController();
    final selectedId = _effectiveSelectedId;

    for (final server in widget.servers) {
      newController.addNode(
        EarthNode(
          id: server.id,
          latitude: server.point.latitude,
          longitude: server.point.longitude,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _focusServerNow(server);
              widget.onServerTap?.call(server);
            },
            child: FullVpnGlobeServerMarker(
              selected: server.id == selectedId,
              connected: widget.connected,
              countryCode: server.countryCode,
              showFlag: widget.showFlagMarkers,
            ),
          ),
        ),
      );
    }

    if (_hasIpPoint) {
      newController.addNode(
        EarthNode(
          id: '__user_ip__',
          latitude: widget.lat!,
          longitude: widget.lon!,
          child: const FullVpnGlobeUserMarker(),
        ),
      );
    }

    final selected = _selectedServer;
    if (_hasIpPoint && selected != null) {
      newController.connect(
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

    final oldController = _controller;
    _controller = newController;
    _controller.setCameraFocus(_currentLat, _currentLon);

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      oldController.dispose();
    });
  }

  void _populateScene() {
    final selectedId = _effectiveSelectedId;
    for (final server in widget.servers) {
      _controller.addNode(
        EarthNode(
          id: server.id,
          latitude: server.point.latitude,
          longitude: server.point.longitude,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _focusServerNow(server);
              widget.onServerTap?.call(server);
            },
            child: FullVpnGlobeServerMarker(
              selected: server.id == selectedId,
              connected: widget.connected,
              countryCode: server.countryCode,
              showFlag: widget.showFlagMarkers,
            ),
          ),
        ),
      );
    }

    if (_hasIpPoint) {
      _controller.addNode(
        EarthNode(
          id: '__user_ip__',
          latitude: widget.lat!,
          longitude: widget.lon!,
          child: const FullVpnGlobeUserMarker(),
        ),
      );
    }

    final selected = _selectedServer;
    if (_hasIpPoint && selected != null) {
      _controller.connect(
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
    _lastAppliedFocusKey = 'server:${server.id}';
    _fromLat = _currentLat;
    _fromLon = _currentLon;
    _toLat = server.point.latitude;
    _toLon = server.point.longitude;
    _focusCtrl.stop();
    _focusCtrl.value = 0.0;
    _focusCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.black)),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final diameter = math.max(constraints.maxWidth, constraints.maxHeight) * 1.3;
                return InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 3.5,
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