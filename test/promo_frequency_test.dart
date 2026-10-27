import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vedastro_ai/models/subscription_plan.dart';
import 'package:vedastro_ai/services/promo_service.dart';
import 'package:vedastro_ai/services/storage_service.dart';

/// The frequency policy is pure calendar logic, which is exactly where
/// off-by-one errors live — and both failure modes are user-visible in the
/// worst way. Too loose and a 4.1-star app shows a sales screen three
/// times in an evening; too tight and a campaign that was paid for never
/// reaches anyone.
///
/// The rules under test:
///   - one impression per part of the day: morning, afternoon, night
///   - the night slot runs 18:00–04:59 and belongs to the day it STARTED
///   - 4 dismissals starts a 7-day pause, then the counter resets
///   - a paying user never sees it
///   - no profile means no promo
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    await PromoService.resetForTesting();
  });

  Future<void> show(DateTime t) => PromoService.markShown(now: t);
  Future<void> dismiss(DateTime t) => PromoService.markDismissed(now: t);

  group('slot boundaries', () {
    test('each hour maps to the right part of the day', () {
      PromoSlot at(int h) => PromoService.slotFor(DateTime(2026, 11, 8, h));
      expect(at(5), PromoSlot.morning);
      expect(at(11), PromoSlot.morning);
      expect(at(12), PromoSlot.afternoon);
      expect(at(17), PromoSlot.afternoon);
      expect(at(18), PromoSlot.night);
      expect(at(23), PromoSlot.night);
      // Small hours are the tail of the night, not a new morning.
      expect(at(0), PromoSlot.night);
      expect(at(4), PromoSlot.night);
    });

    test('pre-dawn hours belong to the previous day', () {
      // 00:30 on the 9th is the night that began on the 8th. Getting this
      // wrong is what let a third impression through at midnight.
      expect(PromoService.slotDayKey(DateTime(2026, 11, 9, 0, 30)),
          PromoService.slotDayKey(DateTime(2026, 11, 8, 20, 0)));
      expect(PromoService.slotDayKey(DateTime(2026, 11, 9, 5, 0)),
          isNot(PromoService.slotDayKey(DateTime(2026, 11, 8, 20, 0))));
    });
  });

  group('one per slot', () {
    test('a used slot does not come round again the same day', () async {
      final morning = DateTime(2026, 11, 8, 7, 0);
      expect(PromoService.slotUsed(morning), isFalse);
      await show(morning);
      expect(PromoService.slotUsed(morning), isTrue);
      // Opening again two hours later is still the morning slot.
      expect(
          PromoService.slotUsed(DateTime(2026, 11, 8, 9, 30)), isTrue);
    });

    test('the other slots stay available', () async {
      await show(DateTime(2026, 11, 8, 7, 0));
      expect(PromoService.slotUsed(DateTime(2026, 11, 8, 14, 0)), isFalse);
      expect(PromoService.slotUsed(DateTime(2026, 11, 8, 20, 0)), isFalse);
    });

    test('all three can be used across one day', () async {
      final d = DateTime(2026, 11, 8);
      await show(d.add(const Duration(hours: 7)));
      await show(d.add(const Duration(hours: 14)));
      await show(d.add(const Duration(hours: 20)));
      expect(PromoService.slotsUsedOn(d.add(const Duration(hours: 20))), 3);
    });

    test('a new day returns a clean set of slots', () async {
      await show(DateTime(2026, 11, 8, 7, 0));
      await show(DateTime(2026, 11, 8, 14, 0));
      final nextMorning = DateTime(2026, 11, 9, 7, 0);
      expect(PromoService.slotsUsedOn(nextMorning), 0);
      expect(PromoService.slotUsed(nextMorning), isFalse);
    });
  });

  group('the midnight leak is closed', () {
    test('16:00, 20:00 then 00:05 does NOT yield a third impression',
        () async {
      // The previous count-plus-gap policy allowed exactly this: the
      // calendar day rolled at midnight and the 4h gap had elapsed, so a
      // third fired at 00:05 — three impressions in eight hours.
      await show(DateTime(2026, 11, 8, 16, 0)); // afternoon
      await show(DateTime(2026, 11, 8, 20, 0)); // night
      final justAfterMidnight = DateTime(2026, 11, 9, 0, 5);
      expect(PromoService.slotUsed(justAfterMidnight), isTrue,
          reason: '00:05 is still the night slot that began on the 8th');
    });

    test('but the next real morning is available', () async {
      await show(DateTime(2026, 11, 8, 20, 0));
      expect(PromoService.slotUsed(DateTime(2026, 11, 9, 6, 0)), isFalse);
    });
  });

  group('dismissals and the pause', () {
    test('four dismissals start a seven-day rest', () async {
      var t = DateTime(2026, 11, 8, 7, 0);
      for (var i = 0; i < 3; i++) {
        await dismiss(t);
        t = t.add(const Duration(hours: 6));
        expect(PromoService.pausedUntilMs, 0);
      }
      await dismiss(t);
      expect(PromoService.dismissCount, 4);
      final resumesAt =
          DateTime.fromMillisecondsSinceEpoch(PromoService.pausedUntilMs);
      expect(resumesAt.difference(t).inDays, 7);
    });

    test('the pause clears and the counter resets on the next impression',
        () async {
      var t = DateTime(2026, 11, 8, 7, 0);
      for (var i = 0; i < 4; i++) {
        await dismiss(t);
        t = t.add(const Duration(hours: 6));
      }
      await show(DateTime(2026, 11, 16, 7, 0));
      expect(PromoService.pausedUntilMs, 0);
      expect(PromoService.dismissCount, 0,
          reason: 'resuming starts a clean count, not a 5th strike');
    });

    test('an unelapsed pause is left alone', () async {
      var t = DateTime(2026, 11, 8, 7, 0);
      for (var i = 0; i < 4; i++) {
        await dismiss(t);
        t = t.add(const Duration(hours: 6));
      }
      final paused = PromoService.pausedUntilMs;
      await show(DateTime(2026, 11, 10, 7, 0));
      expect(PromoService.pausedUntilMs, paused);
      expect(PromoService.dismissCount, 4);
    });
  });

  group('shouldShowOnAppOpen', () {
    final t = DateTime(2026, 11, 8, 7, 0);

    test('stays off while the pricing flag is false, even when enabled', () {
      // The campaign switch is ON; the pricing switch is not. Both
      // creatives show ₹99 struck through, so enabling the promo must not
      // be enough on its own to put a saving in front of a user that the
      // billing system is not applying. This asserts the AND, not either
      // flag's value — flipping one is meant to be survivable.
      expect(PromoService.enabledOnAppOpen, isTrue);
      expect(kPassIntroPricingLive, isFalse);
      expect(PromoService.shouldShowOnAppOpen(now: t), isFalse);
    });

    test('the diagnosis names the pricing flag as the blocker', () {
      // The admin-facing explanation has to stay truthful about WHY, or
      // it is worse than no diagnostic at all.
      expect(PromoService.appOpenDiagnosis(now: t),
          contains('kPassIntroPricingLive'));
    });

    test('a paying user is excluded before any state is touched', () async {
      await StorageService.upgradeToPremium();
      expect(PromoService.shouldShowOnAppOpen(now: t), isFalse);
      expect(PromoService.slotsUsedOn(t), 0);
      expect(PromoService.pausedUntilMs, 0);
    });

    test('the predicate has no side effects', () {
      for (var i = 0; i < 5; i++) {
        PromoService.shouldShowOnAppOpen(now: t);
      }
      expect(PromoService.slotsUsedOn(t), 0);
      expect(PromoService.dismissCount, 0);
      expect(PromoService.lastShownMs, 0);
    });
  });

  group('constants match the agreed policy', () {
    test('three slots, four dismissals, seven-day rest', () {
      expect(PromoSlot.values.length, 3);
      expect(PromoService.maxDismissals, 4);
      expect(PromoService.pauseAfterDismissals, const Duration(days: 7));
    });

    test('the slots tile the whole 24 hours with no gap or overlap', () {
      // Every hour must belong to exactly one slot, or a user opening the
      // app at that hour either gets nothing or gets double-counted.
      final seen = <int, PromoSlot>{};
      for (var h = 0; h < 24; h++) {
        seen[h] = PromoService.slotFor(DateTime(2026, 11, 8, h));
      }
      expect(seen.length, 24);
      expect(seen.values.toSet(), PromoSlot.values.toSet());
    });
  });
}
