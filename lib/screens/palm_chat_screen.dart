import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../models/palm_result.dart';
import '../services/ai_service.dart';
import '../services/analytics_service.dart';

/// Follow-up conversation about a palm reading.
///
/// Separate from the main chat on purpose. This talks to `/palm/ask`, which
/// answers only from the reading already produced for this hand plus the
/// user's chart. It has no corpus, cites nothing, and will not describe a
/// palm feature that was never observed — ask about a marriage line the
/// photo did not show and it says so rather than inventing one.
///
/// Sending these questions to the normal chat would produce verse citations
/// about a hand the Jyotishi never saw.
class PalmChatScreen extends ConsumerStatefulWidget {
  final PalmReadingResult reading;

  const PalmChatScreen({super.key, required this.reading});

  @override
  ConsumerState<PalmChatScreen> createState() => _PalmChatScreenState();
}

class _PalmChatMessage {
  final String text;
  final bool fromUser;
  const _PalmChatMessage(this.text, {required this.fromUser});
}

class _PalmChatScreenState extends ConsumerState<PalmChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_PalmChatMessage> _messages = [];
  bool _sending = false;

  /// Openers phrased around what the reading actually covers, so a first-time
  /// user is not staring at an empty box wondering what a palm can answer.
  static const _starters = [
    'What does my heart line say about relationships?',
    'How does my hand match my birth chart?',
    'What should I watch out for?',
    'What are my strongest traits?',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final q = text.trim();
    if (q.isEmpty || _sending) return;
    setState(() {
      _messages.add(_PalmChatMessage(q, fromUser: true));
      _sending = true;
      _controller.clear();
    });
    _scrollToEnd();
    Analytics.palmAsked(promptLen: q.length);

    // Last few turns only — the server caps at 6 and the reading itself
    // carries the context that matters.
    final history = _messages
        .take(_messages.length - 1)
        .map((m) => '${m.fromUser ? 'User' : 'Palmist'}: ${m.text}')
        .toList();

    // Prefer the id (cheaper — the server already holds the reading), fall
    // back to posting the reading itself when it was never stored.
    final answer = await AiService.askPalm(
      question: q,
      readingId: widget.reading.readingId,
      reading: widget.reading.readingId == null ? widget.reading.toJson() : null,
      chatHistory: history,
    );

    if (!mounted) return;
    setState(() {
      _messages.add(_PalmChatMessage(
        answer ??
            'I could not read that just now. Please try again in a moment.',
        fromUser: false,
      ));
      _sending = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Ask about your palm'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          if (widget.reading.usedChart) _chartBadge(),
          Expanded(
            child: _messages.isEmpty
                ? _emptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= _messages.length) return _typing();
                      return _bubble(_messages[i]);
                    },
                  ),
          ),
          _composer(),
        ],
      ),
    );
  }

  /// Only shown when the server actually cross-checked against the kundli.
  /// If birth details were missing this stays hidden rather than implying a
  /// depth the reading does not have.
  Widget _chartBadge() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.purpleAccent.withOpacity(0.12),
      child: Row(
        children: [
          Icon(Icons.auto_awesome,
              size: 14, color: AppColors.goldLight.withOpacity(0.9)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This reading was cross-checked with your birth chart',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      children: [
        Text(
          'Ask about what your hand showed',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'I can only speak to what was visible in your photo. '
          'If something was not clear, I will tell you.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        ..._starters.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => _send(s),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: AppColors.purpleAccent.withOpacity(0.35)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s,
                        style: TextStyle(
                          color: AppColors.textPrimary.withOpacity(0.9),
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: AppColors.goldLight.withOpacity(0.7)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubble(_PalmChatMessage m) {
    final isUser = m.fromUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.purpleAccent.withOpacity(0.28)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUser
                ? AppColors.purpleAccent.withOpacity(0.45)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Text(
          m.text,
          style: TextStyle(
            color: AppColors.textPrimary.withOpacity(0.94),
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _typing() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: SizedBox(
          width: 34,
          height: 10,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              3,
              (i) => Padding(
                padding: const EdgeInsets.only(right: 5),
                child: CircleAvatar(
                  radius: 3,
                  backgroundColor: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_sending,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText: 'Ask about your palm',
                  hintStyle:
                      TextStyle(color: AppColors.textMuted, fontSize: 14),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _sending ? null : () => _send(_controller.text),
              icon: Icon(
                Icons.send_rounded,
                color: _sending
                    ? AppColors.textMuted
                    : AppColors.goldLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
