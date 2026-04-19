import 'dart:convert';

class UserProfile {
  final String name;
  final DateTime dateOfBirth;
  final String? timeOfBirth;
  final String placeOfBirth;

  const UserProfile({
    required this.name,
    required this.dateOfBirth,
    this.timeOfBirth,
    required this.placeOfBirth,
  });

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
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String? ?? '',
      dateOfBirth: DateTime.parse(json['dateOfBirth'] as String),
      timeOfBirth: json['timeOfBirth'] as String?,
      placeOfBirth: json['placeOfBirth'] as String? ?? '',
    );
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
