import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';

import '../models/subscription_plan.dart';
import '../screens/paywall_screen.dart';
import '../widgets/promo_offer_sheet.dart';
import 'analytics_service.dart';
import 'auth_service.dart';
import 'promo_config.dart';
import 'storage_service.dart';

/// The part of the day an impression belongs to.
///
/// One impression per slot per day, so the three are naturally spread
/// instead of all landing in whichever session the user happens to have.
enum PromoSlot { morning, afternoon, night }

/// Decides whether the launch promo shows, and which creative.
class PromoService {
  /// Master switch for showing the promo on app open.
  ///
  /// ON, but inert: the check below ALSO requires [kPassIntroPricingLive],
  /// which is still false. Both creatives show "₹99" struck through, so
  /// until the ₹99 standing rate is live in Razorpay that image
  /// advertises a saving that does not exist — and no amount of enabling
  /// here may put a false price in front of a user.
  ///
  /// So the remaining switch is tied to a real external dependency rather
  /// than to anyone's memory: configure the Razorpay plan and offer, flip
  /// kPassIntroPricingLive, and the promo starts. Set this to false to
  /// stop the campaign without touching pricing.
  static const bool enabledOnAppOpen = true;

  static const _keyLastShown = 'promo_last_shown_ms';
  static const _keyDismissCount = 'promo_dismiss_count';
  static const _keyShownDay = 'promo_shown_day';
  static const _keyShownToday = 'promo_shown_today';
  static const _keyPausedUntil = 'promo_paused_until_ms';

  /// Three impressions a day, one per part of the day.
  ///
  /// Slots rather than a counter plus a minimum gap, because a counter
  /// cannot express "spread them out" — it only knows how many have gone.
  /// A plain count of 3 a day lets all three land in one evening, and a
  /// count plus a gap leaks across midnight: shown at 16:00 and 20:00,
  /// the calendar day rolls at 00:00 and the gap has already elapsed, so
  /// a third fires at 00:05. Eight hours, three impressions. Binding each
  /// impression to a window closes that by construction.
  ///
  /// Whichever window the user opens the app in, they get that window's
  /// impression — once. Open at 07:00 and again at 09:00 and only the
  /// first shows; come back at 14:00 and the afternoon one does.
  static const slotHours = <PromoSlot, (int, int)>{
    PromoSlot.morning: (5, 12),    // 05:00–11:59
    PromoSlot.afternoon: (12, 18), // 12:00–17:59
    PromoSlot.night: (18, 5),      // 18:00–04:59, wrapping past midnight
  };

  /// Dismissals before the promo pauses.
  static const maxDismissals = 4;

  /// How long it rests after [maxDismissals], before resuming with a
  /// clean counter.
  ///
  /// This is the release valve on a deliberately frequent campaign. At
  /// three a day the cap is reached inside two days, so the shape over a
  /// fortnight is: ~1.5 days of asking, 7 days of silence, then the same
  /// again. Someone who never engages sees it about eight times in two
  /// weeks rather than forty-two.
  static const pauseAfterDismissals = Duration(days: 7);

  /// Which creative this user sees — STABLE for a given account.
  ///
  /// Assigning per impression would let one person see A then B, and a
  /// purchase could not be attributed to either; the test would produce
  /// numbers that look fine and mean nothing. Hashing the uid gives a
  /// stable ~50/50 split with no server state and survives reinstalls,
  /// because the uid does.
  /// Stable hash of a uid. FNV-1a: tiny, well-distributed on short
  /// strings, and deterministic across platforms — unlike
  /// String.hashCode, which Dart does not guarantee to be stable between
  /// runs or versions.
  @visibleForTesting
  static int hashUid(String uid) {
    var hash = 0x811c9dc5;
    for (final unit in uid.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Picks a creative from the server's list, WEIGHTED.
  ///
  /// Weighted rather than a plain modulo, because weight is how a losing
  /// variant is retired and how a split is rebalanced without a release.
  /// A zero-weight creative is never selected.
  ///
  /// Still keyed on the uid, so assignment is stable for a given account:
  /// picking per impression would let one person see both and no purchase
  /// could be attributed to either.
  ///
  /// Note the split moves if the weights change mid-campaign, which is
  /// the point — but it does mean a rebalance reassigns some users, so it
  /// invalidates comparisons that straddle the change.
  @visibleForTesting
  static RemoteCreative creativeFor(String? uid, List<RemoteCreative> all) {
    final usable = all.where((v) => v.weight > 0).toList();
    if (usable.isEmpty) {
      return all.isNotEmpty ? all.first : PromoConfig.defaults.variants.first;
    }
    final total = usable.fold<int>(0, (a, v) => a + v.weight);
    final point = (uid == null || uid.isEmpty) ? 0 : hashUid(uid) % total;
    var running = 0;
    for (final v in usable) {
      running += v.weight;
      if (point < running) return v;
    }
    return usable.last;
  }

  static RemoteCreative get creative => creativeFor(
      AuthService.currentUser?.uid, PromoConfig.current.variants);

  /// Whether to show the promo on this launch.
  ///
  /// Order matters: the permanent exclusions are checked before anything
  /// that mutates state, so a paying user can never trip the pause timer
  /// or burn a daily slot.
  ///
  /// [now] is injectable so the rules can be tested across days and the
  /// pause window without waiting.
  static bool shouldShowOnAppOpen({DateTime? now}) {
    final t = now ?? DateTime.now();

    // Campaign policy comes from the server now — see PromoConfig. The
    // local switch remains as a build-level override so the feature can
    // be disabled without touching remote state.
    if (!enabledOnAppOpen) return false;
    final config = PromoConfig.current;
    if (!config.live) return false;

    // Took the offer. Never ask again — nothing is more annoying than
    // being sold something you have already bought, and it reads as the
    // app not knowing who you are.
    if (StorageService.isPremium) return false;

    if (AuthService.isAdmin) return false;

    // No profile means onboarding is unfinished, so there is no chart and
    // nothing the Pass would unlock yet. This is targeting, not
    // frequency: a price shown before the product works is wasted.
    if (!StorageService.hasProfile) return false;

    // Resting after too many dismissals.
    final pausedUntil = pausedUntilMs;
    if (pausedUntil != 0) {
      if (t.millisecondsSinceEpoch < pausedUntil) return false;
      // Pause elapsed — resume with a clean slate. Deliberately not done
      // here, because shouldShow must stay side-effect free; markShown
      // clears it on the next real impression.
    }

    if (dismissCount >= config.maxDismissals) return false;

    // This window's impression already used.
    if (slotUsed(t)) return false;

    return true;
  }

  /// Which part of the day [t] falls in.
  static PromoSlot slotFor(DateTime t) {
    final h = t.hour;
    if (h >= 5 && h < 12) return PromoSlot.morning;
    if (h >= 12 && h < 18) return PromoSlot.afternoon;
    return PromoSlot.night;
  }

  /// The day a slot belongs to.
  ///
  /// Anything before 05:00 counts as the PREVIOUS day's night. Someone
  /// using the app at 00:30 is finishing their evening, not starting a
  /// new day — and attributing it correctly is what stops the night slot
  /// being handed out twice either side of midnight.
  static String slotDayKey(DateTime t) =>
      _dayKey(t.hour < 5 ? t.subtract(const Duration(days: 1)) : t);

  /// Whether [t]'s window has already been used.
  static bool slotUsed(DateTime t) {
    final p = StorageService.prefs;
    if (p?.getString(_keyShownDay) != slotDayKey(t)) return false;
    final mask = p?.getInt(_keyShownToday) ?? 0;
    return mask & _bit(slotFor(t)) != 0;
  }

  /// How many of today's three windows have been used.
  static int slotsUsedOn(DateTime t) {
    final p = StorageService.prefs;
    if (p?.getString(_keyShownDay) != slotDayKey(t)) return 0;
    final mask = p?.getInt(_keyShownToday) ?? 0;
    return PromoSlot.values.where((s) => mask & _bit(s) != 0).length;
  }

  static int _bit(PromoSlot s) => 1 << s.index;

  static String _dayKey(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  static int get pausedUntilMs =>
      StorageService.prefs?.getInt(_keyPausedUntil) ?? 0;

  static int get lastShownMs =>
      StorageService.prefs?.getInt(_keyLastShown) ?? 0;

  static int get dismissCount =>
      StorageService.prefs?.getInt(_keyDismissCount) ?? 0;

  static Future<void> markShown({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final p = StorageService.prefs;
    if (p == null) return;

    // A pause that has elapsed clears here rather than in shouldShow, so
    // the predicate stays free of side effects and can be called as often
    // as the launch path likes.
    if (pausedUntilMs != 0 && t.millisecondsSinceEpoch >= pausedUntilMs) {
      await p.remove(_keyPausedUntil);
      await p.setInt(_keyDismissCount, 0);
    }

    // Read the mask BEFORE moving the day key, or a new day would be
    // written with the old day's bits still set.
    final existing =
        p.getString(_keyShownDay) == slotDayKey(t) ? (p.getInt(_keyShownToday) ?? 0) : 0;

    await p.setInt(_keyLastShown, t.millisecondsSinceEpoch);
    await p.setInt(_keyShownToday, existing | _bit(slotFor(t)));
    await p.setString(_keyShownDay, slotDayKey(t));
  }

  static Future<void> markDismissed({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final p = StorageService.prefs;
    if (p == null) return;

    final config = PromoConfig.current;
    final count = dismissCount + 1;
    await p.setInt(_keyDismissCount, count);

    // Hitting the cap starts the rest period rather than stopping for
    // good. The campaign is seasonal and the user may simply have been
    // busy the first few times. Both numbers are server-controlled.
    if (count >= config.maxDismissals) {
      await p.setInt(
        _keyPausedUntil,
        t.add(Duration(days: config.pauseDays)).millisecondsSinceEpoch,
      );
    }
  }

  /// Clears the frequency state. Admin-only, for testing the real flow on
  /// a device without waiting a week or reinstalling.
  static Future<void> resetForTesting() async {
    final p = StorageService.prefs;
    await p?.remove(_keyLastShown);
    await p?.remove(_keyDismissCount);
    await p?.remove(_keyShownDay);
    await p?.remove(_keyShownToday);
    await p?.remove(_keyPausedUntil);
  }

  /// Why the promo would or would not show right now, in plain words.
  ///
  /// Admins are excluded from the real app-open path so their launches
  /// cannot skew a variant that has only just started collecting, which
  /// leaves nobody able to confirm the trigger actually works. This runs
  /// the real predicate and reports the FIRST reason it said no, so the
  /// launch path can be verified without a second account and without
  /// touching the funnel.
  static String appOpenDiagnosis({DateTime? now}) {
    final t = now ?? DateTime.now();
    if (!enabledOnAppOpen) return 'off: enabledOnAppOpen is false (build)';
    final config = PromoConfig.current;
    if (config.expired) return 'off: campaign end date has passed (server)';
    if (!config.enabled) return 'off: enabled=false in app_config/promo';
    if (!config.pricingIntroLive) {
      return 'off: pricingIntroLive=false in app_config/promo';
    }
    if (!kPassIntroPricingLive) {
      return 'off: kPassIntroPricingLive is false — the ₹99 plan is not '
          'live in Razorpay, so the struck-through price would be untrue';
    }
    if (StorageService.isPremium) return 'skipped: already subscribed';
    if (AuthService.isAdmin) {
      return 'skipped: admins are excluded from the real path';
    }
    if (!StorageService.hasProfile) return 'skipped: no birth profile yet';
    if (pausedUntilMs > t.millisecondsSinceEpoch) {
      final until = DateTime.fromMillisecondsSinceEpoch(pausedUntilMs);
      return 'paused after ${config.maxDismissals} dismissals until '
          '${until.day}/${until.month}';
    }
    if (dismissCount >= config.maxDismissals) {
      return 'paused: dismissal cap reached';
    }
    if (slotUsed(t)) {
      return 'already shown in the ${slotFor(t).name} slot today';
    }
    return 'WOULD SHOW now (${slotFor(t).name} slot, '
        'variant ${creative.id.toUpperCase()})';
  }

  /// Shows the sheet, records the outcome, and opens the paywall if taken.
  ///
  /// The analytics live here rather than inside the widget so the admin
  /// preview can render the sheet without polluting the funnel — a
  /// handful of admin opens is enough to move the numbers on a variant
  /// that has only just started collecting.
  ///
  /// Accepting routes to the paywall rather than straight to Razorpay.
  /// The whole creative is tappable, so a stray tap must cost nothing.
  static Future<void> present(
    BuildContext context, {
    RemoteCreative? forced,
    bool debugOverlay = false,
    bool track = true,
  }) async {
    final c = forced ?? creative;
    if (track) {
      Analytics.promoShown(trigger: c.trigger);
      await markShown();
    }
    final started = DateTime.now();

    final accepted = await PromoOfferSheet.show(
      context,
      c,
      debugOverlay: debugOverlay,
    );
    if (!context.mounted) return;

    if (accepted == true) {
      if (track) Analytics.promoAccepted(trigger: c.trigger);
      // PaywallScreen fires paywall_viewed itself, so the next stage of
      // the funnel is recorded there rather than here.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaywallScreen(
            trigger: c.trigger,
            availablePlans: SubscriptionPlan.free.upgradeOptions,
          ),
        ),
      );
      return;
    }

    if (track) {
      await markDismissed();
      Analytics.promoDismissed(
        trigger: c.trigger,
        secondsViewed: DateTime.now().difference(started).inSeconds,
      );
    }
  }
}
