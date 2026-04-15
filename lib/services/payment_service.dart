import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../config/api_config.dart';
import 'storage_service.dart';
import 'firestore_service.dart';
import 'auth_service.dart';

/// Callback types for payment results
typedef PaymentSuccessCallback = void Function(String paymentId, String plan);
typedef PaymentFailureCallback = void Function(String message);

/// Razorpay payment service
class PaymentService {
  static Razorpay? _razorpay;
  static PaymentSuccessCallback? _onSuccess;
  static PaymentFailureCallback? _onFailure;
  static String _currentPlan = 'monthly';

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

  /// Open Razorpay checkout for premium purchase
  static void openCheckout({
    required String plan, // 'monthly' or 'yearly'
    required PaymentSuccessCallback onSuccess,
    required PaymentFailureCallback onFailure,
  }) {
    if (_razorpay == null) init();

    _onSuccess = onSuccess;
    _onFailure = onFailure;
    _currentPlan = plan;

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
      'method': {
        'upi': true,
        'card': true,
        'netbanking': true,
        'wallet': true,
        'paylater': true,
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
      _onFailure?.call('Could not open payment: $e');
    }
  }

  // ─── Razorpay Callbacks ─────────────────────────

  static void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    final paymentId = response.paymentId ?? 'unknown';
    print('[PAYMENT] Success! ID: $paymentId, Plan: $_currentPlan');

    // Activate premium locally
    await StorageService.upgradeToPremium();

    // Sync to Firestore
    final uid = AuthService.currentUser?.uid;
    if (uid != null) {
      await FirestoreService.setPremium(uid, true);
      // Store payment record
      await FirestoreService.savePaymentRecord(
        uid: uid,
        paymentId: paymentId,
        plan: _currentPlan,
        amount: _currentPlan == 'yearly'
            ? ApiConfig.premiumPriceYearlyPaise
            : ApiConfig.premiumPriceMonthlyPaise,
      );
    }

    _onSuccess?.call(paymentId, _currentPlan);
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
