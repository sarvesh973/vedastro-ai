enum MessageRole { user, ai }

class VedicSource {
  final String book;
  final String chapter;
  final String chapterName;
  final double similarity;

  const VedicSource({
    required this.book,
    required this.chapter,
    required this.chapterName,
    required this.similarity,
  });

  factory VedicSource.fromJson(Map<String, dynamic> json) {
    return VedicSource(
      book: json['book']?.toString() ?? '',
      chapter: json['chapter']?.toString() ?? '',
      chapterName: json['chapter_name']?.toString() ?? '',
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// One expandable "chapter" behind a summary point. The chat bubble shows
/// short summary bullets; each bullet has a matching ChapterDetail rendered
/// as a tappable card below the bubble — tap to reveal the full reasoning.
class ChapterDetail {
  /// Classical text + chapter/topic, e.g.
  /// "Brihat Parashara Hora Shastra — 10th House of Karma".
  final String chapter;

  /// Full Hinglish reasoning behind the matching summary point.
  final String explanation;

  const ChapterDetail({required this.chapter, required this.explanation});

  factory ChapterDetail.fromJson(Map<String, dynamic> json) {
    return ChapterDetail(
      chapter: json['chapter']?.toString() ?? '',
      explanation: json['explanation']?.toString() ?? '',
    );
  }
}

class ChatMessage {
  final String text;
  final MessageRole role;
  final DateTime timestamp;
  final List<VedicSource> sources;

  /// Tappable chapter cards shown under an AI answer — one per summary
  /// bullet, same order. Empty for user messages and for AI answers that
  /// came back without structured details.
  final List<ChapterDetail> details;

  /// Admin-only diagnostic payload. Captures the raw HTTP response body
  /// from the chat server + which parser branch produced [text]. Surfaced
  /// via long-press on the bubble when the signed-in user is an admin —
  /// lets us see exactly what came back when parsing went sideways.
  final String? debugRaw;

  const ChatMessage({
    required this.text,
    required this.role,
    required this.timestamp,
    this.sources = const [],
    this.details = const [],
    this.debugRaw,
  });

  bool get isUser => role == MessageRole.user;
  bool get isAi => role == MessageRole.ai;
  bool get hasSources => sources.isNotEmpty;
  bool get hasDetails => details.isNotEmpty;
  bool get hasDebug => debugRaw != null && debugRaw!.isNotEmpty;
}
