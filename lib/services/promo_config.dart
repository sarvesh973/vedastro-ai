import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/subscription_plan.dart';
import 'auth_service.dart';
import 'storage_service.dart';

/// Campaign policy for the launch banner, fetched from the server.
///
/// These used to be compile-time constants, which meant stopping a
/// campaign, changing its end date, or correcting the price claim all
/// required a build, a Play review, and then waiting for users to update.
/// For a festive campaign carrying a price in the artwork, that is too
/// slow to be safe.
///
/// The constants survive as DEFAULTS, and they are deliberately OFF: a
/// server that cannot be reached must never be the reason a campaign
/// starts.
class PromoConfig {
  final bool enabled;

  /// Whether the ₹99 standing rate is live in Razorpay. Both creatives
  /// show ₹99 struck through, so this being wrong is a false price
  /// claim rather than a cosmetic bug.
  final bool pricingIntroLive;

  final int maxDismissals;
  final int pauseDays;

  /// Relative weights per creative id. A zero retires a variant without
  /// a release.
  final Map<String, int> variantWeights;

  /// True when the server says the campaign's end date has passed.
  /// Resolved server-side so a wrong device clock cannot extend it.
  final bool expired;

  const PromoConfig({
    required this.enabled,
    required this.pricingIntroLive,
    required this.maxDismissals,
    required this.pauseDays,
    required this.variantWeights,
    this.expired = false,
  });

  /// Used until the server answers, and whenever it cannot be reached.
  /// OFF, on purpose.
  static const defaults = PromoConfig(
    enabled: false,
    pricingIntroLive: false,
    maxDismissals: 4,
    pauseDays: 7,
    variantWeights: {'a': 50, 'b': 50},
  );

  /// Both switches, as the app sees them.
  ///
  /// kPassIntroPricingLive is still consulted and still wins when false.
  /// The server can turn the price claim OFF remotely but cannot turn it
  /// on for a build that does not have the matching plan logic — a
  /// remote flag must not be able to make the app assert a price its own
  /// code does not implement.
  bool get live => enabled && pricingIntroLive && kPassIntroPricingLive;

  @visibleForTesting
  factory PromoConfig.fromJson(Map<String, dynamic> json) {
    final rawWeights = json['variantWeights'];
    final weights = <String, int>{};
    if (rawWeights is Map) {
      for (final entry in rawWeights.entries) {
        final v = entry.value;
        if (v is num && v >= 0) weights['${entry.key}'] = v.round();
      }
    }
    final total = weights.values.fold<int>(0, (a, b) => a + b);

    int clamp(Object? v, int fallback, int lo, int hi) {
      final n = v is num ? v.round() : null;
      if (n == null) return fallback;
      return n < lo ? lo : (n > hi ? hi : n);
    }

    return PromoConfig(
      // Require real booleans. A server returning "true" as a string must
      // not start a campaign.
      enabled: json['enabled'] == true,
      pricingIntroLive: json['pricingIntroLive'] == true,
      expired: json['expired'] == true,
      maxDismissals:
          clamp(json['maxDismissals'], defaults.maxDismissals, 1, 20),
      pauseDays: clamp(json['pauseDays'], defaults.pauseDays, 1, 60),
      // All-zero or absent weights would leave nothing to pick.
      variantWeights: total > 0 ? weights : defaults.variantWeights,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'pricingIntroLive': pricingIntroLive,
        'expired': expired,
        'maxDismissals': maxDismissals,
        'pauseDays': pauseDays,
        'variantWeights': variantWeights,
      };

  static const _keyCached = 'promo_config_cache';

  /// The config the app is currently acting on.
  ///
  /// Read SYNCHRONOUSLY from the last cached copy, because the decision
  /// to show the banner happens on the launch path and must not wait on
  /// the network. [refresh] updates the cache in the background.
  static PromoConfig get current {
    final raw = StorageService.prefs?.getString(_keyCached);
    if (raw == null || raw.isEmpty) return defaults;
    try {
      return PromoConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A corrupt cache must not be worse than no cache.
      return defaults;
    }
  }

  /// Fetches and caches. Fire-and-forget from app start.
  ///
  /// On any failure the previous cached copy stands. That is deliberate:
  /// a user who goes offline mid-campaign keeps the policy they last
  /// saw, rather than reverting to defaults and having the banner vanish
  /// — and a campaign that was turned OFF stays off, because the cached
  /// copy says so.
  static Future<void> refresh() async {
    try {
      final token = await AuthService.currentUser?.getIdToken();
      if (token == null) return;
      final res = await http.get(
        Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/promo/config'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return;
      // Round-trip through fromJson so a malformed field is normalised
      // before it reaches the cache, not after.
      final config = PromoConfig.fromJson(decoded);
      await StorageService.prefs
          ?.setString(_keyCached, jsonEncode(config.toJson()));
    } catch (_) {
      // Never let campaign config break app start.
    }
  }
}
