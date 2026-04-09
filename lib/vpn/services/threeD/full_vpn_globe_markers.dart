import 'package:flutter/material.dart';

class FullVpnGlobeServerMarker extends StatelessWidget {
  final bool selected;
  final bool connected;

  const FullVpnGlobeServerMarker({
    super.key,
    required this.selected,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
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