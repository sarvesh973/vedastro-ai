/// Subscription plans for VedAstro AI.
/// All pricing is in INR (paise).
///
/// Compliance notes:
///  - All plans use Razorpay Subscriptions API (not one-time payments) so
///    RBI e-mandate rules and India CCPA dark-pattern guidelines are
///    enforced by Razorpay's checkout UI automatically.
///  - The Trial plan auto-converts to ₹99/month after 7 days. This MUST
///    be disclosed in BOLD on the paywall before payment, and the user
///    must be able to cancel in one tap from Settings.
enum SubscriptionPlan {
  /// Free tier — 2 chats, 1 palm reading total. No subscription.
  free,

  /// ₹1 today, ₹99/month auto-debit after 7 days. 10 chats during trial.
  trial,

  /// ₹199/month. 30 chats + 5 palm readings per month.
  standard,

  /// ₹499/month. Unlimited chats + unlimited palm readings (soft cap 100/day
  /// to prevent abuse) + family profiles + detailed predictions.
  premium,
}

extension SubscriptionPlanInfo on SubscriptionPlan {
  /// Plan ID configured in Razorpay dashboard.
  /// These MUST match the plan IDs you create on dashboard.razorpay.com
  /// → Subscriptions → Plans. Replace before going live.
  String get razorpayPlanId {
    switch (this) {
      case SubscriptionPlan.trial:
        return 'plan_trial_99';      // ₹99/month after 7-day ₹1 trial
      case SubscriptionPlan.standard:
        return 'plan_standard_199';  // ₹199/month
      case SubscriptionPlan.premium:
        return 'plan_premium_499';   // ₹499/month
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
        return 'Free 7-Day Trial';
      case SubscriptionPlan.standard:
        return 'Standard';
      case SubscriptionPlan.premium:
        return 'Premium';
    }
  }

  /// Headline price label (e.g. "₹199/month", "Free 7 days, then ₹99/month")
  String get priceLabel {
    switch (this) {
      case SubscriptionPlan.free:
        return 'Free';
      case SubscriptionPlan.trial:
        return 'Free 7 days, then ₹99/month';
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
        return 'Limited free chats';
      case SubscriptionPlan.trial:
        return 'No charge today — auto-renews ₹99/month after 7 days';
      case SubscriptionPlan.standard:
        return 'For regular seekers';
      case SubscriptionPlan.premium:
        return 'Unlimited everything';
    }
  }

  /// Amount in PAISE that Razorpay should charge for the FIRST debit.
  /// For free trial = 0 (mandate setup only, first charge happens day 7).
  /// For monthly plans = monthly price.
  int get firstChargePaise {
    switch (this) {
      case SubscriptionPlan.free:
        return 0;
      case SubscriptionPlan.trial:
        return 0;         // Free trial — no charge today
      case SubscriptionPlan.standard:
        return 19900;     // ₹199
      case SubscriptionPlan.premium:
        return 49900;     // ₹499
    }
  }

  /// Recurring monthly amount in paise.
  /// For trial, this is what gets charged on day 7.
  int get recurringPaise {
    switch (this) {
      case SubscriptionPlan.free:
        return 0;
      case SubscriptionPlan.trial:
        return 9900;      // ₹99 after trial
      case SubscriptionPlan.standard:
        return 19900;     // ₹199
      case SubscriptionPlan.premium:
        return 49900;     // ₹499
    }
  }

  /// Trial duration in days. 0 means no trial.
  int get trialDays {
    return this == SubscriptionPlan.trial ? 7 : 0;
  }

  /// Chat questions allowed per billing cycle. -1 means unlimited.
  int get chatLimit {
    switch (this) {
      case SubscriptionPlan.free:
        return 2;
      case SubscriptionPlan.trial:
        return 10;
      case SubscriptionPlan.standard:
        return 30;
      case SubscriptionPlan.premium:
        return -1; // unlimited (soft cap enforced server-side at 100/day)
    }
  }

  /// Palm readings allowed per billing cycle. -1 means unlimited.
  int get palmLimit {
    switch (this) {
      case SubscriptionPlan.free:
        return 1;
      case SubscriptionPlan.trial:
        return 2;
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
        return ['2 free chats', '1 free palm reading', 'Daily horoscope'];
      case SubscriptionPlan.trial:
        return [
          '10 chats during the 7-day trial',
          '2 palm readings',
          'No charge today — cancel anytime',
          'Auto-renews ₹99/month after day 7',
        ];
      case SubscriptionPlan.standard:
        return [
          '30 chats per month',
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
