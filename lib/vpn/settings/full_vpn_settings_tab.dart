import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../translations/app_localizations.dart';
import '../services/full_vpn_backend.dart';
import 'full_vpn_privacy_security_screen.dart';
import 'full_vpn_split_tunneling_screen.dart';

class FullVpnSettingsTab extends StatefulWidget {
  final FullVpnController c;
  final Widget Function(BuildContext context, {bool showWhenDisconnected}) usageRow;

  const FullVpnSettingsTab({
    super.key,
    required this.c,
    required this.usageRow,
  });

  @override
  State<FullVpnSettingsTab> createState() => _FullVpnSettingsTabState();
}

class _FullVpnSettingsTabState extends State<FullVpnSettingsTab> {
  Timer? _refreshTimer;
  bool _refreshing = false;

  static const String _discordSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 127.14 96.36">
  <path fill="currentColor" d="M107.7 8.07A105.15 105.15 0 0 0 81.47 0a72.06 72.06 0 0 0-3.36 6.83A97.68 97.68 0 0 0 49 6.83 72.37 72.37 0 0 0 45.64 0 105.89 105.89 0 0 0 19.39 8.09C2.79 32.65-1.71 56.6.54 80.21h.02a105.73 105.73 0 0 0 32.17 16.15 77.7 77.7 0 0 0 6.89-11.27 68.42 68.42 0 0 1-10.85-5.18c.91-.66 1.8-1.34 2.66-2.06 20.94 9.57 43.73 9.57 64.41 0 .87.72 1.76 1.4 2.66 2.06a68.68 68.68 0 0 1-10.87 5.19 77 77 0 0 0 6.89 11.26A105.25 105.25 0 0 0 126.6 80.22c2.64-27.34-4.5-51.07-18.9-72.15ZM42.45 65.69C36.18 65.69 31 59.96 31 52.91c0-7.05 5.05-12.78 11.45-12.78 6.45 0 11.57 5.78 11.45 12.78 0 7.05-5.05 12.78-11.45 12.78Zm42.24 0c-6.27 0-11.45-5.73-11.45-12.78 0-7.05 5.05-12.78 11.45-12.78 6.45 0 11.57 5.78 11.45 12.78 0 7.05-5.05 12.78-11.45 12.78Z"/>
</svg>
''';

  FullVpnController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAccountData() async {
    final signedIn = c.token.isNotEmpty && c.me != null;
    if (!signedIn || c.busy || _refreshing) return;

    _refreshing = true;
    try {
      await c.refreshMe();
      await c.fetchUsage(showSync: true);
      if (mounted) {
        setState(() {});
      }
    } finally {
      _refreshing = false;
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();

    _refreshTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      await _refreshAccountData();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshAccountData();
    });
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

  Widget _settingsNavTile(
      BuildContext context, {
        required Widget leading,
        required String title,
        required String body,
        required VoidCallback onTap,
        bool showDivider = true,
      }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: leading,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.bodyMedium?.copyWith(
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
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: scheme.outlineVariant.withOpacity(0.16),
          ),
      ],
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
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        if (!signedIn) ...[
          Text(
            l10n.vpnSettingsSignInToContinue,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.vpnSettingsAccountSyncBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
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
          Builder(
            builder: (context) {
              final pfp = (c.me?["pfp"] ??
                  c.me?["photoUrl"] ??
                  c.me?["photo_url"] ??
                  c.me?["picture"] ??
                  c.me?["avatarUrl"] ??
                  c.me?["avatar_url"] ??
                  "")
                  .toString()
                  .trim();

              if (pfp.isEmpty) {
                return Text(
                  email.isEmpty ? l10n.vpnSettingsSignedIn : email,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                );
              }

              return Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Image.network(
                      pfp,
                      width: 22,
                      height: 22,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      email.isEmpty ? l10n.vpnSettingsSignedIn : email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            plan.isEmpty ? l10n.vpnSettingsPlanUnknown : l10n.vpnSettingsPlanLabel(plan),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          widget.usageRow(context, showWhenDisconnected: true),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final uri = Uri.parse("https://api.colourswift.com/account");
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  child: const Text("Dashboard"),
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

  Widget _subSettingsSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vpnTheme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Options",
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              _settingsNavTile(
                context,
                leading: Icon(
                  Icons.alt_route_rounded,
                  color: scheme.onSurface,
                  size: 22,
                ),
                title: "Split tunneling",
                body: "Choose which apps bypass the VPN and use your normal connection.",
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Theme(
                        data: vpnTheme,
                        child: const FullVpnSplitTunnelingScreen(),
                      ),
                    ),
                  );
                },
              ),
              _settingsNavTile(
                context,
                leading: Icon(
                  Icons.shield_rounded,
                  color: scheme.onSurface,
                  size: 22,
                ),
                title: l10n.vpnSettingsPrivacySecurityTitle,
                body: "View privacy details, logging policy, protocol and protection features.",
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Theme(
                        data: vpnTheme,
                        child: const FullVpnPrivacySecurityScreen(),
                      ),
                    ),
                  );
                },
              ),
              _settingsNavTile(
                context,
                leading: SvgPicture.string(
                  _discordSvg,
                  colorFilter: ColorFilter.mode(
                    scheme.onSurface,
                    BlendMode.srcIn,
                  ),
                ),
                title: "Join our Discord",
                body: "Get updates, ask questions and join the community.",
                showDivider: false,
                onTap: () async {
                  final uri = Uri.parse("https://discord.gg/VYubQJfcYM");
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _accountSection(context),
                    const SizedBox(height: 18),
                    _subSettingsSection(context),
                    const Expanded(child: SizedBox()),
                    _brandFooter(context),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}