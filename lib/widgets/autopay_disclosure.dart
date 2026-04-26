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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.gold.withOpacity(0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline,
                  color: AppColors.goldLight, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Auto-renewal Notice',
                style: TextStyle(
                  color: AppColors.goldLight,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ─── Today's charge ─────────────────────────────────────
          _row(
            'Charged today',
            isTrial ? '₹1' : '₹${plan.firstChargePaise ~/ 100}',
            bold: true,
          ),

          if (isTrial) ...[
            const SizedBox(height: 8),
            _row(
              'After 7 days',
              '₹99/month — auto-debited',
              bold: true,
              highlight: true,
            ),
          ] else ...[
            const SizedBox(height: 8),
            _row(
              'Renews automatically',
              '₹${plan.recurringPaise ~/ 100} every month',
              bold: true,
            ),
          ],

          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),

          // ─── Cancellation rights ────────────────────────────────
          _bulletPoint(
            'You can cancel anytime in Settings → Subscription',
            icon: Icons.check_circle_outline,
            iconColor: AppColors.success,
          ),
          const SizedBox(height: 6),
          _bulletPoint(
            "We'll send an SMS 24 hours before each auto-debit",
            icon: Icons.check_circle_outline,
            iconColor: AppColors.success,
          ),
          const SizedBox(height: 6),
          _bulletPoint(
            'Your bank will require OTP for the first ₹$_recurringRupees charge',
            icon: Icons.check_circle_outline,
            iconColor: AppColors.success,
          ),
          if (isTrial) ...[
            const SizedBox(height: 6),
            _bulletPoint(
              "Cancel during trial = no ₹99 charge, ever",
              icon: Icons.check_circle_outline,
              iconColor: AppColors.success,
            ),
          ],

          const SizedBox(height: 16),

          // ─── Required acknowledgement checkbox ─────────────────
          // The Pay button stays disabled until the user ticks this.
          // This is the legal "informed consent" gate.
          GestureDetector(
            onTap: () => onAcknowledgedChanged(!acknowledged),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: acknowledged,
                    onChanged: (v) => onAcknowledgedChanged(v ?? false),
                    activeColor: AppColors.purpleAccent,
                    side: const BorderSide(
                        color: AppColors.textMuted, width: 1.5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isTrial
                        ? "I understand: ₹1 will be charged now, and ₹99/month will be auto-debited after 7 days unless I cancel."
                        : "I understand: ₹${plan.recurringPaise ~/ 100} will be auto-debited every month until I cancel.",
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
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

  String get _recurringRupees => (plan.recurringPaise ~/ 100).toString();

  Widget _row(String label, String value,
      {bool bold = false, bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            color: highlight ? AppColors.goldLight : AppColors.textPrimary,
            fontSize: bold ? 15 : 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _bulletPoint(String text,
      {required IconData icon, required Color iconColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
