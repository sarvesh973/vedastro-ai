import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../config/api_config.dart';
import '../providers/providers.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String _selectedPlan = 'yearly';
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

  void _handlePurchase(String plan) {
    if (_isProcessing) return;

    // Check if Razorpay key is configured
    if (!ApiConfig.isRazorpayConfigured) {
      // Fallback: simulate payment for development
      _simulatePurchase(plan);
      return;
    }

    setState(() => _isProcessing = true);

    PaymentService.openCheckout(
      plan: plan,
      onSuccess: (paymentId, plan) {
        if (!mounted) return;
        setState(() => _isProcessing = false);

        // Update providers
        ref.read(isPremiumProvider.notifier).state = true;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.workspace_premium, color: AppColors.goldLight, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text('Premium activated! Enjoy unlimited access.')),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        Navigator.pop(context);
      },
      onFailure: (message) {
        if (!mounted) return;
        setState(() => _isProcessing = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      },
    );
  }

  /// Fallback for when Razorpay key isn't set (dev/testing)
  void _simulatePurchase(String plan) {
    StorageService.upgradeToPremium();
    ref.read(isPremiumProvider.notifier).state = true;

    final uid = AuthService.currentUser?.uid;
    if (uid != null) {
      FirestoreService.setPremium(uid, true);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.workspace_premium, color: AppColors.goldLight, size: 20),
            SizedBox(width: 10),
            Expanded(child: Text('Premium activated! (Test mode)')),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    Navigator.pop(context);
  }

  String get _displayPrice {
    final paise = _selectedPlan == 'yearly'
        ? ApiConfig.premiumPriceYearlyPaise
        : ApiConfig.premiumPriceMonthlyPaise;
    final rupees = paise / 100;
    if (rupees == rupees.toInt()) {
      return '\u20B9${rupees.toInt()}';
    }
    return '\u20B9${rupees.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // Close button
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
                    child: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                  ),
                ),
              ),

              const Spacer(flex: 1),

              // Crown icon
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.gold.withValues(alpha: 0.3),
                      AppColors.gold.withValues(alpha: 0.05),
                    ],
                  ),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  color: AppColors.goldLight,
                  size: 40,
                ),
              )
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .scaleXY(begin: 0.8, end: 1.0, duration: 600.ms),

              const SizedBox(height: 28),

              Text(
                'Unlock Full Access',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: AppColors.goldLight,
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 200.ms),

              const SizedBox(height: 12),

              Text(
                'You\'ve used your free sessions.\nUpgrade for unlimited readings.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 300.ms),

              const SizedBox(height: 40),

              // Features
              _buildFeatureRow(Icons.chat_bubble_outline, 'Unlimited astrology chat')
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 400.ms)
                  .slideX(begin: -0.1, end: 0, duration: 400.ms, delay: 400.ms),
              const SizedBox(height: 16),
              _buildFeatureRow(Icons.back_hand_outlined, 'Unlimited palm readings')
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 500.ms)
                  .slideX(begin: -0.1, end: 0, duration: 400.ms, delay: 500.ms),
              const SizedBox(height: 16),
              _buildFeatureRow(Icons.auto_awesome, 'Deeper, personalized insights')
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 600.ms)
                  .slideX(begin: -0.1, end: 0, duration: 400.ms, delay: 600.ms),
              const SizedBox(height: 16),
              _buildFeatureRow(Icons.cloud_sync_outlined, 'Cloud backup of all chats')
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 700.ms)
                  .slideX(begin: -0.1, end: 0, duration: 400.ms, delay: 700.ms),

              const Spacer(flex: 2),

              // Price cards
              Row(
                children: [
                  // Monthly
                  Expanded(
                    child: _buildPriceCard(
                      context: context,
                      title: 'Monthly',
                      price: '\u20B9${(ApiConfig.premiumPriceMonthlyPaise / 100).toInt()}',
                      period: '/month',
                      isSelected: _selectedPlan == 'monthly',
                      onTap: () => setState(() => _selectedPlan = 'monthly'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Yearly
                  Expanded(
                    child: _buildPriceCard(
                      context: context,
                      title: 'Yearly',
                      price: '\u20B9${(ApiConfig.premiumPriceYearlyPaise / 100).toInt()}',
                      period: '/year',
                      isSelected: _selectedPlan == 'yearly',
                      badge: 'BEST VALUE',
                      onTap: () => setState(() => _selectedPlan = 'yearly'),
                    ),
                  ),
                ],
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 800.ms),

              const SizedBox(height: 20),

              // Pay button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : () => _handlePurchase(_selectedPlan),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.background,
                    disabledBackgroundColor: AppColors.gold.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.background,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock_open_rounded, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Pay $_displayPrice & Unlock',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 900.ms),

              const SizedBox(height: 10),

              // Secure payment badge
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, size: 14, color: AppColors.textMuted.withValues(alpha: 0.5)),
                  const SizedBox(width: 6),
                  Text(
                    'Secured by Razorpay',
                    style: TextStyle(
                      color: AppColors.textMuted.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Restore + Terms
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () {
                      // Restore: check Firestore for premium status
                      _restorePurchase();
                    },
                    child: const Text(
                      'Restore Purchase',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
                  const Text('\u2022', style: TextStyle(color: AppColors.textMuted)),
                  TextButton(
                    onPressed: () {},
                    child: const Text(
                      'Terms',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _restorePurchase() async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please sign in to restore purchases.'),
          backgroundColor: AppColors.surfaceLight,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final usage = await FirestoreService.getUsageStats(uid);
    if (usage['isPremium'] == true) {
      await StorageService.upgradeToPremium();
      ref.read(isPremiumProvider.notifier).state = true;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.workspace_premium, color: AppColors.goldLight, size: 20),
                SizedBox(width: 10),
                Text('Premium restored successfully!'),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.pop(context);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No previous purchase found.'),
            backgroundColor: AppColors.surfaceLight,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Widget _buildPriceCard({
    required BuildContext context,
    required String title,
    required String price,
    required String period,
    required bool isSelected,
    String? badge,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    AppColors.purpleAccent.withValues(alpha: 0.25),
                    AppColors.purpleSoft.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? AppColors.gold.withValues(alpha: 0.6)
                : AppColors.divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: AppColors.goldLight,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? AppColors.goldLight : AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: price,
                    style: TextStyle(
                      color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: period,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 6),
              Icon(Icons.check_circle, color: AppColors.gold, size: 18),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.purpleAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.purpleAccent, size: 20),
        ),
        const SizedBox(width: 16),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}
