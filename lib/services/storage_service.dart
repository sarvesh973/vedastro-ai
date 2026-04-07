import '../models/user_profile.dart';

/// Simple in-memory storage for MVP
class StorageService {
  static UserProfile? _currentProfile;
  static int _chatQuestionsUsed = 0;
  static int _palmReadingsUsed = 0;
  static bool _isPremium = false;

  static const int freeChatLimit = 5;
  static const int freePalmLimit = 2;

  static UserProfile? get currentProfile => _currentProfile;
  static bool get isPremium => _isPremium;
  static int get chatQuestionsUsed => _chatQuestionsUsed;
  static int get palmReadingsUsed => _palmReadingsUsed;

  static bool get canAskChatQuestion =>
      _isPremium || _chatQuestionsUsed < freeChatLimit;

  static bool get canDoPalmReading =>
      _isPremium || _palmReadingsUsed < freePalmLimit;

  static void saveProfile(UserProfile profile) {
    _currentProfile = profile;
  }

  static void incrementChatQuestions() {
    _chatQuestionsUsed++;
  }

  static void incrementPalmReadings() {
    _palmReadingsUsed++;
  }

  static void upgradeToPremium() {
    _isPremium = true;
  }

  static void reset() {
    _currentProfile = null;
    _chatQuestionsUsed = 0;
    _palmReadingsUsed = 0;
    _isPremium = false;
  }
}
