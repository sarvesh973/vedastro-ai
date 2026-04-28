import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/subscription_plan.dart';

/// COMPLIANCE-CRITICAL widget.
///
/// Shows the user EXACTLY what they're about to be charged, when, and how
/// to cancel. Required before any subscription checkout to comply with:
///   - India's CCPA dark-pattern guidelines (Nov 2023)
///   - RBI e-mandate transparency rules
///   - Google Play subscription policy
///
/// Do NOT remove fields, soften copy, or hide this behind a "?" icon.
/// The whole point is that users see the autopay schedule clearly BEFORE
/// they pay, not buried in fine print.
///
/// Visual hierarchy (top → bottom):
///   1. BOLD red header — impossible to miss
///   2. BIG price boxes for "Today" + "Day 7 / Monthly" amounts
///   3. List of cancellation rights
///   4. Required acknowledgement checkbox
class AutopayDisclosure extends StatelessWidget {
  final SubscriptionPlan plan;

  /// User must check this checkbox to enable the Pay button.
  /// Pass the bool state from parent + a setter callback.
  final bool acknowledged;
  final ValueChanged<bool> onAcknowledgedChanged;

  const AutopayDisclosure({
    super.key,
    required this.plan,
    required this.acknowledged,
    required this.onAcknowledgedChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (plan == SubscriptionPlan.free) return const SizedBox.shrink();

    final isTrial = plan == SubscriptionPlan.trial;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.6),
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── BOLD HEADER BAND ───────────────────────────────────
          // Solid color band — impossible to scroll past without seeing.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.gold.withValues(alpha: 0.18),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_rounded,
                    color: AppColors.goldLight, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'AUTO-PAY NOTICE',
                    style: TextStyle(
                      color: AppColors.goldLight,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── BIG PRICE BOXES (the main message) ──────────
                if (isTrial) ...[
                  _bigPriceBox(
                    label: 'TODAY',
                    amount: 'FREE',
                    subtitle: '7-day trial — no charge today',
                    accentColor: AppColors.success,
                  ),
                  const SizedBox(height: 10),
                  _arrowDown(),
                  const SizedBox(height: 10),
                  _bigPriceBox(
                    label: 'ON DAY 7',
                    amount: '₹99',
                    subtitle: 'Auto-debited from your bank',
                    accentColor: AppColors.goldLight,
                    isHighlighted: true,
                  ),
                  const SizedBox(height: 10),
                  _arrowDown(),
                  const SizedBox(height: 10),
                  _bigPriceBox(
                    label: 'EVERY MONTH AFTER',
                    amount: '₹99',
                    subtitle: 'Until you cancel',
                    accentColor: AppColors.purpleLight,
                  ),
                ] else ...[
                  _bigPriceBox(
                    label: 'CHARGED TODAY',
                    amount: '₹${plan.firstChargePaise ~/ 100}',
                    subtitle: '${plan.displayName} — first month',
                    accentColor: AppColors.success,
                  ),
                  const SizedBox(height: 10),
                  _arrowDown(),
                  const SizedBox(height: 10),
                  _bigPriceBox(
                    label: 'EVERY MONTH AFTER',
                    amount: '₹${plan.recurringPaise ~/ 100}',
                    subtitle: 'Auto-debited until you cancel',
                    accentColor: AppColors.goldLight,
                    isHighlighted: true,
                  ),
                ],

                const SizedBox(height: 18),
                Container(height: 1, color: AppColors.divider),
                const SizedBox(height: 14),

                // ─── Your rights ───────────────────────────────
                const Text(
                  'YOUR RIGHTS',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                _bulletPoint(
                  'Cancel anytime — Settings → Subscription → Cancel',
                ),
                _bulletPoint(
                  'SMS reminder 24 hours before every auto-debit',
                ),
                _bulletPoint(
                  'Bank requires OTP for the first ₹99 charge',
                ),
                if (isTrial)
                  _bulletPoint(
                    'Cancel during 7-day trial → ₹99 will NOT be charged',
                    bold: true,
                  ),
                _bulletPoint(
                  'Refund within 48 hours by emailing support',
                ),

                const SizedBox(height: 16),
                Container(height: 1, color: AppColors.divider),
                const SizedBox(height: 14),

                // ─── Required acknowledgement checkbox ─────────
                // The Pay button stays disabled until the user ticks this.
                // This is the legal "informed consent" gate.
                GestureDetector(
                  onTap: () => onAcknowledgedChanged(!acknowledged),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: acknowledged
                          ? AppColors.purpleAccent.withValues(alpha: 0.12)
                          : AppColors.surfaceLight.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: acknowledged
                            ? AppColors.purpleAccent.withValues(alpha: 0.6)
                            : AppColors.divider,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: acknowledged,
                            onChanged: (v) =>
                                onAcknowledgedChanged(v ?? false),
                            activeColor: AppColors.purpleAccent,
                            side: const BorderSide(
                                color: AppColors.textMuted, width: 1.5),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isTrial
                                ? "I understand: today's trial is FREE, and ₹99/month will auto-debit from my bank starting day 7 unless I cancel during the trial."
                                : "I understand: ₹${plan.recurringPaise ~/ 100} will be auto-debited every month from my bank until I cancel.",
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Big eye-catching price block. Used 2-3 times in the trial breakdown.
  Widget _bigPriceBox({
    required String label,
    required String amount,
    required String subtitle,
    required Color accentColor,
    bool isHighlighted = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHighlighted
            ? accentColor.withValues(alpha: 0.12)
            : AppColors.surfaceLight.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withValues(alpha: isHighlighted ? 0.6 : 0.25),
          width: isHighlighted ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              color: accentColor,
              fontSize: isHighlighted ? 28 : 22,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// Subtle down-arrow that visually links the price boxes (today → day 7 → ongoing).
  Widget _arrowDown() {
    return Center(
      child: Icon(
        Icons.arrow_downward_rounded,
        color: AppColors.textMuted.withValues(alpha: 0.5),
        size: 18,
      ),
    );
  }

  Widget _bulletPoint(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: bold
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
