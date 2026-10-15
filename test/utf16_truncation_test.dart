import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for Crashlytics "Invalid argument(s): string is not
/// well-formed UTF-16" — 2,723 fatals across 232 users in one week.
///
/// Cause: TypewriterText revealed AI replies one UTF-16 CODE UNIT at a
/// time via substring(). An emoji is a surrogate PAIR, so stepping by one
/// guaranteed a frame where the slice ended between its two halves, and
/// rendering that half threw. Deterministic, not a race: the animation
/// visits every index, so every emoji crashed the app every time.
///
/// These tests assert the property directly — every prefix the animation
/// can produce must be well-formed — and also assert that the OLD
/// approach fails, so the test cannot silently stop testing anything.

/// True when [s] contains no unpaired surrogate. This is exactly the
/// condition Flutter's text layer rejects.
bool isWellFormedUtf16(String s) {
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 >= s.length) return false; // high surrogate at the end
      final next = s.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return false; // unpaired high
      i++; // valid pair, skip the low half
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return false; // low surrogate with no high before it
    }
  }
  return true;
}

void main() {
  // Text of the kind the model actually returns: emoji headers, a ZWJ
  // family sequence, a flag (two regional indicators), and Devanagari.
  const samples = <String>[
    '✨ Business outlook\nYour 10th lord Saturn sits in the 3rd. 🔮',
    'Family matters 👨‍👩‍👧 need patience this month.',
    'Travel abroad 🇮🇳 is supported by Rahu in the 12th.',
    'शनि महादशा 🙏 9 जुलाई 2029 तक चलेगी।',
    'Plain ascii with no emoji at all.',
    '🌟',
  ];

  group('typewriter reveal', () {
    test('every grapheme-stepped prefix is well-formed UTF-16', () {
      for (final text in samples) {
        final total = text.characters.length;
        for (var i = 0; i <= total; i++) {
          final visible = i >= total
              ? text
              : text.characters.take(i).toString();
          expect(
            isWellFormedUtf16(visible),
            isTrue,
            reason: 'grapheme prefix $i of ${jsonish(text)} was malformed: '
                '${jsonish(visible)}',
          );
        }
      }
    });

    test('the old code-unit substring DOES break — test still has teeth', () {
      // If this ever passes, the samples stopped containing surrogate
      // pairs and the test above is no longer proving anything.
      var sawMalformed = false;
      for (final text in samples) {
        for (var i = 0; i <= text.length; i++) {
          if (!isWellFormedUtf16(text.substring(0, i))) {
            sawMalformed = true;
            break;
          }
        }
      }
      expect(sawMalformed, isTrue,
          reason: 'samples no longer contain surrogate pairs');
    });

    test('the full text is always reached exactly', () {
      for (final text in samples) {
        final total = text.characters.length;
        expect(text.characters.take(total).toString(), equals(text));
      }
    });
  });

  group('_shortPoint style truncation', () {
    // Mirrors the fixed home_screen helper: cut by grapheme, not offset.
    String takeChars(String s, int n) =>
        s.characters.length <= n ? s : s.characters.take(n).toString();

    test('fixed-length cuts never split a surrogate pair', () {
      // An emoji placed at every offset, so some cut lands mid-pair.
      for (var pad = 0; pad < 70; pad++) {
        final text = '${'a' * pad}🔮 trailing words to force truncation here';
        for (final n in const [55, 60]) {
          expect(isWellFormedUtf16(takeChars(text, n)), isTrue,
              reason: 'pad=$pad n=$n produced a malformed cut');
        }
      }
    });
  });
}

/// Printable form for failure messages — escapes surrogates so a broken
/// string doesn't itself break the test reporter.
String jsonish(String s) {
  final b = StringBuffer();
  for (final unit in s.codeUnits) {
    if (unit >= 0x20 && unit < 0x7f) {
      b.writeCharCode(unit);
    } else {
      b.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
    }
  }
  return b.toString();
}
