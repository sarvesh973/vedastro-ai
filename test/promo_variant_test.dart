import 'package:flutter_test/flutter_test.dart';
import 'package:vedastro_ai/services/promo_config.dart';
import 'package:vedastro_ai/services/promo_service.dart';

/// The A/B assignment decides whether the experiment produces a usable
/// answer, and every way it can fail is silent: a skewed split, an
/// unstable assignment, or a variant that never appears all yield numbers
/// that look perfectly reasonable and mean nothing.
///
/// Now that creatives come from the server, weight also has to be
/// honoured — it is how a losing variant is retired and how a split is
/// rebalanced without a release.
void main() {
  /// Firebase uids are 28 chars of [A-Za-z0-9]. Generating realistic ones
  /// matters — a hash can distribute evenly on sequential integers and
  /// badly on the alphabet a real uid actually uses.
  List<String> fakeUids(int n) {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    var seed = 12345;
    int next() {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      return seed;
    }

    return List.generate(n, (_) {
      final b = StringBuffer();
      for (var i = 0; i < 28; i++) {
        b.write(alphabet[next() % alphabet.length]);
      }
      return b.toString();
    });
  }

  const even = [
    RemoteCreative(id: 'a', weight: 50, closeOnLeft: true),
    RemoteCreative(id: 'b', weight: 50),
  ];

  group('assignment is stable', () {
    test('the same uid always gets the same creative', () {
      // If this drifts, one person sees A then B and a purchase cannot be
      // attributed to either — the test silently stops measuring.
      for (final uid in fakeUids(200)) {
        final first = PromoService.creativeFor(uid, even).id;
        for (var i = 0; i < 5; i++) {
          expect(PromoService.creativeFor(uid, even).id, first);
        }
      }
    });
  });

  group('weights are honoured', () {
    test('an even split lands within 5 points of 50/50', () {
      var a = 0;
      final uids = fakeUids(4000);
      for (final uid in uids) {
        if (PromoService.creativeFor(uid, even).id == 'a') a++;
      }
      final pct = a / uids.length * 100;
      expect(pct, greaterThan(45.0), reason: 'variant A got $pct%');
      expect(pct, lessThan(55.0), reason: 'variant A got $pct%');
    });

    test('a zero-weight creative is NEVER selected', () {
      // This is how a losing variant is retired mid-campaign. If a zero
      // weight still got traffic, retiring one would be impossible
      // without a release — the thing moving config to the server was
      // meant to fix.
      const retired = [
        RemoteCreative(id: 'a', weight: 100),
        RemoteCreative(id: 'b', weight: 0),
      ];
      for (final uid in fakeUids(500)) {
        expect(PromoService.creativeFor(uid, retired).id, 'a');
      }
    });

    test('an uneven split roughly tracks the weights', () {
      const skewed = [
        RemoteCreative(id: 'a', weight: 90),
        RemoteCreative(id: 'b', weight: 10),
      ];
      var a = 0;
      final uids = fakeUids(3000);
      for (final uid in uids) {
        if (PromoService.creativeFor(uid, skewed).id == 'a') a++;
      }
      final pct = a / uids.length * 100;
      expect(pct, greaterThan(85.0), reason: 'variant A got $pct%');
      expect(pct, lessThan(95.0), reason: 'variant A got $pct%');
    });

    test('three variants all get traffic', () {
      const three = [
        RemoteCreative(id: 'a', weight: 34),
        RemoteCreative(id: 'b', weight: 33),
        RemoteCreative(id: 'c', weight: 33),
      ];
      final seen =
          fakeUids(600).map((u) => PromoService.creativeFor(u, three).id).toSet();
      expect(seen, {'a', 'b', 'c'},
          reason: 'adding a third creative must not need a release');
    });
  });

  group('degenerate input', () {
    test('a signed-out uid still yields a creative', () {
      expect(PromoService.creativeFor(null, even).id, isNotEmpty);
      expect(PromoService.creativeFor('', even).id, isNotEmpty);
    });

    test('an all-zero list still yields something', () {
      // Never crash the launch path over a misconfigured campaign.
      const allZero = [
        RemoteCreative(id: 'a', weight: 0),
        RemoteCreative(id: 'b', weight: 0),
      ];
      expect(PromoService.creativeFor('someuid', allZero).id, isNotEmpty);
    });

    test('an empty list falls back to a bundled default', () {
      expect(PromoService.creativeFor('someuid', const []).id, isNotEmpty);
    });
  });

  group('creative definitions', () {
    test('triggers are distinct and carry the variant', () {
      final triggers = even.map((c) => c.trigger).toList();
      expect(triggers.toSet().length, triggers.length,
          reason: 'two creatives sharing a trigger would merge the funnels');
      for (final c in even) {
        expect(c.trigger, 'app_open_promo_${c.id}');
      }
    });

    test('the dismiss strip clears both baked buttons', () {
      // Measured from the artwork: variant A's CTA ends at 0.9225 of the
      // image height, variant B's at 0.9220.
      for (final c in even) {
        expect(c.dismissTop, greaterThan(0.9225),
            reason: '${c.id} would swallow its own CTA');
        expect(c.dismissTop, lessThan(0.97));
      }
    });

    test('every creative resolves a bundled asset as its floor', () {
      // The fallback for a first launch, an offline launch or a dead URL.
      for (final c in even) {
        expect(c.bundledAsset, startsWith('assets/images/promo/'));
        expect(c.bundledAsset, endsWith('.webp'));
      }
    });
  });

  group('remote creative parsing', () {
    test('rejects an unsafe id', () {
      expect(RemoteCreative.fromJson({'id': 'bad id', 'weight': 10}), isNull);
      expect(RemoteCreative.fromJson({'id': '', 'weight': 10}), isNull);
      expect(RemoteCreative.fromJson({'weight': 10}), isNull);
    });

    test('accepts https and rejects everything else', () {
      String? url(Object? v) =>
          RemoteCreative.fromJson({'id': 'a', 'weight': 1, 'imageUrl': v})
              ?.imageUrl;
      expect(url('https://cdn.example/a.webp'), 'https://cdn.example/a.webp');
      // A stale cache written by an older server must not smuggle an
      // http url past the app's network security config.
      expect(url('http://cdn.example/a.webp'), isNull);
      expect(url('javascript:alert(1)'), isNull);
      expect(url(42), isNull);
    });

    test('an out-of-range dismissTop falls back rather than being honoured',
        () {
      double? dt(Object? v) =>
          RemoteCreative.fromJson({'id': 'a', 'weight': 1, 'dismissTop': v})
              ?.dismissTop;
      expect(dt(0.88), 0.88);
      // Below 0.5 most taps would dismiss, which is not a promo; above
      // 0.99 the strip is unreachable. Either way a wrong value puts the
      // strip over the creative's own call to action.
      expect(dt(0.2), 0.93);
      expect(dt(1.4), 0.93);
      expect(dt('low'), 0.93);
    });
  });
}
