import 'package:flutter/material.dart';
import '../../../translations/app_localizations.dart';
import '../services/full_vpn_backend.dart';
import '../services/sound_controller/vpn_sound_controller.dart';

class FullVpnSoundSettingsScreen extends StatefulWidget {
  final FullVpnController c;

  const FullVpnSoundSettingsScreen({
    super.key,
    required this.c,
  });

  @override
  State<FullVpnSoundSettingsScreen> createState() => _FullVpnSoundSettingsScreenState();
}

class _FullVpnSoundSettingsScreenState extends State<FullVpnSoundSettingsScreen> {
  VpnSoundController get sounds => widget.c.soundController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Connection sounds"),
      ),
      body: AnimatedBuilder(
        animation: sounds,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              SwitchListTile(
                value: sounds.enabled,
                onChanged: (v) async {
                  await sounds.setEnabled(v);
                  if (mounted) setState(() {});
                },
                contentPadding: EdgeInsets.zero,
                title: Text(
                  "Enable sounds",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  "Play sounds when the VPN connects or disconnects.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.2)),
              const SizedBox(height: 24),
              _SoundSection(
                title: "Connect sound",
                options: sounds.connectionSupported,
                selected: sounds.selectedConnectKey,
                enabled: sounds.enabled,
                onSelect: (key) async {
                  await sounds.setSelectedConnectKey(key);
                  await sounds.playConnect();
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 24),
              _SoundSection(
                title: "Disconnect sound",
                options: sounds.disconnectionSupported,
                selected: sounds.selectedDisconnectKey,
                enabled: sounds.enabled,
                onSelect: (key) async {
                  await sounds.setSelectedDisconnectKey(key);
                  await sounds.playDisconnect();
                  if (mounted) setState(() {});
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SoundSection extends StatelessWidget {
  final String title;
  final List<VpnSoundOption> options;
  final String selected;
  final bool enabled;
  final void Function(String key) onSelect;

  const _SoundSection({
    required this.title,
    required this.options,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < options.length; i++) ...[
          RadioListTile<String>(
            value: options[i].key,
            groupValue: selected,
            onChanged: enabled ? (v) { if (v != null) onSelect(v); } : null,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            title: Text(
              options[i].label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: selected == options[i].key
                    ? FontWeight.w900
                    : FontWeight.w600,
                color: enabled
                    ? scheme.onSurface
                    : scheme.onSurface.withOpacity(0.38),
              ),
            ),
          ),
          if (i < options.length - 1)
            Divider(
              height: 1,
              indent: 52,
              color: scheme.outlineVariant.withOpacity(0.16),
            ),
        ],
      ],
    );
  }
}