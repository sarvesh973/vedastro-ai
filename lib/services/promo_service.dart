import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';

import '../models/subscription_plan.dart';
import '../screens/paywall_screen.dart';
import '../widgets/promo_offer_sheet.dart';
import 'analytics_service.dart';
import 'auth_service.dart';
import 'storage_service.dart';

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

  /// At most once a week.
  static const minGap = Duration(days: 7);

  /// Stop asking after this many dismissals. Someone who has closed it
  /// twice has answered; continuing to ask is how an app earns one-star
  /// reviews, and at 4.1 stars that costs more than the conversion.
  static const maxDismissals = 2;

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
  /// Never on a first run: someone who has not had a reading yet has no
  /// idea what they would be buying, and a price is a poor first
  /// impression. Never to someone already paying, for the obvious reason.
  static bool shouldShowOnAppOpen() {
    if (!enabledOnAppOpen || !kPassIntroPricingLive) return false;
    if (StorageService.isPremium) return false;
    if (AuthService.isAdmin) return false;
    // Has the user actually used the app yet?
    if (StorageService.chatQuestionsUsed == 0 &&
        !StorageService.hasProfile) {
      return false;
    }
    if (dismissCount >= maxDismissals) return false;

    final last = lastShownMs;
    if (last != 0 &&
        DateTime.now().millisecondsSinceEpoch - last < minGap.inMilliseconds) {
      return false;
    }
    return true;
  }

  static int get lastShownMs =>
      StorageService.prefs?.getInt(_keyLastShown) ?? 0;

  static int get dismissCount =>
      StorageService.prefs?.getInt(_keyDismissCount) ?? 0;

  static Future<void> markShown() async {
    await StorageService.prefs
        ?.setInt(_keyLastShown, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> markDismissed() async {
    await StorageService.prefs?.setInt(_keyDismissCount, dismissCount + 1);
  }

  /// Clears the frequency state. Admin-only, for testing the real flow on
  /// a device without waiting a week or reinstalling.
  static Future<void> resetForTesting() async {
    await StorageService.prefs?.remove(_keyLastShown);
    await StorageService.prefs?.remove(_keyDismissCount);
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
