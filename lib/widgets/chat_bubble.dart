import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/chat_message.dart';
import 'typewriter_text.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool animate;
  final bool isLatestAiMessage;
  final VoidCallback? onTypewriterComplete;

  const ChatBubble({
    super.key,
    required this.message,
    this.animate = true,
    this.isLatestAiMessage = false,
    this.onTypewriterComplete,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    Widget bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 48 : 0,
          right: isUser ? 0 : 48,
          bottom: 12,
        ),
        child: isUser ? _buildUserBubble() : _buildAiBubble(),
      ),
    );

    if (animate) {
      bubble = bubble
          .animate()
          .fadeIn(duration: 400.ms, curve: Curves.easeOut)
          .slideY(
            begin: 0.1,
            end: 0,
            duration: 400.ms,
            curve: Curves.easeOut,
          );
    }

    return bubble;
  }

  Widget _buildUserBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.purpleAccent, AppColors.purpleSoft],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Text(
        message.text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildAiBubble() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.aiBubble,
            border: Border.all(color: AppColors.divider, width: 0.5),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: isLatestAiMessage
              ? TypewriterText(
                  key: ValueKey('tw_${message.timestamp.millisecondsSinceEpoch}'),
                  text: message.text,
                  // Melooha-like pace — slower, calmer, easier to read.
                  charDuration: const Duration(milliseconds: 35),
                  onComplete: onTypewriterComplete,
                )
              : _buildFormattedAiText(message.text),
        ),
        // Always show sources below — even for the latest message currently
        // being typed — so users see citations in the dedicated section
        // instead of cluttering the answer body.
        if (message.hasSources) _buildSourceCitations(),
      ],
    );
  }

  Widget _buildSourceCitations() {
    final seen = <String>{};
    final unique = message.sources.where((s) {
      final key = '${s.book}_${s.chapter}';
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: unique.take(3).map((source) {
          final label = source.book == 'BPHS'
              ? 'BPHS Ch.${source.chapter}'
              : 'Phaladeepika Ch.${source.chapter}';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.goldLight.withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.menu_book_rounded, size: 12,
                    color: AppColors.goldLight.withOpacity(0.7)),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(
                  color: AppColors.textMuted.withOpacity(0.8),
                  fontSize: 11, fontWeight: FontWeight.w500,
                )),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFormattedAiText(String text) {
    final sections = text.split('\n\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections.map((section) {
        final trimmed = section.trim();
        if (trimmed.isEmpty) return const SizedBox.shrink();

        // Check if section starts with an emoji header
        if (trimmed.startsWith('\u{1F52E}') ||
            trimmed.startsWith('\u{1F4D6}') ||
            trimmed.startsWith('\u{1F9D8}') ||
            trimmed.startsWith('\u{1F64F}') ||
            trimmed.startsWith('\u2764') ||
            trimmed.startsWith('\u{1F4C8}') ||
            trimmed.startsWith('\u{1F9EC}') ||
            trimmed.startsWith('\u2728') ||
            trimmed.startsWith('\u{1F31F}')) {
          final lines = trimmed.split('\n');
          final header = lines.first;
          final body = lines.length > 1 ? lines.sublist(1).join('\n') : '';

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  header,
                  style: const TextStyle(
                    color: AppColors.goldLight,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _buildRichText(body.trim()),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildRichText(trimmed),
        );
      }).toList(),
    );
  }

  /// Parse markdown-style **bold** and *italic* into styled RichText
  Widget _buildRichText(String text) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      // Add text before this match
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      if (match.group(1) != null) {
        // **bold**
        spans.add(TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.goldLight),
        ));
      } else if (match.group(2) != null) {
        // *italic*
        spans.add(TextSpan(
          text: match.group(2),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      }

      lastEnd = match.end;
    }

    // Add remaining text
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14.5,
          height: 1.55,
        ),
        children: spans.isEmpty ? [TextSpan(text: text)] : spans,
      ),
    );
  }
}
