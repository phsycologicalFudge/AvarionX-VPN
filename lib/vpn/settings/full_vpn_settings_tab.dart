import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../translations/app_localizations.dart';
import '../screens/full_vpn_sound_settings_screen.dart';
import '../services/full_vpn_backend.dart';
import 'full_vpn_account_screen.dart';
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
  static const String _discordSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 127.14 96.36">
  <path fill="currentColor" d="M107.7 8.07A105.15 105.15 0 0 0 81.47 0a72.06 72.06 0 0 0-3.36 6.83A97.68 97.68 0 0 0 49 6.83 72.37 72.37 0 0 0 45.64 0 105.89 105.89 0 0 0 19.39 8.09C2.79 32.65-1.71 56.6.54 80.21h.02a105.73 105.73 0 0 0 32.17 16.15 77.7 77.7 0 0 0 6.89-11.27 68.42 68.42 0 0 1-10.85-5.18c.91-.66 1.8-1.34 2.66-2.06 20.94 9.57 43.73 9.57 64.41 0 .87.72 1.76 1.4 2.66 2.06a68.68 68.68 0 0 1-10.87 5.19 77 77 0 0 0 6.89 11.26A105.25 105.25 0 0 0 126.6 80.22c2.64-27.34-4.5-51.07-18.9-72.15ZM42.45 65.69C36.18 65.69 31 59.96 31 52.91c0-7.05 5.05-12.78 11.45-12.78 6.45 0 11.57 5.78 11.45 12.78 0 7.05-5.05 12.78-11.45 12.78Zm42.24 0c-6.27 0-11.45-5.73-11.45-12.78 0-7.05 5.05-12.78 11.45-12.78 6.45 0 11.57 5.78 11.45 12.78 0 7.05-5.05 12.78-11.45 12.78Z"/>
</svg>
''';

  FullVpnController get c => widget.c;

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
                    child: SizedBox(width: 24, height: 24, child: leading),
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
                    child: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
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

  String _accountTileBody() {
    final signedIn = c.token.isNotEmpty && c.me != null;
    if (!signedIn) return "Sign in to sync your account across devices.";
    return "Manage your account";
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _settingsSwitchTile(
      BuildContext context, {
        required Widget leading,
        required String title,
        required String body,
        required bool value,
        required ValueChanged<bool> onChanged,
        bool showDivider = true,
      }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(width: 24, height: 24, child: leading),
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
              Transform.scale(
                scale: 0.92,
                child: Switch(value: value, onChanged: onChanged),
              ),
            ],
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

  Widget _optionsSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vpnTheme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, "Account"),
        _settingsNavTile(
          context,
          leading: Icon(Icons.person_rounded, color: scheme.onSurface, size: 22),
          title: "My Account",
          body: _accountTileBody(),
          showDivider: false,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Theme(data: vpnTheme, child: FullVpnAccountScreen(c: c)),
          )),
        ),

        _sectionLabel(context, "Features"),
        _settingsNavTile(
          context,
          leading: Icon(Icons.alt_route_rounded, color: scheme.onSurface, size: 22),
          title: "Split tunneling",
          body: "Choose which apps bypass the VPN and use your normal connection.",
          showDivider: false,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Theme(data: vpnTheme, child: const FullVpnSplitTunnelingScreen()),
          )),
        ),

        _sectionLabel(context, "Customisation"),
        _settingsSwitchTile(
          context,
          leading: Icon(Icons.flag_rounded, color: scheme.onSurface, size: 22),
          title: "Flag markers",
          body: "Show country flags on the map instead of dots.",
          value: c.showFlagMarkers,
          onChanged: (v) {
            c.setShowFlagMarkers(v);
            setState(() {});
          },
        ),
        _settingsNavTile(
          context,
          leading: Icon(Icons.music_note_rounded, color: scheme.onSurface, size: 22),
          title: "Connection sounds",
          body: "Choose the sounds used when the VPN connects and disconnects.",
          showDivider: false,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Theme(data: vpnTheme, child: FullVpnSoundSettingsScreen(c: c)),
          )),
        ),

        _sectionLabel(context, "About us"),
        _settingsNavTile(
          context,
          leading: Icon(Icons.shield_rounded, color: scheme.onSurface, size: 22),
          title: l10n.vpnSettingsPrivacySecurityTitle,
          body: "View privacy details, logging policy, protocol and protection features.",
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Theme(data: vpnTheme, child: const FullVpnPrivacySecurityScreen()),
          )),
        ),
        _settingsNavTile(
          context,
          leading: SvgPicture.string(
            _discordSvg,
            colorFilter: ColorFilter.mode(scheme.onSurface, BlendMode.srcIn),
          ),
          title: "Join our Discord",
          body: "Get updates, ask questions and join the community.",
          onTap: () async => launchUrl(
            Uri.parse("https://discord.gg/VYubQJfcYM"),
            mode: LaunchMode.externalApplication,
          ),
        ),
        _settingsNavTile(
          context,
          leading: Icon(Icons.forum_rounded, color: scheme.onSurface, size: 22),
          title: "Reddit",
          body: "Follow r/AvarionX for news and updates.",
          showDivider: false,
          onTap: () async => launchUrl(
            Uri.parse("https://www.reddit.com/r/AvarionX/"),
            mode: LaunchMode.externalApplication,
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
                    _optionsSection(context),
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