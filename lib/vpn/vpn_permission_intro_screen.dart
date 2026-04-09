import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../translations/app_localizations.dart';
import 'screens/mainScreen.dart';
import 'package:flutter/services.dart';

class VpnPermissionIntroScreen extends StatefulWidget {
  const VpnPermissionIntroScreen({super.key});

  static const kDoneKey = "vpn_permission_intro_done";

  @override
  State<VpnPermissionIntroScreen> createState() => _VpnPermissionIntroScreenState();
}

class _VpnPermissionIntroScreenState extends State<VpnPermissionIntroScreen> {
  bool _busy = false;

  ThemeData _vpnDarkTheme() {
    const bg = Color(0xFF0B1220);
    const surface = Color(0xFF111827);
    const surface2 = Color(0xFF1F2937);
    const accent = Color(0xFF60A5FA);

    final base = ThemeData.dark(useMaterial3: true);
    final scheme = base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: accent,
      secondary: accent,
      surface: surface,
      surfaceContainerHighest: surface2,
      background: bg,
      onSurface: const Color(0xFFE7ECF5),
      onSurfaceVariant: const Color(0xFFB7C1D6),
      outline: const Color(0xFF22304A),
      outlineVariant: const Color(0xFF1B2740),
      tertiary: accent,
      onTertiary: bg,
      tertiaryContainer: const Color(0xFF0B2545),
      onTertiaryContainer: const Color(0xFFE7ECF5),
      primaryContainer: const Color(0xFF0B2545),
      onPrimaryContainer: const Color(0xFFE7ECF5),
      secondaryContainer: const Color(0xFF0B2545),
      onSecondaryContainer: const Color(0xFFE7ECF5),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: Color(0xFFE7ECF5),
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface2,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant.withOpacity(0.4)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Future<void> _openPrivacyPolicy() async {
    const u = "https://colourswift.com/Policies/Private-Policy";
    final ok = await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("Failed to open Privacy Policy.")),
      );
    }
  }

  Future<void> _markDoneAndClose({required bool accepted}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(VpnPermissionIntroScreen.kDoneKey, accepted);
    if (!mounted) return;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(accepted);
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const FullVpnModeScreen()),
    );
  }

  Future<void> _skip() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _markDoneAndClose(accepted: false);
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() => _busy = true);

    bool ok = false;
    try {
      const chan = MethodChannel("cs_vpn_permission");
      final res = await chan.invokeMethod("prepareVpn");
      ok = res == true || res == null;
    } catch (_) {
      ok = false;
    }

    if (!mounted) return;

    if (!ok) {
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("VPN permission was not granted.")),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(VpnPermissionIntroScreen.kDoneKey, true);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const FullVpnModeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Theme(
      data: _vpnDarkTheme(),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;

          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.vpnTitleSecure),
              actions: [
                TextButton(
                  onPressed: _busy ? null : _skip,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                  child: const Text("Skip"),
                ),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.surface.withOpacity(0.35),
                        border: Border.all(color: scheme.outlineVariant.withOpacity(0.28)),
                      ),
                      child: Icon(
                        Icons.vpn_lock_rounded,
                        size: 34,
                        color: scheme.primary.withOpacity(0.95),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      "VPN permission required",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "AvarionX VPN creates a secure, encrypted connection and applies your selected DNS blocklists. You can turn it off at any time.",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _busy ? null : _openPrivacyPolicy,
                      child: Text(
                        l10n.vpnPrivacyPolicy,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _continue,
                        child: Text(_busy ? "Continuing..." : "Continue"),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _busy ? null : _skip,
                        child: const Text("Skip"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}