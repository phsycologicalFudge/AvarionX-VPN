import 'dart:math' as math;
import 'dart:ui';
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
  bool _showModeHint = false;
  final Set<String> _expandedCountries = {};

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

  String _transportForTab() {
    if (_tab == "obfuscation") return "amnezia";
    if (_tab == "stealth_plus") return "hysteria";
    return "wireguard";
  }

  String _titleForTab(String tab) {
    if (tab == "obfuscation") return "Obfuscation";
    if (tab == "stealth_plus") return "Stealth+";
    return "Privacy";
  }

  String _bodyForTab(String tab) {
    if (tab == "obfuscation") {
      return "Designed for networks that interfere with VPN connections and helps when standard routing struggles.";
    }
    if (tab == "stealth_plus") {
      return "Most resilient mode for restrictive or closely monitored networks.";
    }
    return "Standard routing mode for privacy, speed, and everyday use.";
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

  List<MapEntry<String, List<FullVpnServerLocation>>> _grouped() {
    final map = <String, List<FullVpnServerLocation>>{};
    final order = <String>[];
    for (final s in _servers) {
      final code = s.countryCode.toUpperCase();
      if (!map.containsKey(code)) {
        map[code] = [];
        order.add(code);
      }
      map[code]!.add(s);
    }
    return [for (final c in order) MapEntry(c, map[c]!)];
  }

  Widget _modeHint(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: child,
          ),
        );
      },
      child: !_showModeHint
          ? const SizedBox.shrink(key: ValueKey("hint_hidden"))
          : Padding(
        key: ValueKey(_tab),
        padding: const EdgeInsets.only(top: 14, bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _titleForTab(_tab),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.90),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _bodyForTab(_tab),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                height: 1.40,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget tabRow() {
      Widget tab({
        required String value,
        required String label,
        required bool locked,
      }) {
        final selected = _tab == value;
        final enabled = !locked;

        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled
                ? () => setState(() {
              _tab = value;
              _expandedCountries.clear();
            })
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(
                        alpha: enabled ? 0.45 : 0.25,
                      ),
                    ),
                  ),
                  if (locked) ...[
                    const SizedBox(width: 5),
                    Text(
                      "Pro",
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.28),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }

      final tabs = ["privacy", "obfuscation", "stealth_plus"];
      final selectedIndex = tabs.indexOf(_tab).clamp(0, 2);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              tab(value: "privacy", label: "Privacy", locked: false),
              tab(value: "obfuscation", label: "Obfuscation", locked: false),
              tab(value: "stealth_plus", label: "Stealth+", locked: !widget.hasPro),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final tabW = w / 3;
              return Stack(
                children: [
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    left: selectedIndex * tabW + tabW * 0.20,
                    top: 0,
                    child: Container(
                      width: tabW * 0.60,
                      height: 1,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );
    }

    Widget groupHeaderRow(String code, List<FullVpnServerLocation> group) {
      final isMulti = group.length > 1;
      final expanded = _expandedCountries.contains(code);
      final anySelected = group.any((s) => s.id == widget.selectedServerId);
      final unlocked = _tab == "privacy" ? true : widget.isServerUnlocked(group.first);

      return AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: unlocked ? 1.0 : 0.35,
        child: Container(
          color: anySelected && !isMulti
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: unlocked
                      ? () async {
                    final server = isMulti
                        ? group[math.Random().nextInt(group.length)]
                        : group.first;
                    await widget.onSelect(server, _transportForTab());
                  }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 13),
                    child: Row(
                      children: [
                        CountryFlag.fromCountryCode(code, height: 20, width: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _countryName(code),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: anySelected ? FontWeight.w800 : FontWeight.w600,
                              color: Colors.white.withValues(
                                alpha: unlocked ? (anySelected ? 1.0 : 0.85) : 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isMulti)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    if (expanded) {
                      _expandedCountries.remove(code);
                    } else {
                      _expandedCountries.add(code);
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    child: AnimatedRotation(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      turns: expanded ? 0.125 : 0,
                      child: Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: expanded ? 0.55 : 0.32),
                      ),
                    ),
                  ),
                )
              else if (!unlocked)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 15,
                    color: Colors.white.withValues(alpha: 0.30),
                  ),
                )
              else if (anySelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
            ],
          ),
        ),
      );
    }

    Widget citySubRow(FullVpnServerLocation s) {
      final selected = s.id == widget.selectedServerId;
      final unlocked = _tab == "privacy" ? true : widget.isServerUnlocked(s);
      final city = (s.city?.trim().isNotEmpty == true) ? s.city! : _countryName(s.countryCode);

      return InkWell(
        onTap: unlocked
            ? () async {
          await widget.onSelect(s, _transportForTab());
        }
            : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: unlocked ? 1.0 : 0.35,
          child: Container(
            padding: const EdgeInsets.only(left: 46, right: 10, top: 11, bottom: 11),
            color: selected
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: Colors.white.withValues(
                        alpha: unlocked ? (selected ? 0.95 : 0.55) : 0.35,
                      ),
                    ),
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget locationsList() {
      if (_servers.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            "No nodes available in this mode yet.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.35),
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }

      final groups = _grouped();
      final divider = Padding(
        padding: const EdgeInsets.only(left: 46),
        child: Divider(
          height: 1,
          thickness: 0.5,
          color: Colors.white.withValues(alpha: 0.06),
        ),
      );
      final subDivider = Padding(
        padding: const EdgeInsets.only(left: 46),
        child: Divider(
          height: 1,
          thickness: 0.5,
          color: Colors.white.withValues(alpha: 0.04),
        ),
      );

      final rows = <Widget>[];
      for (int i = 0; i < groups.length; i++) {
        final code = groups[i].key;
        final group = groups[i].value;
        final expanded = _expandedCountries.contains(code);

        if (i > 0) rows.add(divider);
        rows.add(groupHeaderRow(code, group));

        if (group.length > 1 && expanded) {
          for (final s in group) {
            rows.add(subDivider);
            rows.add(citySubRow(s));
          }
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.70,
      minChildSize: 0.46,
      maxChildSize: 0.92,
      builder: (_, controller) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0B1220).withValues(alpha: 0.72),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 3.5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          "Choose location",
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _showModeHint = !_showModeHint),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(
                            _showModeHint
                                ? Icons.close_rounded
                                : Icons.info_outline_rounded,
                            color: Colors.white.withValues(alpha: 0.38),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _modeHint(context),
                  const SizedBox(height: 18),
                  tabRow(),
                  const SizedBox(height: 16),
                  locationsList(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}