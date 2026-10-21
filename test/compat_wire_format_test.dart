import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedastro_ai/screens/compat_screen.dart';

/// The compat screen sends a birth date and time as strings, and the
/// server parses them with regexes whose failure mode is SILENT.
///
/// For the time: `/(\d{1,2}):(\d{2})\s*(AM|PM)?/`. On no match the parser
/// leaves its own default of 12:00 standing, so an unreadable time does
/// not 400 — it returns a reading for a noon birth. That is the bug these
/// tests exist to prevent, and it cannot be caught by analysis or by
/// eyeballing the UI, because the wrong answer looks exactly like a right
/// one.
///
/// For the date: the server reads DD/MM/YYYY and swaps day and month only
/// when the SECOND field exceeds 12. A previous version swapped whenever
/// day > 12, which corrupted every date after the 12th of a month and
/// left roughly 60% of users with no chart at all.
///
/// Both server regexes are replicated here deliberately. If someone
/// changes the wire format on either side, one of these fails.
void main() {
  // Mirrors the server's time parser, including its noon default.
  ({int hour, int minute}) serverParseTime(String s) {
    var hours = 12, minutes = 0; // the dangerous default
    final m = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)?', caseSensitive: false)
        .firstMatch(s);
    if (m != null) {
      hours = int.parse(m.group(1)!);
      minutes = int.parse(m.group(2)!);
      final ampm = m.group(3)?.toUpperCase();
      if (ampm == 'PM' && hours != 12) hours += 12;
      if (ampm == 'AM' && hours == 12) hours = 0;
    }
    return (hour: hours, minute: minutes);
  }

  group('compatTimeString', () {
    test('is zero-padded 24-hour HH:mm', () {
      expect(compatTimeString(const TimeOfDay(hour: 0, minute: 0)), '00:00');
      expect(compatTimeString(const TimeOfDay(hour: 9, minute: 5)), '09:05');
      expect(compatTimeString(const TimeOfDay(hour: 12, minute: 54)), '12:54');
      expect(compatTimeString(const TimeOfDay(hour: 21, minute: 15)), '21:15');
      expect(compatTimeString(const TimeOfDay(hour: 23, minute: 59)), '23:59');
    });

    test('round-trips through the server parser for every minute of the day',
        () {
      // Exhaustive: 1440 cases is cheap, and a single hour that survives
      // the regex but decodes to the wrong value is a silently wrong
      // reading for everyone born in it.
      for (var h = 0; h < 24; h++) {
        for (var m = 0; m < 60; m++) {
          final wire = compatTimeString(TimeOfDay(hour: h, minute: m));
          final parsed = serverParseTime(wire);
          expect(parsed.hour, h, reason: 'hour lost for $wire');
          expect(parsed.minute, m, reason: 'minute lost for $wire');
        }
      }
    });

    test('midnight does not decode as noon', () {
      // The specific collision worth naming: the parser defaults to 12:00,
      // and 00:00 is the value most likely to be confused with it. A
      // 12-hour "12:00 AM" would also be correct, but only because of the
      // AM branch — HH:mm needs no such branch.
      final parsed = serverParseTime(
          compatTimeString(const TimeOfDay(hour: 0, minute: 0)));
      expect(parsed.hour, 0);
      expect(parsed.hour, isNot(12));
    });

    test('the free-text values this screen used to accept are unsafe', () {
      // These are the strings the old hint "e.g. 09:15 PM" invited. Each
      // one silently decodes to noon, which is why the field had to stop
      // being free text rather than just gaining a stricter message.
      for (final bad in ['9 PM', 'nine fifteen', '0915', 'morning', '']) {
        final parsed = serverParseTime(bad);
        expect(parsed.hour, 12,
            reason: '"$bad" should expose the noon fallback');
        expect(parsed.minute, 0);
      }
    });
  });

  group('compatDateString', () {
    test('is zero-padded dd/MM/yyyy', () {
      expect(compatDateString(DateTime(2003, 7, 9)), '09/07/2003');
      expect(compatDateString(DateTime(1998, 12, 31)), '31/12/1998');
      expect(compatDateString(DateTime(2000, 1, 1)), '01/01/2000');
    });

    test('a day past the 12th is never read as a month', () {
      // The server swaps only when the SECOND field is > 12. Day-first
      // with a zero-padded month means that can never fire on our output.
      for (final d in [
        DateTime(2003, 9, 16),
        DateTime(1995, 2, 28),
        DateTime(1980, 1, 13),
      ]) {
        final parts = compatDateString(d).split('/');
        expect(int.parse(parts[0]), d.day);
        expect(int.parse(parts[1]), d.month);
        expect(int.parse(parts[2]), d.year);
        expect(int.parse(parts[1]), lessThanOrEqualTo(12),
            reason: 'month field must never exceed 12, or the server swaps');
      }
    });

    test('an ambiguous date still sends day first', () {
      // 09/07 could be 9 July or 7 September. The server resolves it as
      // day-first, which is what we send — this pins the agreement rather
      // than leaving it to coincidence.
      expect(compatDateString(DateTime(2003, 7, 9)), '09/07/2003');
      expect(compatDateString(DateTime(2003, 9, 7)), '07/09/2003');
    });
  });
}
