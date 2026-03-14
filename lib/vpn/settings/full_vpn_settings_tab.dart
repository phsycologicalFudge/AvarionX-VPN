import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
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

  Widget _settingsNavTile(BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.42),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.24)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: scheme.surface.withOpacity(0.55),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: scheme.onSurface, size: 21),
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: scheme.onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: scheme.onSurfaceVariant,
        ),
        onTap: onTap,
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
          style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        if (!signedIn) ...[
          Text(
            l10n.vpnSettingsSignInToContinue,
            style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900),
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
        ] else
          ...[
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
                        fontWeight: FontWeight.w900),
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
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              plan.isEmpty ? l10n.vpnSettingsPlanUnknown : l10n
                  .vpnSettingsPlanLabel(plan),
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
                      final uri = Uri.parse(
                          "https://api.colourswift.com/account");
                      await launchUrl(
                          uri, mode: LaunchMode.externalApplication);
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
    final vpnTheme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Options",
          style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        _settingsNavTile(
          context,
          icon: Icons.alt_route_rounded,
          title: "Split tunneling",
          body: "Choose which apps bypass the VPN and use your normal connection.",
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    Theme(
                      data: vpnTheme,
                      child: const FullVpnSplitTunnelingScreen(),
                    ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _settingsNavTile(
          context,
          icon: Icons.shield_rounded,
          title: l10n.vpnSettingsPrivacySecurityTitle,
          body: "View privacy details, logging policy, protocol and protection features.",
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    Theme(
                      data: vpnTheme,
                      child: const FullVpnPrivacySecurityScreen(),
                    ),
              ),
            );
          },
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