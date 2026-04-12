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
      book: json['book'] as String? ?? '',
      chapter: json['chapter'] as String? ?? '',
      chapterName: json['chapter_name'] as String? ?? '',
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ChatMessage {
  final String text;
  final MessageRole role;
  final DateTime timestamp;
  final List<VedicSource> sources;

  const ChatMessage({
    required this.text,
    required this.role,
    required this.timestamp,
    this.sources = const [],
  });

  bool get isUser => role == MessageRole.user;
  bool get isAi => role == MessageRole.ai;
  bool get hasSources => sources.isNotEmpty;
}
