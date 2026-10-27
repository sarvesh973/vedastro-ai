import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/subscription_plan.dart';
import 'auth_service.dart';
import 'storage_service.dart';

/// One creative, as the server describes it.
///
/// [imageUrl] is optional. Without it the app renders the creative
/// bundled under [id] — which is what makes a first launch, an offline
/// launch, or a dead URL produce a usable banner rather than a broken
/// one. Remote artwork is an upgrade on the bundled pair, never a
/// replacement for having any.
class RemoteCreative {
  final String id;
  final int weight;
  final String? imageUrl;

  /// Fraction below which a tap dismisses instead of opening the paywall.
  ///
  /// Per-creative because it depends on the ARTWORK: it has to sit under
  /// whatever "Not now" the image draws. Both shipped creatives put their
  /// button's bottom edge at ~0.922, so 0.93 clears them.
  final double dismissTop;

  /// Where the close control goes. Variant A's top-right corner is
  /// occupied by its Diwali pill.
  final bool closeOnLeft;

  const RemoteCreative({
    required this.id,
    required this.weight,
    this.imageUrl,
    this.dismissTop = 0.93,
    this.closeOnLeft = false,
  });

  /// The asset bundled under this id, used when [imageUrl] is absent or
  /// fails to load.
  String get bundledAsset => 'assets/images/promo/diwali_$id.webp';

  /// Analytics trigger, e.g. 'app_open_promo_a'. The variant rides in the
  /// trigger because that is already a registered GA4 dimension flowing
  /// through the whole funnel.
  String get trigger => 'app_open_promo_$id';

  /// Null for anything that cannot be rendered correctly. A creative with
  /// a bad id or an out-of-range dismiss strip should not run — the strip
  /// would sit over its own call to action.
  static RemoteCreative? fromJson(Map<dynamic, dynamic> json) {
    final id = json['id'];
    if (id is! String || !RegExp(r'^[a-z0-9_-]{1,16}$').hasMatch(id)) {
      return null;
    }
    final w = json['weight'];
    final dt = json['dismissTop'];
    final url = json['imageUrl'];
    return RemoteCreative(
      id: id,
      weight: w is num && w >= 0 ? w.round().clamp(0, 1000) : 0,
      // https only. The server validates this too; doing it here as well
      // means a stale cache written by an older server cannot smuggle an
      // http url past the app's network config.
      imageUrl: url is String && url.startsWith('https://') && url.length < 500
          ? url
          : null,
      dismissTop: dt is num && dt >= 0.5 && dt <= 0.99 ? dt.toDouble() : 0.93,
      closeOnLeft: json['closeOnLeft'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'weight': weight,
        'imageUrl': imageUrl,
        'dismissTop': dismissTop,
        'closeOnLeft': closeOnLeft,
      };
}

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

  /// The creatives themselves, so adding, replacing or retiring one is a
  /// server edit rather than a release.
  final List<RemoteCreative> variants;

  /// True when the server says the campaign's end date has passed.
  /// Resolved server-side so a wrong device clock cannot extend it.
  final bool expired;

  const PromoConfig({
    required this.enabled,
    required this.pricingIntroLive,
    required this.maxDismissals,
    required this.pauseDays,
    required this.variants,
    this.expired = false,
  });

  /// Used until the server answers, and whenever it cannot be reached.
  /// OFF, on purpose.
  /// Used until the server answers, and whenever it cannot be reached.
  /// The two bundled creatives, so an offline first launch still has
  /// something to show if the campaign is ever turned on.
  static const defaults = PromoConfig(
    enabled: false,
    pricingIntroLive: false,
    maxDismissals: 4,
    pauseDays: 7,
    variants: [
      RemoteCreative(id: 'a', weight: 50, closeOnLeft: true),
      RemoteCreative(id: 'b', weight: 50),
    ],
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
    final rawVariants = json['variants'];
    final variants = <RemoteCreative>[];
    if (rawVariants is List) {
      for (final entry in rawVariants) {
        if (entry is! Map) continue;
        final parsed = RemoteCreative.fromJson(entry);
        if (parsed != null) variants.add(parsed);
      }
    }
    final total = variants.fold<int>(0, (a, v) => a + v.weight);

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
      // An empty list, or every weight zero, would leave nothing to pick.
      variants: total > 0 ? variants : defaults.variants,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'pricingIntroLive': pricingIntroLive,
        'expired': expired,
        'maxDismissals': maxDismissals,
        'pauseDays': pauseDays,
        'variants': variants.map((v) => v.toJson()).toList(),
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
