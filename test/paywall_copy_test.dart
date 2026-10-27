import 'package:flutter_test/flutter_test.dart';
import 'package:vedastro_ai/screens/paywall_screen.dart';

/// Guards the paywall copy, including the constraint that it must not be
/// fear-based. That is a product promise in the Play listing, not a style
/// preference, and copy is exactly the kind of thing that drifts one
/// well-meaning edit at a time.
void main() {
  /// Surfaces that blocked the user, and so get copy naming what they hit.
  const blocked = ['chat_limit', 'palm_limit', 'compat', 'mulank'];

  /// Surfaces the user chose to visit. Nothing was taken away, so the
  /// generic header is the honest one.
  const browsing = [
    'home_banner', 'drawer', 'drawer_upgrade', 'settings',
    'settings_upgrade', 'post_purchase_upsell', 'unknown', '',
  ];

  group('which surfaces get their own copy', () {
    test('every blocked surface does', () {
      for (final t in blocked) {
        final c = paywallCopyFor(t, isFreeUser: true);
        expect(c, isNotNull, reason: '$t should name what was hit');
        expect(c!.headline.trim(), isNotEmpty);
        expect(c.subline.trim(), isNotEmpty);
      }
    });

    test('browsing surfaces keep the generic header', () {
      for (final t in browsing) {
        expect(paywallCopyFor(t, isFreeUser: true), isNull,
          reason: '$t is browsing — inventing a loss there is manufactured '
              'urgency');
      }
    });

    test('paying users never get free-tier copy', () {
      // A Standard subscriber at their cap must hear about THAT, not about
      // a free question they used months ago.
      for (final t in [...blocked, ...browsing]) {
        expect(paywallCopyFor(t, isFreeUser: false), isNull,
          reason: '$t leaked free-user copy to a paying user');
      }
    });
  });

  group('copy is not fear-based', () {
    // The listing promises no fear-based manipulation. These are the
    // standard levers for it: fake scarcity, countdowns, implied loss,
    // and shaming.
    const banned = [
      'last chance', 'hurry', 'act now', 'don\'t miss', 'dont miss',
      'expires', 'expiring', 'only today', 'limited time', 'running out',
      'before it\'s too late', 'final', 'warning', 'urgent', 'risk losing',
      'lose access', 'miss out', 'you\'ll regret',
    ];

    test('no urgency or scarcity language', () {
      for (final t in blocked) {
        final c = paywallCopyFor(t, isFreeUser: true)!;
        final text = '${c.headline} ${c.subline}'.toLowerCase();
        for (final phrase in banned) {
          expect(text.contains(phrase), isFalse,
            reason: '$t copy contains "$phrase"');
        }
      }
    });

    test('no exclamation marks', () {
      // A reading app that shouts reads as a sales funnel.
      for (final t in blocked) {
        final c = paywallCopyFor(t, isFreeUser: true)!;
        expect('${c.headline}${c.subline}'.contains('!'), isFalse,
          reason: '$t copy shouts');
      }
    });
  });

  group('copy is accurate about the product', () {
    test('the chat wall states the real Pass allowance', () {
      // The Pass is 21 chats per WEEK (SubscriptionPlan.pass.chatLimit and
      // the server's RATE_LIMITS both say 21). The server's own 429 still
      // claims "5 chats a day for 7 days" — 35, and billed as a one-off.
      // This screen must not repeat that.
      final c = paywallCopyFor('chat_limit', isFreeUser: true)!;
      expect(c.subline, contains('21'));
      expect(c.subline, isNot(contains('5 chats')));
      expect(c.subline.toLowerCase(), isNot(contains('7 days')));
    });

    test('the palm wall names the Pass exclusion', () {
      // Palm is palmLimit 0 on both free AND the ₹49 Pass. Without saying
      // so, a blocked user can buy the Pass and only then find out — which
      // is a refund and a one-star review.
      final c = paywallCopyFor('palm_limit', isFreeUser: true)!;
      final s = c.subline.toLowerCase();
      expect(s, contains('starter pass'));
      expect(s, anyOf(contains('not include'), contains('does not')));
    });

    test('compat and mulank say what is already free', () {
      // Both surfaces give something away before asking for money, and the
      // copy should lead with that rather than with the lock.
      expect(paywallCopyFor('compat', isFreeUser: true)!.subline.toLowerCase(),
        contains('yours to keep'));
      expect(paywallCopyFor('mulank', isFreeUser: true)!.subline.toLowerCase(),
        contains('free'));
    });
  });

  group('copy fits the header', () {
    test('headlines stay short enough for one line at 22px', () {
      for (final t in blocked) {
        expect(paywallCopyFor(t, isFreeUser: true)!.headline.length,
          lessThanOrEqualTo(32),
          reason: '$t headline will wrap or ellipsise');
      }
    });

    test('sublines stay within about three lines', () {
      for (final t in blocked) {
        expect(paywallCopyFor(t, isFreeUser: true)!.subline.length,
          lessThanOrEqualTo(180),
          reason: '$t subline pushes the plan cards off screen');
      }
    });
  });
}
