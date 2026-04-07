import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../widgets/glow_button.dart';
import '../widgets/starfield_background.dart';
import 'user_details_screen.dart';
import 'palm_upload_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StarfieldBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Logo / Icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.purpleAccent.withOpacity(0.3),
                        AppColors.purpleAccent.withOpacity(0.05),
                      ],
                    ),
                    border: Border.all(
                      color: AppColors.purpleAccent.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: AppColors.goldLight,
                    size: 44,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 800.ms)
                    .scaleXY(begin: 0.8, end: 1.0, duration: 800.ms, curve: Curves.easeOut),

                const SizedBox(height: 32),

                // Title
                Text(
                  'VedAstro AI',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    letterSpacing: 1,
                    color: AppColors.textPrimary,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 600.ms, delay: 200.ms)
                    .slideY(begin: 0.2, end: 0, duration: 600.ms, delay: 200.ms),

                const SizedBox(height: 12),

                // Subtitle
                Text(
                  'Your personal Vedic astrologer',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 15,
                    letterSpacing: 0.3,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 600.ms, delay: 400.ms),

                const Spacer(flex: 2),

                // Astrology Chat Button
                GlowButton(
                  text: 'Start Astrology Chat',
                  icon: Icons.chat_bubble_outline_rounded,
                  onPressed: () {
                    Navigator.of(context).push(
                      _buildPageRoute(const UserDetailsScreen()),
                    );
                  },
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 600.ms)
                    .slideY(begin: 0.3, end: 0, duration: 500.ms, delay: 600.ms),

                const SizedBox(height: 16),

                // Palm Reading Button
                GlowButton(
                  text: 'Scan Your Palm',
                  icon: Icons.back_hand_outlined,
                  color: AppColors.purpleSoft,
                  onPressed: () {
                    Navigator.of(context).push(
                      _buildPageRoute(const PalmUploadScreen()),
                    );
                  },
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 800.ms)
                    .slideY(begin: 0.3, end: 0, duration: 500.ms, delay: 800.ms),

                const Spacer(flex: 3),

                // Bottom text
                Text(
                  'Based on Brihat Parashara Hora Shastra\n& Phaladeepika',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted.withOpacity(0.6),
                    fontSize: 11,
                    height: 1.5,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 600.ms, delay: 1000.ms),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PageRouteBuilder _buildPageRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 400),
    );
  }
}
