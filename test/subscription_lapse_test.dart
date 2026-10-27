import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vedastro_ai/models/subscription_plan.dart';
import 'package:vedastro_ai/models/subscription_status.dart';
import 'package:vedastro_ai/services/storage_service.dart';

/// Guards the rule that makes revoking premium safe:
///
///   only a status that was actually READ may take access away.
///
/// loadCurrentSubscription returns a free-looking status for three
/// different reasons — no subscription, no signed-in uid, and a thrown
/// read (offline, permission error, Firestore hiccup). For GRANTING
/// access that ambiguity is harmless, since all three mean "do not
/// unlock". For REVOKING it, it is the difference between correctly
/// downgrading a lapsed user and stripping premium from someone who paid
/// five minutes ago because their train went through a tunnel.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
  });

  group('resolved marks which statuses may be acted on', () {
    test('the fallback free status is NOT resolved', () {
      // This is the value returned on a caught exception. If it were
      // resolved, every offline launch would downgrade a paying user.
      expect(SubscriptionStatus.free.resolved, isFalse);
      expect(SubscriptionStatus.free.isActive, isFalse);
    });

    test('confirmedFree IS resolved', () {
      // Returned when the document was read and genuinely absent.
      expect(SubscriptionStatus.confirmedFree.resolved, isTrue);
      expect(SubscriptionStatus.confirmedFree.isActive, isFalse);
    });

    test('the two are otherwise identical', () {
      // Same plan and state — resolved is the ONLY difference, so nothing
      // else in the app can accidentally behave differently between them.
      expect(SubscriptionStatus.free.plan,
          SubscriptionStatus.confirmedFree.plan);
      expect(SubscriptionStatus.free.state,
          SubscriptionStatus.confirmedFree.state);
    });

    test('anything parsed from a document is resolved by default', () {
      final s = SubscriptionStatus.fromJson({
        'plan': 'standard',
        'state': 'active',
      });
      expect(s.resolved, isTrue,
          reason: 'it came from a document we actually read');
    });

    test('an explicitly unresolved parse stays unresolved', () {
      final s = SubscriptionStatus.fromJson(
        {'plan': 'standard', 'state': 'active'},
        resolved: false,
      );
      expect(s.resolved, isFalse);
    });
  });

  group('the downgrade decision', () {
    /// Mirrors the guard in main.dart's _syncCloudData.
    bool shouldDowngrade(SubscriptionStatus s,
            {required bool isPremium, required bool isAdmin}) =>
        !s.isActive && s.resolved && isPremium && !isAdmin;

    test('downgrades a stale flag when the cloud confirms no subscription',
        () {
      expect(
        shouldDowngrade(SubscriptionStatus.confirmedFree,
            isPremium: true, isAdmin: false),
        isTrue,
      );
    });

    test('NEVER downgrades on an unreadable subscription', () {
      // The case this whole mechanism exists for.
      expect(
        shouldDowngrade(SubscriptionStatus.free,
            isPremium: true, isAdmin: false),
        isFalse,
      );
    });

    test('never downgrades an active subscriber', () {
      final active = SubscriptionStatus.fromJson({
        'plan': 'standard',
        'state': 'active',
      });
      expect(active.isActive, isTrue);
      expect(shouldDowngrade(active, isPremium: true, isAdmin: false),
          isFalse);
    });

    test('never downgrades an admin', () {
      // Admins are granted premium at launch and have no subscription
      // document, so without this guard they would be downgraded on
      // every single launch.
      expect(
        shouldDowngrade(SubscriptionStatus.confirmedFree,
            isPremium: true, isAdmin: true),
        isFalse,
      );
    });

    test('does nothing when the flag is already false', () {
      expect(
        shouldDowngrade(SubscriptionStatus.confirmedFree,
            isPremium: false, isAdmin: false),
        isFalse,
      );
    });
  });

  group('a lapsed one-time Pass', () {
    test('is inactive once it expires, and resolved', () {
      final expired = SubscriptionStatus.fromJson({
        'plan': 'trial',
        'state': 'active',
        'isOneTime': true,
        'passExpiresAt': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      });
      expect(expired.isActive, isFalse,
          reason: 'day 8 of a 7-day pass');
      expect(expired.resolved, isTrue,
          reason: 'so it is safe to downgrade on');
    });

    test('is still active inside its window', () {
      final live = SubscriptionStatus.fromJson({
        'plan': 'trial',
        'state': 'active',
        'isOneTime': true,
        'passExpiresAt':
            DateTime.now().add(const Duration(days: 2)).toIso8601String(),
      });
      expect(live.isActive, isTrue);
    });
  });

  group('downgradeToFree', () {
    test('clears both the flag and the stale plan tag', () async {
      await StorageService.upgradeToPremium();
      await StorageService.setLastPurchasedPlan(SubscriptionPlan.pass.id);
      expect(StorageService.isPremium, isTrue);
      expect(StorageService.lastPurchasedPlan, isNotNull);

      await StorageService.downgradeToFree();

      expect(StorageService.isPremium, isFalse);
      // The plan tag drives the Settings label and the upgrade options,
      // so leaving it would keep showing a tier the user no longer has.
      expect(StorageService.lastPurchasedPlan, isNull);
    });

    test('is safe to call when already free', () async {
      await StorageService.downgradeToFree();
      expect(StorageService.isPremium, isFalse);
    });

    test('round-trips with upgrade', () async {
      await StorageService.upgradeToPremium();
      expect(StorageService.isPremium, isTrue);
      await StorageService.downgradeToFree();
      expect(StorageService.isPremium, isFalse);
      await StorageService.upgradeToPremium();
      expect(StorageService.isPremium, isTrue,
          reason: 'a win-back purchase must still work');
    });
  });
}
