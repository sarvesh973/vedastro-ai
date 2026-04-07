import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

/// Persistent storage service using SharedPreferences
class StorageService {
  static SharedPreferences? _prefs;
  static UserProfile? _currentProfile;

  static const int freeChatLimit = 5;
  static const int freePalmLimit = 2;

  // Keys
  static const String _keyOnboardingComplete = 'onboarding_complete';
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserPassword = 'user_password';
  static const String _keyProfile = 'user_profile';
  static const String _keyChatUsed = 'chat_questions_used';
  static const String _keyPalmUsed = 'palm_readings_used';
  static const String _keyIsPremium = 'is_premium';

  /// Initialize SharedPreferences (call once at app start)
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Load profile from storage
    final profileJson = _prefs?.getString(_keyProfile);
    _currentProfile = UserProfile.fromJsonString(profileJson);
  }

  // ─── Onboarding ─────────────────────────────────
  static bool get isOnboardingComplete =>
      _prefs?.getBool(_keyOnboardingComplete) ?? false;

  static Future<void> setOnboardingComplete() async {
    await _prefs?.setBool(_keyOnboardingComplete, true);
  }

  // ─── Auth ───────────────────────────────────────
  static bool get isLoggedIn => _prefs?.getBool(_keyIsLoggedIn) ?? false;
  static String? get userEmail => _prefs?.getString(_keyUserEmail);

  static Future<void> signUp(String email, String password) async {
    await _prefs?.setString(_keyUserEmail, email);
    await _prefs?.setString(_keyUserPassword, password);
    await _prefs?.setBool(_keyIsLoggedIn, true);
  }

  static Future<bool> login(String email, String password) async {
    final storedEmail = _prefs?.getString(_keyUserEmail);
    final storedPassword = _prefs?.getString(_keyUserPassword);
    if (storedEmail == email && storedPassword == password) {
      await _prefs?.setBool(_keyIsLoggedIn, true);
      return true;
    }
    // For MVP: auto-login with any credentials (simulated)
    await _prefs?.setString(_keyUserEmail, email);
    await _prefs?.setBool(_keyIsLoggedIn, true);
    return true;
  }

  static Future<void> logout() async {
    await _prefs?.setBool(_keyIsLoggedIn, false);
    _currentProfile = null;
  }

  // ─── Profile ────────────────────────────────────
  static UserProfile? get currentProfile => _currentProfile;
  static bool get hasProfile => _currentProfile != null;

  static Future<void> saveProfile(UserProfile profile) async {
    _currentProfile = profile;
    await _prefs?.setString(_keyProfile, profile.toJsonString());
  }

  static Future<void> clearProfile() async {
    _currentProfile = null;
    await _prefs?.remove(_keyProfile);
  }

  // ─── Usage Tracking ─────────────────────────────
  static bool get isPremium => _prefs?.getBool(_keyIsPremium) ?? false;
  static int get chatQuestionsUsed => _prefs?.getInt(_keyChatUsed) ?? 0;
  static int get palmReadingsUsed => _prefs?.getInt(_keyPalmUsed) ?? 0;

  static bool get canAskChatQuestion =>
      isPremium || chatQuestionsUsed < freeChatLimit;

  static bool get canDoPalmReading =>
      isPremium || palmReadingsUsed < freePalmLimit;

  static Future<void> incrementChatQuestions() async {
    final current = chatQuestionsUsed + 1;
    await _prefs?.setInt(_keyChatUsed, current);
  }

  static Future<void> incrementPalmReadings() async {
    final current = palmReadingsUsed + 1;
    await _prefs?.setInt(_keyPalmUsed, current);
  }

  static Future<void> upgradeToPremium() async {
    await _prefs?.setBool(_keyIsPremium, true);
  }

  // ─── Reset ──────────────────────────────────────
  static Future<void> reset() async {
    _currentProfile = null;
    await _prefs?.clear();
  }
}
