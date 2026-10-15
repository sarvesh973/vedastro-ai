import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Guards against the fatal that has dominated Crashlytics:
///
///   Invalid argument(s): string is not well-formed UTF-16
///
/// Flutter's `ParagraphBuilder.addText()` rejects any string containing an
/// unpaired surrogate — half of a character whose other half is missing.
/// Every widget that lays out text goes through it, so one bad string is a
/// hard crash on whatever screen shows it.
///
/// WHY A GUARD RATHER THAN JUST FIXING THE SOURCE
///
/// Two earlier attempts fixed a specific suspected source and the crash
/// continued, because the suspected source was not the real one. The
/// honest position is that a lone surrogate can enter from several places
/// — a keyboard delivering half a typed emoji, text sliced by UTF-16 code
/// unit somewhere, data stored while already corrupt — and we do not yet
/// know which. Guarding where text meets the renderer removes the whole
/// class whatever the origin.
///
/// It also INSTRUMENTS it. When a bad string is found we record the
/// context to Crashlytics, so the next report names the source instead of
/// requiring another round of guessing. Only the position and code-unit
/// value are recorded — never the text itself, which is user content.
///
/// The fast path allocates nothing: well-formed strings, which is almost
/// all of them, are returned unchanged after a single scan.

/// True when [s] contains an unpaired surrogate — exactly the condition
/// the text layer rejects.
bool hasLoneSurrogate(String s) {
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 >= s.length) return true; // high surrogate at the end
      final next = s.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return true; // unpaired high
      i++; // valid pair — skip its low half
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return true; // low surrogate with no high before it
    }
  }
  return false;
}

/// Drops unpaired surrogates, keeping valid pairs (real emoji) intact.
String stripLoneSurrogates(String s) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 < s.length) {
        final next = s.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          out.writeCharCode(unit);
          out.writeCharCode(next);
          i++;
          continue;
        }
      }
      continue; // orphaned high surrogate
    }
    if (unit >= 0xDC00 && unit <= 0xDFFF) continue; // orphaned low surrogate
    out.writeCharCode(unit);
  }
  return out.toString();
}

/// Contexts already reported this session, so one persistently corrupt
/// value cannot flood Crashlytics on every rebuild.
final Set<String> _reported = <String>{};

/// Position and code unit of the first offender. Deliberately excludes the
/// text — that is user content, and the index plus unit is enough to
/// identify where it came from.
String _describe(String s) {
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    final isHigh = unit >= 0xD800 && unit <= 0xDBFF;
    final isLow = unit >= 0xDC00 && unit <= 0xDFFF;
    if (!isHigh && !isLow) continue;
    if (isHigh && i + 1 < s.length) {
      final next = s.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        i++;
        continue;
      }
    }
    return 'idx=$i len=${s.length} unit=0x${unit.toRadixString(16)} '
        '${isHigh ? 'unpairedHigh' : 'unpairedLow'}';
  }
  return 'none';
}

/// Make [input] safe to hand to a text widget.
///
/// [context] names the call site (for example 'chat.ai', 'profile.name')
/// and appears in Crashlytics, so a future report says which field was
/// corrupt rather than only that something was.
String safeText(String? input, {required String context}) {
  if (input == null || input.isEmpty) return '';
  if (!hasLoneSurrogate(input)) return input; // fast path, no allocation
  final detail = _describe(input);
  if (_reported.add(context)) {
    // Never let diagnostics cause the crash they exist to diagnose.
    try {
      FirebaseCrashlytics.instance
          .setCustomKey('utf16_lone_surrogate_$context', detail);
      FirebaseCrashlytics.instance
          .log('utf16: stripped unpaired surrogate in $context ($detail)');
    } catch (_) {}
  }
  return stripLoneSurrogates(input);
}
