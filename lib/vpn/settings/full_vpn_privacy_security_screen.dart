import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../translations/app_localizations.dart';

class FullVpnPrivacySecurityScreen extends StatelessWidget {
  const FullVpnPrivacySecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withOpacity(0.42),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.24)),
        ),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.vpnSettingsPrivacySecurityTitle),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
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
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () async {
                final uri = Uri.parse("https://colourswift.com/Private-Policy");
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: const Text("Privacy Policy"),
            ),
          ),
        ],
      ),
    );
  }
}