import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../widgets/moksha_wordmark_image.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'user_details_screen.dart';

/// Plays right after the native splash. Holds the Om-mandala in place,
/// then fades + shimmers in the "moksha" wordmark and tagline. After ~2.5s
/// it routes to the right starting screen (onboarding / login / home / etc).
class AnimatedSplashScreen extends ConsumerStatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  ConsumerState<AnimatedSplashScreen> createState() =>
      _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends ConsumerState<AnimatedSplashScreen> {
  @override
  void initState() {
    super.initState();
    _scheduleRoute();
  }

  Future<void> _scheduleRoute() async {
    // Total intro: logo settle (200ms) + wordmark reveal (800ms) +
    // tagline reveal (700ms) + breathing pause (800ms) ≈ 2500ms.
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    final next = _resolveStartScreen();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  Widget _resolveStartScreen() {
    if (!StorageService.isOnboardingComplete) return const OnboardingScreen();
    if (!AuthService.isLoggedIn && !StorageService.isLoggedIn) {
      return const LoginScreen();
    }
    if (!StorageService.hasProfile) {
      return const UserDetailsScreen(fromOnboarding: true);
    }
    return const HomeScreen();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ─── Om-mandala logo ─────────────────────────────────
              // Same image used for the native splash → no flicker
              // when the framework hands off to this screen.
              Container(
                width: 160,
                height: 160,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/icon/app_splash_logo.png',
                  fit: BoxFit.cover,
                ),
              )
                  .animate()
                  .scaleXY(
                    begin: 0.95,
                    end: 1.0,
                    duration: 600.ms,
                    curve: Curves.easeOutBack,
                  )
                  .then(delay: 200.ms)
                  // Subtle breathing glow that stays through the route.
                  .shimmer(
                    duration: 1800.ms,
                    color: AppColors.goldLight.withOpacity(0.35),
                  ),

              const SizedBox(height: 18),

              // ─── moksha wordmark + tagline (single asset) ───────
              // Same widget the home screen uses, so the brand
              // continuity from splash → home reads as a single
              // continuous shot. The asset bakes the wordmark and
              // tagline together; cropped + colour-inverted to read
              // on the dark cosmic background.
              const MokshaWordmarkImage(widthFactor: 0.78)
                  .animate()
                  .fadeIn(duration: 800.ms, delay: 400.ms)
                  .slideY(
                    begin: 0.3,
                    end: 0,
                    duration: 800.ms,
                    delay: 400.ms,
                    curve: Curves.easeOutCubic,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
