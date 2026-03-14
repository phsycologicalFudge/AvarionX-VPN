import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/full_vpn_installed_apps_worker.dart';

class FullVpnSplitTunnelingScreen extends StatefulWidget {
  const FullVpnSplitTunnelingScreen({super.key});

  static const kSplitExcludedPkgs = "cs_vpn_split_excluded_pkgs";

  @override
  State<FullVpnSplitTunnelingScreen> createState() => _FullVpnSplitTunnelingScreenState();
}

class _FullVpnSplitTunnelingScreenState extends State<FullVpnSplitTunnelingScreen> {
  int _reloadTick = 0;

  Future<List<String>> _loadExcludedPkgs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(FullVpnSplitTunnelingScreen.kSplitExcludedPkgs) ?? const <String>[];
    return list.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  Future<void> _saveExcludedPkgs(List<String> pkgs) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = pkgs.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await prefs.setStringList(FullVpnSplitTunnelingScreen.kSplitExcludedPkgs, cleaned);
  }

  void _reload() {
    setState(() => _reloadTick++);
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
          content: Text(
            res.isEmpty ? "Split tunneling cleared." : "Split tunneling saved.",
          ),
        ),
      );
    }

    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Split tunneling"),
      ),
      body: FutureBuilder<List<String>>(
        future: _loadExcludedPkgs().then((v) => v),
        key: ValueKey(_reloadTick),
        builder: (ctx, snap) {
          final list = snap.data ?? const <String>[];

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withOpacity(0.42),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scheme.outlineVariant.withOpacity(0.24)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Excluded apps (${list.length})",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 14),
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
              if (list.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  "Selected apps",
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<FullVpnInstalledApp>>(
                  future: FullVpnInstalledAppsWorker.listLaunchableApps(),
                  builder: (ctx, appsSnap) {
                    final apps = appsSnap.data ?? const <FullVpnInstalledApp>[];
                    final nameByPkg = <String, String>{
                      for (final a in apps) a.packageName: a.name,
                    };

                    return Column(
                      children: list.map((pkg) {
                        final title = nameByPkg[pkg] ?? pkg.split('.').last;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              FutureBuilder<List<int>?>(
                                future: FullVpnInstalledAppsWorker.loadIconBytes(pkg),
                                builder: (ctx, iconSnap) {
                                  final bytes = iconSnap.data;
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
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      pkg,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () async {
                                  final next = List<String>.from(list)..remove(pkg);
                                  await _saveExcludedPkgs(next);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                    SnackBar(content: Text("Removed ${title.trim().isEmpty ? pkg.split('.').last : title}.")),
                                  );
                                  _reload();
                                },
                                icon: Icon(Icons.delete_outline_rounded, color: scheme.onSurfaceVariant),
                                tooltip: "Remove",
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ],
          );
        },
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