import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/subscription_plan.dart';
import '../models/subscription_status.dart';
import '../providers/providers.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/payment_service.dart';
import '../services/storage_service.dart';
import 'paywall_screen.dart';

/// Settings → Subscription management screen.
///
/// Shows the user's current subscription state and lets them cancel.
/// One-tap cancel is REQUIRED by Google Play subscription policy + India
/// CCPA dark-pattern guidelines — without this, app submissions are
/// rejected.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() =>
      _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _isCancelling = false;

  @override
  Widget build(BuildContext context) {
    final isAdmin = AuthService.isAdmin;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Subscription'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isAdmin)
              _buildAdminCard()
            else
              // Live subscription state from Firestore. Stream means the
              // screen updates the moment a webhook lands (paid/refunded/
              // cancelled) without the user having to refresh.
              StreamBuilder<SubscriptionStatus>(
                stream: FirestoreService.subscriptionStream(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData) {
                    return _buildLoadingCard();
                  }
                  final sub = snap.data ?? SubscriptionStatus.free;
                  if (sub.isActive) {
                    return _buildActiveCard(sub);
                  }
                  // Edge case: app marked user premium locally (e.g. just
                  // paid, webhook hasn't landed yet OR they're on an old
                  // build that didn't sync). Don't show "No subscription"
                  // — show a fallback that lets them contact support.
                  if (StorageService.isPremium) {
                    return _buildPremiumNoRecordCard();
                  }
                  return _buildNoSubscriptionCard();
                },
              ),

            const SizedBox(height: 28),

            // Always show — answers common cancellation questions
            _buildFAQ(),
          ],
        ),
      ),
    );
  }

  /// Shown when the app thinks the user is premium (local cache) but the
  /// Firestore subscription record isn't there yet. Could be:
  ///  - Just-completed payment, webhook still in flight (~1-5 sec)
  ///  - Admin user on an old account who upgraded via legacy path
  ///  - Webhook delivery failure (rare but possible)
  /// Either way, don't show "No subscription" — explain + offer support.
  Widget _buildPremiumNoRecordCard() {
    // Try to recover the plan the user actually purchased from local
    // storage — set immediately on Razorpay success. Without this we'd
    // hardcode "Premium Active" which is wrong for Trial / Standard
    // buyers and hides the upgrade path entirely (the original bug).
    //
    // Legacy users (purchased before this field existed) won't have
    // lastPurchasedPlan set. For them we keep the neutral "Subscription
    // Active" headline and no upgrade tap — the webhook-driven Firestore
    // record will populate the real plan name on next launch / pull.
    final localPlanId = StorageService.lastPurchasedPlan;
    final localPlan = localPlanId == null
        ? null
        : SubscriptionPlanInfo.fromId(localPlanId);
    final headline = (localPlan == null || localPlan == SubscriptionPlan.free)
        ? 'Subscription Active'
        : '${localPlan.displayName} — Active';
    final upgradeOptions = localPlan?.upgradeOptions ?? const [];
    final canUpgrade = upgradeOptions.isNotEmpty;

    final cardBody = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium,
                  color: AppColors.goldLight, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (canUpgrade)
                const Icon(Icons.chevron_right,
                    color: AppColors.goldLight, size: 22),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            canUpgrade
                ? "Your subscription is active. We're still syncing details "
                    "— tap here to upgrade your plan, or pull to refresh in "
                    "a moment to see the cancel option."
                : "Your subscription is active. We're still syncing your "
                    "details — pull to refresh in a moment to see plan info "
                    "and the cancel option.",
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              "Need to cancel right now? Email support@vedastro.ai "
              "with your registered email and we'll cancel within "
              "24 hours.",
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  height: 1.5),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: canUpgrade ? () => _openUpgradePaywall(upgradeOptions) : null,
            borderRadius: BorderRadius.circular(16),
            child: cardBody,
          ),
        ).animate().fadeIn(duration: 400.ms),
      ],
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.purpleLight),
        ),
      ),
    );
  }

  Widget _buildActiveCard(SubscriptionStatus sub) {
    final df = DateFormat('d MMM yyyy');
    final isTrialing = sub.state == SubscriptionState.trialing;
    final isCancelled = sub.state == SubscriptionState.cancelledPending;
    final periodEnds = sub.currentPeriodEndsAt;
    final trialEnds = sub.trialEndsAt;

    String headlineLabel;
    String headlineSub;
    if (isTrialing) {
      headlineLabel = 'Free Trial — ${sub.trialDaysRemaining}d left';
      headlineSub = trialEnds != null
          ? 'First ₹99 charge on ${df.format(trialEnds)}'
          : 'Auto-renews ₹99/month after day 7';
    } else if (isCancelled) {
      headlineLabel = 'Cancelled — access until period end';
      headlineSub = periodEnds != null
          ? 'Premium ends on ${df.format(periodEnds)}'
          : 'Premium ends at the end of your current period';
    } else {
      headlineLabel = '${sub.plan.displayName} — Active';
      headlineSub = periodEnds != null
          ? 'Renews on ${df.format(periodEnds)} • ₹${sub.plan.recurringPaise ~/ 100}/mo'
          : '₹${sub.plan.recurringPaise ~/ 100}/month';
    }

    // Upgrades: only offered when there's a higher tier AND the sub isn't
    // already cancel-pending (we don't want to charge a new plan on top of
    // a winding-down one — they should let it lapse first, then resubscribe).
    final upgradeOptions = sub.plan.upgradeOptions;
    final canUpgrade = !isCancelled && upgradeOptions.isNotEmpty;

    final cardBody = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.18),
            AppColors.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withValues(alpha: 0.2),
                ),
                child: const Icon(Icons.workspace_premium,
                    color: AppColors.goldLight, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headlineLabel,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      headlineSub,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (canUpgrade)
                const Icon(Icons.chevron_right,
                    color: AppColors.goldLight, size: 22),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              isCancelled
                  ? "Your subscription is already cancelled. You'll keep "
                      "premium access until the end of your current paid "
                      "period, then automatically move to the Free plan."
                  : canUpgrade
                      ? "Tap to upgrade your plan. You can cancel anytime — "
                          "you'll keep your current plan's access until the "
                          "end of the paid period."
                      : "Manage your subscription below. You can cancel "
                          "anytime — you'll keep premium access until the end "
                          "of your current paid period.",
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: canUpgrade ? () => _openUpgradePaywall(upgradeOptions) : null,
            borderRadius: BorderRadius.circular(16),
            child: cardBody,
          ),
        )
            .animate()
            .fadeIn(duration: 400.ms)
            .slideY(begin: 0.05, end: 0, duration: 400.ms),

        const SizedBox(height: 16),

        // ─── Cancel button (the legal requirement) ─────────────
        // Hidden if subscription is already cancelled-pending — there's
        // nothing to cancel twice. Stays visible for trialing + active.
        if (!isCancelled)
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton.icon(
              onPressed: _isCancelling
                  ? null
                  : () => _confirmCancel(sub.razorpaySubscriptionId),
            icon: _isCancelling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.error),
                  )
                : const Icon(Icons.cancel_outlined,
                    color: AppColors.error, size: 20),
            label: Text(
              _isCancelling ? 'Cancelling…' : 'Cancel Subscription',
              style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: AppColors.error.withValues(alpha: 0.5),
                  width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoSubscriptionCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surfaceLight,
                    ),
                    child: const Icon(Icons.lock_outline,
                        color: AppColors.textMuted, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'No active subscription',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                "You're on the Free plan. Upgrade for unlimited chats, "
                "palm readings, and family profiles.",
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.purpleAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text(
              'View Plans',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.gold.withValues(alpha: 0.2),
          AppColors.surface,
        ]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        children: [
          const Icon(Icons.workspace_premium,
              color: AppColors.goldLight, size: 36),
          const SizedBox(height: 10),
          const Text(
            "Moksha Admin",
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Unlimited access — no subscription needed.\n${AuthService.userEmail ?? ''}",
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildFAQ() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'COMMON QUESTIONS',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          _faqItem(
            'Will I get a refund if I cancel?',
            "No. All payments are final and non-refundable. When you "
                "cancel, you keep access until the end of your current "
                "paid period — no future charges happen, but past "
                "charges are not returned.",
          ),
          _faqItem(
            'Can I cancel during my free trial?',
            "Yes — cancel anytime during the 7-day trial and you'll "
                "never be charged. The auto-debit only activates if you "
                "don't cancel before day 7. This is the safest way to "
                "explore the app.",
          ),
          _faqItem(
            'I was charged by mistake, what do I do?',
            "If you believe a charge is genuinely unauthorized (someone "
                "else used your card), contact your bank to dispute it. "
                "For all other cases, please cancel from this screen so "
                "no future debits happen — past charges are non-refundable.",
          ),
        ],
      ),
    );
  }

  Widget _faqItem(String q, String a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            a,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Upgrade flow ───────────────────────────────────────────────

  void _openUpgradePaywall(List<SubscriptionPlan> options) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaywallScreen(availablePlans: options),
      ),
    );
  }

  // ─── Cancel flow ────────────────────────────────────────────────

  void _confirmCancel(String? subscriptionId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Cancel subscription?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          "You'll keep premium access until the end of your current paid "
          "period. After that, you'll go back to the Free plan.\n\n"
          "Continue with cancellation?",
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Subscription',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executeCancel(subscriptionId);
            },
            child: const Text('Yes, Cancel',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _showSupportFallback() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        title: const Text("Couldn't find your subscription",
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          "We couldn't locate your subscription record automatically. "
          "Please email support@vedastro.ai with your registered email "
          "and we'll cancel within 24 hours.",
          style:
              TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(color: AppColors.purpleLight)),
          ),
        ],
      ),
    );
  }

  void _executeCancel(String? subscriptionId) async {
    setState(() => _isCancelling = true);

    // The subscription ID comes from Firestore (synced by webhook on
    // subscription.activated). If for some reason it's not yet present
    // (e.g. webhook hasn't fired), fall back to email-based contact.
    if (subscriptionId == null || subscriptionId.isEmpty) {
      setState(() => _isCancelling = false);
      _showSupportFallback();
      return;
    }

    final ok = await PaymentService.cancelSubscription(
      subscriptionId: subscriptionId,
    );

    if (!mounted) return;
    setState(() => _isCancelling = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Subscription cancelled. You'll keep access until period ends."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      // Fallback: tell the user how to cancel via support
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18)),
          title: const Text("Couldn't cancel automatically",
              style: TextStyle(color: AppColors.textPrimary)),
          content: const Text(
            "There was a problem reaching the cancellation service.\n\n"
            "Please email support@vedastro.ai with your registered email "
            "and we'll cancel your subscription within 24 hours so no "
            "further charges happen.",
            style:
                TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK',
                  style: TextStyle(color: AppColors.purpleLight)),
            ),
          ],
        ),
      );
    }
  }
}
