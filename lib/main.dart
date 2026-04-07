// VedAstro AI - Vedic Astrology Platform
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'services/storage_service.dart';
import 'services/auth_service.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize persistent storage
  await StorageService.init();

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
      home: _getStartScreen(),
    );
  }

  /// Determine the initial screen based on app state
  Widget _getStartScreen() {
    // First time user -> Onboarding
    if (!StorageService.isOnboardingComplete) {
      return const OnboardingScreen();
    }

    // Check Firebase auth state first, then fall back to local
    if (AuthService.isLoggedIn) {
      return const HomeScreen();
    }

    // Not logged in -> Login
    if (!StorageService.isLoggedIn) {
      return const LoginScreen();
    }

    // Local login exists but no Firebase (offline user)
    return const HomeScreen();
  }
}
