import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';

/// Cloud Firestore service for persistent cloud storage
class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  // ─── User Profile ───────────────────────────────

  /// Save user profile to Firestore
  static Future<void> saveProfile(String uid, UserProfile profile) async {
    await _db.collection('users').doc(uid).set({
      ...profile.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Get user profile from Firestore
  static Future<UserProfile?> getProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserProfile.fromJson(doc.data()!);
  }

  // ─── Chat History ───────────────────────────────

  /// Save a chat message
  static Future<void> saveChatMessage({
    required String uid,
    required String text,
    required String role,
  }) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('chats')
        .add({
      'text': text,
      'role': role,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Get chat history for a user
  static Future<List<Map<String, dynamic>>> getChatHistory(String uid) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('chats')
        .orderBy('timestamp', descending: false)
        .limit(100)
        .get();

    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  /// Clear chat history
  static Future<void> clearChatHistory(String uid) async {
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
  }

  // ─── Usage Tracking ─────────────────────────────

  /// Get usage stats
  static Future<Map<String, dynamic>> getUsageStats(String uid) async {
    final doc = await _db.collection('usage').doc(uid).get();
    if (!doc.exists) {
      return {'chatUsed': 0, 'palmUsed': 0, 'isPremium': false};
    }
    return doc.data() ?? {'chatUsed': 0, 'palmUsed': 0, 'isPremium': false};
  }

  /// Increment chat usage
  static Future<void> incrementChatUsage(String uid) async {
    await _db.collection('usage').doc(uid).set({
      'chatUsed': FieldValue.increment(1),
      'lastChatAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Increment palm usage
  static Future<void> incrementPalmUsage(String uid) async {
    await _db.collection('usage').doc(uid).set({
      'palmUsed': FieldValue.increment(1),
      'lastPalmAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Set premium status
  static Future<void> setPremium(String uid, bool isPremium) async {
    await _db.collection('usage').doc(uid).set({
      'isPremium': isPremium,
      'premiumSince': isPremium ? FieldValue.serverTimestamp() : null,
    }, SetOptions(merge: true));
  }

  // ─── Palm Reading History ───────────────────────

  /// Save palm reading result
  static Future<void> savePalmReading({
    required String uid,
    required Map<String, dynamic> result,
  }) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('palmReadings')
        .add({
      'result': result,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
