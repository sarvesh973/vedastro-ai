import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/chat_message.dart';
import '../providers/providers.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chapter_detail_card.dart';
import '../widgets/contextual_loader.dart';
import '../models/subscription_plan.dart';
import 'paywall_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _hasInitialized = false;
  bool _isTypewriterActive = false;

  /// Last question the user asked — passed to ContextualLoader so it can
  /// show topic-aware "Reading your career line..." style messages.
  String _lastUserQuestion = '';

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final profile = ref.read(userProfileProvider);
    if (profile == null) return;

    // Check free limit
    if (!StorageService.canAskChatQuestion) {
      _showPaywall();
      return;
    }

    _messageController.clear();

    // Remember question text so ContextualLoader can show a relevant
    // "Reading your <topic> ..." message while we wait.
    _lastUserQuestion = text;

    final chatNotifier = ref.read(chatMessagesProvider.notifier);
    final typingController = ref.read(isAiTypingProvider.notifier);

    // Add user message
    chatNotifier.addMessage(ChatMessage(
      text: text,
      role: MessageRole.user,
      timestamp: DateTime.now(),
    ));
    // Sync to cloud
    FirestoreService.syncChatMessage(text, 'user');
    _scrollToBottom();

    // Show typing
    typingController.state = true;
    _scrollToBottom();

    // Get AI response (tries Cloud Function RAG -> Direct Gemini -> Fallback)
    final aiResponse = await AiService.getAstrologyResponse(
      profile: profile,
      userMessage: text,
      chatHistory: ref.read(chatMessagesProvider).map((m) => m.text).toList(),
    );

    typingController.state = false;

    // Add AI message and activate typewriter
    setState(() => _isTypewriterActive = true);

    chatNotifier.addMessage(ChatMessage(
      text: aiResponse.text,
      role: MessageRole.ai,
      timestamp: DateTime.now(),
      sources: aiResponse.sources,
      details: aiResponse.details,
    ));
    // Sync AI response to cloud
    FirestoreService.syncChatMessage(aiResponse.text, 'ai');

    await StorageService.incrementChatQuestions();
    ref.read(chatQuestionsUsedProvider.notifier).state =
        StorageService.chatQuestionsUsed;

    _scrollToBottom();

    // Keep scrolling during typewriter animation
    _startAutoScroll();
  }

  void _startAutoScroll() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted || !_isTypewriterActive) return false;
      _scrollToBottom();
      return true;
    });
  }

  Future<void> _showPaywall() async {
    // Smart plan filtering based on the user's *actual* current plan
    // (not the legacy isPremium boolean — that flag is true for trial,
    // standard, AND premium, so it would skip the Standard upgrade for
    // trial users). We read the real plan from Firestore and use the
    // SubscriptionPlan.upgradeOptions helper to pick what to show:
    //  - Free  -> [Trial, Standard, Premium]
    //  - Trial -> [Standard, Premium]
    //  - Standard -> [Premium]
    //  - Premium -> [] (shouldn't reach here — unlimited chats)
    final sub = await FirestoreService.loadCurrentSubscription();
    if (!mounted) return;

    var availablePlans = sub.plan.upgradeOptions;
    // Fallback for accounts where Firestore hasn't synced yet but the
    // legacy isPremium flag is set (just-paid, webhook in flight): treat
    // them as Standard so they at least see a Premium upgrade option.
    if (availablePlans.isEmpty && !StorageService.isPremium) {
      availablePlans = SubscriptionPlan.free.upgradeOptions;
    } else if (availablePlans.isEmpty) {
      availablePlans = const [SubscriptionPlan.premium];
    }

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            PaywallScreen(availablePlans: availablePlans),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);
    final isTyping = ref.watch(isAiTypingProvider);
    final profile = ref.watch(userProfileProvider);

    // Send welcome message on first build
    if (!_hasInitialized && profile != null && messages.isEmpty) {
      _hasInitialized = true;
      setState(() => _isTypewriterActive = true);
      Future.microtask(() {
        ref.read(chatMessagesProvider.notifier).addMessage(ChatMessage(
          text: AiService.getWelcomeMessage(profile),
          role: MessageRole.ai,
          timestamp: DateTime.now(),
        ));
        _startAutoScroll();
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.purpleAccent, AppColors.purpleSoft],
                ),
                border: Border.all(
                  color: AppColors.goldLight.withOpacity(0.4),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.purpleAccent.withOpacity(0.5),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome, size: 19, color: AppColors.goldLight),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Moksha',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  isTyping ? 'typing...' : 'Vedic Astrologer',
                  style: TextStyle(
                    fontSize: 12,
                    color: isTyping ? AppColors.purpleLight : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: Column(
        children: [
          // Quick suggestion chips (shown when few messages)
          if (messages.length <= 2) _buildSuggestionChips(),

          // Messages
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: messages.length + (isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == messages.length && isTyping) {
                        return ContextualLoader(
                          userQuestion: _lastUserQuestion,
                        );
                      }
                      final msg = messages[index];
                      final isLastMessage =
                          index == messages.length - 1;
                      final isLastAi =
                          msg.isAi && isLastMessage && _isTypewriterActive;

                      final bubble = ChatBubble(
                        message: msg,
                        animate: index >= messages.length - 2,
                        isLatestAiMessage: isLastAi,
                        onTypewriterComplete: () {
                          if (mounted) {
                            setState(() => _isTypewriterActive = false);
                          }
                        },
                      );

                      // Follow-up suggestion chips appear below the latest
                      // AI answer once it has fully rendered (typewriter
                      // done) and the AI isn't mid-response. Tapping a chip
                      // sends it as a fresh question — keeps the user in
                      // conversation (e.g. asking for remedies).
                      //
                      // followsUserQuestion: the AI message must be a REPLY
                      // to a user question, not the auto-generated welcome
                      // message at index 0. Without this the chips wrongly
                      // appear under the welcome line before the user has
                      // asked anything.
                      final followsUserQuestion =
                          index > 0 && messages[index - 1].isUser;
                      final showFollowUps = msg.isAi &&
                          isLastMessage &&
                          followsUserQuestion &&
                          !_isTypewriterActive &&
                          !isTyping;

                      // Tappable chapter cards under an AI answer. For the
                      // latest message they appear only once the typewriter
                      // has finished, so they don't pop in mid-render;
                      // older answers (typewriter long done) show them
                      // immediately.
                      final showChapters = msg.isAi &&
                          msg.hasDetails &&
                          (!isLastMessage || !_isTypewriterActive);

                      if (showFollowUps || showChapters) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            bubble,
                            if (showChapters)
                              _buildChapterCards(msg.details),
                            if (showFollowUps) _buildAnswerFollowUps(),
                          ],
                        );
                      }
                      return bubble;
                    },
                  ),
          ),

          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildSuggestionChips() {
    final suggestions = [
      'Mera career kaisa rahega?',
      'Love life ke baare mein batao',
      'Health prediction',
      'Finance & wealth',
    ];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () {
              _messageController.text = suggestions[index];
              _sendMessage();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.purpleAccent.withOpacity(0.3)),
              ),
              child: Text(
                suggestions[index],
                style: const TextStyle(
                  color: AppColors.purpleLight,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    ).animate().fadeIn(duration: 500.ms, delay: 500.ms);
  }

  /// Follow-up suggestion chips shown below the latest AI answer once it
  /// finishes rendering. Tapping one sends it as a new question — keeps
  /// the conversation going. The remedy chip is primary (gold) since the
  /// reading itself no longer ends with a forced remedy; remedies are now
  /// an explicit opt-in step.
  Widget _buildAnswerFollowUps() {
    // (label, icon, message-that-gets-sent, isPrimary)
    final followUps = <(String, IconData, String, bool)>[
      (
        'Remedies & upay',
        Icons.spa_outlined,
        'Iske liye remedies aur upay bataiye — mantra ke saath saath '
            'real-life practical solutions bhi (habits, lifestyle, '
            'career ya finance steps).',
        true,
      ),
      (
        'Explain in more detail',
        Icons.unfold_more_rounded,
        'Iske baare mein thoda aur detail mein samjhaiye.',
        false,
      ),
      (
        'What should I focus on?',
        Icons.center_focus_strong_outlined,
        'Mujhe abhi kis cheez par sabse zyada dhyaan dena chahiye?',
        false,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 2, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              'CONTINUE THE CONVERSATION',
              style: TextStyle(
                color: AppColors.textMuted.withOpacity(0.7),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, icon, message, isPrimary) in followUps)
                GestureDetector(
                  onTap: () {
                    _messageController.text = message;
                    _sendMessage();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isPrimary
                          ? AppColors.goldLight.withOpacity(0.14)
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isPrimary
                            ? AppColors.goldLight.withOpacity(0.5)
                            : AppColors.purpleAccent.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 14,
                          color: isPrimary
                              ? AppColors.goldLight
                              : AppColors.purpleLight,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            color: isPrimary
                                ? AppColors.goldLight
                                : AppColors.purpleLight,
                            fontSize: 12,
                            fontWeight: isPrimary
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms, delay: 150.ms)
        .slideY(begin: 0.15, end: 0, duration: 350.ms, delay: 150.ms);
  }

  /// Tappable chapter-reference cards rendered under an AI answer — one
  /// per summary bullet. Collapsed by default; tap to expand the full
  /// astrological explanation for that point.
  Widget _buildChapterCards(List<ChapterDetail> details) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined,
                    size: 13, color: AppColors.textMuted.withOpacity(0.8)),
                const SizedBox(width: 6),
                Text(
                  'TAP A CHAPTER FOR THE FULL EXPLANATION',
                  style: TextStyle(
                    color: AppColors.textMuted.withOpacity(0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < details.length; i++)
            ChapterDetailCard(
              key: ValueKey('chapter_${details[i].chapter}_$i'),
              pointNumber: i + 1,
              chapter: details[i].chapter.isNotEmpty
                  ? details[i].chapter
                  : 'Classical reference',
              explanation: details[i].explanation,
            ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms, delay: 100.ms)
        .slideY(begin: 0.1, end: 0, duration: 350.ms, delay: 100.ms);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome,
            size: 48,
            color: AppColors.purpleAccent.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Starting your session...',
            style: TextStyle(
              color: AppColors.textMuted.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.purpleAccent.withOpacity(0.22),
                  width: 0.8,
                ),
              ),
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Ask about career, love, health...',
                  hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.purpleAccent, AppColors.purpleSoft],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.purpleAccent.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          )
              .animate()
              .fadeIn(duration: 300.ms),
        ],
      ),
    );
  }
}
