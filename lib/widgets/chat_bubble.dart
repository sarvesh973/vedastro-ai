import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/chat_message.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool animate;

  const ChatBubble({
    super.key,
    required this.message,
    this.animate = true,
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
    return Container(
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
      child: _buildFormattedAiText(message.text),
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
        if (trimmed.startsWith('🔮') ||
            trimmed.startsWith('📖') ||
            trimmed.startsWith('🧘') ||
            trimmed.startsWith('🙏') ||
            trimmed.startsWith('❤️') ||
            trimmed.startsWith('📈') ||
            trimmed.startsWith('🧬')) {
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
}
