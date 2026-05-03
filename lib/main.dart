// VedAstro AI - Vedic Astrology Platform
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'services/storage_service.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/analytics_service.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/user_details_screen.dart';

void main() async {
  // Wrap the entire app in a Zone so any uncaught async errors are
  // captured by Crashlytics. Without this, Future-based crashes are
  // invisible in production.
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // ─── Crashlytics ─────────────────────────────────────────
    // Catches Flutter framework errors AND native crashes. Disabled in
    // debug builds so we don't spam Crashlytics with dev test crashes.
    if (!kDebugMode) {
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      // PlatformDispatcher catches errors outside the Flutter framework
      // (e.g. async errors in plugins).
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } else {
      // In debug, send everything to console instead.
      FlutterError.onError = (details) => FlutterError.presentError(details);
    }
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

    // ─── Analytics ──────────────────────────────────────────
    // Tracks: signup, chat, palm, paywall, subscription events.
    // Never logs PII (name/email/birth/chat content).
    await Analytics.init();

    // Initialize persistent storage
    await StorageService.init();

    // Sync cloud data if user is logged in
    _syncCloudData();

    // Set system UI overlay style for premium dark look
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    // Lock to portrait for best experience
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    runApp(const ProviderScope(child: VedAstroApp()));
  }, (error, stack) {
    // Catches uncaught zone errors (anything not caught by FlutterError /
    // PlatformDispatcher above). Forwarded to Crashlytics in release.
    if (!kDebugMode) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } else {
      debugPrint('Uncaught zone error: $error\n$stack');
    }
  });
}

/// Background cloud sync (non-blocking)
void _syncCloudData() async {
  try {
    if (!AuthService.isLoggedIn) return;

    // Founder/admin auto-unlock on every app launch — defensive check in
    // case someone managed to skip the login_screen path (e.g. existing
    // session from before the admin list was added).
    if (AuthService.isAdmin && !StorageService.isPremium) {
      await StorageService.upgradeToPremium();
    }

    // Try to restore profile from cloud if local is empty
    if (!StorageService.hasProfile) {
      final cloudProfile = await FirestoreService.loadCloudProfile();
      if (cloudProfile != null) {
        await StorageService.saveProfile(cloudProfile);
      }
    }

    // Sync local usage stats to cloud
    FirestoreService.syncUsage(
      StorageService.chatQuestionsUsed,
      StorageService.palmReadingsUsed,
      StorageService.isPremium,
    );
  } catch (_) {
    // Non-critical — app works offline
  }
}

class VedAstroApp extends StatelessWidget {
  const VedAstroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VedAstro AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      locale: const Locale('en', 'IN'),
      supportedLocales: const [Locale('en', 'IN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Auto-track screen views (screen_view event) for funnel analysis
      navigatorObservers: [
        if (Analytics.observer != null) Analytics.observer!,
      ],
      home: _getStartScreen(),
      // Global error handling for UI
      builder: (context, child) {
        // Catch rendering errors gracefully
        ErrorWidget.builder = (FlutterErrorDetails details) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'Something went wrong',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try restarting the app',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        };
        return child ?? const SizedBox();
      },
    );
  }

  /// Determine the initial screen based on app state.
  /// Order: onboarding -> login -> profile -> home.
  /// Profile is now collected AFTER login so each authenticated user has
  /// their own isolated birth-details data tied to their Firebase UID.
  Widget _getStartScreen() {
    // First time user -> Onboarding (welcome slides)
    if (!StorageService.isOnboardingComplete) {
      return const OnboardingScreen();
    }

    // Not logged in (Firebase + no local fallback) -> Login
    if (!AuthService.isLoggedIn && !StorageService.isLoggedIn) {
      return const LoginScreen();
    }

    // Logged in but profile not yet entered for this account -> collect details
    // (e.g. brand-new email/phone signup, or fresh install on a new device
    //  before cloud profile finishes loading).
    if (!StorageService.hasProfile) {
      return const UserDetailsScreen(fromOnboarding: true);
    }

    // Logged in + profile exists -> Home
    return const HomeScreen();
  }
}
