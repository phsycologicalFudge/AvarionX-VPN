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
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = widget.initialMode;
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FullVpnServerLocation> get _servers {
    if (_tab == "obfuscation") return widget.obfuscationServers;
    if (_tab == "stealth_plus") return widget.stealthPlusServers;
    return widget.privacyServers;
  }

  List<FullVpnServerLocation> get _filteredServers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _servers;
    return _servers.where((s) {
      return s.label.toLowerCase().contains(query) ||
          s.countryCode.toLowerCase().contains(query);
    }).toList();
  }

  String _transportForTab() {
    if (_tab == "obfuscation") return "amnezia";
    if (_tab == "stealth_plus") return "hysteria";
    return "wireguard";
  }

  Color _accentForTab(ColorScheme scheme, String tab) {
    if (tab == "obfuscation") return const Color(0xFFE2AE38);
    if (tab == "stealth_plus") return const Color(0xFF9B6BFF);
    return scheme.primary;
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

  Widget _modeInfoRow(
      BuildContext context,
      String tab, {
        required bool locked,
      }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = _tab == tab;
    final accent = _accentForTab(scheme, tab);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: 0.10)
            : scheme.surface.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? accent.withValues(alpha: 0.52)
              : scheme.outlineVariant.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _titleForTab(tab),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: selected ? accent : scheme.onSurface,
                  ),
                ),
              ),
              if (locked)
                Text(
                  "Pro",
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: const Color(0xFFFFE7A3),
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _bodyForTab(tab),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeHintBubble(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = _accentForTab(scheme, _tab);
    final locked = _tab == "stealth_plus" && !widget.hasPro;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
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
          ? const SizedBox.shrink(key: ValueKey("mode_hint_hidden"))
          : Container(
        key: ValueKey(_tab),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.14),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -8,
              right: 18,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.12),
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.14),
                    ),
                    left: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.14),
                    ),
                  ),
                ),
                transform: Matrix4.rotationZ(-0.785398),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _titleForTab(_tab),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                    if (locked)
                      Text(
                        "Pro",
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _bodyForTab(_tab),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
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
    final servers = _filteredServers;

    Widget tabButton({
      required String value,
      required String label,
      required bool locked,
    }) {
      final selected = _tab == value;
      final enabled = !locked;

      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled
              ? () {
            setState(() {
              _tab = value;
            });
          }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? _accentForTab(scheme, value).withValues(alpha: 0.14)
                  : scheme.surface.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? _accentForTab(scheme, value).withValues(alpha: 0.72)
                    : scheme.outlineVariant.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (locked) ...[
                  Icon(
                    Icons.lock_rounded,
                    size: 13,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? _accentForTab(scheme, value)
                          : scheme.onSurface.withValues(alpha: enabled ? 0.88 : 0.42),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget searchField() {
      return Container(
        height: 46,
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.14),
          ),
        ),
        child: TextField(
          controller: _searchController,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: "Search location",
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.70),
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: scheme.onSurfaceVariant,
              size: 19,
            ),
            suffixIcon: _searchController.text.trim().isEmpty
                ? null
                : IconButton(
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
              icon: Icon(
                Icons.close_rounded,
                color: scheme.onSurfaceVariant,
                size: 18,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        ),
      );
    }

    Widget locationRow(FullVpnServerLocation s) {
      final selected = s.id == widget.selectedServerId;
      final unlocked = _tab == "privacy" ? true : widget.isServerUnlocked(s);
      final code = s.countryCode.toUpperCase();

      return InkWell(
        onTap: unlocked
            ? () async {
          await widget.onSelect(s, _transportForTab());
        }
            : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: unlocked ? 1 : 0.42,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? _accentForTab(scheme, _tab).withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CountryFlag.fromCountryCode(
                  code,
                  height: 20,
                  width: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          _countryName(code),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                            color: unlocked ? scheme.onSurface : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (s.city != null && s.city!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            s.city!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: unlocked
                                  ? scheme.onSurfaceVariant.withValues(alpha: 0.92)
                                  : scheme.onSurfaceVariant.withValues(alpha: 0.72),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (!unlocked)
                  Icon(
                    Icons.lock_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  )
                else if (selected)
                  Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: _accentForTab(scheme, _tab),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.60),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget locationsList() {
      if (servers.isEmpty) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.14),
            ),
          ),
          child: Text(
            "No nodes available in this mode yet.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }

      return ListView.separated(
        itemCount: servers.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        separatorBuilder: (_, __) {
          return Padding(
            padding: const EdgeInsets.only(left: 46),
            child: Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.08),
            ),
          );
        },
        itemBuilder: (_, index) => locationRow(servers[index]),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.70,
      minChildSize: 0.46,
      maxChildSize: 0.92,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(30),
            ),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Choose location",
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _showModeHint = !_showModeHint;
                      });
                    },
                    icon: Icon(
                      _showModeHint
                          ? Icons.close_rounded
                          : Icons.info_outline_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                "Pick the routing mode and location you want to use.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_showModeHint) _modeHintBubble(context),
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
              const SizedBox(height: 14),
              searchField(),
              const SizedBox(height: 14),
              locationsList(),
            ],
          ),
        );
      },
    );
  }
}