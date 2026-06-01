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

  Map<String, dynamic> toJson() => {
        'book': book,
        'chapter': chapter,
        'chapter_name': chapterName,
        'similarity': similarity,
      };
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

  /// True for AI replies that came from the local template fallback
  /// (no network / server unreachable). The bubble renders a small
  /// "Offline guidance" badge so the user knows the answer isn't a
  /// personalised AI reading.
  final bool isOffline;

  const ChatMessage({
    required this.text,
    required this.role,
    required this.timestamp,
    this.sources = const [],
    this.details = const [],
    this.debugRaw,
    this.isOffline = false,
  });

  bool get isUser => role == MessageRole.user;
  bool get isAi => role == MessageRole.ai;
  bool get hasSources => sources.isNotEmpty;
  bool get hasDetails => details.isNotEmpty;
  bool get hasDebug => debugRaw != null && debugRaw!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'text': text,
        'role': role == MessageRole.user ? 'user' : 'ai',
        'timestamp': timestamp.toIso8601String(),
        'sources': sources.map((s) => s.toJson()).toList(),
        'details': details
            .map((d) => {'chapter': d.chapter, 'explanation': d.explanation})
            .toList(),
        if (debugRaw != null) 'debugRaw': debugRaw,
        'isOffline': isOffline,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final sourcesJson = (json['sources'] as List?) ?? const [];
    final detailsJson = (json['details'] as List?) ?? const [];
    return ChatMessage(
      text: json['text']?.toString() ?? '',
      role: json['role'] == 'user' ? MessageRole.user : MessageRole.ai,
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      sources: sourcesJson
          .whereType<Map<String, dynamic>>()
          .map(VedicSource.fromJson)
          .toList(),
      details: detailsJson
          .whereType<Map<String, dynamic>>()
          .map(ChapterDetail.fromJson)
          .toList(),
      debugRaw: json['debugRaw']?.toString(),
      isOffline: json['isOffline'] == true,
    );
  }
}
