import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import '../services/full_vpn_server_locations.dart';

class FullVpnServerSelectorChip extends StatelessWidget {
  final List<FullVpnServerLocation> servers;
  final String selectedServerId;
  final String currentModeLabel;
  final bool connected;
  final VoidCallback? onTap;

  const FullVpnServerSelectorChip({
    super.key,
    required this.servers,
    required this.selectedServerId,
    required this.currentModeLabel,
    required this.connected,
    required this.onTap,
  });

  FullVpnServerLocation? _findSelected() {
    for (final s in servers) {
      if (s.id == selectedServerId) return s;
    }
    return null;
  }

  String _displayName(FullVpnServerLocation s) {
    final city = s.city?.trim() ?? "";
    if (city.isNotEmpty) return city;
    return _countryName(s.countryCode);
  }

  String _countryName(String code) {
    switch (code.toUpperCase()) {
      case "US": return "United States";
      case "GB": return "United Kingdom";
      case "JP": return "Japan";
      case "DE": return "Germany";
      case "SG": return "Singapore";
      case "FI": return "Finland";
      case "FR": return "France";
      case "CA": return "Canada";
      case "PL": return "Poland";
      case "NL": return "Netherlands";
      case "AU": return "Australia";
      case "ES": return "Spain";
      default: return code.toUpperCase();
    }
  }

  Color _modeBg() {
    if (currentModeLabel == "Stealth+") {
      return const Color(0xFF7C3AED).withValues(alpha: 0.18);
    }
    if (currentModeLabel == "Obfuscation") {
      return const Color(0xFFB8860B).withValues(alpha: 0.16);
    }
    return const Color(0xFF60A5FA).withValues(alpha: 0.14);
  }

  Color _modeBorder() {
    if (currentModeLabel == "Stealth+") {
      return const Color(0xFF9F67FF).withValues(alpha: 0.40);
    }
    if (currentModeLabel == "Obfuscation") {
      return const Color(0xFFB8860B).withValues(alpha: 0.34);
    }
    return const Color(0xFF60A5FA).withValues(alpha: 0.32);
  }

  Color _modeText() {
    if (currentModeLabel == "Stealth+") {
      return const Color(0xFFE8D9FF);
    }
    if (currentModeLabel == "Obfuscation") {
      return const Color(0xFFFFE7A3);
    }
    return const Color(0xFFBFDBFE);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (servers.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: scheme.surface.withValues(alpha: 0.18),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              "Loading servers...",
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final selected = _findSelected() ?? servers.first;
    final countryCode = selected.countryCode.toUpperCase();
    final displayName = _displayName(selected);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.18),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.055),
                scheme.surface.withValues(alpha: 0.16),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                spreadRadius: -10,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!connected) ...[
              ],
              Row(
                children: [
                  CountryFlag.fromCountryCode(
                    countryCode,
                    height: 24,
                    width: 34,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: _modeBg(),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _modeBorder(),
                      ),
                    ),
                    child: Text(
                      currentModeLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: _modeText(),
                        fontWeight: FontWeight.w900,
                        height: 1,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
                    size: 22,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}