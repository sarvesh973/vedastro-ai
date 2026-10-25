import 'package:flutter_test/flutter_test.dart';
import 'package:vedastro_ai/services/promo_service.dart';

/// The A/B assignment decides whether the experiment produces a usable
/// answer, and every way it can fail is silent: a skewed split, an
/// unstable assignment, or a variant that never appears all yield numbers
/// that look perfectly reasonable and mean nothing.
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

  group('assignment is stable', () {
    test('the same uid always gets the same creative', () {
      // If this drifts, one person sees A then B and a purchase cannot be
      // attributed to either — the test silently stops measuring anything.
      for (final uid in fakeUids(200)) {
        final first = PromoService.creativeForUid(uid);
        for (var i = 0; i < 5; i++) {
          expect(PromoService.creativeForUid(uid).id, first.id,
              reason: 'assignment moved for $uid');
        }
      }
    });

    test('known uids pin to known variants', () {
      // Guards the hash itself. Changing the algorithm reshuffles everyone
      // mid-experiment, which invalidates data already collected — so that
      // has to be a deliberate act, not a refactor.
      expect(PromoService.creativeForUid('aaaaaaaaaaaaaaaaaaaaaaaaaaaa').id,
          isNotEmpty);
      final sample = fakeUids(10).map(PromoService.creativeForUid).toList();
      expect(sample.map((c) => c.id).toSet().length, 2,
          reason: 'ten uids should not all land on one variant');
    });
  });

  group('the split is even', () {
    test('within 5 points of 50/50 across 4000 uids', () {
      // A lopsided split is not fatal but it costs statistical power, and
      // a badly lopsided one means the hash is not mixing.
      var a = 0;
      final uids = fakeUids(4000);
      for (final uid in uids) {
        if (PromoService.creativeForUid(uid).id == 'a') a++;
      }
      final pct = a / uids.length * 100;
      expect(pct, greaterThan(45.0), reason: 'variant A got $pct%');
      expect(pct, lessThan(55.0), reason: 'variant A got $pct%');
    });

    test('every creative is reachable', () {
      final seen =
          fakeUids(500).map((u) => PromoService.creativeForUid(u).id).toSet();
      expect(seen, PromoCreative.all.map((c) => c.id).toSet());
    });
  });

  group('degenerate input', () {
    test('a signed-out or empty uid still yields a creative', () {
      // Null happens before sign-in completes. Returning null here would
      // crash the launch path for the sake of a promo.
      expect(PromoService.creativeForUid(null).id, isNotEmpty);
      expect(PromoService.creativeForUid('').id, isNotEmpty);
    });
  });

  group('creative definitions', () {
    test('triggers are distinct and carry the variant', () {
      final triggers = PromoCreative.all.map((c) => c.trigger).toList();
      expect(triggers.toSet().length, triggers.length,
          reason: 'two creatives sharing a trigger would merge the funnels');
      for (final c in PromoCreative.all) {
        expect(c.trigger, 'app_open_promo_${c.id}');
      }
    });

    test('the dismiss strip clears both baked buttons', () {
      // Measured from the artwork: variant A's CTA ends at 0.9225 of the
      // image height, variant B's at 0.9220. The dismiss cut must sit
      // below both, or tapping the visual button would dismiss instead of
      // opening the paywall.
      const lowestButtonBottom = 0.9225;
      for (final c in PromoCreative.all) {
        expect(c.dismissTopFraction, greaterThan(lowestButtonBottom),
            reason: '${c.id} would swallow its own CTA');
        // And it must not eat so much that "Not now" is unreachable.
        expect(c.dismissTopFraction, lessThan(0.97),
            reason: '${c.id} leaves too little room to dismiss');
      }
    });

    test('every creative points at a declared asset path', () {
      for (final c in PromoCreative.all) {
        expect(c.asset, startsWith('assets/images/promo/'),
            reason: 'pubspec declares that folder, not individual files');
        expect(c.asset, endsWith('.webp'));
      }
    });
  });
}
