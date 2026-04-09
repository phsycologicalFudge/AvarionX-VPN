import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:colourswift_av/vpn/services/full_vpn_backend.dart';
import 'package:colourswift_av/vpn/services/threeD/full_vpn_globe_card.dart';
import 'package:colourswift_av/vpn/settings/full_vpn_settings_tab.dart';
import 'package:colourswift_av/vpn/settings/full_vpn_upgrade_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../translations/app_localizations.dart';
import '../../services/purchase_service.dart';
import '../dns/NetworkProtectionScreen.dart';
import '../full_vpn_footer_nav.dart';
import '../services/full_vpn_location_map.dart';
import '../services/full_vpn_server_locations.dart';
import '../services/full_vpn_notification_worker.dart';
import '../vpn_permission_intro_screen.dart';
import 'package:flutter/services.dart';
import 'package:colourswift_av/vpn/widgets/full_vpn_server_picker_sheet.dart';
import 'package:colourswift_av/vpn/widgets/full_vpn_server_selector_chip.dart';
import 'full_vpn_customisation_screen.dart';
import 'full_vpn_dns_tab.dart';
import 'package:app_links/app_links.dart';
import 'dart:ui' as ui;

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
  String _mapView = "flat";

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
    )..repeat();

    c.init();
    c.addListener(_onControllerChanged);
    _initDeepLinks();
    _loadMapView();
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

  Future<void> _loadMapView() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString("vpn_map_view");
    if (!mounted) return;
    setState(() {
      _mapView = saved == "globe" ? "globe" : "flat";
    });
  }

  Future<void> _setMapView(String value) async {
    if (_mapView == value) return;
    setState(() {
      _mapView = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("vpn_map_view", value);
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
        selectionColor: scheme.primary.withValues(alpha: 0.25),
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
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
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
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.35),
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
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.95),
        contentTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }

  bool _isAwgNode(FullVpnServerLocation s) {
    return s.id.toLowerCase().startsWith("awg-");
  }

  bool _isHysteriaNode(FullVpnServerLocation s) {
    return s.id.toLowerCase().startsWith("hy-");
  }

  List<FullVpnServerLocation> get _privacyServers {
    return c.servers.where((s) => !_isAwgNode(s) && !_isHysteriaNode(s)).toList();
  }

  List<FullVpnServerLocation> get _obfuscationServers {
    return c.servers.where(_isAwgNode).toList();
  }

  List<FullVpnServerLocation> get _stealthPlusServers {
    return c.servers.where(_isHysteriaNode).toList();
  }

  FullVpnServerLocation? get _freeObfuscationServer {
    for (final s in _obfuscationServers) {
      if (s.id.toLowerCase() == "awg-us") return s;
    }
    if (_obfuscationServers.isEmpty) return null;
    return _obfuscationServers.first;
  }

  bool _isServerUnlocked(FullVpnServerLocation server) {
    if (!_hasAnyProEntitlement()) {
      return false;
    }

    return true;
  }

  String _currentModeValue() {
    if (c.isHysteriaTransport) return "stealth_plus";
    if (c.isAmneziaTransport) return "obfuscation";
    return "privacy";
  }

  String _currentModeLabel() {
    final mode = _currentModeValue();
    if (mode == "stealth_plus") return "Stealth+";
    if (mode == "obfuscation") return "Obfuscation";
    return "Privacy";
  }

  String _countryName(String code) {
    switch (code.toUpperCase()) {
      case "US": return "United States";
      case "GB": return "United Kingdom";
      case "JP": return "Japan";
      case "DE": return "Germany";
      case "SG": return "Singapore";
      case "FI": return "Finland";
      case "FR": return "France";
      case "CA": return "Canada";
      case "PL": return "Poland";
      case "NL": return "Netherlands";
      case "AU": return "Australia";
      case "ES": return "Spain";
      default: return code.toUpperCase();
    }
  }

  String get _effectiveServerId {
    if (_hasAnyProEntitlement()) {
      return c.selectedServerId;
    }

    if (c.connected) {
      final countryLower = c.uiCountry.trim().toLowerCase();
      if (countryLower.isNotEmpty) {
        for (final s in c.servers) {
          final name = _countryName(s.countryCode).toLowerCase();
          final code = s.countryCode.toLowerCase();
          final label = s.label.toLowerCase();

          if (name == countryLower || code == countryLower || label.contains(countryLower)) {
            return s.id;
          }
        }
      }
    }

    final deviceCountry = ui.PlatformDispatcher.instance.locale.countryCode?.toUpperCase() ?? "";
    if (deviceCountry.isNotEmpty) {
      for (final s in c.servers) {
        if (s.countryCode.toUpperCase() == deviceCountry) {
          return s.id;
        }
      }
    }

    for (final s in c.servers) {
      if (s.countryCode.toUpperCase() == "US") return s.id;
    }

    return c.servers.isNotEmpty ? c.servers.first.id : c.selectedServerId;
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
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return FullVpnServerPickerSheet(
          privacyServers: _privacyServers,
          obfuscationServers: _obfuscationServers,
          stealthPlusServers: _stealthPlusServers,
          selectedServerId: c.selectedServerId,
          hasPro: _hasAnyProEntitlement(),
          initialMode: _currentModeValue(),
          isServerUnlocked: _isServerUnlocked,
          onSelect: (server, transport) async {
            if (!_isServerUnlocked(server)) return;
            Navigator.pop(ctx);
            await c.setVpnTransport(transport);
            await c.switchServer(server);
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
                    color: scheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.surfaceContainerHighest.withValues(alpha: 0.95),
                      scheme.surface.withValues(alpha: 0.90),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.12),
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
                                  color: scheme.outlineVariant.withValues(alpha: 0.4),
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
    final enabled = _hasAnyProEntitlement();

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: IgnorePointer(
        ignoring: !enabled,
        child: FullVpnServerSelectorChip(
          servers: c.servers,
          selectedServerId: _effectiveServerId,
          currentModeLabel: _currentModeLabel(),
          connected: c.connected,
          onTap: c.busy || !enabled ? null : () => _showServerSheet(context),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${c.formatBytes(c.usedBytes)} / ${c.formatBytes(uiLimit)}",
                style: theme.textTheme.bodySmall,
              ),
              if (c.token.isEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  "Fun fact: Signing in gives you 10 GB of free VPN usage every month.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ],
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

  Widget _mapViewToggle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget item({
      required String value,
      required IconData icon,
      required String label,
    }) {
      final selected = _mapView == value;

      return Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.22)
            : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _setMapView(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        item(
          value: "flat",
          icon: Icons.map_rounded,
          label: "2D",
        ),
        const SizedBox(height: 10),
        item(
          value: "globe",
          icon: Icons.public_rounded,
          label: "3D",
        ),
      ],
    );
  }

  Widget _connectionScreen(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final country = c.uiCountry;

    final mapHeader = c.connectingUi
        ? l10n.vpnStatusConnectingEllipsis
        : (c.connected
        ? (country.isNotEmpty
        ? l10n.vpnStatusConnectedTo(country)
        : l10n.vpnStatusConnected)
        : l10n.vpnTitleSecure);

    final lat = c.locLat() ?? c.lastLat;
    final lon = c.locLon() ?? c.lastLon;

    final canConnect =
        !c.connected && !c.busy && !c.softCapReached && !c.connectingUi;
    final canDisconnect = c.connected && !c.busy;

    final connectStyle = ElevatedButton.styleFrom(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      disabledBackgroundColor: scheme.surface.withValues(alpha: 0.35),
      disabledForegroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.8),
    );

    final disconnectStyle = OutlinedButton.styleFrom(
      foregroundColor: scheme.onSurface,
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      disabledForegroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      textStyle: const TextStyle(fontWeight: FontWeight.w800),
    );

    final connectLabel =
    c.connectingUi ? l10n.vpnStatusConnectingEllipsis : l10n.vpnConnect;

    final cardContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!c.connected) ...[
          Text(
            "You're unprotected",
            style: theme.textTheme.labelLarge?.copyWith(
              color: const Color(0xFFFF7A7A),
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 10),
        ],
        _serverSelector(context),
        const SizedBox(height: 10),
        _usageRow(context),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: canConnect
                    ? () async {
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
        if (!_hasAnyProEntitlement()) ...[
          const SizedBox(height: 8),
          Text(
            "Free access connects automatically to a standard server. Premium gives you manual location selection and extra connection options.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );

    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            reverseDuration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            transitionBuilder: (child, animation) {
              final fade = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              );

              final scale = Tween<double>(
                begin: 0.985,
                end: 1.0,
              ).animate(fade);

              return FadeTransition(
                opacity: fade,
                child: ScaleTransition(
                  scale: scale,
                  child: child,
                ),
              );
            },
            child: _mapView == "globe"
                ? FullVpnGlobeCard(
              key: const ValueKey("globe"),
              lat: lat,
              lon: lon,
              connected: c.connected,
              isConnecting: c.connectingUi,
              headerText: mapHeader,
              servers: c.servers,
              selectedServerId: _effectiveServerId,
              onServerTap: (s) {
                c.selectServerPreview(s);
              },
            )
                : FullVpnLocationMapCard(
              key: const ValueKey("flat"),
              lat: lat,
              lon: lon,
              connected: c.connected,
              isConnecting: c.connectingUi,
              headerText: mapHeader,
              servers: c.servers,
              selectedServerId: _effectiveServerId,
              onServerTap: (s) {
                c.selectServerPreview(s);
              },
            ),
          ),
        ),
        Positioned(
          top: 230,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: _mapViewToggle(context),
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
                        color: scheme.outlineVariant.withValues(alpha: 0.22),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment(-1 + a, -1),
                        end: Alignment(1 + a, 1),
                        colors: [
                          scheme.primaryContainer.withValues(alpha: 0.18),
                          scheme.surfaceContainerHighest.withValues(alpha: 0.86),
                          scheme.primaryContainer.withValues(alpha: 0.14),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.10),
                          blurRadius: 90,
                          spreadRadius: -18,
                          offset: const Offset(0, 28),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
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
    if (c.token.isEmpty || c.me == null) return false;
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
            body = const FullVpnDnsTab();
          } else if (_tab == "customisation") {
            body = FullVpnCustomisationScreen(
              c: c,
              hasProEntitlement: _hasAnyProEntitlement(),
              onRequireSignIn: _showSignInPopup,
            );
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
                actions: [
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
                            foregroundColor: _hasAnyProEntitlement()
                                ? const Color(0xFFBFF7D4)
                                : const Color(0xFFFFE7A3),
                            backgroundColor: _hasAnyProEntitlement()
                                ? const Color(0xFF1B7F4B).withValues(alpha: 0.22)
                                : const Color(0xFFB8860B).withValues(alpha: 0.22),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                              side: BorderSide(
                                color: _hasAnyProEntitlement()
                                    ? const Color(0xFF1B7F4B).withValues(alpha: 0.45)
                                    : const Color(0xFFB8860B).withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                          child: Text(
                            _hasAnyProEntitlement() ? "Premium" : "Upgrade",
                            style: const TextStyle(
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
                        .withValues(alpha: 0.55),
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