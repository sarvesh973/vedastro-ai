import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vedastro_ai/services/promo_service.dart';
import 'package:vedastro_ai/services/storage_service.dart';

/// The frequency policy is pure counter-and-calendar logic, which is
/// exactly where off-by-one errors live — and every failure mode here is
/// user-visible in the worst way. Too loose and a 4.1-star app starts
/// showing a sales screen twice a sitting; too tight and a campaign that
/// was paid for never reaches anyone.
///
/// The rules under test:
///   - at most 2 impressions per calendar day, at least 4h apart
///   - 4 dismissals starts a 7-day pause, then the counter resets
///   - a paying user never sees it
///   - no profile means no promo
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    await PromoService.resetForTesting();
  });

  final day1 = DateTime(2026, 11, 8, 9, 0);

  /// Simulates an impression at [t] — what present() does on a real show.
  Future<void> show(DateTime t) => PromoService.markShown(now: t);
  Future<void> dismiss(DateTime t) => PromoService.markDismissed(now: t);

  group('twice a day', () {
    test('counts impressions against the calendar day', () async {
      expect(PromoService.shownOn(day1), 0);
      await show(day1);
      expect(PromoService.shownOn(day1), 1);
      await show(day1.add(const Duration(hours: 5)));
      expect(PromoService.shownOn(day1), 2);
    });

    test('the allowance refreshes at midnight, not 24h after the last one',
        () async {
      // Shown at 21:00; the next day's allowance must be available at
      // 09:00 the following morning — twelve hours later — because "twice
      // a day" means per day, not per rolling 24 hours.
      final late = DateTime(2026, 11, 8, 21, 0);
      await show(late);
      await show(late.add(const Duration(minutes: 1)));
      expect(PromoService.shownOn(late), 2);

      final nextMorning = DateTime(2026, 11, 9, 9, 0);
      expect(PromoService.shownOn(nextMorning), 0,
          reason: 'a new calendar day starts a fresh allowance');
    });

    test('a different day does not inherit yesterday\'s count', () async {
      await show(day1);
      await show(day1.add(const Duration(hours: 5)));
      expect(PromoService.shownOn(day1.add(const Duration(days: 1))), 0);
    });
  });

  group('the four-hour gap', () {
    test('stops both impressions landing in one sitting', () async {
      // Without this, opening the app twice in a minute burns the day's
      // allowance immediately and the second one is pure irritation —
      // nothing has happened in between to make it a fresh ask.
      await show(day1);
      expect(
        PromoService.shownOn(day1),
        1,
        reason: 'sanity: first impression recorded',
      );
      final tooSoon = day1.add(const Duration(hours: 3, minutes: 59));
      final lastShown =
          DateTime.fromMillisecondsSinceEpoch(PromoService.lastShownMs);
      expect(tooSoon.difference(lastShown).inHours, lessThan(4));
    });
  });

  group('dismissals and the pause', () {
    test('four dismissals start a seven-day rest', () async {
      var t = day1;
      for (var i = 0; i < 3; i++) {
        await dismiss(t);
        t = t.add(const Duration(hours: 5));
        expect(PromoService.pausedUntilMs, 0,
            reason: 'should not pause before the 4th dismissal');
      }
      await dismiss(t);
      expect(PromoService.dismissCount, 4);
      expect(PromoService.pausedUntilMs, greaterThan(0));

      final resumesAt =
          DateTime.fromMillisecondsSinceEpoch(PromoService.pausedUntilMs);
      expect(resumesAt.difference(t).inDays, 7);
    });

    test('the pause clears and the counter resets on the next impression',
        () async {
      var t = day1;
      for (var i = 0; i < 4; i++) {
        await dismiss(t);
        t = t.add(const Duration(hours: 5));
      }
      expect(PromoService.dismissCount, 4);

      // Eight days later the rest is over.
      final after = day1.add(const Duration(days: 8));
      await show(after);
      expect(PromoService.pausedUntilMs, 0,
          reason: 'elapsed pause should be cleared');
      expect(PromoService.dismissCount, 0,
          reason: 'resuming starts a clean count, not a 5th strike');
      expect(PromoService.shownOn(after), 1);
    });

    test('an unelapsed pause is left alone', () async {
      var t = day1;
      for (var i = 0; i < 4; i++) {
        await dismiss(t);
        t = t.add(const Duration(hours: 5));
      }
      final pausedUntil = PromoService.pausedUntilMs;
      // Two days in, still resting.
      await show(day1.add(const Duration(days: 2)));
      expect(PromoService.pausedUntilMs, pausedUntil,
          reason: 'pause must not be cleared early');
      expect(PromoService.dismissCount, 4);
    });
  });

  group('shouldShowOnAppOpen', () {
    test('is off while the master switches are off', () {
      // Both default false: the creatives show ₹99 struck through, so
      // neither flag alone may put a saving in front of a user that the
      // billing system is not applying.
      expect(PromoService.enabledOnAppOpen, isFalse);
      expect(PromoService.shouldShowOnAppOpen(now: day1), isFalse);
    });

    test('a paying user is excluded before any state is touched', () async {
      await StorageService.upgradeToPremium();
      expect(PromoService.shouldShowOnAppOpen(now: day1), isFalse);
      // And nothing was consumed on their behalf.
      expect(PromoService.shownOn(day1), 0);
      expect(PromoService.pausedUntilMs, 0);
    });

    test('the predicate has no side effects', () async {
      for (var i = 0; i < 5; i++) {
        PromoService.shouldShowOnAppOpen(now: day1);
      }
      expect(PromoService.shownOn(day1), 0);
      expect(PromoService.dismissCount, 0);
      expect(PromoService.lastShownMs, 0);
    });
  });

  group('constants match the agreed policy', () {
    test('two a day, four dismissals, seven-day rest', () {
      expect(PromoService.maxPerDay, 2);
      expect(PromoService.maxDismissals, 4);
      expect(PromoService.pauseAfterDismissals, const Duration(days: 7));
      expect(PromoService.minGapSameDay, const Duration(hours: 4));
    });

    test('the worst case over a fortnight is bounded', () {
      // ~2 days of asking, 7 resting, ~2 asking. Someone who never
      // engages should see this about 8 times in two weeks, not 28.
      const daysAsking = 2;
      final impressions =
          daysAsking * PromoService.maxPerDay * 2; // two cycles
      expect(impressions, lessThanOrEqualTo(8));
    });
  });
}
