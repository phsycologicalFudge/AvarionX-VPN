import 'package:colourswift_av/vpn/services/full_vpn_backend.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../translations/app_localizations.dart';
import '../services/prefs/blocklist_prefs.dart';

class FullVpnCustomisationScreen extends StatefulWidget {
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
  State<FullVpnCustomisationScreen> createState() => _FullVpnCustomisationScreenState();
}

class _FullVpnCustomisationScreenState extends State<FullVpnCustomisationScreen> {
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFromSharedPrefs();
  }

  Future<void> _loadFromSharedPrefs() async {
    final stored = await BlocklistPrefs.load();
    final m = widget.c.blocklists;
    if (m is Map<String, bool>) {
      for (final entry in stored.entries) {
        m[entry.key] = entry.value;
      }
      widget.c.notifyListeners();
    }
    if (!mounted) return;
    setState(() => _prefsLoaded = true);
  }

  Future<void> _toggle(String key, bool value) async {
    final m = widget.c.blocklists;
    if (m is! Map<String, bool>) return;

    final writes = <String, bool>{key: value};
    if (value) {
      if (key == 'romain')  writes['malware'] = false;
      if (key == 'malware') writes['romain']  = false;
      if (key == 'oisd')    writes['ads']     = false;
      if (key == 'ads')     writes['oisd']    = false;
    }

    for (final entry in writes.entries) {
      m[entry.key] = entry.value;
      await BlocklistPrefs.set(entry.key, entry.value);
    }

    await widget.c.persistBlocklists();
    widget.c.notifyListeners();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => _FullVpnCustomisationView(
    c: widget.c,
    hasProEntitlement: widget.hasProEntitlement,
    onRequireSignIn: widget.onRequireSignIn,
    onToggle: _toggle,
    prefsLoaded: _prefsLoaded,
  );
}

class _FullVpnCustomisationView extends StatelessWidget {
  final FullVpnController c;
  final bool hasProEntitlement;
  final Future<void> Function() onRequireSignIn;
  final Future<void> Function(String key, bool value) onToggle;
  final bool prefsLoaded;

  const _FullVpnCustomisationView({
    required this.c,
    required this.hasProEntitlement,
    required this.onRequireSignIn,
    required this.onToggle,
    required this.prefsLoaded,
  });

  @override
  Widget build(BuildContext context) {
    if (!prefsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const pro = true;
    final entries = c.blocklists.entries.toList();

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
        case "romain":
          return "Colourswift Malware";
        case "oisd":
          return "Colourswift Ads";
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
        case "romain":
          return "Curated malware and threat list maintained by Colourswift.";
        case "oisd":
          return "Curated ads and tracker list maintained by Colourswift.";
        default:
          return "Blocks domains in this category at network level.";
      }
    }

    const colourswiftKeys = {'romain', 'oisd'};
    const categoryOrder = ['malware', 'ads', 'trackers', 'adult', 'gambling', 'social', 'crypto'];

    final colourswift = <MapEntry<String, bool>>[];
    final categories  = <MapEntry<String, bool>>[];

    for (final e in entries) {
      if (colourswiftKeys.contains(e.key)) {
        colourswift.add(e);
      } else {
        categories.add(e);
      }
    }

    colourswift.sort((a, b) => a.key == 'romain' ? -1 : 1);
    categories.sort((a, b) {
      final ai = categoryOrder.indexOf(a.key);
      final bi = categoryOrder.indexOf(b.key);
      if (ai == -1 && bi == -1) return prettyName(a.key).compareTo(prettyName(b.key));
      if (ai == -1) return 1;
      if (bi == -1) return -1;
      return ai.compareTo(bi);
    });




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
                          : (v) => onToggle(e.key, v),
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




    Widget sectionLabel(String label) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );

    Widget sectionDivider() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(height: 1, thickness: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
    );

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

        if (colourswift.isNotEmpty) ...[
          sectionLabel('COLOURSWIFT'),
          ...List.generate(
            colourswift.length,
                (i) => tile(
              colourswift[i],
              enabled: true,
              forceOff: false,
              showDivider: i != colourswift.length - 1,
            ),
          ),
          sectionDivider(),
        ],

        if (categories.isNotEmpty) ...[
          sectionLabel('CATEGORIES'),
          ...List.generate(
            categories.length,
                (i) => tile(
              categories[i],
              enabled: true,
              forceOff: false,
              showDivider: i != categories.length - 1,
            ),
          ),
        ],

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