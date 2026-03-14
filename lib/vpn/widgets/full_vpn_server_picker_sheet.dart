import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import '../services/full_vpn_server_locations.dart';

class FullVpnServerPickerSheet extends StatefulWidget {
  final List<FullVpnServerLocation> privacyServers;
  final List<FullVpnServerLocation> obfuscationServers;
  final List<FullVpnServerLocation> stealthPlusServers;
  final String selectedServerId;
  final bool hasPro;
  final bool Function(FullVpnServerLocation server) isServerUnlocked;
  final String initialMode;
  final Future<void> Function(FullVpnServerLocation server, String transport) onSelect;

  const FullVpnServerPickerSheet({
    super.key,
    required this.privacyServers,
    required this.obfuscationServers,
    required this.stealthPlusServers,
    required this.selectedServerId,
    required this.hasPro,
    required this.initialMode,
    required this.isServerUnlocked,
    required this.onSelect,
  });

  @override
  State<FullVpnServerPickerSheet> createState() => _FullVpnServerPickerSheetState();
}

class _FullVpnServerPickerSheetState extends State<FullVpnServerPickerSheet> {
  late String _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialMode;
  }

  List<FullVpnServerLocation> get _servers {
    if (_tab == "obfuscation") return widget.obfuscationServers;
    if (_tab == "stealth_plus") return widget.stealthPlusServers;
    return widget.privacyServers;
  }

  bool get _tabLocked {
    if (_tab == "stealth_plus") return !widget.hasPro;
    return false;
  }

  String get _headline {
    if (_tab == "obfuscation") return "Obfuscation nodes";
    if (_tab == "stealth_plus") return "Stealth+ nodes";
    return "Privacy nodes";
  }

  String get _body {
    if (_tab == "obfuscation") {
      return widget.hasPro
          ? "Designed for networks that interfere with VPN connections. Helps maintain a stable connection when standard modes struggle."
          : "Designed for networks that interfere with VPN connections. One starter node is available on free accounts, additional nodes require Premium.";
    }
    if (_tab == "stealth_plus") {
      return "For restrictive or heavily monitored networks. Provides the most resilient connection when other modes cannot connect.";
    }
    return "Become anonymous on the internet and protect your privacy.";
  }

  String _transportForTab() {
    if (_tab == "obfuscation") return "amnezia";
    if (_tab == "stealth_plus") return "hysteria";
    return "wireguard";
  }

  IconData _iconForTab() {
    if (_tab == "obfuscation") return Icons.blur_on_rounded;
    if (_tab == "stealth_plus") return Icons.visibility_off_rounded;
    return Icons.public_rounded;
  }

  Color _tabBg(ColorScheme scheme) {
    if (_tab == "obfuscation") return const Color(0xFFB8860B).withValues(alpha: 0.16);
    if (_tab == "stealth_plus") return const Color(0xFF7C3AED).withValues(alpha: 0.18);
    return scheme.primary.withValues(alpha: 0.14);
  }

  Color _tabBorder(ColorScheme scheme) {
    if (_tab == "obfuscation") return const Color(0xFFB8860B).withValues(alpha: 0.34);
    if (_tab == "stealth_plus") return const Color(0xFF9F67FF).withValues(alpha: 0.42);
    return scheme.primary.withValues(alpha: 0.30);
  }

  Color _tabText(ColorScheme scheme) {
    if (_tab == "obfuscation") return const Color(0xFFFFE7A3);
    if (_tab == "stealth_plus") return const Color(0xFFE8D9FF);
    return scheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final servers = _servers;

    Widget tabButton({
      required String value,
      required String label,
      required bool locked,
    }) {
      final selected = _tab == value;
      final enabled = !locked;

      return Expanded(
        child: GestureDetector(
          onTap: enabled
              ? () {
            setState(() {
              _tab = value;
            });
          }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.16)
                  : scheme.surface.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.92)
                    : scheme.outlineVariant.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (locked) ...[
                  Icon(
                    Icons.lock_rounded,
                    size: 14,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: enabled ? 0.92 : 0.46),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget sectionIntro() {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.18),
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surfaceContainerHighest.withValues(alpha: 0.70),
              scheme.surface.withValues(alpha: 0.36),
            ],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _tabBg(scheme),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _tabBorder(scheme),
                ),
              ),
              child: Icon(
                _iconForTab(),
                color: _tabText(scheme),
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _headline,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  if (_tab == "stealth_plus" && _tabLocked) ...[
                    const SizedBox(height: 8),
                    const Text(
                      "Upgrade to Premium to unlock this mode.",
                      style: TextStyle(
                        color: Color(0xFFFFE7A3),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget serverTile(FullVpnServerLocation s) {
      final selected = s.id == widget.selectedServerId;
      final code = s.countryCode.toUpperCase();
      final unlocked = _tab == "privacy" ? true : widget.isServerUnlocked(s);

      return AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: unlocked ? 1 : 0.42,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected && unlocked
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.22),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: selected && unlocked
                  ? [
                scheme.primary.withValues(alpha: 0.18),
                scheme.surfaceContainerHighest.withValues(alpha: 0.68),
              ]
                  : [
                scheme.surfaceContainerHighest.withValues(alpha: 0.52),
                scheme.surface.withValues(alpha: 0.24),
              ],
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: CountryFlag.fromCountryCode(
              code,
              height: 22,
              width: 32,
            ),
            title: Text(
              s.label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: unlocked ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            subtitle: !unlocked
                ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "Premium",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFFFE7A3).withValues(alpha: 0.90),
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
                : null,
            trailing: selected && unlocked
                ? Icon(Icons.check_rounded, color: scheme.primary)
                : !unlocked
                ? Icon(Icons.lock_rounded, color: scheme.onSurfaceVariant)
                : Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.70),
            ),
            onTap: unlocked
                ? () async {
              await widget.onSelect(s, _transportForTab());
            }
                : null,
          ),
        ),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.66,
      minChildSize: 0.46,
      maxChildSize: 0.88,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Choose location",
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Pick the routing mode and location you want to use.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  tabButton(
                    value: "privacy",
                    label: "Privacy",
                    locked: false,
                  ),
                  const SizedBox(width: 8),
                  tabButton(
                    value: "obfuscation",
                    label: "Obfuscation",
                    locked: false,
                  ),
                  const SizedBox(width: 8),
                  tabButton(
                    value: "stealth_plus",
                    label: "Stealth+",
                    locked: !widget.hasPro,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              sectionIntro(),
              const SizedBox(height: 16),
              if (servers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    "No nodes available in this mode yet.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                ...servers.map(serverTile),
            ],
          ),
        );
      },
    );
  }
}