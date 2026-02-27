import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../translations/app_localizations.dart';
import '../services/full_vpn_backend.dart';
import '../services/full_vpn_installed_apps_worker.dart';

class FullVpnSettingsTab extends StatelessWidget {
  final FullVpnController c;
  final Widget Function(BuildContext context, {bool showWhenDisconnected}) usageRow;

  const FullVpnSettingsTab({
    super.key,
    required this.c,
    required this.usageRow,
  });

  static const _kSplitExcludedPkgs = "cs_vpn_split_excluded_pkgs";

  Future<List<String>> _loadExcludedPkgs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kSplitExcludedPkgs) ?? const <String>[];
    return list.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  Future<void> _saveExcludedPkgs(List<String> pkgs) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = pkgs.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await prefs.setStringList(_kSplitExcludedPkgs, cleaned);
  }

  Future<void> _openSplitTunnelPicker(BuildContext context) async {
    final existing = await _loadExcludedPkgs();
    if (!context.mounted) return;

    final res = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _SplitTunnelPickerSheet(
          initialExcluded: existing,
        );
      },
    );

    if (res == null) return;

    await _saveExcludedPkgs(res);

    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(res.isEmpty ? "Split tunneling cleared." : "Split tunneling saved."),
        ),
      );
    }
  }

  Widget _splitTunnelingSection(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return FutureBuilder<List<String>>(
      future: _loadExcludedPkgs(),
      builder: (ctx, snap) {
        final list = snap.data ?? const <String>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Split tunneling",
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.alt_route_rounded, size: 18, color: scheme.onSurface.withOpacity(0.92)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Excluded apps (${list.length})",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        list.isEmpty
                            ? "No apps excluded. All apps use the VPN."
                            : "Excluded apps bypass the VPN and use your normal connection.",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () async {
                            await _openSplitTunnelPicker(context);
                          },
                          child: Text(list.isEmpty ? "Choose apps" : "Edit apps"),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _privacySection(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    TextStyle? titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w900,
      color: scheme.onSurface,
    );

    TextStyle? bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.35,
      fontWeight: FontWeight.w600,
    );

    Widget item(IconData icon, String title, String body) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: scheme.onSurface.withOpacity(0.92)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: titleStyle),
                  const SizedBox(height: 2),
                  Text(body, style: bodyStyle),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.vpnSettingsPrivacySecurityTitle,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        item(
          Icons.visibility_off_rounded,
          l10n.vpnSettingsNoLogsPolicyTitle,
          l10n.vpnSettingsNoLogsPolicyBody,
        ),
        item(
          Icons.shield_rounded,
          l10n.vpnSettingsNoActivityLogsTitle,
          l10n.vpnSettingsNoActivityLogsBody,
        ),
        item(
          Icons.lock_rounded,
          l10n.vpnSettingsWireGuardTitle,
          l10n.vpnSettingsWireGuardBody,
        ),
        item(
          Icons.gpp_good_rounded,
          l10n.vpnSettingsMalwareProtectionTitle,
          l10n.vpnSettingsMalwareProtectionBody,
        ),
        item(
          Icons.track_changes_rounded,
          l10n.vpnSettingsAdTrackerProtectionTitle,
          l10n.vpnSettingsAdTrackerProtectionBody,
        ),
      ],
    );
  }

  Widget _brandFooter(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            l10n.vpnSettingsBrandFooter,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant.withOpacity(0.55),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountSection(BuildContext context) {
    final signedIn = c.token.isNotEmpty && c.me != null;
    final email = (c.me?["email"] ?? "").toString();
    final plan = (c.me?["plan"] ?? "").toString();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.vpnSettingsAccountTitle,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        if (!signedIn) ...[
          Text(
            l10n.vpnSettingsSignInToContinue,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.vpnSettingsAccountSyncBody,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: c.busy ? null : c.startLoginInBrowser,
              child: Text(l10n.vpnSignIn),
            ),
          ),
        ] else ...[
          Text(
            email.isEmpty ? l10n.vpnSettingsSignedIn : email,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            plan.isEmpty ? l10n.vpnSettingsPlanUnknown : l10n.vpnSettingsPlanLabel(plan),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          usageRow(context, showWhenDisconnected: true),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: c.busy
                      ? null
                      : () async {
                    await c.refreshMe();
                    await c.fetchUsage(showSync: true);
                  },
                  child: Text(l10n.vpnSettingsRefresh),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: c.busy ? null : c.signOut,
                  child: Text(l10n.vpnSettingsSignOut),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _accountSection(context),
          const SizedBox(height: 18),
          _splitTunnelingSection(context),
          const SizedBox(height: 18),
          _privacySection(context),
          _brandFooter(context),
        ],
      ),
    );
  }
}

class _SplitTunnelPickerSheet extends StatefulWidget {
  final List<String> initialExcluded;

  const _SplitTunnelPickerSheet({
    required this.initialExcluded,
  });

  @override
  State<_SplitTunnelPickerSheet> createState() => _SplitTunnelPickerSheetState();
}

class _SplitTunnelPickerSheetState extends State<_SplitTunnelPickerSheet> {
  final _search = TextEditingController();

  List<FullVpnInstalledApp> _apps = const [];
  Set<String> _excluded = <String>{};
  String _q = "";
  bool _loading = true;

  final Map<String, Future<List<int>?>> _iconFutures = {};

  @override
  void initState() {
    super.initState();
    _excluded = widget.initialExcluded.toSet();
    _load();
    _search.addListener(() {
      final v = _search.text.trim().toLowerCase();
      if (v == _q) return;
      setState(() => _q = v);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await FullVpnInstalledAppsWorker.listLaunchableApps();
      if (!mounted) return;
      setState(() {
        _apps = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _apps = const [];
        _loading = false;
      });
    }
  }

  Future<List<int>?> _iconFor(String pkg) {
    return _iconFutures.putIfAbsent(pkg, () => FullVpnInstalledAppsWorker.loadIconBytes(pkg));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final filtered = _q.isEmpty
        ? _apps
        : _apps.where((a) {
      final n = a.name.toLowerCase();
      final p = a.packageName.toLowerCase();
      return n.contains(_q) || p.contains(_q);
    }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.50,
      maxChildSize: 0.95,
      builder: (ctx, controller) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Excluded apps",
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, <String>[]),
                      child: const Text("Clear"),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _excluded.toList()..sort()),
                      child: const Text("Done"),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: "Search apps",
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: scheme.surface.withOpacity(0.30),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(0.30)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(0.30)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: scheme.primary.withOpacity(0.55)),
                    ),
                  ),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(minHeight: 4),
                ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final a = filtered[i];
                    final checked = _excluded.contains(a.packageName);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: scheme.surface.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: checked ? scheme.primary : scheme.outlineVariant.withOpacity(0.22),
                        ),
                      ),
                      child: ListTile(
                        leading: FutureBuilder<List<int>?>(
                          future: _iconFor(a.packageName),
                          builder: (ctx, snap) {
                            final bytes = snap.data;
                            if (bytes == null) {
                              return Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: scheme.surface.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: scheme.outlineVariant.withOpacity(0.22)),
                                ),
                                child: Icon(Icons.apps_rounded, color: scheme.onSurfaceVariant, size: 18),
                              );
                            }
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                Uint8List.fromList(bytes),
                                width: 34,
                                height: 34,
                              ),
                            );
                          },
                        ),
                        title: Text(
                          a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        subtitle: Text(
                          a.packageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Checkbox(
                          value: checked,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _excluded.add(a.packageName);
                              } else {
                                _excluded.remove(a.packageName);
                              }
                            });
                          },
                        ),
                        onTap: () {
                          setState(() {
                            if (checked) {
                              _excluded.remove(a.packageName);
                            } else {
                              _excluded.add(a.packageName);
                            }
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    "Excluded apps bypass the VPN.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}