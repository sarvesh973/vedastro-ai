import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralized analytics wrapper for VedAstro AI.
///
/// Why: gives us one place to:
///   1. Standardize event names (Play Console / Firebase looks at these)
///   2. Sanitize PII from event params (Vedic data is sensitive)
///   3. Disable analytics on web preview / test builds
///   4. Fan out to multiple destinations — currently Firebase Analytics
///      AND Meta (Facebook) App Events for ad attribution.
///
/// Meta App Events: the key acquisition events (registration, trial start,
/// purchase) are also reported to Meta so App-Install / App-Promotion ad
/// campaigns can optimise toward people likely to convert, and so we can
/// see real cost-per-install / cost-per-trial in Ads Manager. The install
/// ("activate app") event is auto-logged by the native SDK via the
/// AndroidManifest meta-data — no code needed for that one.
///
/// Naming convention: snake_case verbs in past tense (Firebase). Meta gets
/// its own standard event names (CompleteRegistration, StartTrial, Purchase).
/// Param values: never include name, email, phone, exact birth date, or chat
/// content. Use bucketed values (age range, sun sign) instead.
class Analytics {
  static FirebaseAnalytics? _instance;
  static FirebaseAnalyticsObserver? _observer;

  /// Meta (Facebook) App Events. No-ops safely until a real Facebook App ID
  /// is set in android/app/src/main/res/values/strings.xml.
  static final FacebookAppEvents _fb = FacebookAppEvents();

  /// Call once after Firebase.initializeApp()
  static Future<void> init() async {
    if (kIsWeb) return; // skip on web preview
    _instance ??= FirebaseAnalytics.instance;
    _observer ??= FirebaseAnalyticsObserver(analytics: _instance!);
    try {
      await _instance!.setAnalyticsCollectionEnabled(true);
    } catch (_) {}
    // Meta App Events: enable auto-logging (install/session) + advertiser
    // tracking. Wrapped so a missing/placeholder App ID never breaks boot.
    try {
      await _fb.setAutoLogAppEventsEnabled(true);
      await _fb.setAdvertiserTracking(enabled: true);
    } catch (_) {}
  }

  /// Fire a Meta App Event. Best-effort; never throws into the app.
  static Future<void> _fbLog(String name,
      {Map<String, dynamic>? params, double? valueToSum}) async {
    try {
      await _fb.logEvent(name: name, parameters: params, valueToSum: valueToSum);
    } catch (_) {}
  }

  /// Hook this into MaterialApp to auto-track screen views.
  static FirebaseAnalyticsObserver? get observer => _observer;

  // ─── USER LIFECYCLE ─────────────────────────────────────────
  static Future<void> signupCompleted({required String method}) {
    // Meta standard event: CompleteRegistration — a key upper-funnel
    // optimisation signal for app campaigns. MUST use the SDK's standard
    // event-name constant (fb_mobile_complete_registration), NOT the string
    // 'CompleteRegistration' — the latter registers as a CUSTOM event and
    // can't be used for standard optimisation.
    _fbLog(FacebookAppEvents.eventNameCompletedRegistration,
        params: {'fb_registration_method': method});
    // GA4 standard event `sign_up` — Google Ads / App Campaigns read this
    // (via the Firebase link) as the registration conversion.
    try {
      _instance?.logSignUp(signUpMethod: method);
    } catch (_) {}
    return _log('signup_completed', {'method': method});
  }

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
  static Future<void> paywallViewed({required String trigger}) {
    // Meta standard event: ViewContent — top-of-funnel signal that someone
    // reached the paywall. Use the SDK's standard constant
    // (fb_mobile_content_view); the string 'ViewContent' registers as custom.
    _fbLog(FacebookAppEvents.eventNameViewedContent,
        params: {'fb_content_type': 'paywall', 'fb_content_id': trigger});
    return _log('paywall_viewed', {'trigger': trigger});
  }
  // trigger: 'chat_limit', 'palm_limit', 'home_banner', 'drawer',
  // 'drawer_upgrade', 'settings', 'settings_upgrade', 'post_purchase_upsell'

  /// Map plan id → INR value for Meta value-optimisation.
  static const Map<String, double> _planValueInr = {
    'trial': 49.0, // one-time Starter Pass
    'standard': 199.0,
    'premium': 499.0,
  };

  /// Fire when the user taps a plan and the Razorpay sheet opens.
  /// Meta standard event: InitiatedCheckout — the key "intent to pay" signal.
  static Future<void> checkoutInitiated({required String plan}) {
    final value = _planValueInr[plan] ?? 0.0;
    try {
      _fb.logInitiatedCheckout(
        totalPrice: value,
        currency: 'INR',
        contentId: plan,
        numItems: 1,
      );
    } catch (_) {}
    // GA4 standard event `begin_checkout` (value + currency) for Google App
    // Campaign optimisation.
    try {
      _instance?.logBeginCheckout(currency: 'INR', value: value);
    } catch (_) {}
    return _log('checkout_initiated', {'plan': plan});
  }

  static Future<void> subscriptionStarted({
    required String plan,
    required String paymentMethod,
  }) {
    // Recurring plan (Standard/Premium) just activated and the first month
    // was charged immediately. There is NO free trial anymore, so we fire:
    //   • Subscribe — the subscription-lifecycle signal (value = monthly INR)
    //   • Purchase  — the actual first-charge revenue (same value)
    // Monthly RENEWALS happen server-side and are NOT covered here — those
    // need the Conversions API on the Razorpay webhook (Phase 2).
    final value = _planValueInr[plan] ?? 0.0;
    // Use the SDK's standard Subscribe constant (kept explicit for clarity /
    // version-safety — it resolves to Meta's standard "Subscribe" event).
    _fbLog(FacebookAppEvents.eventNameSubscribe,
        params: {'fb_currency': 'INR', 'fb_order_id': plan},
        valueToSum: value);
    try {
      _fb.logPurchase(amount: value, currency: 'INR', parameters: {
        'fb_content_type': 'subscription',
        'fb_content_id': plan,
      });
    } catch (_) {}
    // GA4 standard `purchase` (value + currency) → Google App Campaign
    // purchase optimisation + value-based bidding.
    try {
      _instance?.logPurchase(currency: 'INR', value: value);
    } catch (_) {}
    return _log('subscription_started', {
      'plan': plan,
      'payment_method': paymentMethod,
    });
  }

  /// Fire when a subscription becomes a real paid conversion (the day-7
  /// charge succeeds). Reports a Meta Purchase with the plan's value so
  /// App-Promotion campaigns can optimise for paying users / ROAS.
  /// NOTE: the charge happens server-side, so ideally this is also sent via
  /// Meta Conversions API from the webhook; calling it here covers the case
  /// where the app observes the active/charged state on resume.
  static Future<void> subscriptionPurchased({required String plan}) {
    // trial = the one-time ₹49 Starter Pass; standard/premium = monthly.
    final value = _planValueInr[plan] ?? 0.0;
    try {
      _fb.logPurchase(amount: value, currency: 'INR', parameters: {
        'fb_content_type': plan == 'trial' ? 'one_time_pass' : 'subscription',
        'fb_content_id': plan,
      });
    } catch (_) {}
    // GA4 standard `purchase` (value + currency) → Google App Campaign
    // purchase optimisation + value-based bidding.
    try {
      _instance?.logPurchase(currency: 'INR', value: value);
    } catch (_) {}
    return _log('subscription_purchased', {'plan': plan});
  }

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
