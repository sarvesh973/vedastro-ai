import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';

class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

              // Crown / Premium icon
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
                      price: '₹149',
                      period: '/month',
                      isPopular: false,
                      onTap: () => _handlePurchase(context, ref, 'monthly'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Yearly (popular)
                  Expanded(
                    child: _buildPriceCard(
                      context: context,
                      title: 'Yearly',
                      price: '₹999',
                      period: '/year',
                      isPopular: true,
                      savings: 'Save 44%',
                      onTap: () => _handlePurchase(context, ref, 'yearly'),
                    ),
                  ),
                ],
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 800.ms),

              const SizedBox(height: 20),

              // Subscribe button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _handlePurchase(context, ref, 'yearly'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  child: const Text(
                    'Start Premium — ₹999/year',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 900.ms),

              const SizedBox(height: 12),

              // Restore + Terms
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Restore Purchase',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
                  const Text('•', style: TextStyle(color: AppColors.textMuted)),
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

  void _handlePurchase(BuildContext context, WidgetRef ref, String plan) {
    // TODO: Integrate Razorpay here for real payments
    // For now, activate premium (simulated)
    StorageService.upgradeToPremium();
    ref.read(isPremiumProvider.notifier).state = true;

    // Sync to cloud
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
            Text('Premium activated! Enjoy unlimited access.'),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

    Navigator.pop(context);
  }

  Widget _buildPriceCard({
    required BuildContext context,
    required String title,
    required String price,
    required String period,
    required bool isPopular,
    String? savings,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: isPopular
              ? LinearGradient(
                  colors: [
                    AppColors.purpleAccent.withValues(alpha: 0.25),
                    AppColors.purpleSoft.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isPopular ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isPopular
                ? AppColors.gold.withValues(alpha: 0.5)
                : AppColors.divider,
            width: isPopular ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            if (isPopular && savings != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  savings,
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
                color: isPopular ? AppColors.goldLight : AppColors.textMuted,
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
                      color: isPopular ? AppColors.textPrimary : AppColors.textSecondary,
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
