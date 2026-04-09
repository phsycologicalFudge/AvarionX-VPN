import 'package:colourswift_av/vpn/services/full_vpn_backend.dart';
import 'package:flutter/material.dart';
import '../../../translations/app_localizations.dart';

class FullVpnCustomisationScreen extends StatelessWidget {
  final FullVpnController c;
  final bool hasProEntitlement;
  final Future<void> Function() onRequireSignIn;

  const FullVpnCustomisationScreen({
    super.key,
    required this.c,
    required this.hasProEntitlement,
    required this.onRequireSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const pro = true;
    final entries = c.blocklists.entries.toList();

    bool isMalwareKey(String k) {
      final s = k.toLowerCase().trim();
      if (s == "malware") return true;
      if (s.contains("malware")) return true;
      if (s.contains("threat")) return true;
      if (s.contains("phishing")) return true;
      return false;
    }

    String prettyName(String key) {
      switch (key.toLowerCase().trim()) {
        case "ads":
          return "Ads";
        case "trackers":
          return "Trackers";
        case "malware":
          return "Malware";
        case "adult":
          return "Adult";
        case "gambling":
          return "Gambling";
        case "social":
          return "Social Media";
        case "crypto":
          return "Crypto";
        default:
          final parts = key.split(RegExp(r"[_\\s-]+"));
          return parts
              .where((e) => e.trim().isNotEmpty)
              .map((e) => e[0].toUpperCase() + e.substring(1).toLowerCase())
              .join(" ");
      }
    }

    String descriptionFor(String key) {
      switch (key.toLowerCase().trim()) {
        case "ads":
          return "Blocks advertising domains across websites and apps.";
        case "trackers":
          return "Blocks tracking, telemetry and analytics domains.";
        case "malware":
          return "Blocks malicious, phishing and high-risk domains.";
        case "adult":
          return "Blocks adult websites and explicit content domains.";
        case "gambling":
          return "Blocks gambling, betting and casino domains.";
        case "social":
          return "Blocks major social media and related platform domains.";
        case "crypto":
          return "Blocks crypto mining, exchange and related domains.";
        default:
          return "Blocks domains in this category at network level.";
      }
    }

    final malware = <MapEntry<String, bool>>[];
    final premium = <MapEntry<String, bool>>[];

    for (final e in entries) {
      if (isMalwareKey(e.key)) {
        malware.add(e);
      } else {
        premium.add(e);
      }
    }

    malware.sort((a, b) => prettyName(a.key).compareTo(prettyName(b.key)));
    premium.sort((a, b) => prettyName(a.key).compareTo(prettyName(b.key)));

    Widget sectionBadge({
      required bool active,
      required String text,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF1B7F4B).withValues(alpha: 0.16)
              : const Color(0xFFB8860B).withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? const Color(0xFF1B7F4B).withValues(alpha: 0.28)
                : const Color(0xFFB8860B).withValues(alpha: 0.28),
          ),
        ),
        child: Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: active ? const Color(0xFFBFF7D4) : const Color(0xFFFFE7A3),
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 0.1,
          ),
        ),
      );
    }

    Widget sectionHeader({
      required String title,
      required String body,
      Widget? trailing,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing,
          ],
        ],
      );
    }

    Widget tile(
        MapEntry<String, bool> e, {
          required bool enabled,
          required bool forceOff,
          required bool showDivider,
        }) {
      final value = forceOff ? false : e.value;
      final title = prettyName(e.key);
      final body = descriptionFor(e.key);

      return Opacity(
        opacity: enabled ? 1.0 : 0.58,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: enabled
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            body,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.92,
                    child: Switch(
                      value: value,
                      onChanged: !enabled
                          ? null
                          : (v) async {
                        final m = c.blocklists;
                        if (m is Map<String, bool>) {
                          m[e.key] = v;
                          await c.persistBlocklists();
                          c.notifyListeners();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (showDivider)
              Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.14),
              ),
          ],
        ),
      );
    }

    Widget sectionCard({
      required Widget header,
      required List<Widget> children,
      Color? tint,
    }) {
      return Container(
        decoration: BoxDecoration(
          color: tint ?? scheme.surfaceContainerHighest.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.18),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
      children: [
        Text(
          l10n.vpnBlocklistsTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Choose which categories are filtered before traffic reaches your device.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        sectionCard(
          tint: scheme.primaryContainer.withValues(alpha: 0.10),
          header: sectionHeader(
            title: "Essential Protection",
            body: "This core security filter is designed to block harmful domains and common threats.",
          ),
          children: List.generate(
            malware.length,
                (i) => tile(
              malware[i],
              enabled: true,
              forceOff: false,
              showDivider: i != malware.length - 1,
            ),
          ),
        ),
        const SizedBox(height: 16),
        sectionCard(
          tint: scheme.surfaceContainerHighest.withValues(alpha: 0.22),
          header: sectionHeader(
            title: "Extra Filters",
            body: "Extra categories for stronger control over browsing, ads and trackers.",
          ),
          children: List.generate(
            premium.length,
                (i) => tile(
              premium[i],
              enabled: pro,
              forceOff: !pro,
              showDivider: i != premium.length - 1,
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: c.busy
                ? null
                : () async {
              if (c.token.isEmpty) {
                await onRequireSignIn();
                return;
              }
              await c.saveDnsSettings();
            },
            child: Text(l10n.vpnSave),
          ),
        ),
      ],
    );
  }
}