import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/subscription_plan.dart';
import '../providers/providers.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../services/storage_service.dart';
import '../widgets/autopay_confirm_sheet.dart';
import '../widgets/plan_activated_sheet.dart';

/// Paywall with up to three plans: Free 7-Day Trial, Standard (₹199/mo),
/// Premium (₹499/mo).
///
/// Compliance UX:
///  - Plan cards on the screen — no checkbox visible inline
///  - Tap Subscribe -> bottom-sheet popup opens with the full autopay
///    disclosure + required consent checkbox
///  - Razorpay only opens after the user ticks the box and taps Confirm
///
/// Smart upgrade behaviour:
///  - [availablePlans] lets the caller hide irrelevant plans, e.g. when a
///    Standard subscriber hits their cap, only show Premium.
///  - Pass `null` to show all 3 plans (default).
/// Headline and subline for a paywall, keyed on the surface it opened from.
typedef PaywallCopy = ({String headline, String subline});

/// Copy for the surface the user arrived from, or null to keep the generic
/// header ('Unlock Moksha' / 'Pick the plan that suits your journey').
///
/// Only the surfaces where something was actually BLOCKED get their own
/// copy. Arriving from the home banner, the drawer or Settings is browsing
/// — the generic line is the honest one there, because nothing was taken
/// away and implying otherwise would be manufactured urgency.
///
/// [isFreeUser] false returns null throughout: someone already paying who
/// hits their plan's ceiling needs to hear about THAT, not about a free
/// question they used months ago.
///
/// Deliberately calm and declarative. Every line states what the user
/// already has, then what the plans add. No countdowns, no "last chance",
/// no implied loss — the Play listing promises no fear-based manipulation,
/// and at 4.1 stars a paywall that reads as a squeeze costs more in reviews
/// than it earns in conversions. paywall_copy_test.dart enforces this.
@visibleForTesting
PaywallCopy? paywallCopyFor(String trigger, {required bool isFreeUser}) {
  if (!isFreeUser) return null;
  switch (trigger) {
    case 'chat_limit':
      return (
        headline: 'Your chart has more to say',
        // Names the real allowance. The server's own 429 still claims
        // "5 chats a day for 7 days", which is neither what the Pass gives
        // (21 a week) nor how it bills (weekly, recurring). The app has
        // always shown its own copy so users never saw that — but this is
        // the number this screen must not get wrong.
        subline: 'You have used your free question. The Starter Pass '
            'includes 21 a week, and every plan above it includes more.',
      );
    case 'palm_limit':
      return (
        headline: 'Palm readings',
        // The one case where vagueness causes refunds: a free user told to
        // "pick a plan" can buy the ₹49 Pass and only then discover palm
        // is not in it.
        subline: 'Palm reading comes with Standard and above. The ₹49 '
            'Starter Pass does not include it.',
      );
    case 'compat':
      return (
        headline: 'See the whole match',
        subline: 'Your score and all eight kutas are yours to keep. The '
            'written reading covers what each of you needs, and where you '
            'misread each other.',
      );
    case 'mulank':
      return (
        headline: 'Your Mulank, every day',
        subline: 'The monthly overview stays free. Daily and weekly '
            'readings, and asking about your day, come with any plan.',
      );
    default:
      return null;
  }
}

class PaywallScreen extends ConsumerStatefulWidget {
  /// If null, shows all 3 plans. If set, shows only the listed plans
  /// in their order. Used by chat / palm screens to hide already-active
  /// plans after a usage cap is hit (e.g. Standard exhausted -> only
  /// Premium card is shown so the user can upgrade).
  final List<SubscriptionPlan>? availablePlans;

  /// Which surface opened the paywall (e.g. 'chat_limit', 'home_banner',
  /// 'settings'). Reported as Meta ViewContent + Firebase paywall_viewed
  /// so ad campaigns can see which surfaces drive conversions.
  final String trigger;

  const PaywallScreen({
    super.key,
    this.availablePlans,
    this.trigger = 'unknown',
  });

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  late SubscriptionPlan _selectedPlan;
  bool _isProcessing = false;

  /// For the dwell bucket on paywall_dismissed.
  DateTime? _openedAt;

  /// Set when a purchase completes, so dispose() can tell a dismissal from
  /// a conversion — the success sheet replaces this route, which disposes
  /// it just the same.
  bool _purchased = false;

  @override
  void initState() {
    super.initState();
    PaymentService.init();
    // Meta ViewContent + Firebase paywall_viewed. Admins see the bypass
    // screen instead of plans, so their views would only pollute the funnel.
    if (!AuthService.isAdmin) {
      Analytics.paywallViewed(trigger: widget.trigger);
      _openedAt = DateTime.now();
    }
    // Default selection = first plan in the available list (so it works
    // for both "all 3" and "only premium" cases).
    _selectedPlan = (widget.availablePlans ?? _defaultPlanOrder).first;
  }

  static const List<SubscriptionPlan> _defaultPlanOrder = [
    SubscriptionPlan.pass,
    SubscriptionPlan.trial,
    SubscriptionPlan.standard,
    SubscriptionPlan.premium,
  ];

  List<SubscriptionPlan> get _plansToShow =>
      widget.availablePlans ?? _defaultPlanOrder;

  /// The Pass is only ever offered to free users (see
  /// SubscriptionPlan.upgradeOptions), so its presence is the signal that
  /// nobody has paid yet. Someone already paying who hits their plan's
  /// ceiling needs to hear about THAT, not about a free question they used
  /// months ago — so the trigger copy below applies to free users only.
  bool get _isFreeUser => _plansToShow.contains(SubscriptionPlan.pass);

  /// Headline and subline for the surface the user arrived from, or null to
  /// keep the generic header.
  ///
  /// Only the surfaces where something was actually BLOCKED get their own
  /// copy. Arriving from the home banner, the drawer or Settings is
  /// browsing — the generic line is the honest one there, because nothing
  /// was taken away and pretending otherwise would be manufactured urgency.
  ///
  /// Deliberately calm and declarative. Every line names what the user
  /// already has, then what the plans add. No countdowns, no "don't miss
  /// out", no implied loss — the Play listing promises no fear-based
  /// manipulation, and at 4.1 stars a paywall that feels like a squeeze
  /// costs more in reviews than it earns in conversions.
  PaywallCopy? _triggerCopy() =>
      paywallCopyFor(widget.trigger, isFreeUser: _isFreeUser);

  @override
  void dispose() {
    // Fired here rather than on the close buttons so it also catches the
    // Android back button and the edge-swipe, which are how most paywalls
    // are actually dismissed. _openedAt is null for admins, who are
    // excluded from the funnel entirely.
    if (!_purchased && _openedAt != null) {
      Analytics.paywallDismissed(
        trigger: widget.trigger,
        secondsViewed: DateTime.now().difference(_openedAt!).inSeconds,
      );
    }
    PaymentService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Admin / founder bypass — never charge, never limit.
    if (AuthService.isAdmin) {
      return _buildAdminBypassScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _triggerCopy()?.headline ?? 'Unlock Moksha',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 18, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _subtitleForContext(),
                  // height: the trigger-aware sublines run to two or three
                  // lines where the old generic one was always a single
                  // line, and muted 14px text set solid is hard to read at
                  // that length.
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 14, height: 1.45),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ─── Scrollable plan list ──────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // Render only the plans the caller asked for, in order.
                    // Each card animates in with a small stagger.
                    for (var i = 0; i < _plansToShow.length; i++) ...[
                      _planCard(
                        plan: _plansToShow[i],
                        badge: _badgeFor(_plansToShow[i]),
                        badgeColor: _badgeColorFor(_plansToShow[i]),
                      ).animate().fadeIn(delay: (100 + i * 100).ms).slideY(
                            begin: 0.05,
                            end: 0,
                            duration: 400.ms,
                            delay: (100 + i * 100).ms,
                          ),
                      if (i < _plansToShow.length - 1)
                        const SizedBox(height: 12),
                    ],

                    const SizedBox(height: 24),

                    // ─── Trust links ──────────────────────────
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      children: [
                        _trustLink('Terms', _openTerms),
                        _trustLink('Privacy', _openPrivacy),
                        _trustLink('Refund Policy', _openRefund),
                        _trustLink('Restore Purchase', _restorePurchase),
                      ],
                    ),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),

            // ─── Pinned subscribe button ───────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(
                  top: BorderSide(
                      color: AppColors.divider.withValues(alpha: 0.5)),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _handleSubscribe,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.purpleAccent,
                      disabledBackgroundColor:
                          AppColors.surfaceLight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _subscribeButtonLabel(),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Plan card UI ─────────────────────────────────────────────

  Widget _planCard({
    required SubscriptionPlan plan,
    String? badge,
    Color? badgeColor,
  }) {
    final selected = _selectedPlan == plan;
    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = plan),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.purpleAccent.withValues(alpha: 0.1)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.purpleAccent
                : AppColors.divider.withValues(alpha: 0.5),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Radio indicator
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? AppColors.purpleAccent
                          : AppColors.textMuted,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.purpleAccent,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            plan.displayName,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (badgeColor ?? AppColors.gold)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  color: badgeColor ?? AppColors.gold,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plan.subtitle,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  plan.priceLabel,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (selected) ...[
              const SizedBox(height: 14),
              Container(height: 1, color: AppColors.divider),
              const SizedBox(height: 12),
              ...plan.features.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check,
                          color: AppColors.purpleLight, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Trust links ──────────────────────────────────────────────

  Widget _trustLink(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.purpleLight,
            fontSize: 12,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.purpleLight,
          ),
        ),
      ),
    );
  }

  // ─── Plan badges + context-aware copy ─────────────────────────

  String? _badgeFor(SubscriptionPlan plan) {
    switch (plan) {
      case SubscriptionPlan.pass:
        return 'MOST POPULAR';
      case SubscriptionPlan.trial:
        return 'INCLUDES PALM';
      case SubscriptionPlan.premium:
        return _plansToShow.contains(SubscriptionPlan.standard)
            ? 'BEST VALUE'
            : 'UPGRADE';
      default:
        return null;
    }
  }

  Color? _badgeColorFor(SubscriptionPlan plan) {
    switch (plan) {
      case SubscriptionPlan.pass:
        return AppColors.goldLight;
      case SubscriptionPlan.trial:
        return AppColors.success;
      case SubscriptionPlan.premium:
        return AppColors.purpleLight;
      default:
        return null;
    }
  }

  /// Subtitle changes based on which plans are available — gives the user
  /// a clear reason for being on this screen.
  String _subtitleForContext() {
    // The surface the user came from, when it blocked them, is more
    // relevant than anything derivable from the plan list.
    final fromTrigger = _triggerCopy();
    if (fromTrigger != null) return fromTrigger.subline;

    final plans = _plansToShow;
    if (plans.length == 1 && plans.first == SubscriptionPlan.premium) {
      return "You've reached your Standard plan limit. Upgrade to Premium for unlimited access.";
    }
    if (!plans.contains(SubscriptionPlan.trial) &&
        plans.contains(SubscriptionPlan.standard) &&
        plans.contains(SubscriptionPlan.premium)) {
      return "Upgrade your plan for more chats and palm readings.";
    }
    return 'Pick the plan that suits your journey';
  }

  // ─── Action handlers ──────────────────────────────────────────

  String _subscribeButtonLabel() {
    switch (_selectedPlan) {
      case SubscriptionPlan.pass:
        return 'Subscribe — ₹49/week';
      case SubscriptionPlan.trial:
        return 'Subscribe — ₹199/month';
      case SubscriptionPlan.standard:
        return 'Subscribe — ₹499/month';
      case SubscriptionPlan.premium:
        return 'Subscribe — ₹999/month';
      case SubscriptionPlan.free:
        return '';
    }
  }

  /// 1. Show the autopay-confirmation popup (with required tick).
  /// 2. If user confirms, open Razorpay's payment sheet.
  /// 3. On success, mark premium + close the paywall.
  void _handleSubscribe() async {
    if (_isProcessing) return;

    // The Starter Pass is a ONE-TIME ₹49 charge — no e-mandate / autopay,
    // so it skips the autopay-consent sheet entirely and goes straight to
    // Razorpay's one-time Orders checkout. Standard/Premium are recurring
    // and still require the bold autopay disclosure + tick first.
    final isOneTime = _selectedPlan.isOneTime;
    if (!isOneTime) {
      final confirmed = await showAutopayConfirmSheet(
        context: context,
        plan: _selectedPlan,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _isProcessing = true);

    final onSuccess = (String paymentId, String planId) {
      // Set before the mounted check: the conversion happened whether or
      // not this screen is still alive, and dispose() must not then log it
      // as a dismissal.
      _purchased = true;
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ref.read(isPremiumProvider.notifier).state = StorageService.isPremium;
      _showPlanActivatedSheet(_selectedPlan);
    };
    final onFailure = (String message) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    };

    if (isOneTime) {
      await PaymentService.openStarterPassCheckout(
        onSuccess: onSuccess,
        onFailure: onFailure,
        trigger: widget.trigger,
      );
      return;
    }

    await PaymentService.openSubscriptionCheckout(
      plan: _selectedPlan,
      onSuccess: onSuccess,
      onFailure: onFailure,
      trigger: widget.trigger,
    );
  }

  /// Push the success sheet over the paywall. Continue closes both;
  /// upgrade taps re-open the paywall preselected on the higher plan.
  void _showPlanActivatedSheet(SubscriptionPlan activated) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (ctx, _, __) => PlanActivatedSheet(
          activatedPlan: activated,
          onContinue: () => Navigator.of(ctx).pop(),
          onUpgrade: (newPlan) {
            // Replace this screen with a fresh paywall narrowed to the
            // chosen upgrade. Empty list means "show only this one plan"
            // — keeps the upgrade flow focused.
            Navigator.of(ctx).pushReplacement(
              MaterialPageRoute(
                builder: (_) =>
                    PaywallScreen(
                        availablePlans: [newPlan],
                        trigger: 'post_purchase_upsell'),
              ),
            );
          },
        ),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  /// Restore subscription state by re-fetching from cloud.
  /// Useful if the user re-installs or moves to a new device.
  void _restorePurchase() async {
    await StorageService.loadFromCloudForCurrentUser();
    if (!mounted) return;
    ref.read(isPremiumProvider.notifier).state = StorageService.isPremium;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(StorageService.isPremium
            ? 'Premium restored from cloud!'
            : 'No active subscription found for this account.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openTerms() {
    // TODO: open in_app_browser to vedastro.ai/terms
    _showLinkComing('Terms of Service');
  }

  void _openPrivacy() {
    _showLinkComing('Privacy Policy');
  }

  void _openRefund() {
    _showLinkComing('Refund Policy');
  }

  void _showLinkComing(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name will open in browser (link to be configured)'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Shown when an admin/founder email opens the paywall.
  /// They get unlimited access automatically — no payment flow.
  Widget _buildAdminBypassScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        size: 18, color: AppColors.textMuted),
                  ),
                ),
              ),
              const Spacer(),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.gold.withValues(alpha: 0.3),
                      AppColors.gold.withValues(alpha: 0.05),
                    ],
                  ),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.workspace_premium,
                    color: AppColors.goldLight, size: 48),
              ).animate().fadeIn(duration: 400.ms).scale(
                  begin: const Offset(0.85, 0.85),
                  end: const Offset(1, 1),
                  duration: 400.ms),
              const SizedBox(height: 24),
              const Text(
                "You're a Moksha admin",
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 12),
              Text(
                'Unlimited access — no payment needed.\n'
                'Signed in as ${AuthService.userEmail}.',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    _adminPerk('Unlimited chats'),
                    _adminPerk('Unlimited palm readings'),
                    _adminPerk('All horoscope features'),
                    _adminPerk('Unlimited family profiles'),
                    _adminPerk('Bypass all paywalls forever'),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms).slideY(
                  begin: 0.05, end: 0, duration: 400.ms, delay: 400.ms),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purpleAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Continue using app',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 500.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _adminPerk(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle,
              color: AppColors.goldLight, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
