import 'package:flutter/material.dart';

class FullVpnGradientService {
  static LinearGradient getDynamicBackground(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        c.primary.withOpacity(0.25),
        c.tertiary.withOpacity(0.10),
        c.surface.withOpacity(0.0),
      ],
      stops: const [0.0, 0.6, 1.0],
    );
  }

  static LinearGradient getDynamicButtonGradient(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        c.primaryContainer,
        c.secondaryContainer,
      ],
    );
  }
}