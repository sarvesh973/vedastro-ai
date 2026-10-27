import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vedastro_ai/models/subscription_plan.dart';
import 'package:vedastro_ai/services/promo_config.dart';
import 'package:vedastro_ai/services/storage_service.dart';

/// Campaign policy moved to the server so a banner can be stopped, dated
/// or corrected without a Play review. That only helps if the client
/// handles a server it cannot reach — which, on a launch path, is most of
/// the interesting cases.
///
/// The rule under test: a config that cannot be read must never be the
/// reason a campaign STARTS, and must never be the reason one that was
/// turned off comes back.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  Future<void> cache(Map<String, dynamic> json) async =>
      StorageService.prefs?.setString('promo_config_cache', jsonEncode(json));

  group('defaults are off', () {
    test('with no cached config at all', () {
      expect(PromoConfig.current.enabled, isFalse);
      expect(PromoConfig.current.pricingIntroLive, isFalse);
      expect(PromoConfig.current.live, isFalse);
    });

    test('with a corrupt cache', () async {
      await StorageService.prefs
          ?.setString('promo_config_cache', 'not json at all');
      // A corrupt cache must not be worse than no cache.
      expect(PromoConfig.current.enabled, isFalse);
      expect(PromoConfig.current.maxDismissals,
          PromoConfig.defaults.maxDismissals);
    });

    test('with an empty object', () async {
      await cache({});
      expect(PromoConfig.current.live, isFalse);
    });
  });

  group('booleans must be real booleans', () {
    test('a string "true" does not start a campaign', () async {
      // A server bug or a hand-edited Firestore field stored as text
      // should be inert, not a launch.
      await cache({'enabled': 'true', 'pricingIntroLive': 'true'});
      expect(PromoConfig.current.enabled, isFalse);
      expect(PromoConfig.current.pricingIntroLive, isFalse);
    });

    test('a truthy number does not either', () async {
      await cache({'enabled': 1, 'pricingIntroLive': 1});
      expect(PromoConfig.current.enabled, isFalse);
    });

    test('explicit true works', () async {
      await cache({'enabled': true, 'pricingIntroLive': true});
      expect(PromoConfig.current.enabled, isTrue);
      expect(PromoConfig.current.pricingIntroLive, isTrue);
    });
  });

  group('live requires all three switches', () {
    test('server-enabled alone is not enough', () async {
      await cache({'enabled': true, 'pricingIntroLive': false});
      expect(PromoConfig.current.live, isFalse);
    });

    test('the build flag still wins when false', () async {
      await cache({'enabled': true, 'pricingIntroLive': true});
      // The server can turn the price claim OFF remotely but must not be
      // able to turn it ON for a build whose own pricing logic does not
      // implement it. A remote flag asserting a price the app cannot
      // honour is the worst case here.
      expect(kPassIntroPricingLive, isFalse);
      expect(PromoConfig.current.live, isFalse,
          reason: 'remote config cannot override a false build flag');
    });
  });

  group('clamping', () {
    test('out-of-range numbers are pulled back', () async {
      await cache({'maxDismissals': 0, 'pauseDays': 9999});
      expect(PromoConfig.current.maxDismissals, 1,
          reason: 'zero would make the dismissal cap unreachable');
      expect(PromoConfig.current.pauseDays, 60);
    });

    test('non-numeric falls back', () async {
      await cache({'maxDismissals': 'four'});
      expect(PromoConfig.current.maxDismissals,
          PromoConfig.defaults.maxDismissals);
    });
  });

  group('variant weights', () {
    test('pass through', () async {
      await cache({
        'variantWeights': {'a': 70, 'b': 30}
      });
      expect(PromoConfig.current.variantWeights, {'a': 70, 'b': 30});
    });

    test('a variant can be retired with a zero', () async {
      await cache({
        'variantWeights': {'a': 100, 'b': 0}
      });
      expect(PromoConfig.current.variantWeights['b'], 0);
    });

    test('all-zero falls back so there is always something to pick',
        () async {
      await cache({
        'variantWeights': {'a': 0, 'b': 0}
      });
      expect(PromoConfig.current.variantWeights,
          PromoConfig.defaults.variantWeights);
    });

    test('negative weights are dropped', () async {
      await cache({
        'variantWeights': {'a': -5, 'b': 10}
      });
      expect(PromoConfig.current.variantWeights.containsKey('a'), isFalse);
    });
  });

  group('expiry', () {
    test('an expired campaign is reported and not live', () async {
      // The server resolves expiry, so the client only has to respect it.
      await cache({
        'enabled': false,
        'pricingIntroLive': true,
        'expired': true,
      });
      expect(PromoConfig.current.expired, isTrue);
      expect(PromoConfig.current.live, isFalse);
    });
  });

  group('cache survives a round trip', () {
    test('toJson/fromJson preserves every field', () async {
      const original = PromoConfig(
        enabled: true,
        pricingIntroLive: true,
        maxDismissals: 6,
        pauseDays: 3,
        variantWeights: {'a': 20, 'b': 80},
        expired: false,
      );
      final back = PromoConfig.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
      expect(back.enabled, isTrue);
      expect(back.pricingIntroLive, isTrue);
      expect(back.maxDismissals, 6);
      expect(back.pauseDays, 3);
      expect(back.variantWeights, {'a': 20, 'b': 80});
    });
  });
}
