import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../config/api_config.dart';
import '../models/subscription_plan.dart';
import 'storage_service.dart';
import 'firestore_service.dart';
import 'auth_service.dart';

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
  ///   1. POST /subscriptionCreate on our server
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
    final userName = StorageService.currentProfile?.name ?? 'VedAstro User';

    if (plan == SubscriptionPlan.free) {
      onFailure('Free plan needs no subscription.');
      return;
    }

    // Step 1 — ask our server to create a Razorpay subscription
    final Map<String, dynamic> serverResp;
    try {
      final headers = await _authHeaders();
      final resp = await http
          .post(
            Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/subscriptionCreate'),
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
    final options = {
      'key': ApiConfig.razorpayKeyId,
      'subscription_id': subscriptionId,
      'name': ApiConfig.razorpayCompanyName,
      'description': '${plan.displayName} — ${plan.priceLabel}',
      'prefill': {
        'email': userEmail.isNotEmpty ? userEmail : 'user@vedastro.ai',
        'contact': '',
      },
      'recurring': 1,
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

    try {
      _razorpay!.open(options);
    } catch (e) {
      onFailure('Could not open payment sheet: $e');
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
    final userName = StorageService.currentProfile?.name ?? 'VedAstro User';

    final options = {
      'key': ApiConfig.razorpayKeyId,
      'amount': amount,
      'name': ApiConfig.razorpayCompanyName,
      'description': plan == 'yearly'
          ? 'VedAstro Premium — Yearly'
          : 'VedAstro Premium — Monthly',
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
    try {
      final headers = await _authHeaders();
      final resp = await http
          .post(
            Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/subscriptionCancel'),
            headers: headers,
            body: jsonEncode({
              'subscriptionId': subscriptionId,
              'immediate': immediate,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─── Razorpay Callbacks ─────────────────────────

  static void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    final paymentId = response.paymentId ?? 'unknown';
    final planId = _currentPlan?.id ?? 'unknown';
    print('[PAYMENT] Success! paymentId=$paymentId, plan=$planId, sub=${_currentSubscriptionId ?? "n/a"}');

    // Activate premium locally — webhook will also confirm server-side soon.
    await StorageService.upgradeToPremium();

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
