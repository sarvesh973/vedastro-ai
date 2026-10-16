import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../theme/app_theme.dart';
import '../utils/crash_breadcrumbs.dart';

/// Local notifications: reply-ready alerts, three daily reminders, and a
/// gentle re-engagement nudge.
///
/// Everything here is LOCAL — scheduled on the device, no server, no FCM
/// token registry. That covers all four cases we need and keeps the work
/// on one side of the wire. Server push stays an option later if we ever
/// want per-user targeting or campaign analytics, but it would be a lot of
/// infrastructure for reminders a phone can schedule by itself.
///
/// Three deliberate choices worth knowing:
///
/// 1. INEXACT scheduling. Daily reminders do not need to-the-second
///    delivery, and SCHEDULE_EXACT_ALARM drags in an extra Play Console
///    declaration and review. inexactAllowWhileIdle needs no permission
///    and still fires through Doze, typically within a few minutes.
///
/// 2. Permission is NOT requested on launch. A cold prompt is mostly
///    denied, and on Android the denial is sticky — the user has to go
///    into system settings to undo it. We ask after the user has had a
///    real reading, when the value is obvious.
///
/// 3. Everything is behind a user toggle that defaults ON but is one tap
///    to kill in Settings. Play policy expects it, and the app sits at
///    4.1 stars — nudges that feel spammy cost more than they return.
///
/// ANDROID ONLY, deliberately. [InitializationSettings] carries no
/// `iOS`/`macOS` entry because nothing ships there — the only CI workflow
/// is build-apk.yml. If iOS is ever released this needs
/// `DarwinInitializationSettings`, its own permission request
/// (`IOSFlutterLocalNotificationsPlugin.requestPermissions`), and
/// background-mode entitlements; without them it fails silently rather
/// than loudly, so it is called out here rather than left to be found.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Set as MaterialApp.navigatorKey so a notification tap can route.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static bool _ready = false;
  static SharedPreferences? _prefs;

  /// Has the user done anything meaningful since the app came to the
  /// foreground? Drives the re-engagement nudge, which is only armed when
  /// they open the app and leave again without engaging.
  static bool _engagedThisSession = false;

  // ─── Channels ───────────────────────────────────────────────
  // Separate channels so a user who finds the daily reminders noisy can
  // silence just those in system settings without losing reply alerts,
  // which are the ones they actually asked for.
  static const _chanReply = 'chat_reply';
  static const _chanDaily = 'daily_guidance';
  static const _chanNudge = 'reengagement';

  // Stable IDs: re-scheduling REPLACES rather than stacking duplicates.
  static const int idReply = 1;
  static const int idMorning = 100;
  static const int idEvening = 101;
  static const int idNight = 102;
  static const int idNudge = 200;

  static const _keyEnabled = 'notifications_enabled';
  static const _keyAsked = 'notifications_permission_asked';

  /// Route the app was cold-started into by a notification tap, consumed
  /// once by the splash screen. See [takePendingLaunchRoute].
  static String? _pendingLaunchRoute;

  /// Returns the cold-start route exactly once, then forgets it. The
  /// splash calls this after it has replaced itself with the real start
  /// screen, so the back button lands on Home rather than on the splash.
  static String? takePendingLaunchRoute() {
    final route = _pendingLaunchRoute;
    _pendingLaunchRoute = null;
    return route;
  }

  /// Payload values double as route hints — see [routeForPayload].
  static const payloadHoroscope = 'horoscope';
  static const payloadChat = 'chat';
  static const payloadMulank = 'mulank';

  // Route names live here, not as literals in main.dart's `routes` table,
  // so the tap handler and the route registration cannot drift apart. A
  // renamed route that only one of the two knows about produces a tap
  // that throws deep inside Navigator, which is a bad way to find out.
  static const routeHoroscope = '/horoscope';
  static const routeChat = '/chat';
  static const routeMulank = '/mulank';

  // ─── Setup ──────────────────────────────────────────────────

  static Future<void> init() async {
    if (_ready) return;
    try {
      _prefs = await SharedPreferences.getInstance();

      // zonedSchedule needs a real timezone, not UTC, or "08:00" lands at
      // the wrong local hour for everyone outside UTC — i.e. all our users.
      tzdata.initializeTimeZones();
      // flutter_timezone 5.x returns a TimezoneInfo; `identifier` is the
      // IANA name ("Asia/Kolkata") that the tz database is keyed on.
      final name = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(name));

      await _plugin.initialize(
        settings: const InitializationSettings(
          // A white-on-transparent silhouette, NOT the launcher icon:
          // Android tints status-bar icons flat, so a full-colour mandala
          // renders as a white square. See drawable/ic_notification.xml.
          // Bare entry name, not '@drawable/...': the plugin resolves this
          // with getIdentifier(name, "drawable", packageName), and the
          // bare form is the one that call signature is built for.
          android: AndroidInitializationSettings('ic_notification'),
        ),
        onDidReceiveNotificationResponse: _onTap,
      );

      // A tap that COLD-STARTS the app does not come through the callback
      // above — the process did not exist when it happened. It arrives
      // only here, and only on this one call. Without reading it, tapping
      // a reminder from a killed app just opens the home screen and the
      // notification appears to have done nothing.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _pendingLaunchRoute =
            routeForPayload(launch?.notificationResponse?.payload);
        breadcrumb('notifications: cold start route=$_pendingLaunchRoute');
      }
      _ready = true;
      breadcrumb('notifications: init ok tz=$name');

      // Re-arm the daily reminders on every launch. The IDs are stable so
      // this replaces rather than stacks, and it repairs a schedule lost
      // to a reboot the boot receiver missed, or shifted by the user
      // travelling into another timezone. Gated on the prompt having
      // happened so we never schedule for someone not yet asked.
      if (enabled && permissionAlreadyAsked) {
        await scheduleDailyReminders();
      }
    } catch (e) {
      // Never let notification setup break app start.
      breadcrumb('notifications: init failed ${e.runtimeType}');
      _ready = false;
    }
  }

  static bool get enabled => _prefs?.getBool(_keyEnabled) ?? true;

  static Future<void> setEnabled(bool value) async {
    await _prefs?.setBool(_keyEnabled, value);
    if (value) {
      await scheduleDailyReminders();
    } else {
      await cancelAll();
    }
  }

  static bool get permissionAlreadyAsked =>
      _prefs?.getBool(_keyAsked) ?? false;

  /// Ask for POST_NOTIFICATIONS. Call this AFTER the user has seen real
  /// value — never on first launch. Returns false if already asked, so
  /// callers can fire it freely without re-prompting.
  static Future<bool> requestPermissionOnce() async {
    if (!_ready || permissionAlreadyAsked) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? false;
      // Written only once the prompt has actually been shown. Setting it
      // first would burn our one chance if the call threw — we would have
      // recorded "asked" without ever asking, and never try again.
      await _prefs?.setBool(_keyAsked, true);
      breadcrumb('notifications: permission granted=$granted');
      if (granted) await scheduleDailyReminders();
      return granted;
    } catch (e) {
      breadcrumb('notifications: permission request failed ${e.runtimeType}');
      return false;
    }
  }

  // ─── Reply ready ────────────────────────────────────────────

  /// Fired when an answer lands while the user is elsewhere in the app or
  /// has backgrounded it. The reply itself is produced by a client-side
  /// HTTP call, so only the device knows when it finished — this cannot
  /// come from the server without a push round trip we do not need.
  static Future<void> showReplyReady({String? preview}) async {
    if (!_ready || !enabled) return;
    // Strip to one line: a multi-line preview renders badly in the shade.
    final body = (preview ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    await _show(
      id: idReply,
      channelId: _chanReply,
      channelName: 'Chat replies',
      channelDescription: 'When your reading is ready',
      title: 'Your reading is ready',
      body: body.isEmpty
          ? 'Tap to read what the chart says.'
          : (body.length > 120 ? '${body.substring(0, 120)}…' : body),
      payload: payloadChat,
    );
  }

  // ─── Daily reminders ────────────────────────────────────────

  /// Morning, evening and night. Copy is deliberately calm and specific:
  /// the Play listing promises "no fear-based manipulation", so these say
  /// what is waiting rather than inventing urgency about it.
  static Future<void> scheduleDailyReminders() async {
    if (!_ready || !enabled) return;
    await _scheduleDaily(
      id: idMorning,
      hour: 8,
      minute: 0,
      title: 'Today\'s horoscope is ready',
      body: 'See what the day\'s transits mean for you.',
      payload: payloadHoroscope,
    );
    await _scheduleDaily(
      id: idEvening,
      hour: 19,
      minute: 0,
      title: 'Something on your mind?',
      body: 'Ask about career, love or health — your chart is already loaded.',
      payload: payloadChat,
    );
    await _scheduleDaily(
      id: idNight,
      hour: 22,
      minute: 0,
      title: 'Your Mulank for today',
      body: 'A short Ank Jyotish read before the day closes.',
      payload: payloadMulank,
    );
    breadcrumb('notifications: daily reminders scheduled');
  }

  // ─── Re-engagement ──────────────────────────────────────────

  /// Scheduled when the app is backgrounded without the user doing
  /// anything meaningful, and cancelled the moment they do. Fires once,
  /// the next day — not minutes later, which reads as nagging.
  static Future<void> scheduleReengagement() async {
    if (!_ready || !enabled) return;
    // Rotate through the three things worth coming back for, keyed on the
    // day so a user who repeatedly opens-and-leaves does not get the same
    // sentence every time. Identical copy on repeat is what makes a nudge
    // read as automated nagging.
    final variant = _nudgeVariants[
        tz.TZDateTime.now(tz.local).day % _nudgeVariants.length];
    await _scheduleDaily(
      id: idNudge,
      hour: 11,
      minute: 0,
      title: variant.$1,
      body: variant.$2,
      payload: variant.$3,
      oneShot: true,
      // At least 6h out, so closing the app mid-morning does not produce
      // a nudge the same lunchtime.
      minGap: const Duration(hours: 6),
    );
  }

  /// (title, body, payload) for the re-engagement nudge.
  static const List<(String, String, String)> _nudgeVariants = [
    (
      'Your horoscope is waiting',
      'See what today\'s transits mean for you.',
      payloadHoroscope,
    ),
    (
      'Ask your chart one thing',
      'Career, love, money or health — it is already loaded.',
      payloadChat,
    ),
    (
      'Your Mulank for today',
      'A short Ank Jyotish read, two minutes.',
      payloadMulank,
    ),
  ];

  /// Call when the user does something that counts as engagement: opening
  /// a reading, asking a question — anything past the home screen. Kills
  /// a pending nudge and stops a new one being armed on background.
  static Future<void> markEngaged() async {
    if (_engagedThisSession) return; // first call per session is enough
    _engagedThisSession = true;
    await cancelReengagement();
  }

  /// App returned to the foreground: the nudge has done its job (or was
  /// never needed), and a fresh session starts un-engaged.
  static Future<void> onAppResumed() async {
    _engagedThisSession = false;
    await cancelReengagement();
  }

  /// App left the foreground. Arms the nudge only if the user never
  /// engaged — opening the app, looking at home and leaving is exactly
  /// the case this is for.
  static Future<void> onAppPaused() async {
    if (_engagedThisSession) return;
    await scheduleReengagement();
    breadcrumb('notifications: reengagement nudge armed');
  }

  static Future<void> cancelReengagement() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: idNudge);
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      breadcrumb('notifications: all cancelled');
    } catch (_) {}
  }

  // ─── Internals ──────────────────────────────────────────────

  static AndroidNotificationDetails _android(
    String id,
    String name,
    String description,
  ) =>
      AndroidNotificationDetails(
        id,
        name,
        channelDescription: description,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        // Tints the small icon in the expanded notification, so it reads
        // as Moksha rather than as a generic grey system alert.
        color: AppColors.purpleAccent,
        // Default importance, not high: these are reminders, not alarms.
        // High importance heads-up banners over whatever the user is doing
        // is how an app earns a one-star review.
      );

  static Future<void> _show({
    required int id,
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: _android(channelId, channelName, channelDescription),
        ),
        payload: payload,
      );
    } catch (e) {
      breadcrumb('notifications: show failed ${e.runtimeType}');
    }
  }

  static Future<void> _scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
    required String payload,
    bool oneShot = false,
    Duration minGap = Duration.zero,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: _nextInstanceOf(hour, minute, minGap: minGap),
        notificationDetails: NotificationDetails(
          android: _android(
            oneShot ? _chanNudge : _chanDaily,
            oneShot ? 'Reminders' : 'Daily guidance',
            oneShot
                ? 'Occasional nudges when you have not visited in a while'
                : 'Morning, evening and night reminders',
          ),
        ),
        // Inexact: no SCHEDULE_EXACT_ALARM permission, still fires in Doze.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // Repeat daily at this clock time, except the one-shot nudge.
        matchDateTimeComponents: oneShot ? null : DateTimeComponents.time,
        payload: payload,
      );
    } catch (e) {
      breadcrumb('notifications: schedule $id failed ${e.runtimeType}');
    }
  }

  /// The next occurrence of this local clock time. Scheduling a time that
  /// has already passed today would otherwise fire immediately.
  /// [minGap] pushes the result out a day when the next occurrence is too
  /// soon. The re-engagement nudge uses it: a reminder landing an hour
  /// after the user closed the app reads as nagging, not as help.
  static tz.TZDateTime _nextInstanceOf(
    int hour,
    int minute, {
    Duration minGap = Duration.zero,
  }) {
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (!when.isAfter(now.add(minGap))) {
      when = when.add(const Duration(days: 1));
    }
    return when;
  }

  static void _onTap(NotificationResponse response) {
    final route = routeForPayload(response.payload);
    breadcrumb('notifications: tapped payload=${response.payload}');
    if (route == null) return;
    // Named route rather than a widget, so this file does not need to
    // import every screen and create an import cycle.
    navigatorKey.currentState?.pushNamed(route);
  }

  /// Maps a notification payload onto a named route, or null for anything
  /// unrecognised — including null, which is what a notification posted by
  /// an older version of the app looks like after an upgrade.
  @visibleForTesting
  static String? routeForPayload(String? payload) {
    switch (payload) {
      case payloadHoroscope:
        return routeHoroscope;
      case payloadChat:
        return routeChat;
      case payloadMulank:
        return routeMulank;
      default:
        return null;
    }
  }
}

/// Bridges Flutter's app lifecycle into [NotificationService] so the
/// re-engagement nudge is armed on background and cleared on return.
///
/// Installed once in main.dart rather than per-screen: the nudge is about
/// the whole visit, so it has to survive whichever screen the user
/// happens to be on when they leave.
class NotificationLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        NotificationService.onAppResumed();
        break;
      case AppLifecycleState.paused:
        NotificationService.onAppPaused();
        break;
      // inactive/hidden fire on transient interruptions (a phone call, the
      // app switcher being half-open) and are not a real exit. detached is
      // too late to schedule anything.
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }
}

/// Marks engagement from navigation, so "opened the app and did nothing"
/// can be told apart from "opened the app and read something".
///
/// An allowlist, not a denylist: reaching Settings or the privacy policy
/// is not engaging with your chart, and counting it would silence the
/// nudge for exactly the users it is meant for. Route names come from
/// MPageRoute, which labels every route with its widget's type name.
class EngagementObserver extends NavigatorObserver {
  static const _engagingRoutes = <String>{
    'ChatScreen',
    'HoroscopeScreen',
    'MulankScreen',
    'KundliScreen',
    'CompatScreen',
    'PalmUploadScreen',
    'PalmResultScreen',
    'PalmChatScreen',
  };

  void _check(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null) return;
    // Named routes from a notification tap arrive as '/chat' etc.
    final bare = name.startsWith('/') ? name.substring(1) : name;
    if (_engagingRoutes.contains(name) ||
        _engagingRoutes.any((r) => r.toLowerCase() == '${bare.toLowerCase()}screen')) {
      NotificationService.markEngaged();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _check(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _check(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
