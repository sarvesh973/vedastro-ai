import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Widget that reveals text character by character, like ChatGPT.
/// Default pace tuned to feel like Melooha — calm, readable, not racing.
class TypewriterText extends StatefulWidget {
  final String text;
  final Duration charDuration;
  final VoidCallback? onComplete;
  final bool isComplete;

  const TypewriterText({
    super.key,
    required this.text,
    // 35ms per char ≈ Melooha pace. The previous 18ms felt rushed because
    // the implementation also revealed 2 chars per tick (effective 9ms).
    this.charDuration = const Duration(milliseconds: 35),
    this.onComplete,
    this.isComplete = false,
  });

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  int _charIndex = 0;
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.isComplete) {
      _charIndex = widget.text.length;
      _done = true;
    } else {
      _startTyping();
    }
  }

  void _startTyping() {
    _timer = Timer.periodic(widget.charDuration, (timer) {
      if (_charIndex >= widget.text.length) {
        timer.cancel();
        if (!_done) {
          _done = true;
          widget.onComplete?.call();
        }
        return;
      }
      if (mounted) {
        setState(() {
          // One char at a time -> readable Melooha pace.
          // (Was 2 chars/tick before, which made it feel like a flash.)
          _charIndex += 1;
          if (_charIndex > widget.text.length) {
            _charIndex = widget.text.length;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleText = widget.text.substring(0, _charIndex);
    return _buildFormattedText(visibleText);
  }

  /// Formats AI text with gold headers and proper styling
  Widget _buildFormattedText(String text) {
    final sections = text.split('\n\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections.map((section) {
        final trimmed = section.trim();
        if (trimmed.isEmpty) return const SizedBox.shrink();

        // Check if section starts with an emoji header
        if (_isEmojiHeader(trimmed)) {
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
                  Text(
                    body.trim(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14.5,
                      height: 1.55,
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            trimmed,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14.5,
              height: 1.55,
            ),
          ),
        );
      }).toList(),
    );
  }

  bool _isEmojiHeader(String text) {
    return text.startsWith('\u{1F52E}') || // 🔮
        text.startsWith('\u{1F4D6}') ||    // 📖
        text.startsWith('\u{1F9D8}') ||    // 🧘
        text.startsWith('\u{1F64F}') ||    // 🙏
        text.startsWith('\u2764') ||       // ❤️
        text.startsWith('\u{1F4C8}') ||    // 📈
        text.startsWith('\u{1F9EC}') ||    // 🧬
        text.startsWith('\u2728') ||       // ✨
        text.startsWith('\u{1F31F}') ||    // 🌟
        text.startsWith('\u{1F30D}') ||    // 🌍
        text.startsWith('\u26A0');         // ⚠
  }
}
