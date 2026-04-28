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

  void _showPaywall() {
    // Smart plan filtering based on user's current state:
    //  - Free user (no isPremium) -> hide trial, show Standard + Premium
    //    so they can pay directly. Trial is for fresh users picking
    //    their first plan from the home screen, not for users who've
    //    already exhausted free chats.
    //  - Standard subscriber -> show only Premium (upgrade)
    //  - Premium subscriber -> shouldn't reach here (unlimited chats)
    //
    // We don't yet persist the exact plan (Standard vs Premium) — when
    // we do, refine the Standard-exhausted branch to detect it.
    final availablePlans = StorageService.isPremium
        ? const [SubscriptionPlan.premium]
        : const [SubscriptionPlan.standard, SubscriptionPlan.premium];

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
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.purpleAccent.withOpacity(0.6),
                    AppColors.purpleSoft.withOpacity(0.4),
                  ],
                ),
              ),
              child: const Icon(Icons.auto_awesome, size: 18, color: AppColors.goldLight),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VedAstro AI',
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
                      final isLastAi = msg.isAi &&
                          index == messages.length - 1 &&
                          _isTypewriterActive;

                      return ChatBubble(
                        message: msg,
                        animate: index >= messages.length - 2,
                        isLatestAiMessage: isLastAi,
                        onTypewriterComplete: () {
                          if (mounted) {
                            setState(() => _isTypewriterActive = false);
                          }
                        },
                      );
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
