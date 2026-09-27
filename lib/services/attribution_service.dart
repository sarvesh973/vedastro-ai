import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

/// Where an install came from.
///
/// The chain is: an influencer posts `/get?src=<creator>`, the server logs the
/// tap and redirects to Play with `referrer=utm_source=<creator>`, Play stores
/// that string against the install, and this reads it back on first launch.
///
/// Without this, you can see that a creator drove installs but not whether any
/// of them subscribed — which is the only number worth paying a creator on.
///
/// What it cannot see, so nobody reads the numbers as complete:
///  * Delayed installs. Someone who taps the link, closes it, and searches the
///    Play Store two days later arrives with no referrer and counts as organic.
///    Link attribution always undercounts.
///  * Sideloads. Our own CI APKs carry no referrer at all.
///  * iOS. There is no iOS build, and this API is Android-only.
class AttributionService {
  static const _keySource = 'attr_source';
  static const _keyMedium = 'attr_medium';
  static const _keyCampaign = 'attr_campaign';
  static const _keyChecked = 'attr_checked';
  // Separate from _keyChecked on purpose: the referrer is read once and
  // cached even when the read fails, but a FAILED ping must retry on the
  // next launch. Sharing one flag would silently drop those installs.
  static const _keyReported = 'attr_reported';

  static SharedPreferences? _prefs;
  static String? _source;
  static String? _medium;
  static String? _campaign;

  /// utm_source — the creator or channel. 'organic' when we never saw one.
  static String get source => _source ?? 'organic';
  static String? get medium => _medium;
  static String? get campaign => _campaign;

  /// True when this install carries a referrer, i.e. it is genuinely
  /// attributable rather than assumed organic.
  static bool get isAttributed => _source != null && _source!.isNotEmpty;

  /// Read once per install and cache. Safe to call on every launch.
  ///
  /// Deliberately never throws: attribution is a marketing nicety and must
  /// never be able to break app startup. Every failure path leaves the user
  /// as 'organic' and moves on.
  static Future<void> init() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      _source = _prefs!.getString(_keySource);
      _medium = _prefs!.getString(_keyMedium);
      _campaign = _prefs!.getString(_keyCampaign);

      // Already resolved on a previous launch. The Play referrer is a
      // one-time, install-scoped value, so re-reading it gains nothing and
      // costs a platform channel round trip on every cold start.
      if (_prefs!.getBool(_keyChecked) == true) {
        // Referrer already resolved. Still retry the ping if it never got
        // through — a dead network on first launch must not lose the install.
        unawaited(_report());
        return;
      }
      if (!Platform.isAndroid) {
        await _prefs!.setBool(_keyChecked, true);
        return;
      }

      final details = await AndroidPlayInstallReferrer.installReferrer;
      final raw = details.installReferrer;
      if (raw != null && raw.isNotEmpty) {
        final parsed = _parse(raw);
        _source = parsed['utm_source'];
        _medium = parsed['utm_medium'];
        _campaign = parsed['utm_campaign'];
        if (_source != null && _source!.isNotEmpty) {
          await _prefs!.setString(_keySource, _source!);
        }
        if (_medium != null) await _prefs!.setString(_keyMedium, _medium!);
        if (_campaign != null) await _prefs!.setString(_keyCampaign, _campaign!);
      }
      await _prefs!.setBool(_keyChecked, true);
      unawaited(_report());
    } catch (_) {
      // Play Services missing, sideloaded build, API unavailable — all of
      // these are normal and none of them are worth surfacing to the user.
      try {
        _prefs?.setBool(_keyChecked, true);
      } catch (_) {}
    }
  }

  /// Tell the server this install exists, exactly once.
  ///
  /// The server counts taps on /get, and Play counts installs — but only
  /// inside Play Console. Without this, the dashboard can show that a link
  /// was tapped 400 times and never show how many of those became installs,
  /// and an install that never signs up stays invisible entirely.
  ///
  /// Organic installs report too, so installs and taps share a denominator.
  /// Deliberately NOT awaited by init(): main() awaits init() before runApp,
  /// so awaiting this would put a network round trip — up to the timeout — in
  /// front of the first frame. This is bookkeeping; it must never cost a user
  /// a slower cold start, and it must never surface an error.
  static Future<void> _report() async {
    try {
      if (_prefs?.getBool(_keyReported) == true) return;
      final res = await http
          .post(
            Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/install'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'source': source, if (_medium != null) 'medium': _medium}),
          )
          .timeout(const Duration(seconds: 6));
      // Only latch on success, so a 5xx or a timeout retries next launch.
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _prefs?.setBool(_keyReported, true);
      }
    } catch (_) {
      // Offline first launch, server asleep, DNS — all normal. Retry later.
    }
  }

  /// `utm_source=x&utm_medium=y` -> map. Values are sanitised the same way
  /// the server sanitises `?src=`, so a junk referrer cannot become a junk
  /// analytics dimension or a junk Firestore field.
  static Map<String, String> _parse(String raw) {
    final out = <String, String>{};
    for (final pair in raw.split('&')) {
      final i = pair.indexOf('=');
      if (i <= 0) continue;
      final k = pair.substring(0, i).trim().toLowerCase();
      final v = Uri.decodeComponent(pair.substring(i + 1))
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9_]'), '');
      if (v.isEmpty) continue;
      out[k] = v.length > 24 ? v.substring(0, 24) : v;
    }
    return out;
  }

  /// Attribution fields for an analytics event or a Firestore write.
  /// Always includes `source` so organic installs are countable too — a
  /// breakdown that only has attributed rows cannot be read as a share.
  static Map<String, String> get params => {
        'source': source,
        if (_medium != null) 'medium': _medium!,
        if (_campaign != null) 'campaign': _campaign!,
      };
}
