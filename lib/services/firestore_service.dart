import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';

/// Cloud Firestore service for persistent cloud storage
class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  /// Get current user's UID (or null)
  static String? get _uid => AuthService.currentUser?.uid;

  // ─── User Profile ───────────────────────────────

  /// Save user profile to Firestore (auto-uses current UID)
  static Future<void> saveProfile(String uid, UserProfile profile) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _db.collection('users').doc(uid).set({
        ...profile.toJson(),
        'email': user?.email,
        'phoneNumber': user?.phoneNumber,
        'displayName': user?.displayName,
        'authProvider': _resolveAuthProvider(user),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Silently fail — local storage is primary
    }
  }

  /// Identify which auth method the user signed in with
  static String _resolveAuthProvider(User? user) {
    if (user == null) return 'anonymous';
    if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) return 'phone';
    final providers = user.providerData.map((p) => p.providerId).toList();
    if (providers.contains('google.com')) return 'google';
    if (providers.contains('password')) return 'email';
    if (providers.contains('phone')) return 'phone';
    return providers.isNotEmpty ? providers.first : 'unknown';
  }

  /// Sync profile: save to both local and cloud
  static Future<void> syncProfile(UserProfile profile) async {
    if (_uid != null) {
      await saveProfile(_uid!, profile);
    }
  }

  /// Save all family profiles as an array under the user document
  static Future<void> syncFamilyProfiles(List<UserProfile> profiles) async {
    if (_uid == null) return;
    try {
      await _db.collection('users').doc(_uid!).set({
        'familyProfiles': profiles.map((p) => p.toJson()).toList(),
        'familyUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Load family profiles from cloud
  static Future<List<UserProfile>> loadFamilyProfiles() async {
    if (_uid == null) return [];
    try {
      final doc = await _db.collection('users').doc(_uid!).get();
      final data = doc.data();
      if (data == null || data['familyProfiles'] == null) return [];
      final list = data['familyProfiles'] as List;
      return list
          .map((e) => UserProfile.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Get user profile from Firestore
  static Future<UserProfile?> getProfile(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;
      return UserProfile.fromJson(doc.data()!);
    } catch (_) {
      return null;
    }
  }

  /// Load profile from cloud (used on login to restore data)
  static Future<UserProfile?> loadCloudProfile() async {
    if (_uid == null) return null;
    return getProfile(_uid!);
  }

  // ─── Chat History ───────────────────────────────

  /// Save a chat message (fire and forget)
  static Future<void> saveChatMessage({
    required String uid,
    required String text,
    required String role,
  }) async {
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('chats')
          .add({
        'text': text,
        'role': role,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Save chat message using current user
  static void syncChatMessage(String text, String role) {
    if (_uid != null) {
      saveChatMessage(uid: _uid!, text: text, role: role);
    }
  }

  /// Get chat history for a user
  static Future<List<Map<String, dynamic>>> getChatHistory(String uid) async {
    try {
      final snapshot = await _db
          .collection('users')
          .doc(uid)
          .collection('chats')
          .orderBy('timestamp', descending: false)
          .limit(100)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Load chat history for current user
  static Future<List<Map<String, dynamic>>> loadCloudChats() async {
    if (_uid == null) return [];
    return getChatHistory(_uid!);
  }

  /// Clear chat history
  static Future<void> clearChatHistory(String uid) async {
    try {
      final batch = _db.batch();
      final snapshot = await _db
          .collection('users')
          .doc(uid)
          .collection('chats')
          .get();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {}
  }

  // ─── Usage Tracking ─────────────────────────────

  /// Get usage stats
  static Future<Map<String, dynamic>> getUsageStats(String uid) async {
    try {
      final doc = await _db.collection('usage').doc(uid).get();
      if (!doc.exists) {
        return {'chatUsed': 0, 'palmUsed': 0, 'isPremium': false};
      }
      return doc.data() ?? {'chatUsed': 0, 'palmUsed': 0, 'isPremium': false};
    } catch (_) {
      return {'chatUsed': 0, 'palmUsed': 0, 'isPremium': false};
    }
  }

  /// Sync usage stats to cloud
  static Future<void> syncUsage(int chatUsed, int palmUsed, bool isPremium) async {
    if (_uid == null) return;
    try {
      await _db.collection('usage').doc(_uid!).set({
        'chatUsed': chatUsed,
        'palmUsed': palmUsed,
        'isPremium': isPremium,
        'lastSyncAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Increment chat usage
  static Future<void> incrementChatUsage(String uid) async {
    try {
      await _db.collection('usage').doc(uid).set({
        'chatUsed': FieldValue.increment(1),
        'lastChatAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Increment palm usage
  static Future<void> incrementPalmUsage(String uid) async {
    try {
      await _db.collection('usage').doc(uid).set({
        'palmUsed': FieldValue.increment(1),
        'lastPalmAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Set premium status
  static Future<void> setPremium(String uid, bool isPremium) async {
    try {
      await _db.collection('usage').doc(uid).set({
        'isPremium': isPremium,
        'premiumSince': isPremium ? FieldValue.serverTimestamp() : null,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ─── Payment Records ────────────────────────

  /// Save Razorpay payment record
  static Future<void> savePaymentRecord({
    required String uid,
    required String paymentId,
    required String plan,
    required int amount,
  }) async {
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('payments')
          .doc(paymentId)
          .set({
        'paymentId': paymentId,
        'plan': plan,
        'amountPaise': amount,
        'status': 'success',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // ─── Palm Reading History ───────────────────────

  /// Save palm reading result
  static Future<void> savePalmReading({
    required String uid,
    required Map<String, dynamic> result,
  }) async {
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('palmReadings')
          .add({
        'result': result,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Sync palm reading for current user
  static void syncPalmReading(Map<String, dynamic> result) {
    if (_uid != null) {
      savePalmReading(uid: _uid!, result: result);
    }
  }
}
