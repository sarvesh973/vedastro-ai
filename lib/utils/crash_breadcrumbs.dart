import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/widgets.dart';

/// Crashlytics breadcrumbs and state keys.
///
/// The UTF-16 crash took three rounds of guessing partly because its
/// reports carried nothing: Crashlytics was wired for recordError() only,
/// with no log() or setCustomKey() anywhere in the app. A fatal arrived as
/// an obfuscated stack and a message, with no indication of which screen
/// the user was on or what text was being rendered.
///
/// These helpers exist so the NEXT unexplained crash arrives with context
/// attached. Everything here is best-effort and never throws: diagnostics
/// must not be able to cause the incident they are meant to explain.
///
/// PRIVACY: never pass user content. Pass shapes — lengths, counts,
/// booleans, enum-like source names. textShape() below exists so the
/// characteristics of a string can be recorded without the string.

/// Drop a timestamped line into the crash's Logs tab.
void breadcrumb(String message) {
  try {
    FirebaseCrashlytics.instance.log(message);
  } catch (_) {}
}

/// Set a key shown in the crash's Keys tab. Last write wins, so this is
/// for "where was the user" state rather than a timeline.
void crashKey(String key, Object? value) {
  try {
    FirebaseCrashlytics.instance.setCustomKey(key, value?.toString() ?? 'null');
  } catch (_) {}
}

/// Describes a string WITHOUT revealing it: length, how many non-BMP
/// characters it holds (those are the ones stored as surrogate pairs, and
/// the only ones that can be split), and whether it is currently
/// well-formed. Enough to identify a text-shaped cause; useless to anyone
/// trying to read the user's data.
String textShape(String? s) {
  if (s == null) return 'null';
  if (s.isEmpty) return 'empty';
  var nonBmp = 0;
  var lone = 0;
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    final isHigh = unit >= 0xD800 && unit <= 0xDBFF;
    final isLow = unit >= 0xDC00 && unit <= 0xDFFF;
    if (!isHigh && !isLow) continue;
    if (isHigh && i + 1 < s.length) {
      final next = s.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        nonBmp++;
        i++;
        continue;
      }
    }
    lone++;
  }
  return 'len=${s.length} nonBmp=$nonBmp lone=$lone';
}

/// Records navigation into the crash report: a `screen` key holding where
/// the user currently is, plus a breadcrumb trail of how they got there.
///
/// Register alongside the Analytics observer in MaterialApp. Relies on
/// MPageRoute naming its routes after the page widget's type.
class CrashBreadcrumbObserver extends NavigatorObserver {
  void _record(String action, Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return; // dialogs, sheets, barriers
    crashKey('screen', name);
    breadcrumb('nav $action $name');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('push', route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // After a pop the user is on the PREVIOUS route, not the popped one.
    _record('pop-to', previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _record('replace', newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
