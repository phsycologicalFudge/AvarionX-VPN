import 'dart:async';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../translations/app_localizations.dart';
import '../services/full_vpn_backend.dart';

class FullVpnAccountScreen extends StatefulWidget {
  final FullVpnController c;

  const FullVpnAccountScreen({super.key, required this.c});

  @override
  State<FullVpnAccountScreen> createState() => _FullVpnAccountScreenState();
}

class _FullVpnAccountScreenState extends State<FullVpnAccountScreen> {
  static const String _accountLockPrefKey = 'vpn_account_lock_enabled';

  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _refreshing = false;
  bool _authChecked = false;
  bool _authPassed = false;
  bool _authAvailable = false;
  bool _authInProgress = false;
  bool _accountLockEnabled = false;

  FullVpnController get c => widget.c;

  @override
  void initState() {
    super.initState();
    c.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _prepareAccess();
      await _refresh();
    });
  }

  @override
  void dispose() {
    c.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _prepareAccess() async {
    final signedIn = c.token.isNotEmpty && c.me != null;
    if (!signedIn) {
      if (mounted) {
        setState(() {
          _authChecked = true;
          _authPassed = true;
          _authAvailable = false;
          _accountLockEnabled = false;
        });
      }
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLockEnabled = prefs.getBool(_accountLockPrefKey) ?? false;
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      final authAvailable = isSupported || canCheckBiometrics || availableBiometrics.isNotEmpty;

      if (!mounted) return;

      setState(() {
        _authAvailable = authAvailable;
        _accountLockEnabled = savedLockEnabled && authAvailable;
        _authChecked = true;
        _authPassed = !savedLockEnabled || !authAvailable;
      });

      if (savedLockEnabled && !authAvailable) {
        await prefs.setBool(_accountLockPrefKey, false);
      }

      if (_accountLockEnabled) {
        await _authenticate();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _authChecked = true;
        _authPassed = true;
        _authAvailable = false;
        _accountLockEnabled = false;
      });
    }
  }

  Future<void> _setAccountLockEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_accountLockPrefKey, enabled);
    } catch (_) {}
  }

  Future<void> _authenticate() async {
    if (_authInProgress) return;

    if (mounted) setState(() => _authInProgress = true);

    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Unlock your account',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (!mounted) return;

      setState(() {
        _authPassed = didAuthenticate;
        _authChecked = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _authPassed = false;
        _authChecked = true;
      });
    } finally {
      if (mounted) setState(() => _authInProgress = false);
    }
  }

  Future<void> _toggleLock() async {
    if (_authInProgress) return;

    if (_accountLockEnabled) {
      await _setAccountLockEnabled(false);
      if (!mounted) return;
      setState(() {
        _accountLockEnabled = false;
      });
      return;
    }

    if (!_authAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set up device lock, fingerprint, or face unlock first.'),
        ),
      );
      return;
    }

    if (mounted) setState(() => _authInProgress = true);

    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Lock this screen behind authentication',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (!mounted) return;

      if (!didAuthenticate) return;

      await _setAccountLockEnabled(true);

      if (!mounted) return;
      setState(() {
        _accountLockEnabled = true;
        _authPassed = true;
      });
    } finally {
      if (mounted) setState(() => _authInProgress = false);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || c.token.isEmpty) return;
    setState(() => _refreshing = true);
    try {
      await c.refreshMe();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _formatPlanExpiry(dynamic raw) {
    if (raw == null) return "";
    final ts = raw is int ? raw : int.tryParse(raw.toString());
    if (ts == null || ts <= 0) return "";
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
    return "${months[dt.month - 1]} ${dt.day}, ${dt.year}";
  }

  String _planLabel(Map<String, dynamic> me) {
    if (me["isPro"] == true) return "Pro";
    final plan = (me["plan"] ?? "").toString().trim().toLowerCase();
    if (plan == "standard") return "Standard";
    return "Free";
  }

  Widget _infoRow(
      BuildContext context, {
        required String label,
        required String value,
        Color? valueColor,
        bool showDivider = true,
        Widget? trailing,
      }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: trailing ??
                    Text(
                      value,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: valueColor ?? scheme.onSurface,
                      ),
                    ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant.withOpacity(0.16)),
      ],
    );
  }

  Widget _sectionCard(BuildContext context, {required List<Widget> children}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.18)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: children),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _actionButton(
      BuildContext context, {
        required String label,
        required VoidCallback? onTap,
        Color? color,
      }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        textAlign: TextAlign.end,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: onTap == null
              ? scheme.onSurfaceVariant.withOpacity(0.4)
              : (color ?? scheme.primary),
        ),
      ),
    );
  }

  Widget _signedInBody(BuildContext context, Map<String, dynamic> me) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final email = (me["email"] ?? "").toString().trim();
    final emailSecondary =
    (me["emailSecondary"] ?? me["email_secondary"] ?? "").toString().trim();
    final hasPrivateKey = me["has_private_key"] == true;
    final isPro = me["isPro"] == true;
    final planLabel = _planLabel(me);
    final planExpiresAt = me["planExpiresAt"] ?? me["plan_expires_at"];
    final expiryStr = _formatPlanExpiry(planExpiresAt);

    final rawLimit = me["simultaneousLimit"] ?? me["simultaneous_limit"];
    final rawActive = me["connectedDeviceCount"] ?? me["connected_device_count"];

    final String deviceStr;
    if (rawLimit != null && rawActive != null) {
      deviceStr = "$rawActive of $rawLimit";
    } else if (rawLimit != null) {
      deviceStr = "— of $rawLimit";
    } else {
      deviceStr = "—";
    }

    Color? deviceColor;
    if (rawLimit != null && rawActive != null) {
      final active = rawActive is int ? rawActive : int.tryParse(rawActive.toString()) ?? 0;
      final limit  = rawLimit  is int ? rawLimit  : int.tryParse(rawLimit.toString())  ?? 0;
      if (limit > 0 && active >= limit) deviceColor = Colors.red;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, "Identity"),
        _sectionCard(context, children: [
          _infoRow(context,
            label: "Primary email",
            value: email.isEmpty ? "Not set" : email,
            valueColor: email.isEmpty ? scheme.onSurfaceVariant : null,
          ),
          _infoRow(context,
            label: "Backup email",
            value: emailSecondary.isEmpty ? "Not set" : emailSecondary,
            valueColor: emailSecondary.isEmpty ? scheme.onSurfaceVariant : null,
          ),
          _infoRow(context,
            label: "Private key",
            value: hasPrivateKey ? "Configured" : "Not set",
            valueColor: hasPrivateKey ? Colors.green : scheme.onSurfaceVariant,
            showDivider: false,
          ),
        ]),
        const SizedBox(height: 22),
        _sectionLabel(context, "Plan"),
        _sectionCard(context, children: [
          _infoRow(context,
            label: "Current plan",
            value: planLabel,
            valueColor: isPro ? scheme.primary : null,
            showDivider: expiryStr.isNotEmpty || rawLimit != null,
          ),
          if (expiryStr.isNotEmpty)
            _infoRow(context,
              label: "Renews",
              value: expiryStr,
              showDivider: rawLimit != null,
            ),
          if (rawLimit != null)
            _infoRow(context,
              label: "Connected devices",
              value: deviceStr,
              valueColor: deviceColor,
              showDivider: false,
            ),
        ]),
        const SizedBox(height: 22),
        _sectionLabel(context, "Actions"),
        _sectionCard(context, children: [
          _infoRow(context,
            label: "Manage subscription",
            value: "",
            trailing: _actionButton(
              context,
              label: "Open Dashboard",
              onTap: () async {
                final uri = Uri.parse("https://api.colourswift.com/account");
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          ),
          _infoRow(context,
            label: "Session",
            value: "",
            showDivider: false,
            trailing: _actionButton(
              context,
              label: l10n.vpnSettingsSignOut,
              color: Colors.red,
              onTap: c.busy
                  ? null
                  : () async {
                await c.signOut();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ),
        ]),
      ],
    );
  }

  Widget _signedOutBody(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.vpnSettingsSignInToContinue,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.vpnSettingsAccountSyncBody,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: c.busy ? null : c.startLoginInBrowser,
            child: Text(l10n.vpnSignIn),
          ),
        ),
      ],
    );
  }

  Widget _lockedBody(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_rounded,
              size: 44,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              "Unlock required",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Use your device security to open this account screen.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _authInProgress ? null : _authenticate,
                child: const Text("Unlock"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedIn = c.token.isNotEmpty && c.me != null;
    final showLockToggle = signedIn && (!_accountLockEnabled || _authPassed);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Account"),
        centerTitle: false,
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (signedIn && showLockToggle)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _refresh,
            ),
          if (showLockToggle)
            IconButton(
              icon: Icon(
                _accountLockEnabled ? Icons.lock_rounded : Icons.lock_open_rounded,
              ),
              onPressed: _authInProgress ? null : _toggleLock,
            ),
        ],
      ),
      body: !_authChecked
          ? const Center(child: CircularProgressIndicator())
          : (!signedIn || !_accountLockEnabled || _authPassed)
          ? SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: signedIn
            ? _signedInBody(context, c.me!)
            : _signedOutBody(context),
      )
          : _lockedBody(context),
    );
  }
}