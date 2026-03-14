import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PurchaseService {
  static final InAppPurchase _iap = InAppPurchase.instance;

  static const String legacyProId = 'cs_security_pro';
  static const String subscriptionId = 'pro_subscription';
  static const String lifetimeId = 'prounlock';

  static const String basePlanMonthly = 'montly-plan';
  static const String basePlanYearly = 'pro-yearly';

  static const String _kIsPro = 'billing_is_pro';
  static const String _kToken = 'billing_server_verification_data';
  static const String _kLastProductId = 'billing_last_product_id';
  static const String _kPermanentPro = 'billing_permanent_pro';
  static const String _kLocalSubPlan = 'billing_local_sub_plan';
  static const String _kPendingSubPlan = 'billing_pending_sub_plan';
  static const String _kServerSessionPro = 'billing_server_session_pro';
  static const String _kServerSessionSignedIn = 'billing_server_session_signed_in';

  static bool _available = false;
  static bool _isPro = false;
  static String _lastServerVerificationData = '';
  static String _lastProductId = '';
  static bool _permanentPro = false;
  static StreamSubscription<List<PurchaseDetails>>? _sub;
  static bool get available => _available;
  static bool _serverSessionPro = false;
  static bool get isPro => _isPro || _serverSessionPro;
  static Future<bool> hasPro() async => _isPro || _serverSessionPro;
  static String get lastServerVerificationData => _lastServerVerificationData;
  static String get lastProductId => _lastProductId;
  static bool get isFounder => _permanentPro;

  static Future<bool> _debugIgnorePaid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('pro_debug_ignore_paid') ?? false;
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isPro = prefs.getBool(_kIsPro) ?? false;
    _permanentPro = prefs.getBool(_kPermanentPro) ?? false;
    _lastServerVerificationData = prefs.getString(_kToken) ?? '';
    _lastProductId = prefs.getString(_kLastProductId) ?? '';
    _serverSessionPro = (prefs.getBool(_kServerSessionSignedIn) ?? false) &&
        (prefs.getBool(_kServerSessionPro) ?? false);
    final localPlan = prefs.getString(_kLocalSubPlan) ?? '';
    if (localPlan.isNotEmpty) {
      _lastProductId = subscriptionId;
    }

    if (await _debugIgnorePaid()) {
      _isPro = false;
    }

    _available = await _iap.isAvailable();
    if (!_available) return;

    await _sub?.cancel();
    _sub = _iap.purchaseStream.listen(_handlePurchaseUpdates, onError: (_) {});
    await restore();
  }

  static Future<void> ensureReady() async {
    if (_available && _sub != null) return;
    await init();
  }

  static Future<ProductDetailsResponse> queryAll() async {
    await ensureReady();
    if (!_available) throw 'Play Billing unavailable';
    return _iap.queryProductDetails({subscriptionId, lifetimeId, legacyProId});
  }

  static Future<void> debugDumpSubscriptionOffers() async {
    await ensureReady();
    if (!_available) {
      if (kDebugMode) print('IAP unavailable');
      return;
    }

    final res = await _iap.queryProductDetails({subscriptionId});
    if (kDebugMode) {
      print('notFoundIDs: ${res.notFoundIDs}');
      print('productDetails count: ${res.productDetails.length}');
    }

    for (final d in res.productDetails) {
      if (d.id != subscriptionId) continue;

      if (d is! GooglePlayProductDetails) {
        if (kDebugMode) print('Subscription is not GooglePlayProductDetails');
        continue;
      }

      final offers = d.productDetails.subscriptionOfferDetails;
      if (kDebugMode) {
        print('subscriptionId: ${d.id}');
        print('offers null? ${offers == null}');
        print('offers len: ${offers?.length ?? 0}');
      }

      if (offers == null) return;

      for (final o in offers) {
        final basePlanId = (o as dynamic).basePlanId?.toString() ?? '';
        final offerToken = (o as dynamic).offerIdToken?.toString() ?? '';
        final phases = (o as dynamic).pricingPhases as List? ?? const [];

        String firstPrice = '';
        if (phases.isNotEmpty) {
          final p0 = phases.first as dynamic;
          firstPrice = p0.formattedPrice?.toString() ?? '';
        }

        if (kDebugMode) {
          print(
            'offer basePlanId=$basePlanId tokenEmpty=${offerToken.isEmpty} firstPrice=$firstPrice phases=${phases.length}',
          );
        }
      }
    }
  }

  static Future<String> priceForLifetime() async {
    final res = await queryAll();
    for (final d in res.productDetails) {
      if (d.id == lifetimeId) return d.price;
    }
    return '';
  }

  static Future<String> priceForBasePlan(String basePlanId) async {
    final res = await queryAll();

    GooglePlayProductDetails? match;

    for (final d in res.productDetails) {
      if (d.id != subscriptionId) continue;
      if (d is! GooglePlayProductDetails) continue;

      final offers = d.productDetails.subscriptionOfferDetails;
      final idx = d.subscriptionIndex;

      if (offers == null || offers.isEmpty) continue;
      if (idx == null || idx < 0 || idx >= offers.length) continue;

      if (offers[idx].basePlanId == basePlanId) {
        match = d;
        break;
      }
    }

    if (match == null) return '';
    return _priceFromBasePlan(match, basePlanId);
  }

  static String _priceFromBasePlan(GooglePlayProductDetails details, String basePlanId) {
    final offers = details.productDetails.subscriptionOfferDetails;
    if (offers == null || offers.isEmpty) return '';

    final idx = details.subscriptionIndex;
    if (idx == null || idx < 0 || idx >= offers.length) return '';

    final offer = offers[idx];
    if (offer.basePlanId != basePlanId) return '';

    final phases = offer.pricingPhases;
    if (phases.isEmpty) return '';
    return phases.first.formattedPrice;
  }

  static Future<void> buyLegacyLifetime() async {
    await ensureReady();
    if (!_available) throw 'Play Billing unavailable';

    final res = await _iap.queryProductDetails({legacyProId});
    if (res.notFoundIDs.isNotEmpty) throw 'Legacy product not found on Play Console';
    if (res.productDetails.isEmpty) throw 'Legacy product details empty';

    final product = res.productDetails.first;
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  static Future<void> buyLifetime() async {
    await ensureReady();
    if (!_available) throw 'Play Billing unavailable';

    final res = await _iap.queryProductDetails({lifetimeId});
    if (res.notFoundIDs.isNotEmpty) throw 'Lifetime product not found on Play Console';
    if (res.productDetails.isEmpty) throw 'Lifetime product details empty';

    final product = res.productDetails.first;
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  static Future<void> buyMonthly() async {
    await _buySubscriptionBasePlan(basePlanMonthly);
  }

  static Future<void> buyYearly() async {
    await _buySubscriptionBasePlan(basePlanYearly);
  }

  static Future<void> _buySubscriptionBasePlan(String basePlanId) async {
    await ensureReady();
    if (!_available) throw 'Play Billing unavailable';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingSubPlan, basePlanId);

    final res = await _iap.queryProductDetails({subscriptionId});
    if (res.notFoundIDs.isNotEmpty) throw 'Subscription product not found on Play Console';
    if (res.productDetails.isEmpty) throw 'Subscription product details empty';

    GooglePlayProductDetails? match;
    dynamic offerMatch;

    for (final d in res.productDetails) {
      if (d.id != subscriptionId) continue;
      if (d is! GooglePlayProductDetails) continue;

      final offers = d.productDetails.subscriptionOfferDetails;
      if (offers == null || offers.isEmpty) continue;

      for (final o in offers) {
        if (o.basePlanId == basePlanId) {
          match = d;
          offerMatch = o;
          break;
        }
      }

      if (match != null) break;
    }

    if (match == null || offerMatch == null) throw 'No offer token for base plan: $basePlanId';

    final token = offerMatch.offerIdToken.toString();
    if (token.isEmpty) throw 'No offer token for base plan: $basePlanId';

    final param = GooglePlayPurchaseParam(productDetails: match, offerToken: token);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  static Future<bool> restore() async {
    await ensureReady();
    if (!_available) return _isPro;

    final ignorePaid = await _debugIgnorePaid();
    if (ignorePaid) {
      _isPro = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kIsPro, false);
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final completer = Completer<bool>();

    bool sawSub = false;
    bool sawPermanent = _permanentPro;

    late StreamSubscription<List<PurchaseDetails>> sub;

    sub = _iap.purchaseStream.listen((purchases) async {
      for (final p in purchases) {
        final okStatus = p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored;
        if (!okStatus) continue;

        if (p.productID == subscriptionId) {
          sawSub = true;
        }

        if (p.productID == lifetimeId || p.productID == legacyProId) {
          sawPermanent = true;
        }
      }
    });

    await _iap.restorePurchases();

    Future.delayed(const Duration(seconds: 6), () async {
      if (completer.isCompleted) return;

      final shouldBePro = sawPermanent || sawSub;

      _permanentPro = sawPermanent;
      await prefs.setBool(_kPermanentPro, _permanentPro);

      _isPro = shouldBePro;
      await prefs.setBool(_kIsPro, _isPro);

      completer.complete(_isPro);
    });

    final result = await completer.future;
    await sub.cancel();
    return result;
  }

  static void _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('cs_auth_token') ?? '';
    final ignorePaid = await _debugIgnorePaid();

    for (final p in purchases) {
      final okStatus = p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored;
      final isLegacyOrLifetime = p.productID == lifetimeId || p.productID == legacyProId;
      final isSub = p.productID == subscriptionId;

      if (okStatus && (isLegacyOrLifetime || isSub)) {
        final purchaseToken = p.verificationData.serverVerificationData;

        _lastProductId = p.productID;
        await prefs.setString(_kLastProductId, _lastProductId);

        if (purchaseToken.isNotEmpty) {
          _lastServerVerificationData = purchaseToken;
          await prefs.setString(_kToken, _lastServerVerificationData);
        }

        if (isSub) {
          final pending = prefs.getString(_kPendingSubPlan) ?? '';
          if (pending.isNotEmpty) {
            await prefs.setString(_kLocalSubPlan, pending);
            await prefs.remove(_kPendingSubPlan);
          }
        }

        bool serverVerified = false;

        if (authToken.isNotEmpty && purchaseToken.isNotEmpty) {
          try {
            final res = await http.post(
              Uri.parse('https://api.colourswift.com/billing/google/verify'),
              headers: {
                'content-type': 'application/json',
                'authorization': 'Bearer $authToken',
              },
              body: jsonEncode({
                'productId': p.productID,
                'purchaseToken': purchaseToken,
                'packageName': 'com.colourswift.avarionxvpn',
                'basePlanId': isSub ? ((prefs.getString(_kLocalSubPlan) ?? prefs.getString(_kPendingSubPlan) ?? '')) : '',
              }),
            );

            if (kDebugMode) {
              print(res.statusCode);
              print(res.body);
            }

            if (res.statusCode == 200) {
              try {
                final meRes = await http.get(
                  Uri.parse('https://api.colourswift.com/me'),
                  headers: {'authorization': 'Bearer $authToken'},
                );

                if (meRes.statusCode == 200) {
                  final meJson = jsonDecode(meRes.body) as Map<String, dynamic>;
                  final user = (meJson['user'] as Map?)?.cast<String, dynamic>();

                  final plan = (user?['plan'] ?? '').toString();
                  final rawExp = user?['planExpiresAt'];

                  final int? exp = rawExp is num
                      ? rawExp.toInt()
                      : int.tryParse((rawExp ?? '').toString());

                  await prefs.setString('billing_server_plan', plan);

                  await PurchaseService.applyServerAccountEntitlement(
                    signedIn: true,
                    plan: plan,
                    planExpiresAt: exp,
                  );
                }
              } catch (_) {}
            }
          } catch (_) {}
        }

        if (!ignorePaid) {
          if (isLegacyOrLifetime) {
            _permanentPro = true;
            await prefs.setBool(_kPermanentPro, true);
          }

          if (serverVerified || _permanentPro) {
            _isPro = true;
            await prefs.setBool(_kIsPro, true);
          }
        }
      }

      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  static Future<void> applyServerAccountEntitlement({
    required bool signedIn,
    required String plan,
    int? planExpiresAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final cleanPlan = plan.trim().toLowerCase();

    final serverPro = signedIn &&
        cleanPlan == 'pro' &&
        (planExpiresAt == null || planExpiresAt > nowUnix);

    _serverSessionPro = serverPro;

    await prefs.setBool(_kServerSessionSignedIn, signedIn);
    await prefs.setBool(_kServerSessionPro, serverPro);

    if (signedIn) {
      await prefs.setString('billing_server_plan', cleanPlan);
      if (planExpiresAt != null) {
        await prefs.setInt('billing_server_plan_expires_at', planExpiresAt);
      } else {
        await prefs.remove('billing_server_plan_expires_at');
      }
    } else {
      await prefs.remove('billing_server_plan');
      await prefs.remove('billing_server_plan_expires_at');
    }
  }

  static Future<void> clearServerAccountEntitlement() async {
    final prefs = await SharedPreferences.getInstance();
    _serverSessionPro = false;
    await prefs.setBool(_kServerSessionSignedIn, false);
    await prefs.setBool(_kServerSessionPro, false);
    await prefs.remove('billing_server_plan');
    await prefs.remove('billing_server_plan_expires_at');
  }

  static Future<void> clearLocalProFlag() async {
    final prefs = await SharedPreferences.getInstance();
    _isPro = false;
    _permanentPro = false;
    _lastServerVerificationData = '';
    _lastProductId = '';
    await prefs.setBool(_kIsPro, false);
    await prefs.setBool(_kPermanentPro, false);
    await prefs.remove(_kToken);
    await prefs.remove(_kLastProductId);
    await prefs.remove(_kLocalSubPlan);
    await prefs.remove(_kPendingSubPlan);
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  static Future<PlanPriceInfo?> priceInfoForBasePlan(String basePlanId) async {
    final res = await queryAll();

    for (final d in res.productDetails) {
      if (d.id != subscriptionId) continue;
      if (d is! GooglePlayProductDetails) continue;

      final offers = d.productDetails.subscriptionOfferDetails;
      final idx = d.subscriptionIndex;

      if (offers == null || offers.isEmpty) continue;
      if (idx == null || idx < 0 || idx >= offers.length) continue;

      if (offers[idx].basePlanId == basePlanId) {
        final phases = offers[idx].pricingPhases;
        if (phases.isEmpty) continue;

        final phase = phases.first;
        return PlanPriceInfo(
          formattedPrice: phase.formattedPrice,
          priceMicros: phase.priceAmountMicros,
          currencyCode: phase.priceCurrencyCode,
        );
      }
    }

    return null;
  }
}

class PlanPriceInfo {
  final String formattedPrice;
  final int priceMicros;
  final String currencyCode;

  PlanPriceInfo({
    required this.formattedPrice,
    required this.priceMicros,
    required this.currencyCode,
  });

  double get price => priceMicros / 1000000.0;
}