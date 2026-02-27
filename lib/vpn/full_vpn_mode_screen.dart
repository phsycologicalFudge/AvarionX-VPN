import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:colourswift_av/vpn/services/full_vpn_backend.dart';
import 'package:colourswift_av/vpn/settings/full_vpn_settings_tab.dart';
import 'package:colourswift_av/vpn/settings/full_vpn_upgrade_screen.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../translations/app_localizations.dart';
import '../services/purchase_service.dart';
import 'dns/NetworkProtectionScreen.dart';
import 'full_vpn_footer_nav.dart';
import 'services/full_vpn_location_map.dart';
import 'services/full_vpn_notification_worker.dart';
import 'vpn_permission_intro_screen.dart';
import 'package:flutter/services.dart';

class FullVpnModeScreen extends StatefulWidget {
  const FullVpnModeScreen({super.key});

  @override
  State<FullVpnModeScreen> createState() => _FullVpnModeScreenState();
}

class _FullVpnModeScreenState extends State<FullVpnModeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final FullVpnController c;
  late final AnimationController _glowCtrl;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;
  bool _closing = false;
  String _tab = "connection";

  final FullVpnNotificationWorker _notifWorker = FullVpnNotificationWorker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    c = FullVpnController(
      apiBase: "https://api.colourswift.com",
      loginUrl: "https://api.colourswift.com/login",
      deepLinkPrefix: "colourswift://auth?token=",
    );

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )
      ..repeat();

    c.init();
    c.addListener(_onControllerChanged);
    _initDeepLinks();
  }

  @override
  void dispose() {
    _closing = true;
    _linkSub?.cancel();
    _linkSub = null;
    WidgetsBinding.instance.removeObserver(this);
    _glowCtrl.dispose();
    c.removeListener(_onControllerChanged);
    c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      c.onResumed();
    }
  }

  ThemeData _darkTheme(BuildContext context) {
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
      tertiary: const Color(0xFF60A5FA),
      onTertiary: const Color(0xFF0B1220),
      tertiaryContainer: const Color(0xFF0B2545),
      onTertiaryContainer: const Color(0xFFE7ECF5),
      primaryContainer: const Color(0xFF0B2545),
      onPrimaryContainer: const Color(0xFFE7ECF5),
      secondaryContainer: const Color(0xFF0B2545),
      onSecondaryContainer: const Color(0xFFE7ECF5),
    );

    return base.copyWith(
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withOpacity(0.25),
        selectionHandleColor: scheme.primary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant.withOpacity(0.45)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
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
      dividerColor: scheme.outlineVariant.withOpacity(0.35),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          backgroundColor: const Color(0xFF1F2937),
          foregroundColor: const Color(0xFFE7ECF5),
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

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    Future<void> handle(Uri? uri) async {
      if (uri == null) return;
      if (_closing || !mounted) return;

      final u = uri.toString();
      if (!u.startsWith("colourswift://auth")) return;

      final token = uri.queryParameters["token"] ?? "";
      if (token.isEmpty) return;

      await c.setTokenFromLogin(token);

      if (_closing || !mounted) return;

      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    }

    try {
      final initial = await _appLinks.getInitialLink();
      await handle(initial);
    } catch (_) {}

    _linkSub?.cancel();
    _linkSub = _appLinks.uriLinkStream.listen((uri) async {
      await handle(uri);
    });
  }

  Future<void> _showServerSheet(BuildContext context) async {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: c.servers.length,
                itemBuilder: (_, index) {
                  final s = c.servers[index];
                  final selected = s.id == c.selectedServerId;
                  final code = s.countryCode.toUpperCase();

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primary.withOpacity(0.12)
                          : scheme.surface.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? scheme.primary
                            : scheme.outlineVariant.withOpacity(0.25),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      leading: CountryFlag.fromCountryCode(
                        code,
                        height: 22,
                        width: 32,
                      ),
                      title: Text(
                        s.label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      trailing: selected
                          ? Icon(Icons.check_rounded, color: scheme.primary)
                          : null,
                      onTap: () async {
                        Navigator.pop(ctx);
                        await c.switchServer(s);
                      },
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showSignInPopup() async {
    final vpnTheme = _darkTheme(context);
    final scheme = vpnTheme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Theme(
          data: vpnTheme,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: scheme.outlineVariant.withOpacity(0.25),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.surfaceContainerHighest.withOpacity(0.95),
                      scheme.surface.withOpacity(0.90),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withOpacity(0.12),
                      blurRadius: 80,
                      spreadRadius: -20,
                      offset: const Offset(0, 30),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.vpnSignInRequiredTitle,
                              style: vpnTheme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                            splashRadius: 20,
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.vpnSignInRequiredBody,
                        style: vpnTheme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _openPrivacyPolicy,
                        child: Text(
                          l10n.vpnPrivacyPolicy,
                          style: vpnTheme.textTheme.bodyMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: scheme.onSurface,
                                side: BorderSide(
                                  color: scheme.outlineVariant.withOpacity(0.4),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              child: Text(l10n.vpnCancel),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                Navigator.pop(ctx);
                                await c.startLoginInBrowser();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: scheme.primary,
                                foregroundColor: scheme.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                              child: Text(l10n.vpnSignIn),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _ensureVpnPermissionIntro() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(VpnPermissionIntroScreen.kDoneKey);

    if (done == true) return true;

    bool hasPerm = false;
    try {
      const chan = MethodChannel("cs_vpn_permission");
      final res = await chan.invokeMethod("prepareVpn");
      hasPerm = res == true || res == null;
    } catch (_) {
      hasPerm = false;
    }

    if (hasPerm) {
      await prefs.setBool(VpnPermissionIntroScreen.kDoneKey, true);
      return true;
    }

    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const VpnPermissionIntroScreen(),
      ),
    );

    return res == true;
  }

  Widget _serverSelector(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (c.servers.isEmpty) {
      return Text(
        "No servers",
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    final selected = c.servers.firstWhere(
          (s) => s.id == c.selectedServerId,
      orElse: () => c.servers.first,
    );

    final countryCode = selected.countryCode.toUpperCase();

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: c.busy ? null : () => _showServerSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CountryFlag.fromCountryCode(
              countryCode,
              height: 18,
              width: 26,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                selected.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  String _ipv4Only(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return "";
    final m = RegExp(
      r'\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b',
    ).firstMatch(s);
    if (m != null) return m.group(0) ?? "";
    if (s.contains(":")) return "";
    return s;
  }

  Widget _usageRow(BuildContext context, {bool showWhenDisconnected = false}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (!c.connected && !showWhenDisconnected) {
      return const SizedBox.shrink();
    }

    final syncing = c.usageSyncing;

    if (!c.usageEverLoaded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.vpnUsageLoading,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          const LinearProgressIndicator(minHeight: 6),
        ],
      );
    }

    if (c.unlimited) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.vpnUsageNoLimits,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              AnimatedOpacity(
                opacity: syncing ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Text(
                  l10n.vpnUsageSyncing,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "${c.formatBytes(c.usedBytes)} used this month",
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final uiLimit = c.effectiveUiLimitBytes;
    if (uiLimit > 0) {
      final target = (c.usedBytes / uiLimit).clamp(0.0, 1.0);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.vpnUsageDataTitle,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              AnimatedOpacity(
                opacity: syncing ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Text(
                  "Syncing",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: target,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 6),
          Text(
            "${c.formatBytes(c.usedBytes)} / ${c.formatBytes(uiLimit)}",
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }

    return Text(
      l10n.vpnUsageUnavailable,
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  Widget _connectionScreen(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final city = c.uiCity;
    final country = c.uiCountry;
    final ip4 = _ipv4Only(c.uiIp);

    final mapHeader = c.connectingUi
        ? l10n.vpnStatusConnectingEllipsis
        : (c.connected
        ? (country.isNotEmpty
        ? l10n.vpnStatusConnectedTo(country)
        : l10n.vpnStatusConnected)
        : l10n.vpnTitleSecure);

    final lat = c.locLat() ?? c.lastLat;
    final lon = c.locLon() ?? c.lastLon;

    final canConnect = !c.connected && !c.busy && !c.softCapReached && !c.connectingUi;
    final canDisconnect = c.connected && !c.busy;

    final connectStyle = ElevatedButton.styleFrom(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      disabledBackgroundColor: scheme.surface.withOpacity(0.35),
      disabledForegroundColor: scheme.onSurfaceVariant.withOpacity(0.8),
    );

    final disconnectStyle = OutlinedButton.styleFrom(
      foregroundColor: scheme.onSurface,
      side: BorderSide(color: scheme.outlineVariant.withOpacity(0.45)),
      disabledForegroundColor: scheme.onSurfaceVariant.withOpacity(0.8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      textStyle: const TextStyle(fontWeight: FontWeight.w800),
    );

    final titleCountry = c.connectingUi
        ? l10n.vpnStatusConnectingEllipsis
        : (c.connected
        ? (country.isNotEmpty ? country : l10n.vpnTitleSecure)
        : l10n.vpnTitleSecure);

    final subtitle = c.connectingUi
        ? l10n.vpnSubtitleEstablishingTunnel
        : (c.connected
        ? (city.isNotEmpty && country.isNotEmpty
        ? "$city, $country"
        : (country.isNotEmpty ? country : l10n.vpnSubtitleFindingLocation))
        : l10n.vpnStatusNotConnected);

    final ipLine = (c.connected && !c.connectingUi && ip4.isNotEmpty) ? ip4 : "";

    final statusLabel = c.connectingUi
        ? l10n.networkStatusConnecting
        : (c.connected ? l10n.vpnStatusProtected : l10n.vpnStatusNotConnected);

    final statusTone = c.connectingUi
        ? scheme.tertiaryContainer
        : (c.connected
        ? const Color(0xFF0B3B24)
        : scheme.surface.withOpacity(0.30));

    final statusTextTone = c.connectingUi
        ? scheme.onTertiaryContainer
        : (c.connected
        ? const Color(0xFFBFF7D4)
        : scheme.onSurface.withOpacity(0.92));

    final connectLabel =
    c.connectingUi ? l10n.vpnStatusConnectingEllipsis : l10n.vpnConnect;

    final cardContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: scheme.surface.withOpacity(0.28),
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.outlineVariant.withOpacity(0.25),
                ),
              ),
              child: Icon(
                c.connected ? Icons.verified_user_rounded : Icons.shield_outlined,
                color: scheme.onSurface.withOpacity(0.92),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleCountry,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                      height: 1.05,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surface.withOpacity(0.26),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: scheme.outlineVariant.withOpacity(0.25),
                ),
              ),
              child: _serverSelector(context),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: statusTone,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: scheme.outlineVariant.withOpacity(0.22),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusTextTone.withOpacity(0.95),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: statusTextTone,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            if (ipLine.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: scheme.surface.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: scheme.outlineVariant.withOpacity(0.22),
                  ),
                ),
                child: Text(
                  l10n.vpnIpLabel(ipLine),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurface.withOpacity(0.92),
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _usageRow(context),
        const SizedBox(height: 16),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: canConnect
                    ? () async {
                  if (c.token.isEmpty) {
                    await _showSignInPopup();
                    return;
                  }
                  final ok = await _ensureVpnPermissionIntro();
                  if (!ok) return;
                  await c.connect();
                }
                    : null,
                style: connectStyle,
                child: Text(connectLabel),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: canDisconnect
                    ? () async {
                  _notifWorker.resetCache();
                  await c.disconnect();
                }
                    : null,
                style: disconnectStyle,
                child: Text(l10n.vpnDisconnect),
              ),
            ),
          ],
        ),
        if (c.softCapReached) ...[
          const SizedBox(height: 8),
          Text(
            "Free monthly limit reached. Upgrade for unlimited VPN.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );

    return Stack(
      children: [
        Positioned.fill(
          child: FullVpnLocationMapCard(
            lat: lat,
            lon: lon,
            connected: c.connected,
            isConnecting: c.connectingUi,
            headerText: mapHeader,
            servers: c.servers,
            selectedServerId: c.selectedServerId,
            onServerTap: (s) {
              c.selectServerPreview(s);
            },
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: _glowCtrl,
              builder: (context, _) {
                final t = _glowCtrl.value;
                final a = (t * 2) - 1;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: scheme.outlineVariant.withOpacity(0.22),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment(-1 + a, -1),
                        end: Alignment(1 + a, 1),
                        colors: [
                          scheme.primaryContainer.withOpacity(0.18),
                          scheme.surfaceContainerHighest.withOpacity(0.86),
                          scheme.primaryContainer.withOpacity(0.14),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withOpacity(0.10),
                          blurRadius: 90,
                          spreadRadius: -18,
                          offset: const Offset(0, 28),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: cardContent,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _customisationScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final pro = _hasAnyProEntitlement();

    final entries = c.blocklists.entries.toList();

    bool isMalwareKey(String k) {
      final s = k.toLowerCase().trim();
      if (s == "malware") return true;
      if (s.contains("malware")) return true;
      if (s.contains("threat")) return true;
      if (s.contains("phishing")) return true;
      return false;
    }

    final malware = <MapEntry<String, bool>>[];
    final premium = <MapEntry<String, bool>>[];

    for (final e in entries) {
      if (isMalwareKey(e.key)) {
        malware.add(e);
      } else {
        premium.add(e);
      }
    }

    malware.sort((a, b) => a.key.compareTo(b.key));
    premium.sort((a, b) => a.key.compareTo(b.key));

    Widget premiumHeader() {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                "[Premium]",
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
              ),
            ),
            if (!pro)
              Text(
                "pro required",
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      );
    }

    Widget tile(
        MapEntry<String, bool> e, {
          required bool enabled,
          required bool forceOff,
        }) {
      final value = forceOff ? false : e.value;

      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: value,
        title: Text(
          e.key.toLowerCase(),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
        onChanged: !enabled
            ? null
            : (v) async {
          final m = c.blocklists;
          if (m is Map<String, bool>) {
            m[e.key] = v;
            await c.persistBlocklists();
            c.notifyListeners();
          }
        },
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        Text(
          l10n.vpnBlocklistsTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),

        ...malware.map((e) => tile(e, enabled: true, forceOff: false)).toList(),

        premiumHeader(),
        Opacity(
          opacity: pro ? 1.0 : 0.55,
          child: Column(
            children: premium
                .map((e) => tile(e, enabled: pro, forceOff: !pro))
                .toList(),
          ),
        ),

        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: c.busy
                ? null
                : () async {
              if (c.token.isEmpty) {
                await _showSignInPopup();
                return;
              }
              await c.saveDnsSettings();
            },
            child: Text(l10n.vpnSave),
          ),
        ),
      ],
    );
  }

  Widget _settingsScreen(BuildContext context) {
    return FullVpnSettingsTab(
      c: c,
      usageRow: _usageRow,
    );
  }

  Future<void> _pushUsageToNotification() async {
    await _notifWorker.pushUsage(
      connected: c.connected,
      connectingUi: c.connectingUi,
      unlimited: c.unlimited,
      usedBytes: c.usedBytes,
      uiLimitBytes: c.effectiveUiLimitBytes,
      formatBytes: c.formatBytes,
    );
  }

  void _onControllerChanged() {
    _pushUsageToNotification();
  }

  bool _hasAnyProEntitlement() {
    final serverPlan = (c.me?["plan"] ?? "").toString().trim().toLowerCase();
    return PurchaseService.isPro || serverPlan == "pro";
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _darkTheme(context),
      child: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          Widget body;
          if (_tab == "dns") {
            body = const NetworkProtectionScreen();
          } else if (_tab == "customisation") {
            body = _customisationScreen(context);
          } else if (_tab == "settings") {
            body = _settingsScreen(context);
          } else {
            body = _connectionScreen(context);
          }

          return Scaffold(
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: AppBar(
                toolbarHeight: 44,
                automaticallyImplyLeading: false,
                elevation: 0,
                backgroundColor: Colors.transparent,
                actions: _hasAnyProEntitlement()
                    ? const []
                    : [
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Center(
                      child: SizedBox(
                        height: 28,
                        child: TextButton(
                          onPressed: () {
                            final vpnTheme = _darkTheme(context);

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Theme(
                                  data: vpnTheme,
                                  child: const FullVpnUpgradeScreen(),
                                ),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: Size.zero,
                            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            foregroundColor: const Color(0xFFFFE7A3),
                            backgroundColor: const Color(0xFFB8860B).withOpacity(0.22),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                              side: BorderSide(
                                color: const Color(0xFFB8860B).withOpacity(0.45),
                              ),
                            ),
                          ),
                          child: const Text(
                            "Upgrade",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              height: 1.0,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                flexibleSpace: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    color: c.connected
                        ? const Color(0xFF1B7F4B)
                        : Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withOpacity(0.55),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Builder(
                          builder: (context) {
                            final country = c.uiCountry;
                            final ip = _ipv4Only(c.uiIp);
                            final l10n = AppLocalizations.of(context)!;

                            final topLine = c.connectingUi
                                ? (c.connected
                                ? "Securing connection..."
                                : l10n.vpnStatusConnectingEllipsis)
                                : (c.connected
                                ? (country.isNotEmpty
                                ? l10n.vpnStatusConnectedTo(country)
                                : l10n.vpnStatusConnected)
                                : l10n.vpnTitleSecure);

                            final showIp =
                                c.connected && !c.connectingUi && ip.isNotEmpty;

                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  topLine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                                if (showIp)
                                  Text(
                                    ip,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            body: SafeArea(child: body),
            bottomNavigationBar: FullVpnFooterNav(
              active: _tab,
              onTabChange: (t) {
                setState(() => _tab = t);
              },
            ),
          );
        },
      ),
    );
  }
}

class _LoginWebView extends StatefulWidget {
  final String initialUrl;
  final String deepLinkPrefix;
  final Future<void> Function(String token) onToken;

  const _LoginWebView({
    required this.initialUrl,
    required this.deepLinkPrefix,
    required this.onToken,
  });

  @override
  State<_LoginWebView> createState() => _LoginWebViewState();
}

class _LoginWebViewState extends State<_LoginWebView> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (req) async {
            final url = req.url;
            if (url.startsWith(widget.deepLinkPrefix)) {
              final token = Uri.parse(url).queryParameters["token"] ?? "";
              if (token.isNotEmpty) {
                await widget.onToken(token);
              }
              if (mounted) Navigator.of(context).pop();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.vpnSignIn),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}