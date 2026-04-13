import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import '../models/chat_message.dart';
import '../models/palm_result.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';

// User profile provider (loaded from persistent storage)
final userProfileProvider = StateProvider<UserProfile?>((ref) {
  return StorageService.currentProfile;
});

// Family profiles list provider
final familyProfilesProvider = StateProvider<List<UserProfile>>((ref) {
  return StorageService.familyProfiles;
});

// Active profile index
final activeProfileIndexProvider = StateProvider<int>((ref) {
  return StorageService.activeProfileIndex;
});

// Chat messages provider
final chatMessagesProvider =
    StateNotifierProvider<ChatMessagesNotifier, List<ChatMessage>>(
  (ref) => ChatMessagesNotifier(),
);

// AI typing indicator
final isAiTypingProvider = StateProvider<bool>((ref) => false);

// Palm reading result provider
final palmResultProvider = StateProvider<PalmReadingResult?>((ref) => null);

// Palm image path provider
final palmImagePathProvider = StateProvider<String?>((ref) => null);

// Palm loading state
final isPalmAnalyzingProvider = StateProvider<bool>((ref) => false);

// Premium status provider
final isPremiumProvider = StateProvider<bool>((ref) => StorageService.isPremium);

// Chat questions used
final chatQuestionsUsedProvider =
    StateProvider<int>((ref) => StorageService.chatQuestionsUsed);

// Palm readings used
final palmReadingsUsedProvider =
    StateProvider<int>((ref) => StorageService.palmReadingsUsed);

class ChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  ChatMessagesNotifier() : super([]);

  void addMessage(ChatMessage message) {
    state = [...state, message];
  }

  void clear() {
    state = [];
  }

  Future<void> sendMessageAndGetResponse({
    required String text,
    required UserProfile profile,
    required StateController<bool> typingController,
  }) async {
    // Add user message
    addMessage(ChatMessage(
      text: text,
      role: MessageRole.user,
      timestamp: DateTime.now(),
    ));

    // Show typing indicator
    typingController.state = true;

    // Get AI response (Cloud Function RAG -> Direct Gemini -> Fallback)
    final aiResponse = await AiService.getAstrologyResponse(
      profile: profile,
      userMessage: text,
      chatHistory: state.map((m) => m.text).toList(),
    );

    // Hide typing indicator
    typingController.state = false;

    // Add AI message with sources
    addMessage(ChatMessage(
      text: aiResponse.text,
      role: MessageRole.ai,
      timestamp: DateTime.now(),
      sources: aiResponse.sources,
    ));

    // Track usage
    await StorageService.incrementChatQuestions();
  }
}
