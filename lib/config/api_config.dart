/// API Configuration
///
/// Render RAG server URL for RAG-powered responses (primary)
/// Direct Gemini API key as fallback
class ApiConfig {
  static const String geminiApiKey = 'INJECTED_BY_CI_AT_BUILD_TIME';

  /// RAG server base URL (deployed on Render)
  static const String cloudFunctionBaseUrl =
      'https://vedastro-rag-server.onrender.com';

  /// Razorpay LIVE API Key — REAL MONEY mode.
  /// Subscriptions opened with this key WILL CHARGE the user's card.
  /// Get your keys from: https://dashboard.razorpay.com/app/keys
  static const String razorpayKeyId = 'rzp_live_SiqZ5RU6i3w3XV';

  /// Company/App name shown on Razorpay checkout
  static const String razorpayCompanyName = 'VedAstro AI';

  /// Legacy one-time payment prices (paise). Used by the old openCheckout()
  /// flow only. The new openSubscriptionCheckout() flow reads prices from
  /// SubscriptionPlan.firstChargePaise / recurringPaise instead.
  ///
  /// Standard monthly = 19900 paise (₹199)
  /// Premium monthly  = 49900 paise (₹499)
  static const int premiumPriceMonthlyPaise = 19900;
  static const int premiumPriceYearlyPaise = 49900;

  /// Founder / admin / staff emails that bypass paywalls and limits.
  /// These accounts get unlimited access automatically — no Razorpay, no
  /// chat caps, no palm caps. Use for personal testing and team accounts.
  ///
  /// SECURITY: This is just the client-side check. The server (index.js)
  /// MUST also have this same list and verify against the Firebase ID
  /// token's email claim — otherwise anyone could spoof admin by setting
  /// their email locally. Keep both lists in sync.
  ///
  /// Add lowercase only. Emails are normalized to lowercase before compare.
  static const List<String> adminEmails = [
    'sarry1254@gmail.com',
  ];

  /// Returns true if the given email is on the admin list.
  /// Pass null/empty -> returns false.
  static bool isAdminEmail(String? email) {
    if (email == null || email.isEmpty) return false;
    return adminEmails.contains(email.trim().toLowerCase());
  }

  static bool get isConfigured =>
      geminiApiKey.isNotEmpty &&
      geminiApiKey != 'YOUR_GEMINI_API_KEY_HERE' &&
      geminiApiKey != 'PLACEHOLDER_GEMINI' &&
      geminiApiKey != 'INJECTED_BY_CI_AT_BUILD_TIME' &&
      geminiApiKey.length > 30;
  static bool get isRazorpayConfigured =>
      razorpayKeyId.isNotEmpty &&
      !razorpayKeyId.contains('YOUR_KEY') &&
      (razorpayKeyId.startsWith('rzp_test_') || razorpayKeyId.startsWith('rzp_live_'));
}
