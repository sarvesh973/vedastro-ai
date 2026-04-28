/// API Configuration
class ApiConfig {
  static const String geminiApiKey = 'INJECTED_BY_CI_AT_BUILD_TIME';

  static const String cloudFunctionBaseUrl =
      'https://vedastro-rag-server.onrender.com';

  static const String razorpayKeyId = 'rzp_live_SiqZ5RU6i3w3XV';

  static const String razorpayCompanyName = 'VedAstro AI';

  static const int premiumPriceMonthlyPaise = 19900;
  static const int premiumPriceYearlyPaise = 49900;

  static const List<String> adminEmails = [
    'sarry1254@gmail.com',
  ];

  static bool isAdminEmail(String? email) {
    if (email == null || email.isEmpty) return false;
    return adminEmails.contains(email.trim().toLowerCase());
  }

  static bool get isConfigured =>
      geminiApiKey.isNotEmpty &&
      geminiApiKey != 'INJECTED_BY_CI_AT_BUILD_TIME' &&
      geminiApiKey.length > 30;

  static bool get isRazorpayConfigured =>
      razorpayKeyId.isNotEmpty && !razorpayKeyId.contains('YOUR_KEY');
}
