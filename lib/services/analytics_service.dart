import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralized Firebase Analytics wrapper for VedAstro AI.
///
/// Why: gives us one place to:
///   1. Standardize event names (Play Console / Firebase looks at these)
///   2. Sanitize PII from event params (Vedic data is sensitive)
///   3. Disable analytics on web preview / test builds
///   4. Forward to multiple destinations later (Mixpanel, etc.)
///
/// Naming convention: snake_case verbs in past tense.
/// Param values: never include name, email, phone, exact birth date, or chat
/// content. Use bucketed values (age range, sun sign) instead.
class Analytics {
  static FirebaseAnalytics? _instance;
  static FirebaseAnalyticsObserver? _observer;

  /// Call once after Firebase.initializeApp()
  static Future<void> init() async {
    if (kIsWeb) return; // skip on web preview
    _instance ??= FirebaseAnalytics.instance;
    _observer ??= FirebaseAnalyticsObserver(analytics: _instance!);
    try {
      await _instance!.setAnalyticsCollectionEnabled(true);
    } catch (_) {}
  }

  /// Hook this into MaterialApp to auto-track screen views.
  static FirebaseAnalyticsObserver? get observer => _observer;

  // ─── USER LIFECYCLE ─────────────────────────────────────────
  static Future<void> signupCompleted({required String method}) =>
      _log('signup_completed', {'method': method});

  static Future<void> loginCompleted({required String method}) =>
      _log('login_completed', {'method': method});

  static Future<void> profileCreated({String? sunSign}) =>
      _log('profile_created', {'sun_sign': sunSign ?? 'unknown'});

  static Future<void> accountDeleted() => _log('account_deleted', {});

  // ─── CORE FEATURES ──────────────────────────────────────────
  static Future<void> chatSent({int? promptLen, bool? hasChart}) => _log(
        'chat_sent',
        {
          'prompt_len_bucket': _bucketLength(promptLen),
          'has_chart': hasChart == true ? '1' : '0',
        },
      );

  static Future<void> chatReceived({int? sourcesCount, bool? cached}) => _log(
        'chat_received',
        {
          'sources': sourcesCount ?? 0,
          'cached': cached == true ? '1' : '0',
        },
      );

  static Future<void> palmUploaded({required String source}) =>
      _log('palm_uploaded', {'source': source}); // 'camera' or 'gallery'

  static Future<void> palmAnalyzed({required bool success}) =>
      _log('palm_analyzed', {'success': success ? '1' : '0'});

  static Future<void> horoscopeViewed({required String period, String? sign}) =>
      _log('horoscope_viewed', {
        'period': period,
        'sign': sign ?? 'unknown',
      });

  static Future<void> kundliViewed() => _log('kundli_viewed', {});

  // ─── MONETIZATION ───────────────────────────────────────────
  static Future<void> paywallViewed({required String trigger}) =>
      _log('paywall_viewed', {'trigger': trigger});
  // trigger: 'free_chat_limit', 'free_palm_limit', 'settings', 'home'

  static Future<void> subscriptionStarted({
    required String plan,
    required String paymentMethod,
  }) =>
      _log('subscription_started', {
        'plan': plan,
        'payment_method': paymentMethod,
      });

  static Future<void> subscriptionCancelled({required String plan}) =>
      _log('subscription_cancelled', {'plan': plan});

  static Future<void> subscriptionFailed({
    required String plan,
    required String reason,
  }) =>
      _log('subscription_failed', {
        'plan': plan,
        'reason': reason.length > 100 ? reason.substring(0, 100) : reason,
      });

  // ─── ENGAGEMENT ─────────────────────────────────────────────
  static Future<void> rateLimitHit({required String feature}) =>
      _log('rate_limit_hit', {'feature': feature});

  static Future<void> shareUsed({required String type}) =>
      _log('share_used', {'type': type}); // 'palm_result', 'kundli', etc.

  static Future<void> errorEncountered({
    required String code,
    required String location,
  }) =>
      _log('error_encountered', {'code': code, 'location': location});

  // ─── INTERNAL ───────────────────────────────────────────────
  static Future<void> _log(String name, Map<String, Object?> params) async {
    if (_instance == null) return;
    try {
      // Clean up nulls — Firebase rejects null values
      final cleaned = <String, Object>{};
      for (final entry in params.entries) {
        if (entry.value != null) cleaned[entry.key] = entry.value!;
      }
      await _instance!.logEvent(name: name, parameters: cleaned);
    } catch (_) {
      // Never let analytics break the app
    }
  }

  static String _bucketLength(int? len) {
    if (len == null) return 'unknown';
    if (len < 50) return 'short';
    if (len < 200) return 'medium';
    if (len < 500) return 'long';
    return 'very_long';
  }

  /// Call when user logs in / signs up to associate analytics with UID
  static Future<void> setUser({required String uid, String? plan}) async {
    if (_instance == null) return;
    try {
      await _instance!.setUserId(id: uid);
      if (plan != null) {
        await _instance!.setUserProperty(name: 'plan', value: plan);
      }
    } catch (_) {}
  }

  /// Call on logout
  static Future<void> clearUser() async {
    if (_instance == null) return;
    try {
      await _instance!.setUserId(id: null);
    } catch (_) {}
  }
}
