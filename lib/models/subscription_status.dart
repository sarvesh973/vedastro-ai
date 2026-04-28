import 'subscription_plan.dart';

/// Lifecycle states of a subscription.
/// Mirror of Razorpay's subscription states + our own internal ones.
enum SubscriptionState {
  /// User has never subscribed.
  none,

  /// In 7-day free trial. e-mandate registered. ₹99 will auto-debit on day 8.
  trialing,

  /// Active paid subscription.
  active,

  /// User cancelled but current paid period hasn't ended yet.
  /// They keep access until expiresAt, then drop to [none].
  cancelledPending,

  /// Most recent debit failed (insufficient funds, expired card, etc).
  /// Razorpay will retry up to 4 times; if all fail, status -> expired.
  paymentFailed,

  /// Subscription ended (cancelled period elapsed OR all retries failed).
  expired,
}

/// User's current subscription state. Persisted in Firestore at
/// users/{uid}/subscription, mirrored locally in SharedPreferences for
/// offline access.
class SubscriptionStatus {
  final SubscriptionPlan plan;
  final SubscriptionState state;

  /// Razorpay's subscription ID (sub_XXXXXX). Null while user is on free.
  final String? razorpaySubscriptionId;

  /// When the trial converts to paid (if [state] == trialing).
  final DateTime? trialEndsAt;

  /// End of current paid billing period. Renews automatically unless cancelled.
  final DateTime? currentPeriodEndsAt;

  /// When the user clicked Cancel, if applicable.
  final DateTime? cancelledAt;

  /// Number of failed debit retries (Razorpay retries 4× before giving up).
  final int failedAttempts;

  /// Chat questions used in the current billing cycle.
  /// Resets on each successful debit.
  final int chatUsedThisCycle;

  /// Palm readings used in the current billing cycle.
  final int palmUsedThisCycle;

  const SubscriptionStatus({
    required this.plan,
    required this.state,
    this.razorpaySubscriptionId,
    this.trialEndsAt,
    this.currentPeriodEndsAt,
    this.cancelledAt,
    this.failedAttempts = 0,
    this.chatUsedThisCycle = 0,
    this.palmUsedThisCycle = 0,
  });

  /// Default for users who haven't paid yet.
  static const SubscriptionStatus free = SubscriptionStatus(
    plan: SubscriptionPlan.free,
    state: SubscriptionState.none,
  );

  /// True if the user currently has paid features unlocked.
  /// (Trialing or active or cancelled-but-still-paid-up.)
  bool get isActive {
    if (state == SubscriptionState.trialing) return true;
    if (state == SubscriptionState.active) return true;
    if (state == SubscriptionState.cancelledPending &&
        currentPeriodEndsAt != null &&
        currentPeriodEndsAt!.isAfter(DateTime.now())) {
      return true;
    }
    return false;
  }

  /// Can this user ask another chat question?
  bool canAskChat() {
    if (!isActive) return false;
    final limit = plan.chatLimit;
    if (limit == -1) return true; // unlimited
    return chatUsedThisCycle < limit;
  }

  /// Can this user do another palm reading?
  bool canDoPalm() {
    if (!isActive) return false;
    final limit = plan.palmLimit;
    if (limit == -1) return true;
    return palmUsedThisCycle < limit;
  }

  /// Days remaining in trial (if trialing). Negative or 0 means expired.
  int get trialDaysRemaining {
    if (state != SubscriptionState.trialing || trialEndsAt == null) return 0;
    final diff = trialEndsAt!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// Hours remaining in trial — used for last-day countdown UI.
  int get trialHoursRemaining {
    if (state != SubscriptionState.trialing || trialEndsAt == null) return 0;
    final diff = trialEndsAt!.difference(DateTime.now()).inHours;
    return diff < 0 ? 0 : diff;
  }

  Map<String, dynamic> toJson() => {
        'plan': plan.id,
        'state': state.name,
        'razorpaySubscriptionId': razorpaySubscriptionId,
        'trialEndsAt': trialEndsAt?.toIso8601String(),
        'currentPeriodEndsAt': currentPeriodEndsAt?.toIso8601String(),
        'cancelledAt': cancelledAt?.toIso8601String(),
        'failedAttempts': failedAttempts,
        'chatUsedThisCycle': chatUsedThisCycle,
        'palmUsedThisCycle': palmUsedThisCycle,
      };

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      plan: SubscriptionPlanInfo.fromId(json['plan'] as String?),
      state: SubscriptionState.values.firstWhere(
        (s) => s.name == (json['state'] as String?),
        orElse: () => SubscriptionState.none,
      ),
      razorpaySubscriptionId: json['razorpaySubscriptionId'] as String?,
      trialEndsAt: _parseDate(json['trialEndsAt']),
      currentPeriodEndsAt: _parseDate(json['currentPeriodEndsAt']),
      cancelledAt: _parseDate(json['cancelledAt']),
      failedAttempts: (json['failedAttempts'] as int?) ?? 0,
      chatUsedThisCycle: (json['chatUsedThisCycle'] as int?) ?? 0,
      palmUsedThisCycle: (json['palmUsedThisCycle'] as int?) ?? 0,
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  SubscriptionStatus copyWith({
    SubscriptionPlan? plan,
    SubscriptionState? state,
    String? razorpaySubscriptionId,
    DateTime? trialEndsAt,
    DateTime? currentPeriodEndsAt,
    DateTime? cancelledAt,
    int? failedAttempts,
    int? chatUsedThisCycle,
    int? palmUsedThisCycle,
  }) {
    return SubscriptionStatus(
      plan: plan ?? this.plan,
      state: state ?? this.state,
      razorpaySubscriptionId:
          razorpaySubscriptionId ?? this.razorpaySubscriptionId,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      currentPeriodEndsAt: currentPeriodEndsAt ?? this.currentPeriodEndsAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      chatUsedThisCycle: chatUsedThisCycle ?? this.chatUsedThisCycle,
      palmUsedThisCycle: palmUsedThisCycle ?? this.palmUsedThisCycle,
    );
  }
}
