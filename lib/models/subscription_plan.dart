/// Subscription plans for VedAstro AI.
/// All pricing is in INR (paise).
///
/// Monetization model:
///  - FREE: 1 chat total (lifetime), 0 palm. Then the paywall appears.
///  - STARTER PASS (the `trial` enum — name kept for plumbing compat):
///    ONE-TIME ₹49 payment granting 7 days of access, 3 chats/day, NO palm.
///    No auto-renewal / no e-mandate. After 7 days the user reverts to Free
///    and may buy the pass again.
///  - STANDARD ₹199/mo and PREMIUM ₹499/mo: recurring (Razorpay Subscriptions
///    API + e-mandate autopay), cancellable in one tap from Settings.
///
/// So the Starter Pass uses the Razorpay Orders API (one-time), while
/// Standard/Premium use the Subscriptions API (recurring). [isOneTime]
/// distinguishes them for the payment layer.
enum SubscriptionPlan {
  /// Free tier — 1 chat total (lifetime), 0 palm readings.
  free,

  /// Starter Pass — ONE-TIME ₹49 for 7 days, 3 chats/day, no palm.
  /// (Enum symbol kept as `trial` so server plan-ids / Firestore plan tags
  /// don't need a cross-repo rename; it is NOT a free trial anymore.)
  trial,

  /// ₹199/month recurring. 30 chats + 5 palm readings per month.
  standard,

  /// ₹499/month recurring. Unlimited chats + unlimited palm readings
  /// (soft cap 100/day) + family profiles + detailed predictions.
  premium,
}

extension SubscriptionPlanInfo on SubscriptionPlan {
  /// True for one-time purchases (the Starter Pass). Standard/Premium are
  /// recurring subscriptions. Drives which Razorpay flow the app uses.
  bool get isOneTime => this == SubscriptionPlan.trial;

  /// Days of access granted by a one-time pass. 0 for recurring plans.
  int get accessDays => this == SubscriptionPlan.trial ? 7 : 0;

  /// Razorpay subscription plan ID — ONLY used by recurring plans
  /// (Standard/Premium). The Starter Pass is a one-time order, so it has
  /// no plan ID. Replace with the real dashboard IDs before going live.
  String get razorpayPlanId {
    switch (this) {
      case SubscriptionPlan.standard:
        return 'plan_standard_199';  // ₹199/month
      case SubscriptionPlan.premium:
        return 'plan_premium_499';   // ₹499/month
      case SubscriptionPlan.trial:   // one-time order, no plan id
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
        return 'Starter Pass';
      case SubscriptionPlan.standard:
        return 'Standard';
      case SubscriptionPlan.premium:
        return 'Premium';
    }
  }

  /// Headline price label.
  String get priceLabel {
    switch (this) {
      case SubscriptionPlan.free:
        return 'Free';
      case SubscriptionPlan.trial:
        return '₹49 for 7 days';
      case SubscriptionPlan.standard:
        return '₹199/month';
      case SubscriptionPlan.premium:
        return '₹499/month';
    }
  }

  /// Short subtitle used on paywall cards
  String get subtitle {
    switch (this) {
      case SubscriptionPlan.free:
        return '1 free chat';
      case SubscriptionPlan.trial:
        return '3 chats/day for 7 days · one-time, no auto-renewal';
      case SubscriptionPlan.standard:
        return 'For regular seekers';
      case SubscriptionPlan.premium:
        return 'Unlimited everything';
    }
  }

  /// Amount in PAISE charged immediately.
  /// Starter Pass = ₹49 one-time. Standard/Premium = first month's charge.
  int get firstChargePaise {
    switch (this) {
      case SubscriptionPlan.free:
        return 0;
      case SubscriptionPlan.trial:
        return 4900;      // ₹49 one-time
      case SubscriptionPlan.standard:
        return 19900;     // ₹199
      case SubscriptionPlan.premium:
        return 49900;     // ₹499
    }
  }

  /// Recurring monthly amount in paise. 0 for one-time plans.
  int get recurringPaise {
    switch (this) {
      case SubscriptionPlan.free:
        return 0;
      case SubscriptionPlan.trial:
        return 0;         // one-time, never recurs
      case SubscriptionPlan.standard:
        return 19900;     // ₹199
      case SubscriptionPlan.premium:
        return 49900;     // ₹499
    }
  }

  /// Free-trial duration in days. We no longer offer a free trial, so 0
  /// for every plan. (Pass access duration is [accessDays], not a trial.)
  int get trialDays => 0;

  /// Chat questions allowed PER DAY for paid plans; for Free this is the
  /// LIFETIME total. -1 means unlimited.
  int get chatLimit {
    switch (this) {
      case SubscriptionPlan.free:
        return 1;          // 1 chat total (lifetime)
      case SubscriptionPlan.trial:
        return 3;          // 3 chats per day for the 7-day pass
      case SubscriptionPlan.standard:
        return 10;         // 10 chats per day
      case SubscriptionPlan.premium:
        return -1; // unlimited (soft cap enforced server-side)
    }
  }

  /// Palm readings allowed. -1 = unlimited. Palm is NOT part of the
  /// Starter Pass (0) — only Standard/Premium include it.
  int get palmLimit {
    switch (this) {
      case SubscriptionPlan.free:
        return 0;
      case SubscriptionPlan.trial:
        return 0;          // Starter Pass does NOT include palm reading
      case SubscriptionPlan.standard:
        return 5;
      case SubscriptionPlan.premium:
        return -1;
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
          '3 AI astrology chats every day',
          '7 days of full access',
          'One-time ₹49 — no auto-renewal',
          'Daily, weekly & monthly horoscope',
        ];
      case SubscriptionPlan.standard:
        return [
          '10 chats per day',
          'Palm reading included',
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
