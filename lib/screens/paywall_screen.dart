import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/subscription_plan.dart';
import '../providers/providers.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../services/storage_service.dart';
import '../widgets/autopay_disclosure.dart';

/// Paywall with three plans: Trial (₹1 -> ₹99/mo), Standard (₹199/mo),
/// Premium (₹499/mo).
///
/// COMPLIANCE: This screen is designed to be 100% safe under India CCPA
/// dark-pattern guidelines:
///  - All recurring charges shown in BOLD before purchase via AutopayDisclosure
///  - User must explicitly tick "I understand" checkbox to enable Subscribe
///  - Cancel-anytime messaging on every plan
///  - "Restore" link for users who subscribed previously
///
/// The actual Razorpay subscription flow is wired up in PaymentService.
/// This screen only handles plan selection + disclosure consent.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  /// Default selection — Trial is shown first as the strongest hook.
  SubscriptionPlan _selectedPlan = SubscriptionPlan.trial;
  bool _autopayAcknowledged = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    PaymentService.init();
  }

  @override
  void dispose() {
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
                  const Expanded(
                    child: Text(
                      'Unlock VedAstro AI',
                      style: TextStyle(
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pick the plan that suits your journey',
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ─── Scrollable plan list + disclosure ─────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _planCard(
                      plan: SubscriptionPlan.trial,
                      badge: 'TRY FOR ₹1',
                      badgeColor: AppColors.goldLight,
                    ).animate().fadeIn(delay: 100.ms).slideY(
                          begin: 0.05,
                          end: 0,
                          duration: 400.ms,
                          delay: 100.ms,
                        ),
                    const SizedBox(height: 12),
                    _planCard(
                      plan: SubscriptionPlan.standard,
                    ).animate().fadeIn(delay: 200.ms).slideY(
                          begin: 0.05,
                          end: 0,
                          duration: 400.ms,
                          delay: 200.ms,
                        ),
                    const SizedBox(height: 12),
                    _planCard(
                      plan: SubscriptionPlan.premium,
                      badge: 'BEST VALUE',
                      badgeColor: AppColors.purpleLight,
                    ).animate().fadeIn(delay: 300.ms).slideY(
                          begin: 0.05,
                          end: 0,
                          duration: 400.ms,
                          delay: 300.ms,
                        ),

                    const SizedBox(height: 20),

                    // ─── COMPLIANCE: bold autopay disclosure ──
                    AutopayDisclosure(
                      plan: _selectedPlan,
                      acknowledged: _autopayAcknowledged,
                      onAcknowledgedChanged: (v) =>
                          setState(() => _autopayAcknowledged = v),
                    ).animate().fadeIn(delay: 400.ms),

                    const SizedBox(height: 16),

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
                    onPressed: (_canSubscribe() && !_isProcessing)
                        ? _handleSubscribe
                        : null,
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
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _canSubscribe()
                                  ? Colors.white
                                  : AppColors.textMuted,
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
      onTap: () => setState(() {
        _selectedPlan = plan;
        // Re-tick required if user switches plans (different terms).
        _autopayAcknowledged = false;
      }),
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

  // ─── Action handlers ──────────────────────────────────────────

  bool _canSubscribe() => _autopayAcknowledged;

  String _subscribeButtonLabel() {
    if (!_autopayAcknowledged) return 'Tick the box above to continue';
    switch (_selectedPlan) {
      case SubscriptionPlan.trial:
        return 'Pay ₹1 — Start 7-day Trial';
      case SubscriptionPlan.standard:
        return 'Subscribe — ₹199/month';
      case SubscriptionPlan.premium:
        return 'Subscribe — ₹499/month';
      case SubscriptionPlan.free:
        return '';
    }
  }

  /// Calls server to create a Razorpay subscription, opens Razorpay's
  /// payment sheet, and updates premium status on success.
  void _handleSubscribe() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    await PaymentService.openSubscriptionCheckout(
      plan: _selectedPlan,
      onSuccess: (paymentId, planId) {
        if (!mounted) return;
        setState(() => _isProcessing = false);

        // Reflect the new premium state in Riverpod immediately so the
        // home screen / chat / paywall close-state pick it up.
        ref.read(isPremiumProvider.notifier).state =
            StorageService.isPremium;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.workspace_premium,
                    color: AppColors.goldLight, size: 20),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                        'Premium activated! Enjoy your subscription.')),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.pop(context);
      },
      onFailure: (message) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      },
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
                "You're a VedAstro admin",
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
