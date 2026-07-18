/// Subscription plans for VedAstro AI.
/// All pricing is in INR (paise).
///
/// Monetization model — THREE recurring monthly tiers (Razorpay Subscriptions
/// API + e-mandate autopay), cancellable in one tap from Settings:
///  - FREE:      1 chat total (lifetime), 0 palm. Then the paywall appears.
///  - STANDARD   ₹199/mo — 35 chats/mo,  2 palm/mo
///  - PREMIUM    ₹499/mo — 100 chats/mo, 5 palm/mo
///  - UNLIMITED  ₹999/mo — unlimited chats + unlimited palm
///
/// Palm reading is included in EVERY paid tier. Chat + palm allowances are
/// PER CALENDAR MONTH (enforced monthly server-side). The enum symbols
/// (trial/standard/premium) are kept for plumbing/Firestore-tag compat and
/// map to the three paid tiers in ascending price order.
enum SubscriptionPlan {
  /// Free tier — 1 chat total (lifetime), 0 palm readings.
  free,

  /// ₹199/month — 35 chats/mo, 2 palm/mo. (Entry paid tier.)
  trial,

  /// ₹499/month — 100 chats/mo, 5 palm/mo.
  standard,

  /// ₹999/month — unlimited chats + unlimited palm + family profiles.
  premium,
}

extension SubscriptionPlanInfo on SubscriptionPlan {
  /// All paid tiers are now recurring subscriptions — no one-time plans.
  bool get isOneTime => false;

  /// Days of access for a one-time pass. Unused now (all recurring).
  int get accessDays => 0;

  /// Razorpay subscription plan ID (informational — the server creates the
  /// subscription using its own RAZORPAY_PLAN_* env vars). Configure those
  /// env vars to real ₹199/₹499/₹999 monthly plans in the Razorpay dashboard.
  String get razorpayPlanId {
    switch (this) {
      case SubscriptionPlan.trial:
        return 'plan_tier1_199';   // ₹199/month
      case SubscriptionPlan.standard:
        return 'plan_tier2_499';   // ₹499/month
      case SubscriptionPlan.premium:
        return 'plan_tier3_999';   // ₹999/month
      case SubscriptionPlan.free:
        return '';
    }
  }

  /// User-facing plan name
  String get displayName {
    switch (this) {
      case SubscriptionPlan.free:
        return 'Free';
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
      case SubscriptionPlan.trial:
        return 'For regular seekers';
      case SubscriptionPlan.standard:
        return 'For serious seekers';
      case SubscriptionPlan.premium:
        return 'Everything unlimited';
    }
  }

  /// Amount in PAISE charged for the first month (same as recurring).
  int get firstChargePaise {
    switch (this) {
      case SubscriptionPlan.free:
        return 0;
      case SubscriptionPlan.trial:
        return 19900;     // ₹199
      case SubscriptionPlan.standard:
        return 49900;     // ₹499
      case SubscriptionPlan.premium:
        return 99900;     // ₹999
    }
  }

  /// Recurring monthly amount in paise.
  int get recurringPaise {
    switch (this) {
      case SubscriptionPlan.free:
        return 0;
      case SubscriptionPlan.trial:
        return 19900;     // ₹199
      case SubscriptionPlan.standard:
        return 49900;     // ₹499
      case SubscriptionPlan.premium:
        return 99900;     // ₹999
    }
  }

  /// No free trial. 0 for every plan.
  int get trialDays => 0;

  /// Chat questions allowed PER MONTH for paid plans; for Free this is the
  /// LIFETIME total. -1 means unlimited.
  int get chatLimit {
    switch (this) {
      case SubscriptionPlan.free:
        return 1;          // 1 chat total (lifetime)
      case SubscriptionPlan.trial:
        return 35;         // 35 chats per month
      case SubscriptionPlan.standard:
        return 100;        // 100 chats per month
      case SubscriptionPlan.premium:
        return -1;         // unlimited
    }
  }

  /// Palm readings allowed PER MONTH. -1 = unlimited. Palm is included in
  /// EVERY paid tier now (Free = 0).
  int get palmLimit {
    switch (this) {
      case SubscriptionPlan.free:
        return 0;
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
      case SubscriptionPlan.trial:
        return 'trial';
      case SubscriptionPlan.standard:
        return 'standard';
      case SubscriptionPlan.premium:
        return 'premium';
    }
  }
}
