import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vedastro_ai/utils/text_safety.dart';

/// Regression tests for the Crashlytics fatal
/// "Invalid argument(s): string is not well-formed UTF-16" —
/// 2,723 crashes across 232 users in one week.
///
/// Flutter's ParagraphBuilder.addText() rejects any string containing an
/// unpaired surrogate, so one bad string is a hard crash on whatever
/// screen renders it. Two defences are tested here:
///
///   1. Don't CREATE one. TypewriterText revealed replies one UTF-16 code
///      unit at a time; an emoji is a surrogate PAIR, so stepping by one
///      guaranteed a frame that ended between its halves.
///   2. Don't RENDER one. Two earlier source-specific fixes failed to stop
///      the crash, so text is also guarded where it meets the renderer,
///      whatever its origin.

/// True when [s] contains no unpaired surrogate — exactly the condition
/// the text layer requires.
bool isWellFormedUtf16(String s) {
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 >= s.length) return false;
      final next = s.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return false;
      i++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return false;
    }
  }
  return true;
}

/// Printable form for failure messages, so a broken string doesn't itself
/// break the test reporter.
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

void main() {
  // Text of the kind the app actually renders: the emoji headers the
  // fallback templates and client-side Gemini prompt emit, a ZWJ family
  // sequence, a regional-indicator flag, and Devanagari.
  const samples = <String>[
    '🔮 Insight\nYour 10th lord Saturn sits in the 3rd house.',
    '📖 Reason\nPhaladeepika ke anusaar, yeh sthiti shubh hai.',
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
          final visible =
              i >= total ? text : text.characters.take(i).toString();
          expect(isWellFormedUtf16(visible), isTrue,
              reason: 'prefix $i of ${jsonish(text)} was malformed: '
                  '${jsonish(visible)}');
        }
      }
    });

    test('the old code-unit substring DOES break — test still has teeth', () {
      // If this ever fails, the samples lost their surrogate pairs and the
      // test above stopped proving anything.
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
      // Slide an emoji across every offset so some cut lands mid-pair.
      for (var pad = 0; pad < 70; pad++) {
        final text = '${'a' * pad}🔮 trailing words to force truncation here';
        for (final n in const [55, 60]) {
          expect(isWellFormedUtf16(takeChars(text, n)), isTrue,
              reason: 'pad=$pad n=$n produced a malformed cut');
        }
      }
    });
  });

  group('render-boundary guard', () {
    const loneHigh = '\uD83D'; // high half of an emoji, alone
    const loneLow = '\uDE00'; // low half, alone
    const validEmoji = '😀'; // a complete pair

    test('detects unpaired surrogates, ignores valid pairs', () {
      expect(hasLoneSurrogate('plain ascii'), isFalse);
      expect(hasLoneSurrogate('valid $validEmoji here'), isFalse);
      expect(hasLoneSurrogate('शनि महादशा'), isFalse); // Devanagari is BMP
      expect(hasLoneSurrogate('broken $loneHigh here'), isTrue);
      expect(hasLoneSurrogate('broken $loneLow here'), isTrue);
      expect(hasLoneSurrogate(loneHigh), isTrue); // at the very end
    });

    test('stripping yields well-formed text and keeps real emoji', () {
      expect(
          stripLoneSurrogates('broken $loneHigh here'), equals('broken  here'));
      expect(
          stripLoneSurrogates('keep $validEmoji me'), equals('keep $validEmoji me'));
      for (final s in ['a$loneHigh', '$loneLow b', '$loneHigh$validEmoji']) {
        expect(isWellFormedUtf16(stripLoneSurrogates(s)), isTrue,
            reason: 'strip left a malformed string for ${jsonish(s)}');
      }
    });

    test('well-formed input is returned unchanged', () {
      for (final s in ['plain', 'emoji $validEmoji', 'शनि', '']) {
        expect(stripLoneSurrogates(s), equals(s));
      }
    });
  });
}
