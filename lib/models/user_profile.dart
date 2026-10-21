import 'dart:convert';

import '../utils/crash_breadcrumbs.dart';
import '../utils/text_safety.dart';

/// Records the stored name's shape (never its content) before cleaning,
/// so a crash report shows whether the profile text was the culprit.
String _named(String? raw) {
  crashKey('profile_name_shape', textShape(raw));
  return safeText(raw, context: 'profile.name');
}

class UserProfile {
  final String name;
  final DateTime dateOfBirth;
  final String? timeOfBirth;
  final String placeOfBirth;

  /// Coordinates of [placeOfBirth], captured when the user picked the
  /// place out of the autocomplete rather than typing it.
  ///
  /// NULLABLE, and permanently so. Every profile already on a device or
  /// in Firestore was saved before these fields existed, and the app is
  /// live — making them required would stop those profiles loading at
  /// all. Absent coordinates mean "send the place as text and let the
  /// server geocode it", which is what every request did before.
  ///
  /// Why they are worth carrying: the server derives the birthplace
  /// TIMEZONE from lat/lon via geo-tz, and the timezone is what converts
  /// a local birth time to UTC. Resolve the wrong "Patna" and the whole
  /// chart shifts — the ascendant can move several signs.
  final double? birthLat;
  final double? birthLon;

  /// Two-letter ISO country code from the same pick, lowercase. Not used
  /// for calculation; kept because it is the cheapest way to tell two
  /// identically-named towns apart when looking at stored data.
  final String? birthCountryCode;

  const UserProfile({
    required this.name,
    required this.dateOfBirth,
    this.timeOfBirth,
    required this.placeOfBirth,
    this.birthLat,
    this.birthLon,
    this.birthCountryCode,
  });

  /// True only when BOTH coordinates are present. Callers send lat/lon as
  /// a pair or not at all — the server treats a half-pair as missing
  /// (`if (!lat || !lon)`) and falls back to geocoding anyway, so there is
  /// no case where one alone is useful.
  bool get hasCoordinates => birthLat != null && birthLon != null;

  UserProfile copyWith({
    String? name,
    DateTime? dateOfBirth,
    String? timeOfBirth,
    String? placeOfBirth,
    double? birthLat,
    double? birthLon,
    String? birthCountryCode,
  }) =>
      UserProfile(
        name: name ?? this.name,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        timeOfBirth: timeOfBirth ?? this.timeOfBirth,
        placeOfBirth: placeOfBirth ?? this.placeOfBirth,
        birthLat: birthLat ?? this.birthLat,
        birthLon: birthLon ?? this.birthLon,
        birthCountryCode: birthCountryCode ?? this.birthCountryCode,
      );

  String get dobFormatted {
    final day = dateOfBirth.day.toString().padLeft(2, '0');
    final month = dateOfBirth.month.toString().padLeft(2, '0');
    final year = dateOfBirth.year.toString();
    return '$day/$month/$year';
  }

  /// First name only (e.g. "Sarvesh Kumar Singh" -> "Sarvesh").
  /// Used by the AI so it addresses the user by first name only.
  String get firstName {
    if (name.trim().isEmpty) return '';
    return name.trim().split(RegExp(r'\s+')).first;
  }

  String get profileSummary {
    final buffer = StringBuffer();
    if (name.isNotEmpty) {
      buffer.writeln('Full Name: $name');
      buffer.writeln('First Name (ALWAYS address the user by this): $firstName');
    }
    buffer.writeln('Date of Birth: $dobFormatted');
    if (timeOfBirth != null && timeOfBirth!.isNotEmpty) {
      buffer.writeln('Time of Birth: $timeOfBirth');
    }
    buffer.writeln('Place of Birth: $placeOfBirth');
    return buffer.toString();
  }

  /// Get the Sun sign based on sidereal (Vedic) dates
  String get sunSign {
    final month = dateOfBirth.month;
    final day = dateOfBirth.day;
    // Sidereal dates (approximate, Lahiri ayanamsa)
    if ((month == 4 && day >= 14) || (month == 5 && day <= 14)) return 'Mesha (Aries)';
    if ((month == 5 && day >= 15) || (month == 6 && day <= 14)) return 'Vrishabha (Taurus)';
    if ((month == 6 && day >= 15) || (month == 7 && day <= 16)) return 'Mithuna (Gemini)';
    if ((month == 7 && day >= 17) || (month == 8 && day <= 16)) return 'Karka (Cancer)';
    if ((month == 8 && day >= 17) || (month == 9 && day <= 16)) return 'Simha (Leo)';
    if ((month == 9 && day >= 17) || (month == 10 && day <= 16)) return 'Kanya (Virgo)';
    if ((month == 10 && day >= 17) || (month == 11 && day <= 15)) return 'Tula (Libra)';
    if ((month == 11 && day >= 16) || (month == 12 && day <= 15)) return 'Vrishchika (Scorpio)';
    if ((month == 12 && day >= 16) || (month == 1 && day <= 13)) return 'Dhanu (Sagittarius)';
    if ((month == 1 && day >= 14) || (month == 2 && day <= 12)) return 'Makara (Capricorn)';
    if ((month == 2 && day >= 13) || (month == 3 && day <= 13)) return 'Kumbha (Aquarius)';
    return 'Meena (Pisces)';
  }


  /// Get Western zodiac sign
  String get westernSign {
    final month = dateOfBirth.month;
    final day = dateOfBirth.day;
    if ((month == 3 && day >= 21) || (month == 4 && day <= 19)) return 'Aries';
    if ((month == 4 && day >= 20) || (month == 5 && day <= 20)) return 'Taurus';
    if ((month == 5 && day >= 21) || (month == 6 && day <= 20)) return 'Gemini';
    if ((month == 6 && day >= 21) || (month == 7 && day <= 22)) return 'Cancer';
    if ((month == 7 && day >= 23) || (month == 8 && day <= 22)) return 'Leo';
    if ((month == 8 && day >= 23) || (month == 9 && day <= 22)) return 'Virgo';
    if ((month == 9 && day >= 23) || (month == 10 && day <= 22)) return 'Libra';
    if ((month == 10 && day >= 23) || (month == 11 && day <= 21)) return 'Scorpio';
    if ((month == 11 && day >= 22) || (month == 12 && day <= 21)) return 'Sagittarius';
    if ((month == 12 && day >= 22) || (month == 1 && day <= 19)) return 'Capricorn';
    if ((month == 1 && day >= 20) || (month == 2 && day <= 18)) return 'Aquarius';
    return 'Pisces';
  }

  /// Get the Sun sign index (0-11)
  int get sunSignIndex {
    final month = dateOfBirth.month;
    final day = dateOfBirth.day;
    if ((month == 4 && day >= 14) || (month == 5 && day <= 14)) return 0;
    if ((month == 5 && day >= 15) || (month == 6 && day <= 14)) return 1;
    if ((month == 6 && day >= 15) || (month == 7 && day <= 16)) return 2;
    if ((month == 7 && day >= 17) || (month == 8 && day <= 16)) return 3;
    if ((month == 8 && day >= 17) || (month == 9 && day <= 16)) return 4;
    if ((month == 9 && day >= 17) || (month == 10 && day <= 16)) return 5;
    if ((month == 10 && day >= 17) || (month == 11 && day <= 15)) return 6;
    if ((month == 11 && day >= 16) || (month == 12 && day <= 15)) return 7;
    if ((month == 12 && day >= 16) || (month == 1 && day <= 13)) return 8;
    if ((month == 1 && day >= 14) || (month == 2 && day <= 12)) return 9;
    if ((month == 2 && day >= 13) || (month == 3 && day <= 13)) return 10;
    return 11;
  }

  /// Approximate ascendant index based on birth time
  int get approxAscendantIndex {
    if (timeOfBirth == null || timeOfBirth!.isEmpty) return sunSignIndex;
    try {
      final parts = timeOfBirth!.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts.length > 1 ? int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), '')) : 0;
      // Each sign rises for ~2 hours, starting from sunrise (~6 AM)
      final totalMinutes = (hour * 60 + minute) - 360; // minutes from 6 AM
      final signOffset = (totalMinutes / 120).floor(); // each sign ~120 min
      return (sunSignIndex + signOffset) % 12;
    } catch (_) {
      return sunSignIndex;
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'dateOfBirth': dateOfBirth.toIso8601String(),
    'timeOfBirth': timeOfBirth,
    'placeOfBirth': placeOfBirth,
    'birthLat': birthLat,
    'birthLon': birthLon,
    'birthCountryCode': birthCountryCode,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      // Cleaned on the way IN, so a profile saved with a broken character
      // cannot keep crashing every screen that renders it. Some OEM
      // keyboards deliver half a typed emoji, and a name stored that way
      // would otherwise be a permanent crash for that one user — which
      // matches the "repetitive crashes" signature exactly.
      // Shape recorded unconditionally — safeText only reports when it
      // FINDS a problem, and we also want to know when a crashing user's
      // name was perfectly fine, which rules the hypothesis out instead
      // of leaving it open.
      name: _named(json['name'] as String?),
      dateOfBirth: DateTime.parse(json['dateOfBirth'] as String),
      timeOfBirth: json['timeOfBirth'] as String?,
      placeOfBirth:
          safeText(json['placeOfBirth'] as String?, context: 'profile.place'),
      // `as double?` would throw on an int, and JSON round-trips a whole
      // number as an int — a place sitting exactly on the equator or the
      // prime meridian would store 0 and then fail to load. num.toDouble()
      // accepts both. Out-of-range values are dropped rather than trusted:
      // a corrupt coordinate sends the chart somewhere real but wrong,
      // which is harder to notice than no coordinate at all.
      birthLat: _coord(json['birthLat'], 90),
      birthLon: _coord(json['birthLon'], 180),
      birthCountryCode: (json['birthCountryCode'] as String?)?.toLowerCase(),
    );
  }

  /// Reads a stored coordinate, or null if it is absent, unparseable or
  /// outside [-limit, limit].
  static double? _coord(Object? raw, double limit) {
    final v = raw is num ? raw.toDouble() : null;
    if (v == null || v.isNaN || v.isInfinite) return null;
    if (v < -limit || v > limit) return null;
    return v;
  }

  String toJsonString() => jsonEncode(toJson());

  static UserProfile? fromJsonString(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return null;
    try {
      return UserProfile.fromJson(jsonDecode(jsonString));
    } catch (_) {
      return null;
    }
  }
}
