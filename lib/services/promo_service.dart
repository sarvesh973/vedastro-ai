import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';

import '../models/subscription_plan.dart';
import '../screens/paywall_screen.dart';
import '../widgets/promo_offer_sheet.dart';
import 'analytics_service.dart';
import 'auth_service.dart';
import 'storage_service.dart';

/// The part of the day an impression belongs to.
///
/// One impression per slot per day, so the three are naturally spread
/// instead of all landing in whichever session the user happens to have.
enum PromoSlot { morning, afternoon, night }

/// One promotional creative in the A/B test.
///
/// The artwork carries ALL the copy — headline, price, CTA label, "Not
/// now" — so this holds only what the app needs to interact with it.
class PromoCreative {
  /// 'a' or 'b'. Rides into analytics as the trigger suffix.
  final String id;
  final String asset;

  /// Everything at or below this fraction of the image height dismisses;
  /// everything above it opens the paywall.
  ///
  /// Both creatives render a "Not now" under their button, and a visual
  /// "Not now" that starts a checkout is a dark pattern, a refund
  /// generator, and something Play treats as a policy issue. Measured from
  /// the pixels rather than guessed: variant A's button ends at 0.9225 of
  /// the image height and B's at 0.9220, so 0.93 clears both.
  final double dismissTopFraction;

  /// True puts the close X on the left. Variant A has its "शुभ दीपावली"
  /// pill in the top-right corner, so an X there would collide with it.
  final bool closeOnLeft;

  const PromoCreative({
    required this.id,
    required this.asset,
    this.dismissTopFraction = 0.93,
    this.closeOnLeft = false,
  });

  /// Analytics trigger, e.g. 'app_open_promo_a'.
  ///
  /// The variant is encoded in the trigger rather than sent as its own
  /// parameter on purpose: `trigger` is already registered as a GA4 custom
  /// dimension and already flows through paywall_viewed,
  /// paywall_dismissed, subscription_started and subscription_purchased.
  /// So the whole funnel splits by variant with no second dimension to
  /// register — which matters, because registration is not retroactive and
  /// the free tier allows only 50.
  String get trigger => 'app_open_promo_$id';

  static const a = PromoCreative(
    id: 'a',
    asset: 'assets/images/promo/diwali_a.webp',
    closeOnLeft: true,
  );

  static const b = PromoCreative(
    id: 'b',
    asset: 'assets/images/promo/diwali_b.webp',
  );

  static const all = [a, b];
}

/// Decides whether the launch promo shows, and which creative.
class PromoService {
  /// Master switch for showing the promo on app open. Default OFF.
  ///
  /// Also gated on [kPassIntroPricingLive] at the point of use: both
  /// creatives show "₹99" struck through, so until the ₹99 standing rate
  /// is live in Razorpay that image advertises a saving that does not
  /// exist. One flag cannot be flipped without the other being true.
  static const bool enabledOnAppOpen = false;

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
  @visibleForTesting
  static PromoCreative creativeForUid(String? uid) {
    if (uid == null || uid.isEmpty) return PromoCreative.a;
    // FNV-1a: tiny, well-distributed on short strings, and deterministic
    // across platforms — unlike String.hashCode, which Dart does not
    // guarantee to be stable between runs or versions.
    var hash = 0x811c9dc5;
    for (final unit in uid.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return PromoCreative.all[hash % PromoCreative.all.length];
  }

  static PromoCreative get creative =>
      creativeForUid(AuthService.currentUser?.uid);

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

    if (!enabledOnAppOpen || !kPassIntroPricingLive) return false;

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

    if (dismissCount >= maxDismissals) return false;

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

    final count = dismissCount + 1;
    await p.setInt(_keyDismissCount, count);

    // Hitting the cap starts the rest period rather than stopping for
    // good. The campaign is seasonal and the user may simply have been
    // busy the first four times.
    if (count >= maxDismissals) {
      await p.setInt(
        _keyPausedUntil,
        t.add(pauseAfterDismissals).millisecondsSinceEpoch,
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
    PromoCreative? forced,
    bool debugOverlay = false,
    bool track = true,
  }) async {
    final c = forced ?? creative;
    if (track) {
      Analytics.paywallViewed(trigger: c.trigger);
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
      Analytics.paywallDismissed(
        trigger: c.trigger,
        secondsViewed: DateTime.now().difference(started).inSeconds,
      );
    }
  }
}
