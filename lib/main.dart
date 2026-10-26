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
import 'services/notification_service.dart';
import 'utils/crash_breadcrumbs.dart';
import 'services/attribution_service.dart';
import 'services/ui_error_log.dart';
import 'screens/animated_splash_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/horoscope_screen.dart';
import 'screens/mulank_screen.dart';
import 'models/subscription_plan.dart';

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

    // ─── Crashlytics + UiErrorLog ────────────────────────────
    // Crashlytics catches Flutter framework errors AND native crashes
    // (disabled in debug so we don't spam it with dev crashes).
    // UiErrorLog captures the same details in-memory so admins can
    // inspect the actual exception + stack from inside the app (via
    // Settings → "View UI errors" or by tapping the error widget).
    if (!kDebugMode) {
      FlutterError.onError = (details) {
        UiErrorLog.record(details);
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };
      // PlatformDispatcher catches errors outside the Flutter framework
      // (e.g. async errors in plugins).
      PlatformDispatcher.instance.onError = (error, stack) {
        UiErrorLog.record(FlutterErrorDetails(
            exception: error, stack: stack, library: 'PlatformDispatcher'));
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } else {
      // In debug, send everything to console instead — still recorded.
      FlutterError.onError = (details) {
        UiErrorLog.record(details);
        FlutterError.presentError(details);
      };
    }
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

    // ─── Analytics ──────────────────────────────────────────
    // Tracks: signup, chat, palm, paywall, subscription events.
    // Never logs PII (name/email/birth/chat content).
    await Analytics.init();

    // Initialize persistent storage
    await StorageService.init();

    // Where this install came from. Must run before the first signup or
    // purchase event so those carry the source - the Play referrer is
    // install-scoped and read exactly once, so a late read means the
    // conversion that matters most is the one we cannot attribute.
    await AttributionService.init();
    Analytics.setAttribution(AttributionService.params);

    // ─── Local notifications ────────────────────────────────
    // Sets up channels, timezone data and the tap handler, and re-arms
    // the three daily reminders. Deliberately does NOT ask for the
    // POST_NOTIFICATIONS permission — that happens after the user's
    // first real reading, where the value is obvious. Awaited because
    // the tap handler has to be registered before the engine delivers a
    // notification that cold-started the app; it is local work (prefs +
    // tz data) and does not touch the network.
    await NotificationService.init();
    // One process-wide lifecycle observer: the re-engagement nudge is
    // about the whole visit, so it cannot live on a single screen.
    WidgetsBinding.instance.addObserver(NotificationLifecycleObserver());

    // Sync cloud data if user is logged in
    _syncCloudData();

    // Draw the app behind the status bar and navigation bar (edge-to-edge).
    // WITHOUT this, newer Flutter stable builds render an opaque black
    // status-bar strip — the app's starfield no longer bleeds under it,
    // so the top shows a black box and the usable screen shrinks. The
    // CI Flutter channel is 'stable' (auto-updating), so a Flutter bump
    // silently introduced this; explicitly opting into edgeToEdge makes
    // it correct on every Flutter version. Screens already use SafeArea,
    // so content stays clear of the bars while the background fills.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Set system UI overlay style for premium dark look. Both bars are
    // transparent so the app background shows through edge-to-edge.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
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
    UiErrorLog.record(FlutterErrorDetails(
        exception: error, stack: stack, library: 'Zone'));
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

    // Restore subscription state from Firestore.
    // Critical for re-installs: the user paid → webhook wrote subscription
    // to users/{uid}/subscription/current → they uninstall → re-install →
    // sign in same email → without this lookup they'd see "Free plan"
    // even though Firestore knows they're paid.
    // Read it on EVERY launch, not only when the local flag is false.
    //
    // The old shape short-circuited: a user whose local isPremium was
    // true and who had a plan tag never consulted Firestore again. So a
    // lapsed Pass, a cancellation, or a failed renewal was never noticed
    // — isPremium was effectively write-once, cleared only by signing
    // out. Settings kept saying "Subscription Active" to someone who was
    // not, and they could never be offered a win-back.
    final cloudSub = await FirestoreService.loadCurrentSubscription();

    if (cloudSub.isActive) {
      if (!StorageService.isPremium) {
        await StorageService.upgradeToPremium();
      }
      // Persist plan ID so the home banner / drawer can render the
      // specific tier (Trial / Standard / Premium) and offer the right
      // upgrade path. Without this the UI falls back to the generic
      // "Subscription Active" label and the upgrade tap is disabled.
      // Refreshed on every launch now, so an upgrade bought on another
      // device shows the correct tier here too.
      await StorageService.setLastPurchasedPlan(cloudSub.plan.id);
    } else if (cloudSub.resolved &&
        StorageService.isPremium &&
        !AuthService.isAdmin) {
      // Cloud was reachable and says there is no active subscription, so
      // the local flag is stale. Three guards, each load-bearing:
      //
      //   resolved  — a failed read also returns a free-looking status,
      //               and downgrading on that would strip premium from
      //               someone who just paid, every time their connection
      //               dropped.
      //   isPremium — nothing to do if the flag is already false.
      //   !isAdmin  — admins are granted premium a few lines above and
      //               have no subscription document to find, so without
      //               this they would be downgraded on every launch.
      await StorageService.downgradeToFree();
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
      title: 'Moksha',
      debugShowCheckedModeBanner: false,
      // Lets NotificationService route a notification tap without needing
      // a BuildContext it has no way to get.
      navigatorKey: NotificationService.navigatorKey,
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
        // Mirrors navigation into Crashlytics as a `screen` key plus a
        // breadcrumb trail. Crash reports previously arrived with no
        // indication of where the user was, which is a large part of why
        // the UTF-16 fatal needed several rounds to place.
        CrashBreadcrumbObserver(),
        // Tells "opened the app and read something" apart from "opened it
        // and left", which is what decides whether the re-engagement
        // nudge gets armed.
        EngagementObserver(),
      ],
      // Named routes exist solely as notification-tap targets — the rest
      // of the app navigates with MPageRoute and widget instances. The
      // payload strings in NotificationService map onto these three.
      routes: {
        NotificationService.routeHoroscope: (_) => const HoroscopeScreen(),
        NotificationService.routeChat: (_) => const ChatScreen(),
        NotificationService.routeMulank: (_) => const MulankScreen(),
      },
      // AnimatedSplashScreen runs once on launch — plays the wordmark
      // reveal, then routes to the right screen via _getStartScreen logic
      // (kept inside the splash widget itself).
      home: const AnimatedSplashScreen(),
      // Global error handling for UI
      builder: (context, child) {
        // Catch rendering errors gracefully. Every fire is recorded so
        // an admin can inspect the actual exception + stack from
        // Settings → "View UI errors", or by tapping the widget itself.
        ErrorWidget.builder = (FlutterErrorDetails details) {
          UiErrorLog.record(details);
          return _AppErrorWidget(details: details);
        };
        return child ?? const SizedBox();
      },
    );
  }

}

/// Replacement for the default "red screen of death". Shows the same
/// user-friendly "Something went wrong" message for regular users; for
/// admin sign-ins, becomes tappable and surfaces the actual exception
/// + stack in a copyable dialog so we can diagnose the failing widget.
class _AppErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  const _AppErrorWidget({required this.details});

  @override
  Widget build(BuildContext context) {
    final isAdmin = AuthService.isAdmin;
    final body = Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Something went wrong',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              isAdmin
                  ? 'Tap to view exception (admin)'
                  : 'Try restarting the app',
              style: TextStyle(
                color: isAdmin
                    ? AppColors.purpleLight
                    : AppColors.textMuted,
                fontSize: 13,
                fontWeight: isAdmin ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );

    if (!isAdmin) return body;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => _showDetails(context),
        child: body,
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final exception = details.exceptionAsString();
    final stack = details.stack?.toString() ?? '(no stack)';
    final library = details.library ?? 'unknown';
    final full = '[$library]\n$exception\n\n$stack';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bug_report_outlined,
                      color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Widget exception • $library',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded,
                        size: 18, color: AppColors.textMuted),
                    tooltip: 'Copy',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: full));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Copied to clipboard'),
                          backgroundColor: AppColors.purpleSoft,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: AppColors.textMuted),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const Divider(color: AppColors.divider, height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    full,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
