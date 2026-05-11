import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/subscription_plan.dart';
import '../theme/app_theme.dart';

/// Full-screen "plan activated" sheet shown after a successful Razorpay
/// subscription. Replaces the previous toast-only success path.
///
/// Three jobs:
///  1. Tell the user EXACTLY what plan they just activated, in plan-tinted
///     branding (green for trial, purple for standard, gold for premium).
///  2. Remind them what they get — chats, palm readings, family profiles —
///     so the value is visible immediately.
///  3. Offer one-tap upgrade to higher plans. For premium (the highest),
///     the upgrade row is replaced with a "You have our highest plan"
///     line — no upsell.
class PlanActivatedSheet extends StatelessWidget {
  /// The plan that just got activated.
  final SubscriptionPlan activatedPlan;

  /// Called with the plan the user wants to upgrade to. Caller is
  /// responsible for closing this sheet and opening the paywall again
  /// preselected on that plan.
  final void Function(SubscriptionPlan upgradeTo) onUpgrade;

  /// Called when the user dismisses the sheet via the Continue button.
  final VoidCallback onContinue;

  const PlanActivatedSheet({
    super.key,
    required this.activatedPlan,
    required this.onUpgrade,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final tint = _tintFor(activatedPlan);
    final upgradeOptions = _upgradePathFrom(activatedPlan);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            children: [
              // Top close — small, not the primary action.
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: onContinue,
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

              const SizedBox(height: 4),

              // Hero badge — plan-tinted icon in a glowing radial.
              _HeroBadge(plan: activatedPlan, tint: tint)
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .scaleXY(begin: 0.85, end: 1.0, duration: 500.ms, curve: Curves.easeOutBack),

              const SizedBox(height: 24),

              // Title + subtitle.
              Text(
                _titleFor(activatedPlan),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

              const SizedBox(height: 8),

              Text(
                _subtitleFor(activatedPlan),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 300.ms),

              const SizedBox(height: 24),

              // What you get — features card. Plan-tinted border.
              _FeaturesCard(plan: activatedPlan, tint: tint)
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 400.ms)
                  .slideY(
                      begin: 0.05,
                      end: 0,
                      duration: 400.ms,
                      delay: 400.ms),

              const SizedBox(height: 20),

              // Upgrade row OR best-plan message.
              if (upgradeOptions.isEmpty)
                _BestPlanFooter(tint: tint)
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 600.ms)
              else
                _UpgradeOptions(
                  options: upgradeOptions,
                  onTap: onUpgrade,
                )
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 600.ms)
                    .slideY(
                        begin: 0.05,
                        end: 0,
                        duration: 400.ms,
                        delay: 600.ms),

              const Spacer(),

              // Continue — primary CTA, plan-tinted.
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tint,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 700.ms),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Plan-specific copy ─────────────────────────────────────────────

  static String _titleFor(SubscriptionPlan p) {
    switch (p) {
      case SubscriptionPlan.trial:
        return '7-Day Free Trial Activated!';
      case SubscriptionPlan.standard:
        return 'Standard Plan Activated!';
      case SubscriptionPlan.premium:
        return 'Premium Plan Activated!';
      case SubscriptionPlan.free:
        return 'Free plan';
    }
  }

  static String _subtitleFor(SubscriptionPlan p) {
    switch (p) {
      case SubscriptionPlan.trial:
        return 'Free for 7 days, then ₹99/month auto-renew.\nCancel anytime in Settings.';
      case SubscriptionPlan.standard:
        return '₹199/month — auto-renews monthly. Cancel anytime in Settings.';
      case SubscriptionPlan.premium:
        return '₹499/month — the full Moksha experience. Cancel anytime in Settings.';
      case SubscriptionPlan.free:
        return '';
    }
  }

  static Color _tintFor(SubscriptionPlan p) {
    switch (p) {
      case SubscriptionPlan.trial:
        return AppColors.success;
      case SubscriptionPlan.standard:
        return AppColors.purpleAccent;
      case SubscriptionPlan.premium:
        return AppColors.goldLight;
      case SubscriptionPlan.free:
        return AppColors.textMuted;
    }
  }

  /// Higher plans the user can upgrade to from their current plan.
  /// Empty for premium — that's the highest, no upsell shown.
  static List<SubscriptionPlan> _upgradePathFrom(SubscriptionPlan p) {
    switch (p) {
      case SubscriptionPlan.trial:
        return const [SubscriptionPlan.standard, SubscriptionPlan.premium];
      case SubscriptionPlan.standard:
        return const [SubscriptionPlan.premium];
      case SubscriptionPlan.premium:
      case SubscriptionPlan.free:
        return const [];
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Internal widgets
// ═══════════════════════════════════════════════════════════════════════

class _HeroBadge extends StatelessWidget {
  final SubscriptionPlan plan;
  final Color tint;

  const _HeroBadge({required this.plan, required this.tint});

  @override
  Widget build(BuildContext context) {
    final iconData = _iconFor(plan);
    return Stack(
      alignment: Alignment.center,
      children: [
        // Soft glow halo.
        Container(
          width: 144,
          height: 144,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                tint.withValues(alpha: 0.30),
                tint.withValues(alpha: 0.05),
                tint.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
        ),
        // Icon ring.
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surface,
            border: Border.all(color: tint.withValues(alpha: 0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: tint.withValues(alpha: 0.15),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(iconData, color: tint, size: 44),
        ),
        // Tiny sparkle bursts — plan-tinted.
        Positioned(
          top: 8,
          right: 28,
          child: Icon(Icons.auto_awesome,
              color: tint.withValues(alpha: 0.85), size: 14)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(duration: 700.ms)
              .scaleXY(begin: 0.6, end: 1.2, duration: 1100.ms),
        ),
        Positioned(
          bottom: 12,
          left: 24,
          child: Icon(Icons.auto_awesome,
              color: tint.withValues(alpha: 0.6), size: 10)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(delay: 400.ms, duration: 700.ms)
              .scaleXY(begin: 0.6, end: 1.2, duration: 900.ms),
        ),
      ],
    );
  }

  static IconData _iconFor(SubscriptionPlan p) {
    switch (p) {
      case SubscriptionPlan.trial:
        return Icons.local_fire_department_rounded;
      case SubscriptionPlan.standard:
        return Icons.workspace_premium;
      case SubscriptionPlan.premium:
        return Icons.diamond_rounded;
      case SubscriptionPlan.free:
        return Icons.person_outline;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────

class _FeaturesCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final Color tint;

  const _FeaturesCard({required this.plan, required this.tint});

  @override
  Widget build(BuildContext context) {
    final lines = _featureLinesFor(plan);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tint.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: tint, size: 18),
              const SizedBox(width: 8),
              Text(
                'Included in your plan',
                style: TextStyle(
                  color: tint,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...lines.map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check, color: tint, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  /// Concrete feature lines per plan. Concrete numbers > marketing fluff —
  /// users want to know what they actually got.
  static List<String> _featureLinesFor(SubscriptionPlan p) {
    switch (p) {
      case SubscriptionPlan.trial:
        return const [
          '10 AI chats during the 7-day trial',
          '2 palm readings',
          'Daily / weekly / monthly horoscope',
          'Full Kundli chart with D9 + D10',
          'No charge today — cancel before day 7 to skip ₹99',
        ];
      case SubscriptionPlan.standard:
        return const [
          '30 AI chats per month',
          '5 palm readings per month',
          '3 family profiles',
          'Daily / weekly / monthly horoscope',
          'Full Kundli with D9 + D10 + Dasha',
        ];
      case SubscriptionPlan.premium:
        return const [
          'Unlimited AI chats',
          'Unlimited palm readings',
          'Unlimited family profiles',
          'Detailed predictions + remedies',
          'Priority response speed',
          'Yearly forecast PDF',
        ];
      case SubscriptionPlan.free:
        return const ['1 free chat', 'Daily horoscope'];
    }
  }
}

// ─────────────────────────────────────────────────────────────────────

class _UpgradeOptions extends StatelessWidget {
  final List<SubscriptionPlan> options;
  final void Function(SubscriptionPlan) onTap;

  const _UpgradeOptions({required this.options, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'WANT MORE?',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...options.map((plan) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _UpgradeRow(plan: plan, onTap: () => onTap(plan)),
            )),
      ],
    );
  }
}

class _UpgradeRow extends StatelessWidget {
  final SubscriptionPlan plan;
  final VoidCallback onTap;

  const _UpgradeRow({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tint = PlanActivatedSheet._tintFor(plan);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: tint.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.15),
              ),
              child: Icon(_iconFor(plan), color: tint, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upgrade to ${plan.displayName}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    plan.priceLabel,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: tint.withValues(alpha: 0.7), size: 14),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(SubscriptionPlan p) {
    switch (p) {
      case SubscriptionPlan.standard:
        return Icons.workspace_premium;
      case SubscriptionPlan.premium:
        return Icons.diamond_rounded;
      default:
        return Icons.star;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────

class _BestPlanFooter extends StatelessWidget {
  final Color tint;
  const _BestPlanFooter({required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tint.withValues(alpha: 0.18),
            tint.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: tint, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You have our highest plan — enjoy unlimited Moksha.',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
