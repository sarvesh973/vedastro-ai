import 'package:flutter_test/flutter_test.dart';
import 'package:vedastro_ai/models/subscription_plan.dart';

/// Pins the shape of the pricing ladder.
///
/// The Pass bills weekly and everything else bills monthly, so the prices
/// on the paywall cards are not directly comparable and a broken rung is
/// invisible by inspection. These tests normalise both sides to a month
/// and state the real numbers, so a price change has to confront them.
void main() {
  int rupees(int paise) => paise ~/ 100;

  group('monthly equivalents', () {
    test('weekly plans are normalised, monthly ones are not', () {
      expect(SubscriptionPlan.pass.isWeekly, isTrue);
      expect(SubscriptionPlan.trial.isWeekly, isFalse);
      // 52/12 weeks a month, not 4.
      expect(rupees(SubscriptionPlan.pass.monthlyEquivalentPaise),
          kPassIntroPricingLive ? 429 : 212);
      expect(rupees(SubscriptionPlan.trial.monthlyEquivalentPaise), 199);
      expect(rupees(SubscriptionPlan.standard.monthlyEquivalentPaise), 499);
      expect(rupees(SubscriptionPlan.premium.monthlyEquivalentPaise), 999);
    });

    test('chat allowances normalise too', () {
      expect(SubscriptionPlan.pass.monthlyEquivalentChats, 91);
      expect(SubscriptionPlan.trial.monthlyEquivalentChats, 50);
      expect(SubscriptionPlan.premium.monthlyEquivalentChats, -1);
    });
  });

  group('the Pass / Standard rung', () {
    test('documents which way the rung currently points', () {
      final pass = SubscriptionPlan.pass.monthlyEquivalentPaise;
      final standard = SubscriptionPlan.trial.monthlyEquivalentPaise;

      if (kPassIntroPricingLive) {
        // ₹99/week ≈ ₹429 — correctly above Standard's ₹199, so moving
        // from Pass to a monthly tier is a real decision rather than a
        // strictly worse deal.
        expect(pass, greaterThan(standard));
      } else {
        // ₹49/week ≈ ₹212 against ₹199 for 45% fewer chats. This is the
        // inversion raising the Pass to ₹99 exists to fix; asserting it
        // keeps the fact in front of whoever changes the prices next.
        expect(pass, greaterThan(standard));
        expect(SubscriptionPlan.pass.monthlyEquivalentChats,
            greaterThan(SubscriptionPlan.trial.monthlyEquivalentChats));
      }
    });
  });

  group('upgrade options', () {
    test('never offer a cheaper plan as an upgrade', () {
      // Compared on monthly equivalents, not on the headline price. On the
      // headline the Pass is ₹49 and everything looks like an upgrade.
      for (final plan in SubscriptionPlan.values) {
        for (final option in plan.upgradeOptions) {
          expect(
            option.monthlyEquivalentPaise,
            greaterThan(plan.monthlyEquivalentPaise),
            reason: '${plan.displayName} '
                '(₹${rupees(plan.monthlyEquivalentPaise)}/mo) is offered '
                '${option.displayName} '
                '(₹${rupees(option.monthlyEquivalentPaise)}/mo) as an upgrade',
          );
        }
      }
    });
  });
}
