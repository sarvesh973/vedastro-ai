import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/subscription_plan.dart';
import 'autopay_disclosure.dart';

/// Shows the autopay disclosure as a modal bottom sheet (popup) instead of
/// inline on the paywall.
///
/// Returns `true` if the user ticked the consent checkbox AND tapped
/// "Confirm & Pay" — i.e. ready to open Razorpay's payment sheet.
/// Returns `false` if the user cancels or dismisses (taps outside / back).
///
/// This is the legal "informed consent" gate before any subscription
/// payment. The Confirm button stays disabled until the checkbox is ticked.
Future<bool> showAutopayConfirmSheet({
  required BuildContext context,
  required SubscriptionPlan plan,
}) async {
  if (plan == SubscriptionPlan.free) return true; // no charge, no popup

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    isDismissible: true,
    enableDrag: true,
    builder: (sheetCtx) => _AutopayConfirmContent(plan: plan),
  );

  return result ?? false;
}

class _AutopayConfirmContent extends StatefulWidget {
  final SubscriptionPlan plan;
  const _AutopayConfirmContent({required this.plan});

  @override
  State<_AutopayConfirmContent> createState() => _AutopayConfirmContentState();
}

class _AutopayConfirmContentState extends State<_AutopayConfirmContent> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.88;

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── Drag handle ──────────────────────────────
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ─── Title row ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Confirm Subscription',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close,
                        color: AppColors.textMuted, size: 22),
                  ),
                ],
              ),
            ),

            Container(height: 1, color: AppColors.divider),

            // ─── Scrollable disclosure ────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: AutopayDisclosure(
                  plan: widget.plan,
                  acknowledged: _acknowledged,
                  onAcknowledgedChanged: (v) =>
                      setState(() => _acknowledged = v),
                ),
              ),
            ),

            Container(height: 1, color: AppColors.divider),

            // ─── Action buttons (sticky bottom) ────────────
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(
                                color: AppColors.divider, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _acknowledged
                              ? () => Navigator.of(context).pop(true)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.purpleAccent,
                            disabledBackgroundColor:
                                AppColors.surfaceLight,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _confirmButtonLabel(),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _acknowledged
                                  ? Colors.white
                                  : AppColors.textMuted,
                            ),
                          ),
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
    );
  }

  String _confirmButtonLabel() {
    if (!_acknowledged) return 'Tick above to continue';
    switch (widget.plan) {
      case SubscriptionPlan.trial:
        return 'Start Free Trial';
      case SubscriptionPlan.standard:
        return 'Subscribe — ₹199';
      case SubscriptionPlan.premium:
        return 'Subscribe — ₹499';
      case SubscriptionPlan.free:
        return '';
    }
  }
}
