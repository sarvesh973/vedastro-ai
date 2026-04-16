/// API Configuration
///
/// Render RAG server URL for RAG-powered responses (primary)
/// Direct Gemini API key as fallback
class ApiConfig {
  static const String geminiApiKey = 'INJECTED_BY_CI_AT_BUILD_TIME';

  /// RAG server base URL (deployed on Render)
  static const String cloudFunctionBaseUrl =
      'https://vedastro-rag-server.onrender.com';

  /// Razorpay API Key (Test mode — switch to live key before Play Store launch)
  /// Get your keys from: https://dashboard.razorpay.com/app/keys
  static const String razorpayKeyId = 'rzp_test_Sdmo8azvABuanX';

  /// Company/App name shown on Razorpay checkout
  static const String razorpayCompanyName = 'VedAstro AI';

  /// Premium pricing in paise (₹2 = 200 paise for testing)
  static const int premiumPriceMonthlyPaise = 200; // ₹2
  static const int premiumPriceYearlyPaise = 200;  // ₹2 (same for testing)

  static bool get isConfigured =>
      geminiApiKey.isNotEmpty &&
      geminiApiKey != 'YOUR_GEMINI_API_KEY_HERE' &&
      geminiApiKey != 'PLACEHOLDER_GEMINI';
  static bool get isRazorpayConfigured => razorpayKeyId != 'rzp_test_YOUR_KEY_HERE';
}
