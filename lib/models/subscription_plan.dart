/// Subscription plans for VedAstro AI.
/// All pricing is in INR (paise).
///
/// Monetization model — a cheap WEEKLY front-door + three MONTHLY upsell
/// tiers (all recurring via Razorpay Subscriptions + autopay), cancellable
/// in one tap from Settings:
///  - FREE:      1 chat total (lifetime), 0 palm.
///  - PASS       ₹49/WEEK  — 21 chats/week, 0 palm  (the ad front-door)
///  - STANDARD   ₹199/mo   — 50 chats/mo,  2 palm/mo
///  - PREMIUM    ₹499/mo   — 100 chats/mo, 5 palm/mo
///  - UNLIMITED  ₹999/mo   — unlimited chats + unlimited palm
///
/// The Pass is billed WEEKLY (its chat allowance resets weekly server-side);
/// the other three bill/reset MONTHLY. Palm is a paid *monthly-tier* feature
/// — the ₹49 pass has none, so palm is an upgrade reason. Enum symbols map to
/// Firestore/plan tags: pass/trial/standard/premium.
/// Whether the Starter Pass introductory price is LIVE in Razorpay.
///
/// Flip this to true only once BOTH exist in the Razorpay dashboard:
///   1. a ₹99/week plan, with RAZORPAY_PLAN_PASS pointing at it
///   2. a first-cycle offer bringing cycle 1 to ₹49, with
///      RAZORPAY_OFFER_PASS_INTRO pointing at it
///
/// Until then the app charges ₹49 every week, and this must stay false.
///
/// It gates three things at once — the price fields below, the plan
/// labels, and which promo sheet variant is shown — so the displayed
/// price, the autopay disclosure and the actual Razorpay charge cannot
/// drift apart. That matters more than it looks: AutopayDisclosure makes
/// the user tick "I understand ₹N will be auto-debited every week", so a
/// wrong recurring figure here is a false consent record, not a typo.
///
/// Raising the Pass to ₹99 also fixes a real inversion in the ladder. At
/// ₹49/week it costs ~₹212/month for ~91 chats against Standard's ₹199
/// for 50, so nobody who only chats should ever have upgraded. At ₹99 the
/// Pass lands at ~₹429/month and sits correctly above Standard.
const bool kPassIntroPricingLive = false;

enum SubscriptionPlan {
  /// Free tier — 1 chat total (lifetime), 0 palm readings.
  free,

  /// ₹49/week — 21 chats/week, 0 palm. Cheap weekly front-door.
  pass,

  /// ₹199/month — 50 chats/mo, 2 palm/mo.
  trial,

  /// ₹499/month — 100 chats/mo, 5 palm/mo.
  standard,

  /// ₹999/month — unlimited chats + unlimited palm + family profiles.
  premium,
}

extension SubscriptionPlanInfo on SubscriptionPlan {
  /// All paid tiers are recurring subscriptions — no one-time plans.
  bool get isOneTime => false;

  /// True for the weekly-billed Pass; the other paid tiers are monthly.
  bool get isWeekly => this == SubscriptionPlan.pass;

  /// Billing-cycle word for labels ('week' | 'month').
  String get billingCycle => isWeekly ? 'week' : 'month';

  /// Days of access for a one-time pass. Unused (all recurring).
  int get accessDays => 0;

  /// Razorpay subscription plan ID (informational — the server creates the
  /// subscription using its RAZORPAY_PLAN_* env vars). Configure those to
  /// the real weekly ₹49 and monthly ₹199/₹499/₹999 plans.
  String get razorpayPlanId {
    switch (this) {
      case SubscriptionPlan.pass:
        return 'plan_pass_49_weekly'; // ₹49/week
      case SubscriptionPlan.trial:
        return 'plan_tier1_199';      // ₹199/month
      case SubscriptionPlan.standard:
        return 'plan_tier2_499';      // ₹499/month
      case SubscriptionPlan.premium:
        return 'plan_tier3_999';      // ₹999/month
      case SubscriptionPlan.free:
        return '';
    }
  }

  /// User-facing plan name
  String get displayName {
    switch (this) {
      case SubscriptionPlan.free:
        return 'Free';
      case SubscriptionPlan.pass:
        return 'Starter Pass';
      case SubscriptionPlan.trial:
        return 'Standard';
      case SubscriptionPlan.standard:
        return 'Premium';
      case SubscriptionPlan.premium:
        return 'Unlimited';
    }
  }

  /// Headline price label.
  String get priceLabel {
    switch (this) {
      case SubscriptionPlan.free:
        return 'Free';
      case SubscriptionPlan.pass:
        return kPassIntroPricingLive ? '₹49 first week' : '₹49/week';
      case SubscriptionPlan.trial:
        return '₹199/month';
      case SubscriptionPlan.standard:
        return '₹499/month';
      case SubscriptionPlan.premium:
        return '₹999/month';
    }
  }

  /// Short subtitle used on paywall cards
  String get subtitle {
    switch (this) {
      case SubscriptionPlan.free:
        return '1 free chat';
      case SubscriptionPlan.pass:
        return kPassIntroPricingLive
            ? '21 chats a week · then ₹99 a week, cancel anytime'
            : '21 chats a week · billed weekly, cancel anytime';
      case SubscriptionPlan.trial:
        return 'For regular seekers';
      case SubscriptionPlan.standard:
        return 'For serious seekers';
      case SubscriptionPlan.premium:
        return 'Everything unlimited';
    }
  }

  /// Amount in PAISE charged for the first cycle (same as recurring).
  int get firstChargePaise {
    switch (this) {
      case SubscriptionPlan.free:
        return 0;
      case SubscriptionPlan.pass:
        return 4900;      // ₹49 — the first cycle, intro or not
      case SubscriptionPlan.trial:
        return 19900;     // ₹199
      case SubscriptionPlan.standard:
        return 49900;     // ₹499
      case SubscriptionPlan.premium:
        return 99900;     // ₹999
    }
  }

  /// Recurring amount in paise (per [billingCycle]).
  ///
  /// Equal to [firstChargePaise] for every plan EXCEPT the Pass once
  /// intro pricing is live: ₹49 for cycle one, ₹99 after. AutopayDisclosure
  /// renders both figures and puts the recurring one in the consent
  /// checkbox, so this is the number the user actually agrees to.
  int get recurringPaise =>
      (this == SubscriptionPlan.pass && kPassIntroPricingLive)
          ? 9900 // ₹99/week standing rate
          : firstChargePaise;

  /// No free trial. 0 for every plan.
  int get trialDays => 0;

  /// [recurringPaise] normalised to a month, so a weekly plan can be
  /// compared with the monthly tiers at all. 52 weeks / 12 months.
  ///
  /// This is the number that exposes whether the ladder actually goes up.
  /// At ₹49/week the Pass works out to ~₹212/month for ~91 chats, against
  /// Standard at ₹199 for 50 — so the cheaper-looking weekly plan was in
  /// fact the better deal, and nobody who only chats should ever have
  /// upgraded off it. Raising the standing rate to ₹99 puts the Pass at
  /// ~₹429 and restores the order.
  int get monthlyEquivalentPaise =>
      isWeekly ? (recurringPaise * 52 / 12).round() : recurringPaise;

  /// Chat questions per month, normalised the same way, for the same
  /// reason. -1 stays -1 (unlimited).
  int get monthlyEquivalentChats => chatLimit < 0
      ? -1
      : (isWeekly ? (chatLimit * 52 / 12).round() : chatLimit);

  /// Chat questions allowed per BILLING CYCLE (weekly for Pass, monthly for
  /// the rest). For Free this is the LIFETIME total. -1 = unlimited.
  int get chatLimit {
    switch (this) {
      case SubscriptionPlan.free:
        return 1;          // 1 chat total (lifetime)
      case SubscriptionPlan.pass:
        return 21;         // 21 chats per week
      case SubscriptionPlan.trial:
        return 50;         // 50 chats per month
      case SubscriptionPlan.standard:
        return 100;        // 100 chats per month
      case SubscriptionPlan.premium:
        return -1;         // unlimited
    }
  }

  /// Palm readings allowed per cycle. -1 = unlimited. Palm is a monthly-tier
  /// feature — the ₹49 weekly Pass has NONE (upgrade for palm).
  int get palmLimit {
    switch (this) {
      case SubscriptionPlan.free:
        return 0;
      case SubscriptionPlan.pass:
        return 0;          // no palm on the weekly pass
      case SubscriptionPlan.trial:
        return 2;          // 2 palm readings per month
      case SubscriptionPlan.standard:
        return 5;          // 5 palm readings per month
      case SubscriptionPlan.premium:
        return -1;         // unlimited
    }
  }

  /// Family profiles allowed. 1 = self only.
  int get familyProfileLimit {
    switch (this) {
      case SubscriptionPlan.free:
        return 1;
      case SubscriptionPlan.pass:
        return 1;
      case SubscriptionPlan.trial:
        return 1;
      case SubscriptionPlan.standard:
        return 3;
      case SubscriptionPlan.premium:
        return -1; // unlimited
    }
  }

  /// Bullet-point list of features for paywall display
  List<String> get features {
    switch (this) {
      case SubscriptionPlan.free:
        return ['1 free chat', 'Daily horoscope'];
      case SubscriptionPlan.pass:
        return [
          '21 AI astrology chats every week',
          'Billed ₹49/week — cancel anytime',
          'Daily, weekly & monthly horoscope',
          'Full Kundli chart',
        ];
      case SubscriptionPlan.trial:
        return [
          '50 AI astrology chats per month',
          '2 palm readings per month',
          'Daily / weekly / monthly horoscope',
          'Full Kundli chart',
        ];
      case SubscriptionPlan.standard:
        return [
          '100 AI chats per month',
          '5 palm readings per month',
          '3 family profiles',
          'Daily / weekly / monthly horoscope',
        ];
      case SubscriptionPlan.premium:
        return [
          'Unlimited chats',
          'Unlimited palm readings',
          'Unlimited family profiles',
          'Detailed predictions',
          'Priority response',
          'Yearly forecast PDF',
        ];
    }
  }

  /// Plans the user can upgrade *to* from their current plan.
  List<SubscriptionPlan> get upgradeOptions {
    switch (this) {
      case SubscriptionPlan.free:
        return const [
          SubscriptionPlan.pass,
          SubscriptionPlan.trial,
          SubscriptionPlan.standard,
          SubscriptionPlan.premium,
        ];
      case SubscriptionPlan.pass:
        // Standard (₹199/mo) is deliberately absent. On the headline
        // prices it looks like an upgrade from ₹49, but the Pass bills
        // weekly: ~₹212/month for ~91 chats, against ₹199 for 50. Offering
        // it was offering a downgrade — more money per question, 45% fewer
        // questions — and it stays wrong once the Pass goes to ₹99/week
        // (~₹429). plan_ladder_test.dart enforces this on monthly
        // equivalents, which is the only basis on which a weekly plan and
        // a monthly one can be compared at all.
        return const [
          SubscriptionPlan.standard,
          SubscriptionPlan.premium,
        ];
      case SubscriptionPlan.trial:
        return const [SubscriptionPlan.standard, SubscriptionPlan.premium];
      case SubscriptionPlan.standard:
        return const [SubscriptionPlan.premium];
      case SubscriptionPlan.premium:
        return const [];
    }
  }

  static SubscriptionPlan fromId(String? id) {
    switch (id) {
      case 'pass':
        return SubscriptionPlan.pass;
      case 'trial':
        return SubscriptionPlan.trial;
      case 'standard':
        return SubscriptionPlan.standard;
      case 'premium':
        return SubscriptionPlan.premium;
      default:
        return SubscriptionPlan.free;
    }
  }

  String get id {
    switch (this) {
      case SubscriptionPlan.free:
        return 'free';
      case SubscriptionPlan.pass:
        return 'pass';
      case SubscriptionPlan.trial:
        return 'trial';
      case SubscriptionPlan.standard:
        return 'standard';
      case SubscriptionPlan.premium:
        return 'premium';
    }
  }
}
