import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/prefs/blocklist_prefs.dart';
import '../../services/purchase_service.dart';

const _basicHostname = 'basic.dns.colourswift.com';
const _prefDnsHostname = 'cs_private_dns_hostname';
const _prefAdvancedMode = 'cs_advanced_dns_mode';
const _apiBase = 'https://api.colourswift.com';

const _listOrder = ['romain', 'oisd', 'malware', 'ads', 'trackers', 'adult', 'gambling', 'social'];
const _colourswiftKeys = {'romain', 'oisd'};

class PrivateDnsScreen extends StatefulWidget {
  const PrivateDnsScreen({super.key});

  @override
  State<PrivateDnsScreen> createState() => _PrivateDnsScreenState();
}

class _PrivateDnsScreenState extends State<PrivateDnsScreen>
    with SingleTickerProviderStateMixin {
  String? _personalHostname;
  bool _generating = false;
  bool _loaded = false;
  Map<String, bool> _lists = {};
  bool _saving = false;
  bool _advancedMode = false;
  bool _advancedSaving = false;
  String _serverPlan = '';

  bool get _isPro {
    final plan = _serverPlan.trim().toLowerCase();
    return PurchaseService.isPro || plan == 'pro';
  }

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var hostname = prefs.getString(_prefDnsHostname);
    final lists = await BlocklistPrefs.load();
    final advancedMode = prefs.getBool(_prefAdvancedMode) ?? false;
    final serverPlan = prefs.getString('cs_server_plan') ?? '';
    final token = prefs.getString('cs_auth_token') ?? '';

    if (token.isNotEmpty) {
      try {
        final resp = await http.get(
          Uri.parse('$_apiBase/dns/hostname'),
          headers: {
            'authorization': 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final serverHostname = data['hostname'];

          if (serverHostname is String && serverHostname.trim().isNotEmpty) {
            hostname = serverHostname.trim();
            await prefs.setString(_prefDnsHostname, hostname);
          } else {
            hostname = null;
            await prefs.remove(_prefDnsHostname);
          }
        } else if (resp.statusCode == 401 || resp.statusCode == 403) {
          hostname = null;
          await prefs.remove(_prefDnsHostname);
        }
      } catch (_) {}
    } else {
      hostname = null;
      await prefs.remove(_prefDnsHostname);
    }

    if (!mounted) return;
    setState(() {
      _personalHostname = hostname;
      _lists = lists;
      _advancedMode = advancedMode;
      _serverPlan = serverPlan;
      _loaded = true;
    });
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('cs_auth_token') ?? '';
      if (token.isEmpty) return;
      final resp = await http.post(
        Uri.parse('$_apiBase/dns/generate-prefix'),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        if (json['ok'] == true && json['hostname'] is String) {
          final hostname = json['hostname'] as String;
          await prefs.setString(_prefDnsHostname, hostname);
          if (!mounted) return;
          setState(() => _personalHostname = hostname);
        }
      }
    } catch (_) {
    } finally {
      if (!mounted) return;
      setState(() => _generating = false);
    }
  }

  Future<void> _toggle(String key, bool value) async {
    final updated = Map<String, bool>.from(_lists);
    updated[key] = value;
    if (value) {
      if (key == 'romain') updated['malware'] = false;
      if (key == 'malware') updated['romain'] = false;
      if (key == 'oisd') updated['ads'] = false;
      if (key == 'ads') updated['oisd'] = false;
    }
    for (final entry in updated.entries) {
      if (_lists[entry.key] != entry.value) {
        await BlocklistPrefs.set(entry.key, entry.value);
      }
    }
    if (!mounted) return;
    setState(() => _lists = updated);
  }

  String _buildSettingsB64() {
    final enabled = _lists.entries.where((e) => e.value).map((e) => e.key).toList();
    return base64Encode(utf8.encode(jsonEncode({
      'enabled_lists': enabled,
      'advanced_mode': _advancedMode,
    })));
  }

  Future<void> _pushSettings({bool showSnackbar = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('cs_auth_token') ?? '';
    if (token.isEmpty) return;
    final resp = await http.post(
      Uri.parse('$_apiBase/dns/settings'),
      headers: {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      },
      body: jsonEncode({'settings_b64': _buildSettingsB64()}),
    ).timeout(const Duration(seconds: 10));
    if (!showSnackbar || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resp.statusCode == 200 ? 'Settings saved' : 'Failed to save settings')),
    );
  }

  Future<void> _saveSettings() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _pushSettings(showSnackbar: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save settings')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _toggleAdvancedMode(bool value) async {
    if (_advancedSaving) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAdvancedMode, value);
    if (!mounted) return;
    setState(() {
      _advancedMode = value;
      _advancedSaving = true;
    });
    try {
      await _pushSettings(showSnackbar: false);
    } catch (_) {
    } finally {
      if (!mounted) return;
      setState(() => _advancedSaving = false);
    }
  }

  void _showInfo() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Basic DNS', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'The basic address requires no account and automatically blocks ads, trackers, and malware.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 20),
              Text('Premium DNS', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'A private address is linked to your account and applies your custom settings automatically.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddressActions(String hostname) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                hostname,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy address'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: hostname));
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address copied')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Copy & open Private DNS settings'),
              subtitle: const Text('Paste under Private DNS provider hostname'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: hostname));
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                try {
                  await const MethodChannel('cs_vpn_control').invokeMethod('openPrivateDnsSettings');
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied. Go to Settings → Network → Private DNS to paste.'),
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _prettyName(String key) {
    switch (key) {
      case 'romain':   return 'Colourswift Malware';
      case 'oisd':     return 'Colourswift Ads';
      case 'malware':  return 'Malware';
      case 'ads':      return 'Ads';
      case 'trackers': return 'Trackers';
      case 'adult':    return 'Adult';
      case 'gambling': return 'Gambling';
      case 'social':   return 'Social Media';
      default:         return key;
    }
  }

  String _prettyDescription(String key) {
    switch (key) {
      case 'romain':   return 'Curated malware & threat list by Colourswift.';
      case 'oisd':     return 'Curated ads & tracker list by Colourswift.';
      case 'malware':  return 'Blocks malicious, phishing and high-risk domains.';
      case 'ads':      return 'Blocks advertising domains across websites and apps.';
      case 'trackers': return 'Blocks tracking, telemetry and analytics domains.';
      case 'adult':    return 'Blocks adult websites and explicit content domains.';
      case 'gambling': return 'Blocks gambling, betting and casino domains.';
      case 'social':   return 'Blocks major social media and related platform domains.';
      default:         return 'Blocks domains in this category.';
    }
  }

  Widget _sectionLabel(String label, {Widget? trailing}) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 6), trailing],
      ],
    );
  }

  Widget _compactDnsRow({required String title, required String hostname, bool premium = false}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showAddressActions(hostname),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: premium ? 0.10 : 0.06), width: 0.5),
        ),
        child: Row(
          children: [
            Text(title, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
            if (premium) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Premium',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 9,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hostname,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace', color: scheme.onSurfaceVariant, fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.copy_outlined, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _compactLockedRow() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
      ),
      child: Row(
        children: [
          Text('Personal DNS', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Premium',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 9,
              ),
            ),
          ),
          const Spacer(),
          Icon(Icons.lock_outline, size: 14, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45)),
        ],
      ),
    );
  }

  Widget _compactGenerateRow() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(child: Text('Personal DNS', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          SizedBox(
            height: 28,
            child: ElevatedButton(
              onPressed: _generating ? null : _generate,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: _generating
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Generate', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _advancedSection() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Opacity(
      opacity: _isPro ? 1.0 : 0.45,
      child: AbsorbPointer(
        absorbing: !_isPro,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(
              'ADVANCED DNS',
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Pro',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 9,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Advanced Protection',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Uses heuristic analysis to detect phishing sites, lookalike domains, and algorithmically generated malware addresses that may not appear in standard blocklists.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant, height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'May occasionally block legitimate domains. Disable if you notice unexpected issues.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                                height: 1.4,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _advancedSaving
                    ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                  ),
                )
                    : Switch(
                  value: _advancedMode,
                  onChanged: _toggleAdvancedMode,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _blocklistsContent() {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final orderedKeys = _listOrder.where((k) => _lists.containsKey(k)).toList();
    final csKeys   = orderedKeys.where((k) => _colourswiftKeys.contains(k)).toList();
    final commKeys = orderedKeys.where((k) => !_colourswiftKeys.contains(k)).toList();

    Widget buildGroup(List<String> keys) {
      return Column(
        children: List.generate(keys.length, (i) {
          final key     = keys[i];
          final enabled = _lists[key] ?? false;
          final isLast  = i == keys.length - 1;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_prettyName(key), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            _prettyDescription(key),
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: enabled,
                      onChanged: (v) => _toggle(key, v),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(height: 1, thickness: 0.5, color: scheme.outlineVariant.withValues(alpha: 0.12)),
            ],
          );
        }),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: _isPro ? 1.0 : 0.45,
            child: AbsorbPointer(
              absorbing: !_isPro,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('COLOURSWIFT'),
                  buildGroup(csKeys),
                  const SizedBox(height: 16),
                  Divider(height: 1, thickness: 0.5, color: scheme.outlineVariant.withValues(alpha: 0.25)),
                  const SizedBox(height: 16),
                  _sectionLabel('COMMUNITY'),
                  buildGroup(commKeys),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Private DNS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            onPressed: _showInfo,
          ),
        ],
      ),
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('BASIC'),
                    const SizedBox(height: 8),
                    _compactDnsRow(title: 'Basic DNS', hostname: _basicHostname),
                    const SizedBox(height: 20),
                    Divider(height: 1, thickness: 0.5, color: theme.dividerColor.withOpacity(0.25)),
                    const SizedBox(height: 20),
                    _sectionLabel('PREMIUM DNS'),
                    const SizedBox(height: 8),
                    if (!_isPro)
                      _compactLockedRow()
                    else if (!_loaded)
                      const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                    else if (_personalHostname != null)
                        _compactDnsRow(title: 'Your DNS', hostname: _personalHostname!, premium: true)
                      else
                        _compactGenerateRow(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarHeader(
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 20),
                  labelStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
                  labelColor: scheme.onSurface,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: scheme.onSurface,
                  indicatorWeight: 2,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  tabs: const [Tab(text: 'Blocklists'), Tab(text: 'Advanced')],
                ),
                backgroundColor: theme.scaffoldBackgroundColor,
                dividerColor: theme.dividerColor.withOpacity(0.25),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _blocklistsContent(),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: _advancedSection(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;
  final Color dividerColor;

  const _TabBarHeader(this.tabBar, {required this.backgroundColor, required this.dividerColor});

  @override
  double get minExtent => tabBar.preferredSize.height + 0.5;

  @override
  double get maxExtent => tabBar.preferredSize.height + 0.5;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: backgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tabBar,
          Divider(height: 0.5, thickness: 0.5, color: dividerColor),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_TabBarHeader oldDelegate) => false;
}