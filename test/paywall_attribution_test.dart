import 'package:flutter_test/flutter_test.dart';
import 'package:vedastro_ai/models/subscription_plan.dart';
import 'package:vedastro_ai/services/analytics_service.dart';

/// Covers the two pieces of paywall attribution that are pure logic.
///
/// The point of this work is to make "which paywall actually converts"
/// answerable, and the failure mode is silent: a wrong bucket boundary or a
/// plan missing from the upgrade list does not throw, it just produces a
/// funnel that quietly misleads whoever reads it.
void main() {
  group('dwellBucket', () {
    test('boundaries are exact', () {
      // Each threshold is checked on both sides, because an off-by-one here
      // moves real users between "bounce" and "skim" — the distinction the
      // whole metric exists to draw.
      expect(Analytics.dwellBucket(0), 'bounce');
      expect(Analytics.dwellBucket(2), 'bounce');
      expect(Analytics.dwellBucket(3), 'skim');
      expect(Analytics.dwellBucket(14), 'skim');
      expect(Analytics.dwellBucket(15), 'considered');
      expect(Analytics.dwellBucket(59), 'considered');
      expect(Analytics.dwellBucket(60), 'long');
      expect(Analytics.dwellBucket(86400), 'long');
    });

    test('a negative duration still buckets', () {
      // DateTime.difference can go negative if the device clock moves
      // backwards mid-session (NTP correction, manual change). It must not
      // produce a null or an exception inside an analytics call.
      expect(Analytics.dwellBucket(-1), 'bounce');
    });

    test('there are exactly four buckets', () {
      final seen = <String>{};
      for (var s = -5; s < 300; s++) {
        seen.add(Analytics.dwellBucket(s));
      }
      expect(seen, {'bounce', 'skim', 'considered', 'long'},
        reason: 'GA4 collapses high-cardinality dimensions into (other)');
    });
  });

  group('upgradeOptions feed the paywall the trigger describes', () {
    test('a free user is offered the cheap front door', () {
      // The ₹49 weekly Pass is the advertised entry point. If it ever drops
      // out of this list the chat_limit paywall silently stops showing the
      // cheapest option, and the conversion data would look like price
      // resistance rather than a missing card.
      final opts = SubscriptionPlan.free.upgradeOptions;
      expect(opts, contains(SubscriptionPlan.pass));
      expect(opts.first, SubscriptionPlan.pass,
        reason: 'cheapest first, so it is the one seen without scrolling');
    });

    test('nobody is offered their own plan or a downgrade', () {
      for (final plan in SubscriptionPlan.values) {
        final opts = plan.upgradeOptions;
        expect(opts, isNot(contains(plan)),
          reason: '$plan should not be offered itself');
        for (final o in opts) {
          expect(o.firstChargePaise, greaterThan(plan.firstChargePaise),
            reason: '$plan -> $o is not an upgrade');
        }
      }
    });

    test('an unlimited subscriber has nothing left to buy', () {
      expect(SubscriptionPlan.premium.upgradeOptions, isEmpty);
    });
  });
}
