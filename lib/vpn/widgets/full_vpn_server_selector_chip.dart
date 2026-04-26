import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import '../services/full_vpn_server_locations.dart';

class FullVpnServerSelectorChip extends StatelessWidget {
  final List<FullVpnServerLocation> servers;
  final String selectedServerId;
  final int? regionLoad;
  final bool connected;
  final VoidCallback? onTap;

  const FullVpnServerSelectorChip({
    super.key,
    required this.servers,
    required this.selectedServerId,
    required this.regionLoad,
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

  Color _loadColor(int load) {
    if (load >= 75) return const Color(0xFFFF7A7A);
    if (load >= 45) return const Color(0xFFFFBB55);
    return Colors.white.withValues(alpha: 0.55);
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
          child: Row(
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
              if (regionLoad != null) ...[
                Text(
                  '$regionLoad% load',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _loadColor(regionLoad!),
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}