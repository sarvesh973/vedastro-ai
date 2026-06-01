import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/chat_message.dart';
import '../models/user_profile.dart';
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

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _hasInitialized = false;
  bool _isTypewriterActive = false;

  /// Last question the user asked — passed to ContextualLoader so it can
  /// show topic-aware "Reading your career line..." style messages.
  String _lastUserQuestion = '';

  @override
  void initState() {
    super.initState();
    // Observe app lifecycle so we can auto-retry a recent offline reply
    // when the user returns from the recent-apps switcher. Android often
    // kills the in-flight HTTP socket when the app is backgrounded, so
    // a request that would have succeeded gets falsely classified as
    // "offline" by the AI service. On resume, if we see a fresh offline
    // bubble, we silently re-issue it.
    WidgetsBinding.instance.addObserver(this);
    // When the screen opens with pre-existing messages (rehydrated from
    // local cache after process kill, or just returning from Home), we want
    // the user to land on the most recent reply — not at the top of an old
    // thread. The list is built first frame; jump after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;

    final messages = ref.read(chatMessagesProvider);
    if (messages.isEmpty) return;
    final last = messages.last;
    if (!last.isAi || !last.isOffline) return;
    // Only auto-retry if the offline reply was issued recently. Older
    // ones probably reflect a genuinely-offline session — leaving them
    // alone respects what the user actually saw and the user can always
    // use the in-bubble Retry button.
    final age = DateTime.now().difference(last.timestamp);
    if (age > const Duration(seconds: 90)) return;
    _retryLastOfflineMessage();
  }

  /// Instant jump (no animation) — used on first build to land at the latest
  /// message without a visible scroll. The animated variant is _scrollToBottom.
  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
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

  /// [serverPromptOverride] lets the follow-up chips show a clean short
  /// label in the user's bubble ("Explain in more detail") while sending
  /// the AI a far richer prompt that explicitly quotes the previous
  /// answer plus a "expand each point, go deeper" directive. Without
  /// the override the server's structured prompt just re-summarises
  /// the same content and the chip appears to do nothing.
  Future<void> _sendMessage({String? serverPromptOverride}) async {
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

    // Add user message
    chatNotifier.addMessage(ChatMessage(
      text: text,
      role: MessageRole.user,
      timestamp: DateTime.now(),
    ));
    // Sync to cloud
    FirestoreService.syncChatMessage(text, 'user');
    _scrollToBottom();

    await _requestAndStoreAiReply(
      profile: profile,
      visibleText: text,
      serverPromptOverride: serverPromptOverride,
    );
  }

  /// Drop the most-recent offline AI bubble (if any) and re-issue the
  /// request for the user message that preceded it. Used both by the
  /// in-bubble Retry button and by the auto-resume hook above.
  Future<void> _retryLastOfflineMessage() async {
    final profile = ref.read(userProfileProvider);
    if (profile == null) return;

    final messages = ref.read(chatMessagesProvider);
    final offlineIdx = messages.lastIndexWhere((m) => m.isAi && m.isOffline);
    if (offlineIdx <= 0) return;
    final userMsg = messages[offlineIdx - 1];
    if (!userMsg.isUser) return;

    _lastUserQuestion = userMsg.text;
    ref.read(chatMessagesProvider.notifier).removeLastOfflineAi();
    _scrollToBottom();

    await _requestAndStoreAiReply(
      profile: profile,
      visibleText: userMsg.text,
      serverPromptOverride: null,
    );
  }

  /// Shared "ask the AI" path used by send + retry. Pulled out so a
  /// retry doesn't re-add the user's question bubble — only the live
  /// AI request and its result-handling.
  Future<void> _requestAndStoreAiReply({
    required UserProfile profile,
    required String visibleText,
    required String? serverPromptOverride,
  }) async {
    final chatNotifier = ref.read(chatMessagesProvider.notifier);
    final typingController = ref.read(isAiTypingProvider.notifier);

    // Show typing
    typingController.state = true;
    _scrollToBottom();

    // Get AI response (tries Cloud Function RAG -> Direct Gemini -> Fallback).
    // [serverPromptOverride] takes precedence for follow-up chips that
    // need a richer context-laden prompt than the user's visible bubble.
    final aiResponse = await AiService.getAstrologyResponse(
      profile: profile,
      userMessage: serverPromptOverride ?? visibleText,
      chatHistory: ref.read(chatMessagesProvider).map((m) => m.text).toList(),
    );

    // CRITICAL: store the AI reply into the chat-messages provider BEFORE
    // touching any widget state. If the user navigated away during the
    // await above, this State is disposed — calling setState() throws,
    // which would abort the function before the message ever got
    // recorded (the original "user comes back to chat and sees nothing"
    // bug). The provider is global, so addMessage works regardless of
    // whether this screen is still mounted.
    typingController.state = false;

    // Server-side quota exhausted — don't render the 'limit reached'
    // text as a chat bubble. Roll back the user's optimistic bubble
    // (we already added it before sending), restore the text to the
    // input field, and open the paywall sheet so they see upgrade
    // options instead of a discouraging dead-end message. After
    // dismissing the paywall they can retry from a clean state.
    if (aiResponse.rateLimited && mounted) {
      chatNotifier.removeLastMessage();
      _messageController.text = text;
      _showPaywall();
      return;
    }

    chatNotifier.addMessage(ChatMessage(
      text: aiResponse.text,
      role: MessageRole.ai,
      timestamp: DateTime.now(),
      sources: aiResponse.sources,
      details: aiResponse.details,
      debugRaw: aiResponse.debugRaw,
      isOffline: aiResponse.isOffline,
      debugMeta: aiResponse.debugMeta,
    ));

    // Online-only side effects. Skip them when we served a template
    // fallback (no real LLM call happened, so the user's quota should
    // not be charged, and we don't want to permanently log generic
    // template text into the cloud chat history as if it were a real
    // personalised answer).
    if (!aiResponse.isOffline) {
      FirestoreService.syncChatMessage(aiResponse.text, 'ai');
      await StorageService.incrementChatQuestions();
    }

    // The remaining work is UI-only: typewriter animation flag,
    // provider-driven quota counter refresh, scroll positioning. Skip
    // it entirely if the user has left the screen — those calls would
    // either throw (`setState`/`ref.read` after dispose) or be visual
    // no-ops anyway.
    if (!mounted) return;

    setState(() => _isTypewriterActive = true);

    if (!aiResponse.isOffline) {
      ref.read(chatQuestionsUsedProvider.notifier).state =
          StorageService.chatQuestionsUsed;
    }

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

                      // Only the most-recent offline AI bubble offers a
                      // Retry tap — older ones are historical and a retry
                      // would only confuse the conversation context.
                      final isLastOfflineAi = msg.isAi &&
                          msg.isOffline &&
                          isLastMessage;

                      final bubble = ChatBubble(
                        message: msg,
                        animate: index >= messages.length - 2,
                        isLatestAiMessage: isLastAi,
                        onTypewriterComplete: () {
                          if (mounted) {
                            setState(() => _isTypewriterActive = false);
                          }
                        },
                        onRetry: isLastOfflineAi
                            ? _retryLastOfflineMessage
                            : null,
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
    // Suggestion text is sent verbatim as the user's question, so the
    // language has to match the user's pick — otherwise an English user
    // taps a chip and their own message appears in Hinglish.
    final isEnglish = StorageService.languagePreference == 'english';
    final suggestions = isEnglish
        ? const [
            'How will my career be?',
            'Tell me about my love life',
            'Health prediction',
            'Finance & wealth',
          ]
        : const [
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
    // Tapping a chip sends the message text as the user's next question.
    // Both the chip label AND the sent text need to match the user's
    // chosen language — otherwise an English user taps "Remedies" and
    // suddenly their own bubble shows a Hinglish prompt.
    final isEnglish = StorageService.languagePreference == 'english';

    // (label, icon, message-that-gets-sent, isPrimary)
    final followUps = isEnglish
        ? <(String, IconData, String, bool)>[
            (
              'Remedies',
              Icons.spa_outlined,
              'Please share remedies for this — mantras as well as real-life '
                  'practical steps (habits, lifestyle, career or finance).',
              true,
            ),
            (
              'Explain in more detail',
              Icons.unfold_more_rounded,
              'Please explain this in more detail.',
              false,
            ),
            (
              'What should I focus on?',
              Icons.center_focus_strong_outlined,
              'What should I focus on the most right now?',
              false,
            ),
          ]
        : <(String, IconData, String, bool)>[
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
                    // Build a context-rich prompt for the server that
                    // explicitly quotes the previous AI answer + tells
                    // the model to go deeper. The user's bubble still
                    // shows the short clean [label]. Without this, the
                    // server's structured-output prompt just re-summarises
                    // the same content and "Explain in more detail"
                    // appears to do nothing.
                    final override = _buildFollowUpServerPrompt(
                      label: label,
                      fallback: message,
                      isEnglish: isEnglish,
                    );
                    _messageController.text = label;
                    _sendMessage(serverPromptOverride: override);
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

  /// Builds the server-side prompt for a follow-up chip. Quotes the
  /// most recent AI answer verbatim and tells the model exactly how to
  /// go deeper — fixes the "Explain in more detail just repeats the
  /// same bullets" bug where the vague "iske baare mein detail bataiye"
  /// gave the structured-output template nothing to grip on.
  ///
  /// Falls back to [fallback] if there's no previous AI message yet
  /// (shouldn't happen in practice since chips only appear under one).
  String _buildFollowUpServerPrompt({
    required String label,
    required String fallback,
    required bool isEnglish,
  }) {
    // IMPORTANT: do NOT inline the previous AI reply here. It already
    // travels to the server in `chatHistory`. Inlining it pushed the
    // prompt to ~2KB which tipped Gemini past the 60s timeout — the
    // server call failed and the user landed on the keyword-template
    // fallback instead of a real expanded reading. Short, sharp
    // directives that REFER to "your previous reply" are both faster
    // and more effective.

    if (label == 'Explain in more detail') {
      return isEnglish
          ? 'Take your previous reply in this conversation and expand each '
              'point significantly. For every point: add deeper Vedic '
              'reasoning (cite the BPHS / Phaladeepika chapter or verse), '
              'explain the dasha or transit mechanics, and give a concrete '
              'real-life example. The reply must be noticeably longer and '
              'richer — every point should carry new insight, not just '
              'rephrase the previous one.'
          : 'Apne pichle reply mein jo points the, un sab ko detail mein '
              'expand kijiye. Har point ke liye: gehre Vedic reasoning '
              '(BPHS ya Phaladeepika ka exact adhyay ya shloka), dasha aur '
              'transit ki mechanics, aur ek real-life example. Pichle '
              'answer se kaafi longer aur deeper hona chahiye — har point '
              'mein nayi baat ho, sirf rephrase nahi.';
    } else if (label.startsWith('Remedies')) {
      return isEnglish
          ? 'For the reading you just gave me, share remedies and upay — '
              'BOTH classical (mantras with the right day/time/count, '
              'fasts, gemstones if appropriate) AND real-life practical '
              'steps (habits, lifestyle, specific career or finance '
              'actions I can start this week).'
          : 'Aapne abhi jo reading di hai uske liye remedies aur upay '
              'bataiye — classical (mantra sahi din/samay/count ke saath, '
              'vrat, ratna jo bhi sahi ho) ke saath saath real-life '
              'practical steps bhi (habits, lifestyle, career ya finance '
              'ke kaam jo main is hafte se shuru kar sakta hoon).';
    } else if (label == 'What should I focus on?') {
      return isEnglish
          ? 'Based on the reading you just gave me, what single most '
              'important thing should I focus on right now? Pick the most '
              'urgent point and explain in detail why it matters most this '
              'month and what exactly I should do about it.'
          : 'Aapne abhi jo reading di uske aadhar par, mujhe sabse zyada '
              'kis cheez par dhyaan dena chahiye? Sabse important ek baat '
              'chuniye aur detail mein samjhaiye ki yeh is mahine sabse '
              'zaroori kyun hai aur main exactly kya karoon.';
    }
    return fallback;
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
