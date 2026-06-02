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
  bool _importing = false;

  Future<void> _handleImport() async {
    setState(() => _importing = true);
    final result = await sounds.importSound();
    if (!mounted) return;
    setState(() => _importing = false);

    if (result.error == null && result.sound != null) {
      await sounds.previewSound(result.sound!);
      return;
    }

    if (result.error == SoundImportError.longButAllowed && result.pendingPath != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("That's a long one"),
          content: const Text(
            'The recommended length is under 5 seconds.\nThis length will still work.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Import anyway'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;

      setState(() => _importing = true);
      final committed = await sounds.importSoundFromPath(result.pendingPath!);
      if (!mounted) return;
      setState(() => _importing = false);

      if (committed.sound != null) {
        await sounds.previewSound(committed.sound!);
      } else if (committed.error == SoundImportError.copyFailed) {
        await _showErrorDialog('Failed to save the sound.');
      }
      return;
    }

    final msg = switch (result.error!) {
      SoundImportError.cancelled => null,
      SoundImportError.tooLong => 'Sounds must be under 5 minutes.',
      SoundImportError.unreadable => 'Could not read that file.',
      SoundImportError.copyFailed => 'Failed to save the sound.',
      SoundImportError.longButAllowed => null,
    };
    if (msg != null) await _showErrorDialog(msg);
  }

  Future<void> _showErrorDialog(String msg) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import failed'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(VpnSoundOption option) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove sound'),
        content: Text('Remove "${option.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await sounds.deleteCustomSound(option.key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection sounds'),
        actions: [
          if (_importing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _handleImport,
              tooltip: 'Import sound',
            ),
        ],
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
                  'Enable sounds',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  'Play sounds when the VPN connects or disconnects.',
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
                title: 'Connect sound',
                sounds: sounds,
                selectedKey: sounds.selectedConnectKey,
                enabled: sounds.enabled,
                onSelect: (key) async {
                  await sounds.setSelectedConnectKey(key);
                  await sounds.playConnect();
                  if (mounted) setState(() {});
                },
                onDeleteCustom: _confirmDelete,
              ),
              const SizedBox(height: 24),
              _SoundSection(
                title: 'Disconnect sound',
                sounds: sounds,
                selectedKey: sounds.selectedDisconnectKey,
                enabled: sounds.enabled,
                onSelect: (key) async {
                  await sounds.setSelectedDisconnectKey(key);
                  await sounds.playDisconnect();
                  if (mounted) setState(() {});
                },
                onDeleteCustom: _confirmDelete,
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
  final VpnSoundController sounds;
  final String selectedKey;
  final bool enabled;
  final void Function(String key) onSelect;
  final void Function(VpnSoundOption option) onDeleteCustom;

  const _SoundSection({
    required this.title,
    required this.sounds,
    required this.selectedKey,
    required this.enabled,
    required this.onSelect,
    required this.onDeleteCustom,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final options = sounds.sounds;

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
          Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  value: options[i].key,
                  groupValue: selectedKey,
                  onChanged: enabled ? (v) { if (v != null) onSelect(v); } : null,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    options[i].label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selectedKey == options[i].key
                          ? FontWeight.w900
                          : FontWeight.w600,
                      color: enabled
                          ? scheme.onSurface
                          : scheme.onSurface.withOpacity(0.38),
                    ),
                  ),
                ),
              ),
              if (options[i].isCustom)
                GestureDetector(
                  onTap: () => onDeleteCustom(options[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: scheme.onSurfaceVariant.withOpacity(0.6),
                    ),
                  ),
                ),
            ],
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