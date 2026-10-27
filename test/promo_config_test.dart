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

    test('the server can turn the price claim off remotely', () async {
      // The build flag is on, so the server is now the live control:
      // setting pricingIntroLive false must stop the ₹99 claim without a
      // release. That is the whole reason it moved off the client.
      await cache({'enabled': true, 'pricingIntroLive': false});
      expect(kPassIntroPricingLive, isTrue);
      expect(PromoConfig.current.live, isFalse);
    });

    test('all three on makes it live', () async {
      await cache({'enabled': true, 'pricingIntroLive': true});
      expect(PromoConfig.current.live, isTrue);
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

  group('variants', () {
    test('come from the server, with urls', () async {
      await cache({
        'variants': [
          {
            'id': 'x',
            'weight': 70,
            'imageUrl': 'https://cdn.example/x.webp',
            'dismissTop': 0.9,
          },
          {'id': 'y', 'weight': 30},
        ],
      });
      final v = PromoConfig.current.variants;
      expect(v.map((c) => c.id), ['x', 'y']);
      expect(v.first.imageUrl, 'https://cdn.example/x.webp');
      expect(v.first.dismissTop, 0.9);
      // A creative with no url still works — it renders the bundled
      // asset for its id.
      expect(v.last.imageUrl, isNull);
      expect(v.last.bundledAsset, contains('diwali_y'));
    });

    test('a brand new creative needs no app release', () async {
      // The whole point of moving this server-side: adding a third
      // variant is a config edit.
      await cache({
        'variants': [
          {'id': 'a', 'weight': 34},
          {'id': 'b', 'weight': 33},
          {'id': 'holi', 'weight': 33, 'imageUrl': 'https://cdn.example/h.webp'},
        ],
      });
      expect(PromoConfig.current.variants.length, 3);
      expect(PromoConfig.current.variants.last.trigger, 'app_open_promo_holi');
    });

    test('malformed entries are dropped, not repaired', () async {
      await cache({
        'variants': [
          {'id': 'bad id', 'weight': 50},
          {'weight': 50},
          {'id': 'ok', 'weight': 50},
        ],
      });
      expect(PromoConfig.current.variants.map((c) => c.id), ['ok']);
    });

    test('an all-zero list falls back so there is something to pick',
        () async {
      await cache({
        'variants': [
          {'id': 'a', 'weight': 0},
          {'id': 'b', 'weight': 0},
        ],
      });
      expect(PromoConfig.current.variants.map((c) => c.id),
          PromoConfig.defaults.variants.map((c) => c.id));
    });

    test('an absent list falls back to the bundled pair', () async {
      await cache({'enabled': true});
      expect(PromoConfig.current.variants.length, 2);
      expect(PromoConfig.current.variants.every((c) => c.imageUrl == null),
          isTrue, reason: 'defaults are the bundled creatives');
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
        variants: [
          RemoteCreative(
            id: 'a',
            weight: 20,
            imageUrl: 'https://cdn.example/a.webp',
            dismissTop: 0.91,
            closeOnLeft: true,
          ),
          RemoteCreative(id: 'b', weight: 80),
        ],
        expired: false,
      );
      final back = PromoConfig.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
      expect(back.enabled, isTrue);
      expect(back.pricingIntroLive, isTrue);
      expect(back.maxDismissals, 6);
      expect(back.pauseDays, 3);
      // The whole creative survives the cache, not just its weight — a
      // dropped url or dismissTop would mean the cached copy rendered
      // differently from the live one.
      expect(back.variants.length, 2);
      expect(back.variants.first.imageUrl, 'https://cdn.example/a.webp');
      expect(back.variants.first.dismissTop, 0.91);
      expect(back.variants.first.closeOnLeft, isTrue);
      expect(back.variants.last.weight, 80);
      expect(back.variants.last.imageUrl, isNull);
    });
  });
}
