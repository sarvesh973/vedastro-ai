import 'package:flutter/foundation.dart';

/// In-memory log of Flutter UI errors — widget build failures captured
/// by [ErrorWidget.builder] and framework errors captured by
/// [FlutterError.onError]. Bounded so a runaway widget can't OOM the
/// app. Reviewed by admins from Settings → "View UI errors".
class UiErrorLog {
  /// Hard cap on the in-memory ring. The most recent error sits at
  /// index 0; older entries get evicted as new ones come in.
  static const int _maxEntries = 30;

  static final List<UiErrorEntry> _log = [];

  /// Record one error. Safe to call from inside `ErrorWidget.builder`
  /// or `FlutterError.onError` — only mutates a list, never throws.
  static void record(FlutterErrorDetails details) {
    try {
      _log.insert(
        0,
        UiErrorEntry(
          time: DateTime.now(),
          library: details.library ?? 'unknown',
          exception: details.exceptionAsString(),
          stack: details.stack?.toString() ?? '',
        ),
      );
      if (_log.length > _maxEntries) {
        _log.removeRange(_maxEntries, _log.length);
      }
    } catch (_) {
      // Diagnostic must never crash the app.
    }
  }

  /// Most recent error, or null if nothing has been recorded.
  static UiErrorEntry? get latest => _log.isEmpty ? null : _log.first;

  /// Unmodifiable snapshot of all captured errors (newest first).
  static List<UiErrorEntry> get entries => List.unmodifiable(_log);

  static void clear() => _log.clear();

  /// Plain-text dump of every captured error — for copy-to-clipboard.
  static String formatAll() {
    if (_log.isEmpty) return 'No errors captured.';
    final buf = StringBuffer();
    for (var i = 0; i < _log.length; i++) {
      final e = _log[i];
      buf
        ..writeln('#${i + 1}  [${e.time.toIso8601String()}]  (${e.library})')
        ..writeln(e.exception)
        ..writeln('-- stack --')
        ..writeln(e.stack)
        ..writeln('\n');
    }
    return buf.toString();
  }
}

class UiErrorEntry {
  final DateTime time;
  final String library;
  final String exception;
  final String stack;

  const UiErrorEntry({
    required this.time,
    required this.library,
    required this.exception,
    required this.stack,
  });

  /// Short single-line label for list rendering — first line of the
  /// exception, truncated to keep the list tidy.
  String get oneLine {
    final firstLine = exception.split('\n').first.trim();
    return firstLine.length > 100
        ? '${firstLine.substring(0, 100)}…'
        : firstLine;
  }
}
