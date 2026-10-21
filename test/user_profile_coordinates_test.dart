import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vedastro_ai/models/user_profile.dart';
import 'package:vedastro_ai/services/ai_service.dart';

/// UserProfile gained birthLat / birthLon / birthCountryCode while the app
/// was already live, so the thing most worth testing is not the happy
/// path — it is that a profile saved WITHOUT these fields still loads.
///
/// Every profile on every installed device, and every profile in
/// Firestore, predates them. A fromJson that threw on a missing or
/// int-typed coordinate would not degrade gracefully: StorageService
/// catches the error and returns null, so the user would simply find
/// their birth details gone.
void main() {
  final dob = DateTime(2003, 7, 9);

  UserProfile withCoords() => UserProfile(
        name: 'Sarvesh Mishra',
        dateOfBirth: dob,
        timeOfBirth: '00:54',
        placeOfBirth: 'Bhore, Bihar, India',
        birthLat: 26.3842,
        birthLon: 84.1234,
        birthCountryCode: 'in',
      );

  group('legacy profiles', () {
    test('JSON written before the fields existed still loads', () {
      // Exactly what toJson produced before this change.
      final legacy = jsonEncode({
        'name': 'Sarvesh Mishra',
        'dateOfBirth': dob.toIso8601String(),
        'timeOfBirth': '00:54',
        'placeOfBirth': 'Bhore, Bihar, India',
      });

      final p = UserProfile.fromJsonString(legacy);
      expect(p, isNotNull, reason: 'a pre-coordinate profile must still load');
      expect(p!.name, 'Sarvesh Mishra');
      expect(p.placeOfBirth, 'Bhore, Bihar, India');
      expect(p.birthLat, isNull);
      expect(p.birthLon, isNull);
      expect(p.hasCoordinates, isFalse);
    });

    test('a legacy profile sends no coordinates, so the server geocodes', () {
      final p = UserProfile.fromJsonString(jsonEncode({
        'name': 'A',
        'dateOfBirth': dob.toIso8601String(),
        'placeOfBirth': 'Patna',
      }))!;
      expect(AiService.coordsOf(p), isEmpty);
    });

    test('explicit nulls are tolerated', () {
      // What toJson writes NOW for a profile with no pick — the keys are
      // present with null values, which must not be read as zero.
      final p = UserProfile.fromJsonString(jsonEncode({
        'name': 'A',
        'dateOfBirth': dob.toIso8601String(),
        'placeOfBirth': 'Patna',
        'birthLat': null,
        'birthLon': null,
        'birthCountryCode': null,
      }))!;
      expect(p.hasCoordinates, isFalse);
      expect(p.birthLat, isNull);
    });
  });

  group('round trip', () {
    test('coordinates survive encode and decode', () {
      final back = UserProfile.fromJsonString(withCoords().toJsonString())!;
      expect(back.birthLat, closeTo(26.3842, 1e-9));
      expect(back.birthLon, closeTo(84.1234, 1e-9));
      expect(back.birthCountryCode, 'in');
      expect(back.hasCoordinates, isTrue);
    });

    test('a whole-number coordinate is not lost', () {
      // JSON encodes 0.0 as `0`, which comes back as an int. `as double?`
      // would throw here, so a birthplace on the equator or the prime
      // meridian would have failed to load at all.
      final p = UserProfile.fromJsonString(jsonEncode({
        'name': 'A',
        'dateOfBirth': dob.toIso8601String(),
        'placeOfBirth': 'Null Island',
        'birthLat': 0,
        'birthLon': 0,
      }));
      expect(p, isNotNull);
      expect(p!.birthLat, 0.0);
      expect(p.birthLon, 0.0);
      expect(p.hasCoordinates, isTrue,
          reason: '0,0 is a real coordinate, not a missing one');
    });

    test('country code is normalised to lowercase', () {
      final p = UserProfile.fromJsonString(jsonEncode({
        'name': 'A',
        'dateOfBirth': dob.toIso8601String(),
        'placeOfBirth': 'Patna',
        'birthCountryCode': 'IN',
      }))!;
      expect(p.birthCountryCode, 'in');
    });
  });

  group('corrupt coordinates are dropped, not trusted', () {
    // A bad coordinate does not fail loudly — it sends the chart to a real
    // but wrong place, and the reading comes back confident. Falling back
    // to the server's geocode of the place text is strictly safer.
    for (final bad in <Map<String, Object?>>[
      {'birthLat': 91.0, 'birthLon': 0.0},
      {'birthLat': -91.0, 'birthLon': 0.0},
      {'birthLat': 0.0, 'birthLon': 181.0},
      {'birthLat': 0.0, 'birthLon': -181.0},
      {'birthLat': 'twenty-six', 'birthLon': 84.0},
      {'birthLat': 26.0, 'birthLon': true},
    ]) {
      test('rejects $bad', () {
        final p = UserProfile.fromJsonString(jsonEncode({
          'name': 'A',
          'dateOfBirth': dob.toIso8601String(),
          'placeOfBirth': 'Patna',
          ...bad,
        }));
        expect(p, isNotNull, reason: 'must degrade, not fail to load');
        expect(p!.hasCoordinates, isFalse);
        expect(AiService.coordsOf(p), isEmpty);
      });
    }
  });

  group('coordsOf', () {
    test('sends both keys when the profile has coordinates', () {
      expect(AiService.coordsOf(withCoords()),
          {'lat': 26.3842, 'lon': 84.1234});
    });

    test('never sends a half pair', () {
      // The server reads `if (!lat || !lon) geocodePlace(place)`, so one
      // alone is ignored anyway — but emitting it would imply otherwise.
      final halves = [
        UserProfile(
            name: 'A',
            dateOfBirth: dob,
            placeOfBirth: 'P',
            birthLat: 26.0),
        UserProfile(
            name: 'A',
            dateOfBirth: dob,
            placeOfBirth: 'P',
            birthLon: 84.0),
      ];
      for (final p in halves) {
        expect(p.hasCoordinates, isFalse);
        expect(AiService.coordsOf(p), isEmpty);
      }
    });
  });

  group('copyWith', () {
    test('keeps coordinates when they are not being changed', () {
      final renamed = withCoords().copyWith(name: 'Someone Else');
      expect(renamed.birthLat, closeTo(26.3842, 1e-9));
      expect(renamed.birthCountryCode, 'in');
    });

    test('replaces coordinates when given new ones', () {
      final moved = withCoords().copyWith(birthLat: 28.6, birthLon: 77.2);
      expect(moved.birthLat, closeTo(28.6, 1e-9));
      expect(moved.birthLon, closeTo(77.2, 1e-9));
    });
  });
}
