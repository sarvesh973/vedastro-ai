import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';
import '../services/storage_service.dart';

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
                    decoration: BoxDecoration(
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
                      AppColors.gold.withOpacity(0.3),
                      AppColors.gold.withOpacity(0.05),
                    ],
                  ),
                  border: Border.all(
                    color: AppColors.gold.withOpacity(0.4),
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
                'You\'ve used your free session.\nUpgrade for unlimited readings.',
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

              const Spacer(flex: 2),

              // Price card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.purpleAccent.withOpacity(0.2),
                      AppColors.purpleSoft.withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.purpleAccent.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'VedAstro Premium',
                      style: TextStyle(
                        color: AppColors.goldLight,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    RichText(
                      text: const TextSpan(
                        children: [
                          TextSpan(
                            text: '\$4.99',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: ' /month',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 700.ms),

              const SizedBox(height: 20),

              // Subscribe button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Simulate purchase for MVP
                    StorageService.upgradeToPremium();
                    ref.read(isPremiumProvider.notifier).state = true;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Premium activated! Enjoy unlimited access.'),
                        backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );

                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Start Premium',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 800.ms),

              const SizedBox(height: 16),

              // Restore
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Restore Purchase',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
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
            color: AppColors.purpleAccent.withOpacity(0.1),
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
