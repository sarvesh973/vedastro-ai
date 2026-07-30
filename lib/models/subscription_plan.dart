/// Subscription plans for VedAstro AI.
/// All pricing is in INR (paise).
///
/// Monetization model — a cheap WEEKLY front-door + three MONTHLY upsell
/// tiers (all recurring via Razorpay Subscriptions + autopay), cancellable
/// in one tap from Settings:
///  - FREE:      1 chat total (lifetime), 0 palm.
///  - PASS       ₹79/WEEK  — 21 chats/week, 0 palm  (the ad front-door)
///  - STANDARD   ₹199/mo   — 35 chats/mo,  2 palm/mo
///  - PREMIUM    ₹499/mo   — 100 chats/mo, 5 palm/mo
///  - UNLIMITED  ₹999/mo   — unlimited chats + unlimited palm
///
/// The Pass is billed WEEKLY (its chat allowance resets weekly server-side);
/// the other three bill/reset MONTHLY. Palm is a paid *monthly-tier* feature
/// — the ₹79 pass has none, so palm is an upgrade reason. Enum symbols map to
/// Firestore/plan tags: pass/trial/standard/premium.
enum SubscriptionPlan {
  /// Free tier — 1 chat total (lifetime), 0 palm readings.
  free,

  /// ₹79/week — 21 chats/week, 0 palm. Cheap weekly front-door.
  pass,

  /// ₹199/month — 35 chats/mo, 2 palm/mo.
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
  /// the real weekly ₹79 and monthly ₹199/₹499/₹999 plans.
  String get razorpayPlanId {
    switch (this) {
      case SubscriptionPlan.pass:
        return 'plan_pass_79_weekly'; // ₹79/week
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
        return '₹79/week';
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
        return '21 chats a week · billed weekly, cancel anytime';
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
        return 7900;      // ₹79
      case SubscriptionPlan.trial:
        return 19900;     // ₹199
      case SubscriptionPlan.standard:
        return 49900;     // ₹499
      case SubscriptionPlan.premium:
        return 99900;     // ₹999
    }
  }

  /// Recurring amount in paise (per [billingCycle]).
  int get recurringPaise => firstChargePaise;

  /// No free trial. 0 for every plan.
  int get trialDays => 0;

  /// Chat questions allowed per BILLING CYCLE (weekly for Pass, monthly for
  /// the rest). For Free this is the LIFETIME total. -1 = unlimited.
  int get chatLimit {
    switch (this) {
      case SubscriptionPlan.free:
        return 1;          // 1 chat total (lifetime)
      case SubscriptionPlan.pass:
        return 21;         // 21 chats per week
      case SubscriptionPlan.trial:
        return 35;         // 35 chats per month
      case SubscriptionPlan.standard:
        return 100;        // 100 chats per month
      case SubscriptionPlan.premium:
        return -1;         // unlimited
    }
  }

  /// Palm readings allowed per cycle. -1 = unlimited. Palm is a monthly-tier
  /// feature — the ₹79 weekly Pass has NONE (upgrade for palm).
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
          'Billed ₹79/week — cancel anytime',
          'Daily, weekly & monthly horoscope',
          'Full Kundli chart',
        ];
      case SubscriptionPlan.trial:
        return [
          '35 AI astrology chats per month',
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
        return const [
          SubscriptionPlan.trial,
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
