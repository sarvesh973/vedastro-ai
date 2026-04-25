import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import 'firestore_service.dart';

/// Persistent storage service using SharedPreferences
class StorageService {
  static SharedPreferences? _prefs;
  static UserProfile? _currentProfile;

  static const int freeChatLimit = 2;
  static const int freePalmLimit = 1;

  static List<UserProfile> _familyProfiles = [];

  // Keys
  static const String _keyOnboardingComplete = 'onboarding_complete';
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserPassword = 'user_password';
  static const String _keyProfile = 'user_profile';
  static const String _keyFamilyProfiles = 'family_profiles';
  static const String _keyActiveProfileIndex = 'active_profile_index';
  static const String _keyChatUsed = 'chat_questions_used';
  static const String _keyPalmUsed = 'palm_readings_used';
  static const String _keyIsPremium = 'is_premium';

  /// Initialize SharedPreferences (call once at app start)
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Load family profiles
    _loadFamilyProfiles();
    // Load active profile from storage
    final profileJson = _prefs?.getString(_keyProfile);
    _currentProfile = UserProfile.fromJsonString(profileJson);
  }

  // ─── Family Profiles ───────────────────────────
  static List<UserProfile> get familyProfiles => _familyProfiles;
  static int get activeProfileIndex => _prefs?.getInt(_keyActiveProfileIndex) ?? 0;

  static void _loadFamilyProfiles() {
    final jsonList = _prefs?.getStringList(_keyFamilyProfiles) ?? [];
    _familyProfiles = jsonList
        .map((json) => UserProfile.fromJsonString(json))
        .where((p) => p != null)
        .cast<UserProfile>()
        .toList();
  }

  static Future<void> _saveFamilyProfiles() async {
    final jsonList = _familyProfiles.map((p) => p.toJsonString()).toList();
    await _prefs?.setStringList(_keyFamilyProfiles, jsonList);
  }

  static Future<void> addFamilyProfile(UserProfile profile) async {
    _familyProfiles.add(profile);
    await _saveFamilyProfiles();
    // Auto-switch to new profile
    await switchToProfile(_familyProfiles.length - 1);
  }

  static Future<void> removeFamilyProfile(int index) async {
    if (index < 0 || index >= _familyProfiles.length) return;
    _familyProfiles.removeAt(index);
    await _saveFamilyProfiles();
    // Switch to first profile or clear
    if (_familyProfiles.isNotEmpty) {
      await switchToProfile(0);
    } else {
      await clearProfile();
    }
  }

  static Future<void> switchToProfile(int index) async {
    if (index < 0 || index >= _familyProfiles.length) return;
    _currentProfile = _familyProfiles[index];
    await _prefs?.setInt(_keyActiveProfileIndex, index);
    await _prefs?.setString(_keyProfile, _currentProfile!.toJsonString());
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
    // Also add to family profiles if not already there
    final exists = _familyProfiles.any((p) =>
        p.name == profile.name &&
        p.dateOfBirth == profile.dateOfBirth &&
        p.placeOfBirth == profile.placeOfBirth);
    if (!exists) {
      _familyProfiles.add(profile);
      await _saveFamilyProfiles();
      await _prefs?.setInt(_keyActiveProfileIndex, _familyProfiles.length - 1);
    }
    // Sync to cloud (Firestore) — tied to current Firebase UID (Google/phone/email)
    // Fire-and-forget; local save is authoritative, cloud is backup.
    FirestoreService.syncProfile(profile);
    _saveFamilyToCloud();
  }

  /// Sync all family profiles to cloud (as array)
  static Future<void> _saveFamilyToCloud() async {
    try {
      await FirestoreService.syncFamilyProfiles(_familyProfiles);
    } catch (_) {}
  }

  /// Load profile + family profiles from cloud for the currently signed-in
  /// Firebase user. Call this right after login to restore data on a new
  /// device or fresh install. Non-destructive — cloud wins for main profile,
  /// but local family profiles get merged (deduplicated).
  static Future<bool> loadFromCloudForCurrentUser() async {
    try {
      // Main profile
      final cloudProfile = await FirestoreService.loadCloudProfile();
      if (cloudProfile != null) {
        _currentProfile = cloudProfile;
        await _prefs?.setString(_keyProfile, cloudProfile.toJsonString());
      }

      // Family profiles — merge with local (dedup by name+dob+place)
      final cloudFamily = await FirestoreService.loadFamilyProfiles();
      if (cloudFamily.isNotEmpty) {
        for (final p in cloudFamily) {
          final exists = _familyProfiles.any((lp) =>
              lp.name == p.name &&
              lp.dateOfBirth == p.dateOfBirth &&
              lp.placeOfBirth == p.placeOfBirth);
          if (!exists) _familyProfiles.add(p);
        }
        await _saveFamilyProfiles();
      }
      return cloudProfile != null || cloudFamily.isNotEmpty;
    } catch (_) {
      return false;
    }
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
    _familyProfiles = [];
    await _prefs?.clear();
  }

  /// Wipe ALL user-specific data from local storage.
  /// Called on signOut and before signIn so switching between Gmail accounts
  /// (or email / phone numbers) never leaks one user's data into another.
  /// Keeps the onboarding flag (the new user won't have to re-do the tour
  /// on the same physical device).
  static Future<void> clearAllLocalData() async {
    _currentProfile = null;
    _familyProfiles = [];
    await _prefs?.remove(_keyProfile);
    await _prefs?.remove(_keyFamilyProfiles);
    await _prefs?.remove(_keyActiveProfileIndex);
    await _prefs?.remove(_keyUserEmail);
    await _prefs?.remove(_keyUserPassword);
    await _prefs?.remove(_keyIsLoggedIn);
    await _prefs?.remove(_keyChatUsed);
    await _prefs?.remove(_keyPalmUsed);
    await _prefs?.remove(_keyIsPremium);
  }
}
