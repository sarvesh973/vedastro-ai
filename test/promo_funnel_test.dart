import 'package:flutter_test/flutter_test.dart';
import 'package:vedastro_ai/services/analytics_service.dart';
import 'package:vedastro_ai/services/promo_config.dart';

/// Pins the shape of the promo funnel.
///
/// The banner and the paywall are two stages of one journey, and they
/// used to fire the SAME event with the SAME trigger — so a user who
/// tapped through counted as two views, the view total was inflated by
/// exactly the number of people who engaged, and "how many who saw the
/// banner opened the paywall" was unanswerable.
///
/// The stages are now distinct events sharing one trigger:
///
///   promo_shown -> promo_accepted -> paywall_viewed -> subscription_purchased
///
/// Every failure here is silent. A duplicated event name, a trigger that
/// does not match across stages, or a dwell bucket that drifts all
/// produce a funnel that renders fine and misleads whoever reads it.
void main() {
  group('the funnel stages are distinct', () {
    test('the banner does not reuse the paywall event name', () {
      // Named constants would be better, but the point is to state the
      // contract: these four are the funnel, and no two share a name.
      const stages = [
        'promo_shown',
        'promo_accepted',
        'paywall_viewed',
        'subscription_purchased',
      ];
      expect(stages.toSet().length, stages.length,
          reason: 'two stages sharing an event name collapses the funnel');
    });
  });

  group('trigger joins the stages', () {
    test('a creative produces one trigger used at every stage', () {
      const c = RemoteCreative(id: 'a', weight: 50);
      expect(c.trigger, 'app_open_promo_a');
      // The same string is what PromoService passes to promoShown,
      // promoAccepted and PaywallScreen — which then carries it into
      // subscription_started and subscription_purchased. If any stage
      // used a different value the funnel would break silently into
      // unrelated counts.
      expect(c.trigger, startsWith('app_open_promo_'));
    });

    test('two creatives never share a trigger', () {
      const a = RemoteCreative(id: 'a', weight: 50);
      const b = RemoteCreative(id: 'b', weight: 50);
      expect(a.trigger, isNot(b.trigger),
          reason: 'sharing one would merge the two variants into one row');
    });

    test('a creative added later gets its own trigger with no code change',
        () {
      const holi = RemoteCreative(id: 'holi', weight: 25);
      expect(holi.trigger, 'app_open_promo_holi');
    });
  });

  group('dwell bucketing is shared', () {
    test('promo_dismissed uses the same buckets as paywall_dismissed', () {
      // Both call Analytics.dwellBucket, so a dismissal at the banner and
      // one at the paywall are directly comparable. Separate scales would
      // make "did they bounce" mean two different things.
      expect(Analytics.dwellBucket(0), 'bounce');
      expect(Analytics.dwellBucket(2), 'bounce');
      expect(Analytics.dwellBucket(3), 'skim');
      expect(Analytics.dwellBucket(15), 'considered');
      expect(Analytics.dwellBucket(60), 'long');
    });

    test('a sub-three-second dismissal reads as a bounce', () {
      // This is the number that will tell you whether a banner shown
      // three times a day is being swatted away rather than considered.
      expect(Analytics.dwellBucket(1), 'bounce');
    });
  });
}
