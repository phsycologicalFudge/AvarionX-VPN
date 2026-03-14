import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/purchase_service.dart';
import '../../../translations/app_localizations.dart';

enum VpnProPlanType { yearly, monthly }

class FullVpnUpgradeScreen extends StatefulWidget {
  const FullVpnUpgradeScreen({super.key});

  @override
  State<FullVpnUpgradeScreen> createState() => _FullVpnUpgradeScreenState();
}

class _FullVpnUpgradeScreenState extends State<FullVpnUpgradeScreen> {
  VpnProPlanType _selected = VpnProPlanType.yearly;
  bool _loading = true;
  bool _buying = false;

  PlanPriceInfo? _monthlyInfo;
  PlanPriceInfo? _yearlyInfo;

  bool _isPro = false;
  VpnProPlanType? _currentPlanType;
  String _currentStatusLabel = 'Free';

  @override
  void initState() {
    super.initState();
    _loadDefaultPlan();
    _loadPrices();
    _loadCurrentStatus();
  }

  Future<void> _loadDefaultPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('pro_default_plan') ?? 'yearly';
    if (!mounted) return;
    setState(() {
      _selected = v == 'monthly' ? VpnProPlanType.monthly : VpnProPlanType.yearly;
    });
  }

  Future<void> _persistDefaultPlan(VpnProPlanType p) async {
    final prefs = await SharedPreferences.getInstance();
    final v = p == VpnProPlanType.monthly ? 'monthly' : 'yearly';
    await prefs.setString('pro_default_plan', v);
  }

  VpnProPlanType? _planTypeFromServerPlan(String plan) {
    final p = plan.toLowerCase();
    if (p.contains('year')) return VpnProPlanType.yearly;
    if (p.contains('annual')) return VpnProPlanType.yearly;
    if (p.contains('month')) return VpnProPlanType.monthly;
    return null;
  }

  Future<void> _loadCurrentStatus() async {
    final prefs = await SharedPreferences.getInstance();

    String serverPlan = (prefs.getString('billing_server_plan') ?? '').toLowerCase();
    VpnProPlanType? planType = _planTypeFromServerPlan(serverPlan);

    if (planType == null) {
      final localPlan = (prefs.getString('billing_local_sub_plan') ?? '').toString();
      if (localPlan == PurchaseService.basePlanYearly) {
        planType = VpnProPlanType.yearly;
      } else if (localPlan == PurchaseService.basePlanMonthly) {
        planType = VpnProPlanType.monthly;
      }
    }

    final isPro = PurchaseService.isPro || (prefs.getBool('billing_is_pro') ?? false);

    if (!mounted) return;
    setState(() {
      _isPro = isPro;
      _currentPlanType = isPro ? planType : null;
      _currentStatusLabel = isPro
          ? (planType == null
          ? 'Pro'
          : (planType == VpnProPlanType.yearly ? 'Yearly' : 'Monthly'))
          : 'Free';
    });
  }

  Future<void> _loadPrices() async {
    try {
      await PurchaseService.ensureReady();
      await PurchaseService.debugDumpSubscriptionOffers();
      await PurchaseService.debugDumpSubscriptionOffers();

      final monthlyInfo = await PurchaseService.priceInfoForBasePlan(
        PurchaseService.basePlanMonthly,
      );

      final yearlyInfo = await PurchaseService.priceInfoForBasePlan(
        PurchaseService.basePlanYearly,
      );

      if (!mounted) return;
      setState(() {
        _monthlyInfo = monthlyInfo;
        _yearlyInfo = yearlyInfo;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  String _titleFor(VpnProPlanType p, AppLocalizations l10n) {
    switch (p) {
      case VpnProPlanType.monthly:
        return l10n.settingsMonthly;
      case VpnProPlanType.yearly:
        return l10n.settingsYearly;
    }
  }

  String _ctaLabel(VpnProPlanType p, AppLocalizations l10n) {
    switch (p) {
      case VpnProPlanType.monthly:
        return l10n.settingsSubscribeMonthly;
      case VpnProPlanType.yearly:
        return l10n.settingsSubscribeYearly;
    }
  }

  String _formatCurrency(double value, String currencyCode) {
    return NumberFormat.simpleCurrency(name: currencyCode).format(value);
  }

  bool _isSelectedCurrentPlan() {
    return _isPro && _currentPlanType != null && _selected == _currentPlanType;
  }

  Future<void> _showThankYou() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (context) {
        return AlertDialog(
          backgroundColor: scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Thank you',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Your subscription is confirmed.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.ok),
            ),
          ],
        );
      },
    );
  }

  Future<void> _buySelected() async {
    if (_buying) return;
    if (_isSelectedCurrentPlan()) return;

    setState(() => _buying = true);

    try {
      if (_selected == VpnProPlanType.monthly) {
        await PurchaseService.buyMonthly();
      } else {
        await PurchaseService.buyYearly();
      }

      await PurchaseService.restore();

      if (!mounted) return;

      await _loadCurrentStatus();

      final nowOnSelectedPlan = _isSelectedCurrentPlan();

      if (nowOnSelectedPlan) {
        await _persistDefaultPlan(_selected);
        await _showThankYou();
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.settingsPurchaseNotConfirmed),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.settingsPurchaseFailed(e.toString())),
        ),
      );
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  void _openPlanPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;
        final l10n = AppLocalizations.of(ctx)!;

        Widget option(VpnProPlanType p, {String? badge, String? subtitle}) {
          final selected = _selected == p;
          final isCurrent = _isPro && _currentPlanType != null && _currentPlanType == p;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: scheme.surface.withOpacity(0.25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? scheme.primary.withOpacity(0.75)
                    : scheme.outlineVariant.withOpacity(0.25),
              ),
            ),
            child: ListTile(
              enabled: !isCurrent,
              onTap: isCurrent
                  ? null
                  : () {
                Navigator.pop(ctx);
                setState(() => _selected = p);
              },
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      _titleFor(p, l10n),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isCurrent
                            ? scheme.onSurface.withOpacity(0.6)
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                  if (badge != null && !isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: scheme.primary.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: scheme.primary.withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        badge,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  if (isCurrent) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: scheme.surface.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: scheme.outlineVariant.withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        'Current',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  if (selected) Icon(Icons.check_rounded, color: scheme.primary),
                ],
              ),
              subtitle: subtitle == null
                  ? null
                  : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }

        final yearlySubtitle = _yearlyInfo?.formattedPrice ?? '';
        final monthlySubtitle = _monthlyInfo?.formattedPrice ?? '';

        return Padding(
          padding: EdgeInsets.only(
            left: 14,
            right: 14,
            top: 10,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 14,
          ),
          child: Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.settingsSwitchPlan,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  option(
                    VpnProPlanType.yearly,
                    badge: l10n.settingsBestValue,
                    subtitle: yearlySubtitle.isEmpty ? null : yearlySubtitle,
                  ),
                  option(
                    VpnProPlanType.monthly,
                    subtitle: monthlySubtitle.isEmpty ? null : monthlySubtitle,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _lineItem(BuildContext context, String title, String body) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 7),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.9),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
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
                const SizedBox(height: 2),
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
        ],
      ),
    );
  }

  Widget _sectionBox(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withOpacity(0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final monthly = _monthlyInfo;
    final yearly = _yearlyInfo;
    final hasPrices = monthly != null && yearly != null;

    double? yearlyPerMonth;
    int? savePercent;

    if (hasPrices) {
      yearlyPerMonth = yearly!.price / 12.0;
      final ratio = yearlyPerMonth / monthly!.price;
      savePercent = ((1.0 - ratio) * 100.0).round();
      if (savePercent < 0) savePercent = 0;
      if (savePercent > 95) savePercent = 95;
    }

    Widget planPriceBlock() {
      if (!hasPrices) {
        return Text(
          l10n.settingsPlanPriceLoading,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        );
      }

      if (_selected == VpnProPlanType.yearly) {
        final perMonthStr = _formatCurrency(yearlyPerMonth!, yearly!.currencyCode);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${monthly!.formattedPrice} / month',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$perMonthStr / month',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Billed ${yearly.formattedPrice} yearly',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (savePercent != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: scheme.primary.withOpacity(0.25)),
                ),
                child: Text(
                  'Save $savePercent%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${monthly!.formattedPrice} / month',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Cancel anytime',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final disabledBuy = _buying || _isSelectedCurrentPlan();

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        title: Text(
          l10n.settingsUnlockPro,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: scheme.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionBox(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: scheme.primary.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: scheme.primary.withOpacity(0.25),
                            ),
                          ),
                          child: Text(
                            'VPN PRO',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _openPlanPicker,
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.onSurface,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            backgroundColor: scheme.surface.withOpacity(0.22),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            l10n.settingsSwitchPlan,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: scheme.surface.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outlineVariant.withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        'Current status: ${_currentStatusLabel.isEmpty ? 'Free' : _currentStatusLabel}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Unlimited VPN access',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      decoration: BoxDecoration(
                        color: scheme.surface.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: scheme.outlineVariant.withOpacity(0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _titleFor(_selected, l10n),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          planPriceBlock(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: disabledBuy ? null : _buySelected,
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: _buying
                            ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                            : Text(
                          _isSelectedCurrentPlan()
                              ? 'Current plan'
                              : _ctaLabel(_selected, l10n),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _sectionBox(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsProBenefitsTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _lineItem(
                      context,
                      'Unlimited VPN',
                      'No monthly cap.',
                    ),
                    _lineItem(
                      context,
                      'Unlimited DNS queries',
                      'No cap on dns queries.',
                    ),
                    _lineItem(
                      context,
                      'Advanced blocklists',
                      'Unlock premium categories like ads, trackers, and more.',
                    ),
                    _lineItem(
                      context,
                      'Up to 5 active devices',
                      'Use your pro plan on up to 5 devices at the same time.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _sectionBox(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AvarionX Antivirus benefits',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _lineItem(
                      context,
                      'Scheduled scans',
                      'Run automatic scans on a schedule.',
                    ),
                    _lineItem(
                      context,
                      'Customisation',
                      'Unlock advanced antivirus settings and controls.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.settingsProFinePrint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withOpacity(0.9),
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}