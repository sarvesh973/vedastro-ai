import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../config/api_config.dart';
import '../models/subscription_plan.dart';
import 'storage_service.dart';
import 'firestore_service.dart';
import 'auth_service.dart';
import 'analytics_service.dart';

/// Get headers with Firebase Auth ID token. Cloud Functions reject
/// unauthenticated subscription requests.
Future<Map<String, String>> _authHeaders() async {
  final user = FirebaseAuth.instance.currentUser;
  String token = '';
  if (user != null) {
    try {
      token = await user.getIdToken() ?? '';
    } catch (_) {}
  }
  return {
    'Content-Type': 'application/json',
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
}

/// Callback types for payment results
typedef PaymentSuccessCallback = void Function(String paymentId, String plan);
typedef PaymentFailureCallback = void Function(String message);

/// Razorpay payment service.
///
/// Two flows are supported:
///  1. [openSubscriptionCheckout] — recurring subscriptions (Trial / Standard /
///     Premium). The server creates a Razorpay subscription via API, and the
///     app opens Razorpay's checkout sheet with that subscription_id.
///     Razorpay UI handles e-mandate registration + first ₹X charge in one
///     go, then auto-debits monthly. RBI-compliant by default.
///  2. [openCheckout] — legacy one-time payment, kept for backward compat.
class PaymentService {
  static Razorpay? _razorpay;
  static PaymentSuccessCallback? _onSuccess;
  static PaymentFailureCallback? _onFailure;
  static SubscriptionPlan? _currentPlan;
  static String? _currentSubscriptionId;
  // True while a one-time Starter Pass (₹49) order is in flight, so the
  // success handler verifies it via /order/verify instead of treating it as
  // a recurring subscription.
  static bool _isOneTimeFlow = false;

  /// Initialize Razorpay (call once)
  static void init() {
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  /// Dispose Razorpay (call on app close)
  static void dispose() {
    _razorpay?.clear();
    _razorpay = null;
  }

  // ─── Subscription Flow (PRIMARY) ──────────────────────────────────

  /// Open Razorpay subscription checkout for the given plan.
  ///
  /// Flow:
  ///   1. POST /subscription/create on our server
  ///   2. Server creates a Razorpay subscription via Razorpay API,
  ///      returns subscriptionId + shortUrl
  ///   3. App opens Razorpay's payment sheet with subscriptionId
  ///   4. User pays ₹X with card/UPI/etc → e-mandate registered
  ///   5. Razorpay fires webhook to our server -> Firestore updated
  ///   6. App's _handlePaymentSuccess callback runs -> unlock premium locally
  ///
  /// Special case: if the user's email is on ADMIN_EMAILS, the server returns
  /// {admin: true} immediately and we unlock premium without any payment.
  static Future<void> openSubscriptionCheckout({
    required SubscriptionPlan plan,
    required PaymentSuccessCallback onSuccess,
    required PaymentFailureCallback onFailure,
  }) async {
    if (_razorpay == null) init();

    _onSuccess = onSuccess;
    _onFailure = onFailure;
    _currentPlan = plan;

    final userEmail = AuthService.userEmail ?? '';
    final uid = AuthService.currentUser?.uid ?? '';
    final userName = StorageService.currentProfile?.name ?? 'Moksha User';

    if (plan == SubscriptionPlan.free) {
      onFailure('Free plan needs no subscription.');
      return;
    }

    // Email/password users must verify their email before paying. This
    // protects them (receipts go to a real inbox) and us (refund
    // disputes can be tied to a recoverable identity). Google / Phone
    // users skip this — their email is implicitly verified or absent.
    if (AuthService.needsEmailVerification) {
      onFailure('Please verify your email before subscribing. '
          'Check your inbox or tap the banner on the home screen to resend.');
      return;
    }

    // Step 1 — ask our server to create a Razorpay subscription
    final Map<String, dynamic> serverResp;
    try {
      final headers = await _authHeaders();
      final resp = await http
          .post(
            Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/subscription/create'),
            headers: headers,
            body: jsonEncode({
              'plan': plan.id,
              // userEmail and userId come from the verified Firebase token
              // server-side; we don't trust client-supplied values anymore.
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) {
        onFailure('Server error (${resp.statusCode}): ${resp.body}');
        return;
      }
      serverResp = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      onFailure('Could not reach server. Check internet and try again.');
      return;
    }

    // Special case: server detected admin email → no payment needed
    if (serverResp['admin'] == true) {
      await StorageService.upgradeToPremium();
      await StorageService.setLastPurchasedPlan(plan.id);
      final uidForCloud = AuthService.currentUser?.uid;
      if (uidForCloud != null) {
        await FirestoreService.setPremium(uidForCloud, true);
      }
      onSuccess('admin_bypass', plan.id);
      return;
    }

    final subscriptionId = serverResp['subscriptionId'] as String?;
    if (subscriptionId == null || subscriptionId.isEmpty) {
      onFailure('Server did not return a subscription. ${serverResp['error'] ?? ''}');
      return;
    }
    _currentSubscriptionId = subscriptionId;

    // Step 2 — open Razorpay's payment sheet bound to that subscription_id
    //
    // IMPORTANT: when subscription_id is set, do NOT also pass `recurring: 1`.
    // Those are two different Razorpay products:
    //   - subscription_id  → Subscriptions API (recurring with mandate)
    //   - recurring: 1     → Recurring Payments API (saved-card future charges)
    // Mixing them routes auth through the wrong code path and every mandate
    // attempt fails at payment_authentication step, even on real working
    // UPI/cards. Customer-side error reason: 'payment_cancelled'.
    //
    // Also: prefill.contact must be a real phone or omitted entirely; empty
    // string triggers Razorpay validation oddities on UPI flows.
    final options = <String, dynamic>{
      'key': ApiConfig.razorpayKeyId,
      'subscription_id': subscriptionId,
      'name': ApiConfig.razorpayCompanyName,
      'description': '${plan.displayName} — ${plan.priceLabel}',
      'prefill': {
        'email': userEmail.isNotEmpty ? userEmail : 'user@vedastro.ai',
        // contact intentionally omitted; Razorpay collects it in-checkout.
      },
      'notes': {
        'plan': plan.id,
        'user': userName,
        'uid': uid,
      },
      'theme': {
        'color': '#7C3AED',
      },
      'modal': {
        'confirm_close': true,
      },
    };

    // Meta InitiatedCheckout — user committed to paying for a recurring plan.
    Analytics.checkoutInitiated(plan: plan.id);

    try {
      _razorpay!.open(options);
    } catch (e) {
      onFailure('Could not open payment sheet: $e');
    }
  }

  // ─── Starter Pass — one-time ₹49 / 7-day order ────────────────────

  /// Open Razorpay checkout for the ONE-TIME ₹49 Starter Pass.
  ///
  /// Unlike [openSubscriptionCheckout], this uses the Razorpay Orders API
  /// (no e-mandate, no auto-renewal):
  ///   1. POST /order/create → server makes a Razorpay order, returns orderId
  ///   2. App opens checkout with `order_id` (NOT subscription_id)
  ///   3. User pays ₹49 once
  ///   4. _handlePaymentSuccess → POST /order/verify (server checks the
  ///      signature and grants a 7-day pass), then unlocks locally
  static Future<void> openStarterPassCheckout({
    required PaymentSuccessCallback onSuccess,
    required PaymentFailureCallback onFailure,
  }) async {
    if (_razorpay == null) init();

    _onSuccess = onSuccess;
    _onFailure = onFailure;
    _currentPlan = SubscriptionPlan.trial; // the ₹49 pass
    _isOneTimeFlow = true;
    _currentSubscriptionId = null;

    final userEmail = AuthService.userEmail ?? '';
    final uid = AuthService.currentUser?.uid ?? '';
    final userName = StorageService.currentProfile?.name ?? 'Moksha User';

    if (AuthService.needsEmailVerification) {
      onFailure('Please verify your email before purchasing. '
          'Check your inbox or tap the banner on the home screen to resend.');
      return;
    }

    // Step 1 — ask our server to create a one-time Razorpay order
    final Map<String, dynamic> serverResp;
    try {
      final headers = await _authHeaders();
      final resp = await http
          .post(
            Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/order/create'),
            headers: headers,
            body: jsonEncode({'plan': SubscriptionPlan.trial.id}),
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        onFailure('Server error (${resp.statusCode}): ${resp.body}');
        return;
      }
      serverResp = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      onFailure('Could not reach server. Check internet and try again.');
      return;
    }

    // Admin email → unlock without payment
    if (serverResp['admin'] == true) {
      await StorageService.upgradeToPremium();
      await StorageService.setLastPurchasedPlan(SubscriptionPlan.trial.id);
      final uidForCloud = AuthService.currentUser?.uid;
      if (uidForCloud != null) {
        await FirestoreService.setPremium(uidForCloud, true);
      }
      onSuccess('admin_bypass', SubscriptionPlan.trial.id);
      return;
    }

    final orderId = serverResp['orderId'] as String?;
    if (orderId == null || orderId.isEmpty) {
      onFailure('Server did not return an order. ${serverResp['error'] ?? ''}');
      return;
    }

    // Step 2 — open Razorpay with order_id (one-time, no subscription/mandate)
    final options = <String, dynamic>{
      'key': serverResp['keyId'] ?? ApiConfig.razorpayKeyId,
      'order_id': orderId,
      'amount': serverResp['amount'] ?? SubscriptionPlan.trial.firstChargePaise,
      'currency': serverResp['currency'] ?? 'INR',
      'name': ApiConfig.razorpayCompanyName,
      'description': 'Starter Pass — ₹49 for 7 days',
      'prefill': {
        'email': userEmail.isNotEmpty ? userEmail : 'user@vedastro.ai',
      },
      'notes': {'plan': SubscriptionPlan.trial.id, 'user': userName, 'uid': uid},
      'theme': {'color': '#7C3AED'},
      'modal': {'confirm_close': true},
    };

    // Meta InitiatedCheckout — user committed to buying the ₹49 Starter Pass.
    Analytics.checkoutInitiated(plan: SubscriptionPlan.trial.id);

    try {
      _razorpay!.open(options);
    } catch (e) {
      onFailure('Could not open payment sheet: $e');
    }
  }

  /// Verify a completed Starter Pass payment with the server (signature
  /// check) and grant the 7-day pass. Returns true on success.
  static Future<bool> _verifyStarterPass(
      PaymentSuccessResponse response) async {
    try {
      final headers = await _authHeaders();
      final resp = await http
          .post(
            Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/order/verify'),
            headers: headers,
            body: jsonEncode({
              'razorpay_order_id': response.orderId,
              'razorpay_payment_id': response.paymentId,
              'razorpay_signature': response.signature,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return resp.statusCode == 200;
    } catch (e) {
      print('[PAYMENT] Starter Pass verify failed: $e');
      return false;
    }
  }

  // ─── Legacy one-time payment flow (kept for backward compat) ─────

  /// Open Razorpay checkout for a one-time premium purchase (NOT recurring).
  /// Prefer [openSubscriptionCheckout] for new code — this is left in place
  /// so existing callers that haven't migrated yet still compile.
  static void openCheckout({
    required String plan, // 'monthly' or 'yearly'
    required PaymentSuccessCallback onSuccess,
    required PaymentFailureCallback onFailure,
  }) {
    if (_razorpay == null) init();

    _onSuccess = onSuccess;
    _onFailure = onFailure;
    _currentPlan = plan == 'yearly'
        ? SubscriptionPlan.premium
        : SubscriptionPlan.standard;

    final amount = plan == 'yearly'
        ? ApiConfig.premiumPriceYearlyPaise
        : ApiConfig.premiumPriceMonthlyPaise;

    final userEmail = AuthService.userEmail ?? 'user@vedastro.ai';
    final userName = StorageService.currentProfile?.name ?? 'Moksha User';

    final options = {
      'key': ApiConfig.razorpayKeyId,
      'amount': amount,
      'name': ApiConfig.razorpayCompanyName,
      'description': plan == 'yearly'
          ? 'Moksha Premium — Yearly'
          : 'Moksha Premium — Monthly',
      'prefill': {
        'email': userEmail,
        'contact': '9999999999',
      },
      'notes': {
        'plan': plan,
        'user': userName,
      },
      'theme': {
        'color': '#7C3AED',
      },
      'modal': {
        'confirm_close': true,
      },
    };

    try {
      _razorpay!.open(options);
    } catch (e) {
      onFailure('Could not open payment: $e');
    }
  }

  // ─── Cancel a subscription ────────────────────────────────────────

  /// Cancels the user's active subscription via the server.
  /// Default behavior: cancel at end of current billing period (user keeps
  /// access until their paid period ends — this is RBI-compliant).
  /// Pass [immediate]=true to cut access right now (rare; used for refunds).
  static Future<bool> cancelSubscription({
    required String subscriptionId,
    bool immediate = false,
  }) async {
    // Calls Render's /subscription/cancel — same server that creates the
    // subscription and handles the Razorpay webhook. The Firebase Function
    // path that used to live here was never deployed, so cancel was
    // silently 404ing for every user.
    try {
      final headers = await _authHeaders();
      final url = Uri.parse(
          '${ApiConfig.cloudFunctionBaseUrl}/subscription/cancel');
      final resp = await http
          .post(
            url,
            headers: headers,
            body: jsonEncode({
              'subscriptionId': subscriptionId,
              // Render flag is the inverse of `immediate`: cancelAtCycleEnd
              // = false means cancel right now (keep `true` for the default
              // RBI-compliant "lapse at period end" behaviour).
              'cancelAtCycleEnd': !immediate,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) return true;
      print('[CANCEL] Non-200 from Render: '
          '${resp.statusCode} — body: ${resp.body}');
      return false;
    } catch (e) {
      print('[CANCEL] Network/timeout error: $e');
      return false;
    }
  }

  // ─── Razorpay Callbacks ─────────────────────────

  static void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    final paymentId = response.paymentId ?? 'unknown';
    final planId = _currentPlan?.id ?? 'unknown';
    print('[PAYMENT] Success! paymentId=$paymentId, plan=$planId, '
        'oneTime=$_isOneTimeFlow, sub=${_currentSubscriptionId ?? "n/a"}');

    // One-time Starter Pass: verify the signature server-side BEFORE we grant
    // anything locally — a valid Razorpay callback isn't proof of payment on
    // its own. The server checks the HMAC and writes the 7-day pass.
    if (_isOneTimeFlow) {
      final ok = await _verifyStarterPass(response);
      if (!ok) {
        _isOneTimeFlow = false;
        _onFailure?.call(
            'Payment received but could not be verified. If money was '
            'deducted it will be auto-refunded; please contact support.');
        return;
      }
      // ₹49 one-time purchase → Meta Purchase event (not a trial).
      Analytics.subscriptionPurchased(plan: planId);
      final uidA = AuthService.currentUser?.uid;
      if (uidA != null) Analytics.setUser(uid: uidA, plan: planId);

      await StorageService.upgradeToPremium();
      await StorageService.setLastPurchasedPlan(planId);
      final uid = AuthService.currentUser?.uid;
      if (uid != null) {
        await FirestoreService.setPremium(uid, true);
        await FirestoreService.savePaymentRecord(
          uid: uid,
          paymentId: paymentId,
          plan: planId,
          amount: SubscriptionPlan.trial.firstChargePaise,
        );
      }
      _isOneTimeFlow = false;
      _onSuccess?.call(paymentId, planId);
      return;
    }

    // Analytics: subscription started
    Analytics.subscriptionStarted(plan: planId, paymentMethod: 'razorpay');
    // Update user's plan in analytics
    final uidForAnalytics = AuthService.currentUser?.uid;
    if (uidForAnalytics != null) {
      Analytics.setUser(uid: uidForAnalytics, plan: planId);
    }

    // Activate premium locally — webhook will also confirm server-side soon.
    await StorageService.upgradeToPremium();
    // Record which plan was purchased so the Settings → Subscription screen
    // shows the correct plan name (and correct upgrade options) until the
    // webhook lands and the Firestore stream takes over.
    await StorageService.setLastPurchasedPlan(planId);

    // Sync to Firestore
    final uid = AuthService.currentUser?.uid;
    if (uid != null) {
      await FirestoreService.setPremium(uid, true);
      await FirestoreService.savePaymentRecord(
        uid: uid,
        paymentId: paymentId,
        plan: planId,
        amount: _currentPlan?.firstChargePaise ?? 0,
      );
    }

    _onSuccess?.call(paymentId, planId);
  }

  static void _handlePaymentError(PaymentFailureResponse response) {
    final code = response.code ?? -1;
    final desc = response.message ?? 'unknown';
    Analytics.subscriptionFailed(
      plan: _currentPlan?.id ?? 'unknown',
      reason: 'code=$code: $desc',
    );
    final msg = response.message ?? 'Payment failed';
    print('[PAYMENT] Error: code=$code, msg=$msg');

    String userMsg;
    switch (code) {
      case Razorpay.PAYMENT_CANCELLED:
        userMsg = 'Payment cancelled. No charges were made.';
        break;
      case Razorpay.NETWORK_ERROR:
        userMsg = 'Network error. Please check your internet and try again.';
        break;
      default:
        userMsg = 'Payment failed. Please try again.';
    }

    _onFailure?.call(userMsg);
  }

  static void _handleExternalWallet(ExternalWalletResponse response) {
    print('[PAYMENT] External wallet: ${response.walletName}');
    // External wallet selected — payment will continue via wallet app
  }
}
