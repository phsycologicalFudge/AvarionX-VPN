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
    });
  }

  Future<void> _loadPrices() async {
    try {
      await PurchaseService.ensureReady();

      final res = await PurchaseService.queryAll();

      final monthlyInfo = PurchaseService.priceInfoForBasePlanFromResponse(
        res,
        PurchaseService.basePlanMonthly,
      );

      final yearlyInfo = PurchaseService.priceInfoForBasePlanFromResponse(
        res,
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

  Widget _buildFeatureRow(BuildContext context, String title, String subtitle) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Icon(
            Icons.check_circle_outline_rounded,
            color: Colors.white54,
            size: 28,
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required BuildContext context,
    required VpnProPlanType type,
    required String title,
    required String priceStr,
    required String subtitleStr,
    String? discountBadge,
    String? crossedOutPrice,
  }) {
    final theme = Theme.of(context);
    final isSelected = _selected == type;
    final isCurrent = _isPro && _currentPlanType == type;

    return Expanded(
      child: GestureDetector(
        onTap: isCurrent ? null : () => setState(() => _selected = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? Colors.blueAccent.withOpacity(0.8)
                  : Colors.white.withOpacity(0.1),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle, color: Colors.blueAccent, size: 18)
                  else if (isCurrent)
                    Text("Current", style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey))
                  else if (discountBadge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          discountBadge,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                ],
              ),
              const SizedBox(height: 12),
              if (crossedOutPrice != null)
                Text(
                  crossedOutPrice,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                    decoration: TextDecoration.lineThrough,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                priceStr,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitleStr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white60,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    double? yearlyPerMonth;
    int? savePercent;
    bool hasTrialForSelected = false;

    if (_monthlyInfo != null && _yearlyInfo != null) {
      yearlyPerMonth = _yearlyInfo!.price / 12.0;
      final ratio = yearlyPerMonth / _monthlyInfo!.price;
      savePercent = ((1.0 - ratio) * 100.0).round().clamp(0, 95);

      hasTrialForSelected = _selected == VpnProPlanType.yearly
          ? _yearlyInfo!.hasFreeTrial
          : _monthlyInfo!.hasFreeTrial;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B101E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: PurchaseService.restore,
            child: const Text("Restore", style: TextStyle(color: Colors.white70)),
          )
        ],
      ),
      extendBodyBehindAppBar: true,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0,
            height: 300,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.blueAccent.withOpacity(0.2),
                    const Color(0xFF0B101E),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        Icon(Icons.rocket_launch_rounded, size: 80, color: Colors.blueAccent.shade100),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "AvarionX ",
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white, width: 1.5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "PRO",
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  _buildFeatureRow(
                      context,
                      'Global Server Access',
                      'Access every VPN server location, including premium high-speed regions.'
                  ),
                  _buildFeatureRow(
                      context,
                      'Advanced Stealth+ Mode',
                      'Unlock obfuscation transport for restrictive networks and improved compatibility.'
                  ),
                  _buildFeatureRow(
                      context,
                      'Premium Security & DNS',
                      'Unlimited secure DNS queries'
                  ),
                  _buildFeatureRow(
                      context,
                      'Up to 5 Devices',
                      'Secure all your hardware. Use your Pro plan on up to 5 devices simultaneously.'
                  ),
                  _buildFeatureRow(
                      context,
                      'AvarionX Antivirus',
                      'Unlock scheduled scans and advanced customisation for complete device protection.'
                  ),
                  const SizedBox(height: 30),

                  Row(
                    children: [
                      _buildPlanCard(
                        context: context,
                        type: VpnProPlanType.monthly,
                        title: 'Monthly',
                        priceStr: _monthlyInfo?.formattedPrice ?? '-',
                        subtitleStr: 'Billed Monthly',
                      ),
                      const SizedBox(width: 12),
                      _buildPlanCard(
                        context: context,
                        type: VpnProPlanType.yearly,
                        title: 'Yearly',
                        discountBadge: savePercent != null ? '-$savePercent%' : null,
                        crossedOutPrice: _monthlyInfo != null ? '${_monthlyInfo!.formattedPrice}/mo' : null,
                        priceStr: yearlyPerMonth != null
                            ? '${_formatCurrency(yearlyPerMonth, _yearlyInfo!.currencyCode)}/mo'
                            : '-',
                        subtitleStr: 'Billed Annually at ${_yearlyInfo?.formattedPrice ?? '-'}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE2D6FF), Color(0xFFC1F1FF)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: (_buying || _isSelectedCurrentPlan()) ? null : _buySelected,
                        child: Center(
                          child: _buying
                              ? const SizedBox(
                            height: 24, width: 24,
                            child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black87),
                          )
                              : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isSelectedCurrentPlan() ? 'Current plan' : 'Subscribe',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              if (hasTrialForSelected && !_isSelectedCurrentPlan())
                                Text(
                                  "7 Days Free, then ${_selected == VpnProPlanType.yearly ? _yearlyInfo?.formattedPrice : _monthlyInfo?.formattedPrice}",
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    "Subscriptions may be managed monthly, yearly or turned off by going to the Play Store Account Settings after purchase. All prices include applicable taxes.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white38,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}