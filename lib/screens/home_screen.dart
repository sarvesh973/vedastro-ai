import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../widgets/starfield_background.dart';
import '../services/storage_service.dart';
import '../providers/providers.dart';
import 'user_details_screen.dart';
import 'chat_screen.dart';
import 'palm_upload_screen.dart';
import 'kundli_screen.dart';
import 'settings_screen.dart';
import 'paywall_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);

    // Load saved profile on first build
    if (profile == null && StorageService.currentProfile != null) {
      Future.microtask(() {
        ref.read(userProfileProvider.notifier).state = StorageService.currentProfile;
      });
    }

    return Scaffold(
      body: StarfieldBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(height: 8),

                // Top bar with greeting and settings
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Greeting
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getGreeting(),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profile?.name.isNotEmpty == true
                              ? profile!.name
                              : 'Explorer',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    // Settings button
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          _buildPageRoute(const SettingsScreen()),
                        );
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceLight,
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: const Icon(
                          Icons.settings_outlined,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                )
                    .animate()
                    .fadeIn(duration: 500.ms),

                const Spacer(flex: 1),

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

                const SizedBox(height: 24),

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

                const SizedBox(height: 8),

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

                // Sun sign badge (if profile exists)
                if (profile != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.goldLight.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.goldLight.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wb_sunny_outlined, color: AppColors.goldLight, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          profile.sunSign,
                          style: const TextStyle(
                            color: AppColors.goldLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 500.ms),
                ],

                const Spacer(flex: 1),

                // Feature buttons grid
                Row(
                  children: [
                    Expanded(
                      child: _buildFeatureCard(
                        context: context,
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Astrology\nChat',
                        color: AppColors.purpleAccent,
                        delay: 600,
                        onTap: () {
                          if (profile != null) {
                            Navigator.of(context).push(
                              _buildPageRoute(const ChatScreen()),
                            );
                          } else {
                            Navigator.of(context).push(
                              _buildPageRoute(const UserDetailsScreen()),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFeatureCard(
                        context: context,
                        icon: Icons.back_hand_outlined,
                        label: 'Palm\nReading',
                        color: AppColors.purpleSoft,
                        delay: 700,
                        onTap: () {
                          Navigator.of(context).push(
                            _buildPageRoute(const PalmUploadScreen()),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _buildFeatureCard(
                        context: context,
                        icon: Icons.auto_awesome_mosaic_outlined,
                        label: 'Kundli\nChart',
                        color: AppColors.gold,
                        delay: 800,
                        onTap: () {
                          Navigator.of(context).push(
                            _buildPageRoute(const KundliScreen()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFeatureCard(
                        context: context,
                        icon: Icons.workspace_premium_outlined,
                        label: 'Go\nPremium',
                        color: const Color(0xFFD4A574),
                        delay: 900,
                        onTap: () {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder: (_, __, ___) => const PaywallScreen(),
                              transitionsBuilder: (_, animation, __, child) {
                                return SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 1),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                                  child: child,
                                );
                              },
                              transitionDuration: const Duration(milliseconds: 400),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const Spacer(flex: 2),

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

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Widget _buildFeatureCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required int delay,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.15),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 500.ms, delay: Duration(milliseconds: delay))
        .slideY(begin: 0.2, end: 0, duration: 500.ms, delay: Duration(milliseconds: delay));
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
