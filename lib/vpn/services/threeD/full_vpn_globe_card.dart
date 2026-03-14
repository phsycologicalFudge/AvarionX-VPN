import 'dart:math' as math;
import 'package:colourswift_av/vpn/services/full_vpn_server_locations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_globe_3d/flutter_globe_3d.dart';

class FullVpnGlobeCard extends StatefulWidget {
  final double? lat;
  final double? lon;
  final bool connected;
  final bool isConnecting;
  final String headerText;
  final List<FullVpnServerLocation> servers;
  final String? selectedServerId;
  final ValueChanged<FullVpnServerLocation>? onServerTap;

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
  });

  @override
  State<FullVpnGlobeCard> createState() => _FullVpnGlobeCardState();
}

class _FullVpnGlobeCardState extends State<FullVpnGlobeCard> {
  late EarthController _controller;
  bool _sceneReady = false;
  int _sceneVersion = 0;
  String? _lastFocusKey;

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

  FullVpnServerLocation? _selectedServer() {
    final id = _effectiveSelectedId;
    if (id == null) return null;
    for (final s in widget.servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  double _midLat(double a, double b) => (a + b) / 2.0;

  double _midLon(double a, double b) {
    var diff = (b - a + 540.0) % 360.0 - 180.0;
    var mid = a + diff / 2.0;
    if (mid > 180.0) mid -= 360.0;
    if (mid < -180.0) mid += 360.0;
    return mid;
  }

  double get _focusLat {
    final selected = _selectedServer();

    if (!widget.connected && selected != null) {
      return selected.point.latitude;
    }

    if (widget.isConnecting && _hasIpPoint && selected != null) {
      return _midLat(widget.lat!, selected.point.latitude);
    }

    if (widget.connected && selected != null) {
      return selected.point.latitude;
    }

    if (_hasIpPoint) {
      return widget.lat!;
    }

    return 20.0;
  }

  double get _focusLon {
    final selected = _selectedServer();

    if (!widget.connected && selected != null) {
      return selected.point.longitude;
    }

    if (widget.isConnecting && _hasIpPoint && selected != null) {
      return _midLon(widget.lon!, selected.point.longitude);
    }

    if (widget.connected && selected != null) {
      return selected.point.longitude;
    }

    if (_hasIpPoint) {
      return widget.lon!;
    }

    return 0.0;
  }

  String get _focusKey =>
      '${_focusLat.toStringAsFixed(4)}:${_focusLon.toStringAsFixed(4)}:${widget.connected}:${widget.isConnecting}:${_effectiveSelectedId ?? ''}';

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
    _populateScene(_controller);
    _sceneReady = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyFocusIfNeeded(force: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FullVpnGlobeCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final selectedChanged = oldWidget.selectedServerId != widget.selectedServerId;
    final connectedChanged = oldWidget.connected != widget.connected;
    final connectingChanged = oldWidget.isConnecting != widget.isConnecting;
    final latChanged = oldWidget.lat != widget.lat;
    final lonChanged = oldWidget.lon != widget.lon;
    final serverCountChanged = oldWidget.servers.length != widget.servers.length;
    final serverIdsChanged = !_sameServerIds(oldWidget.servers, widget.servers);

    if (selectedChanged ||
        connectedChanged ||
        connectingChanged ||
        latChanged ||
        lonChanged ||
        serverCountChanged ||
        serverIdsChanged) {
      _rebuildScene();
    }

    if (selectedChanged || connectedChanged || connectingChanged || latChanged || lonChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyFocusIfNeeded();
      });
    }
  }

  bool _sameServerIds(
      List<FullVpnServerLocation> a,
      List<FullVpnServerLocation> b,
      ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  EarthController _buildController() {
    final controller = EarthController();
    controller.rotateSpeed = 0;
    controller.enableAutoRotate = false;
    controller.minZoom = 0.75;
    controller.setLightMode(EarthLightMode.fixedCoordinates);
    controller.setFixedLightCoordinates(18.0, -35.0);
    return controller;
  }

  void _rebuildScene() {
    final oldController = _controller;
    _controller = _buildController();
    _populateScene(_controller);
    _sceneVersion++;
    _sceneReady = true;
    setState(() {});
    oldController.dispose();
  }

  void _applyFocusIfNeeded({bool force = false}) {
    final nextKey = _focusKey;
    if (!force && _lastFocusKey == nextKey) return;
    _lastFocusKey = nextKey;
    _controller.setCameraFocus(_focusLat, _focusLon);
  }

  void _populateScene(EarthController controller) {
    final selectedId = _effectiveSelectedId;

    for (final server in widget.servers) {
      final isSelected = server.id == selectedId;

      controller.addNode(
        EarthNode(
          id: server.id,
          latitude: server.point.latitude,
          longitude: server.point.longitude,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onServerTap?.call(server),
            child: _serverMarker(
              selected: isSelected,
              connected: widget.connected,
            ),
          ),
        ),
      );
    }

    if (_hasIpPoint) {
      controller.addNode(
        EarthNode(
          id: '__user_ip__',
          latitude: widget.lat!,
          longitude: widget.lon!,
          child: _userMarker(),
        ),
      );
    }

    final selected = _selectedServer();
    final showRoute = _hasIpPoint &&
        selected != null &&
        (widget.connected || widget.isConnecting);

    if (showRoute) {
      controller.connect(
        EarthConnection(
          fromId: '__user_ip__',
          toId: selected.id,
          color: widget.connected
              ? Colors.greenAccent
              : const Color(0xFF60A5FA),
          width: widget.connected ? 2.4 : 2.0,
          isDashed: widget.isConnecting,
          showArrow: widget.isConnecting,
        ),
      );
    }
  }

  Widget _serverMarker({
    required bool selected,
    required bool connected,
  }) {
    final dotColor = selected
        ? (connected ? Colors.greenAccent : const Color(0xFF60A5FA))
        : const Color(0xFF7DB7FF);

    return Container(
      width: selected ? 18 : 14,
      height: selected ? 18 : 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dotColor,
        border: Border.all(
          color: Colors.white.withOpacity(0.92),
          width: selected ? 2.2 : 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: dotColor.withOpacity(0.45),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _userMarker() {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: const Color(0xFF60A5FA),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.35),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(color: Colors.black),
          ),
          Positioned.fill(
            child: _sceneReady
                ? LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                final diameter = math.max(width, height) * 1.28;

                return OverflowBox(
                  maxWidth: diameter,
                  maxHeight: diameter,
                  alignment: Alignment.center,
                  child: Center(
                    child: Earth3D(
                      key: ValueKey(_sceneVersion),
                      controller: _controller,
                      initialScale: 3.25,
                      texture: const AssetImage(
                        'assets/globe/earth_minimal_vpn_texture.png',
                      ),
                      size: Size(diameter, diameter),
                    ),
                  ),
                );
              },
            )
                : const SizedBox.shrink(),
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
                      Colors.black.withOpacity(0.55),
                      Colors.black.withOpacity(0.10),
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