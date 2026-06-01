import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import 'firestore_service.dart';

/// Persistent storage service using SharedPreferences
class StorageService {
  static SharedPreferences? _prefs;
  static UserProfile? _currentProfile;

  static const int freeChatLimit = 1;
  static const int freePalmLimit = 0; // Palm reading is paid-only

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
  // Plan ID (free/trial/standard/premium) of the user's most recent
  // purchase. Set immediately on Razorpay success so the UI can show the
  // correct plan name and the correct upgrade options BEFORE the webhook
  // writes the canonical Firestore record. The Firestore stream takes over
  // once the webhook lands; this is just the fallback for those few seconds
  // (or longer if the webhook fails).
  static const String _keyLastPurchasedPlan = 'last_purchased_plan';
  // Local cache of the in-app chat thread, JSON-encoded list of ChatMessage.
  // Persisted on every add so the conversation survives process kill (user
  // swiping the app out of recents). Wiped on sign-in/sign-out so two
  // accounts never see each other's chats on the same device.
  static const String _keyChatThread = 'chat_thread_json';

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

  /// Update the user's currently-active profile in place.
  ///
  /// Use for the "edit profile" path — replaces the entry at
  /// activeProfileIndex with the new profile and writes it as the
  /// current profile. Does NOT add a new family entry. If there is no
  /// family entry yet (first-ever profile / cloud-restore), the profile
  /// is appended.
  ///
  /// For the "add a new family profile" flow, call [addNewProfile]
  /// instead — that one always appends and switches to the new entry.
  static Future<void> saveProfile(UserProfile profile) async {
    _currentProfile = profile;
    await _prefs?.setString(_keyProfile, profile.toJsonString());

    final activeIdx = activeProfileIndex;
    if (activeIdx >= 0 && activeIdx < _familyProfiles.length) {
      _familyProfiles[activeIdx] = profile;
      await _saveFamilyProfiles();
    } else {
      // First save (no family entry yet) — append and point active at it.
      _familyProfiles.add(profile);
      await _saveFamilyProfiles();
      await _prefs?.setInt(
          _keyActiveProfileIndex, _familyProfiles.length - 1);
    }

    // Sync to cloud (Firestore) — tied to current Firebase UID (Google/phone/email)
    // Fire-and-forget; local save is authoritative, cloud is backup.
    FirestoreService.syncProfile(profile);
    _saveFamilyToCloud();
  }

  /// Append a brand-new family profile and switch to it.
  ///
  /// Used for "Add another profile" flows (e.g. user_details_screen
  /// when not in onboarding). If an identical profile (same name + DOB
  /// + place) already exists, no duplicate is created — we just switch
  /// to the existing entry.
  static Future<void> addNewProfile(UserProfile profile) async {
    final dupIdx = _familyProfiles.indexWhere((p) =>
        p.name == profile.name &&
        p.dateOfBirth == profile.dateOfBirth &&
        p.placeOfBirth == profile.placeOfBirth);

    if (dupIdx >= 0) {
      _familyProfiles[dupIdx] = profile;
      await _saveFamilyProfiles();
      await switchToProfile(dupIdx);
    } else {
      _familyProfiles.add(profile);
      await _saveFamilyProfiles();
      await switchToProfile(_familyProfiles.length - 1);
    }

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

      // Subscription state — critical for re-installs. Without this,
      // a paying user who reinstalls sees "Free plan" instead of their
      // active subscription. Webhook already wrote it; we just read it
      // back into local SharedPreferences so the UI immediately reflects
      // their paid status.
      try {
        final cloudSub = await FirestoreService.loadCurrentSubscription();
        if (cloudSub.isActive) {
          await _prefs?.setBool(_keyIsPremium, true);
        }
      } catch (_) {}

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

  // ─── Chat thread persistence ────────────────────
  // Stored as a single JSON string. We cap at the most recent 200 messages
  // so a long-running thread can't blow up SharedPreferences.
  static String? get chatThreadRaw => _prefs?.getString(_keyChatThread);

  static Future<void> saveChatThreadRaw(String json) async {
    await _prefs?.setString(_keyChatThread, json);
  }

  static Future<void> clearChatThread() async {
    await _prefs?.remove(_keyChatThread);
  }

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

  /// The plan ID the user most recently purchased (e.g. "trial", "standard").
  /// Returns null if none recorded yet (free user, or pre-feature install).
  static String? get lastPurchasedPlan =>
      _prefs?.getString(_keyLastPurchasedPlan);

  static Future<void> setLastPurchasedPlan(String planId) async {
    await _prefs?.setString(_keyLastPurchasedPlan, planId);
  }

  // ─── Language preference ────────────────────────
  // 'english'  → all AI content (chat, kundli insights, horoscope) in
  //              pure English.
  // 'hinglish' → Hindi+English mix in Roman script.
  // Default 'hinglish' — the app is India-first; this matches the prior
  // behaviour (the server prompts used to default to Hinglish).
  static const String _keyLanguage = 'language_preference';

  static String get languagePreference =>
      _prefs?.getString(_keyLanguage) ?? 'hinglish';

  /// True once the user has explicitly chosen on the language screen.
  /// Used to decide whether to show that screen during onboarding.
  static bool get hasChosenLanguage =>
      _prefs?.getString(_keyLanguage) != null;

  static Future<void> setLanguagePreference(String lang) async {
    await _prefs?.setString(_keyLanguage, lang);
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
    await _prefs?.remove(_keyLastPurchasedPlan);
    await _prefs?.remove(_keyChatThread);
  }
}
