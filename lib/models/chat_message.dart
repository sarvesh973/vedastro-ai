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

  /// Admin-only inline diagnostic — the topic/focus/tone the server
  /// classifier picked for THIS question, plus the chunk books it
  /// pulled. Rendered as a small bluish summary line under the bubble
  /// (only when AuthService.isAdmin is true) so we can verify the
  /// classifier is routing questions correctly without opening logs.
  final ChatDebugMeta? debugMeta;

  const ChatMessage({
    required this.text,
    required this.role,
    required this.timestamp,
    this.sources = const [],
    this.details = const [],
    this.debugRaw,
    this.isOffline = false,
    this.debugMeta,
  });

  bool get isUser => role == MessageRole.user;
  bool get isAi => role == MessageRole.ai;
  bool get hasSources => sources.isNotEmpty;
  bool get hasDetails => details.isNotEmpty;
  bool get hasDebug => debugRaw != null && debugRaw!.isNotEmpty;
  bool get hasDebugMeta => debugMeta != null;

  // Local-persistence serialisation (used by ChatMessagesNotifier to
  // survive process kill via SharedPreferences). debugMeta and debugRaw
  // are admin-only diagnostics; persisting them across cold starts isn't
  // necessary — the next chat fetch will repopulate them — so we
  // deliberately drop them on serialise rather than blow up the cache.
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

/// Tiny inline classifier diagnostic. Only built when the server's
/// chat response includes a `_debug` block — older deploys / non-RAG
/// fallbacks leave this null and the bubble renders without it.
class ChatDebugMeta {
  final String topic;
  final String topicSource; // 'llm' | 'regex'
  final String tone;
  final String focus;
  final List<String> books;
  final List<String> chunks;
  final int classifyMs;

  const ChatDebugMeta({
    required this.topic,
    required this.topicSource,
    required this.tone,
    required this.focus,
    required this.books,
    required this.chunks,
    required this.classifyMs,
  });

  static ChatDebugMeta? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    return ChatDebugMeta(
      topic: (raw['topic'] as String?) ?? 'general',
      topicSource: (raw['topicSource'] as String?) ?? 'regex',
      tone: (raw['tone'] as String?) ?? 'neutral',
      focus: (raw['focus'] as String?) ?? '',
      books: (raw['books'] as List?)?.whereType<String>().toList() ?? const [],
      chunks: (raw['chunks'] as List?)?.whereType<String>().toList() ?? const [],
      classifyMs: (raw['classifyMs'] as int?) ?? 0,
    );
  }
}
