import 'package:flutter/material.dart';

class FullVpnGlobeServerMarker extends StatelessWidget {
  final bool selected;
  final bool connected;
  final String countryCode;
  final bool showFlag;

  const FullVpnGlobeServerMarker({
    super.key,
    required this.selected,
    required this.connected,
    required this.countryCode,
    required this.showFlag,
  });

  static String _toFlagEmoji(String code) {
    return code.toUpperCase().runes
        .map((r) => String.fromCharCode(r + 127397))
        .join();
  }

  @override
  Widget build(BuildContext context) {
    if (showFlag) {
      return _FlagMarker(
        countryCode: countryCode,
        selected: selected,
        connected: connected,
      );
    }

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
}

class _FlagMarker extends StatelessWidget {
  final String countryCode;
  final bool selected;
  final bool connected;

  const _FlagMarker({
    required this.countryCode,
    required this.selected,
    required this.connected,
  });

  static String _toFlagEmoji(String code) {
    return code.toUpperCase().runes
        .map((r) => String.fromCharCode(r + 127397))
        .join();
  }

  @override
  Widget build(BuildContext context) {
    final size = selected ? 26.0 : 20.0;
    final borderColor = selected
        ? (connected ? Colors.greenAccent : const Color(0xFF60A5FA))
        : Colors.white.withOpacity(0.7);
    final glowColor = selected
        ? (connected ? Colors.greenAccent : const Color(0xFF60A5FA))
        : Colors.white;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(0.35),
        border: Border.all(color: borderColor, width: selected ? 2.0 : 1.5),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(selected ? 0.4 : 0.15),
            blurRadius: selected ? 12 : 6,
            spreadRadius: 0,
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Center(
        child: Text(
          _toFlagEmoji(countryCode),
          style: TextStyle(fontSize: selected ? 14 : 10, height: 1),
        ),
      ),
    );
  }
}

class FullVpnGlobeUserMarker extends StatelessWidget {
  const FullVpnGlobeUserMarker({super.key});

  @override
  Widget build(BuildContext context) {
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
}