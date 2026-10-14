import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import '../models/user_profile.dart';
import '../models/subscription_plan.dart';
import '../models/subscription_status.dart';
import 'auth_service.dart';

/// Cloud Firestore service for persistent cloud storage
class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  /// Get current user's UID (or null)
  static String? get _uid => AuthService.currentUser?.uid;

  // ─── UTF-16 safety for the Firestore platform channel ───────────
  //
  // Crashlytics issue bd6a788b: "Invalid argument(s): string is not
  // well-formed UTF-16", fatal, 929 events across 1.1.3-1.1.10, with
  // FlutterFirebaseFirestorePlugin.documentReferenceSet in flight.
  //
  // The channel encodes every string as UTF-8. An unpaired surrogate —
  // half of an emoji whose partner got lost — has no UTF-8 encoding, so
  // the codec throws. That throw happens inside the channel rather than
  // in the Future we await, so the `catch (_)` wrappers below never see
  // it: it escapes as an uncaught FlutterError and kills the app.
  //
  // Sanitising at this boundary fixes the whole class at once, which
  // matters because the character can arrive from anywhere a user types
  // or pastes (names, birthplace, family profiles).

  /// Drop unpaired UTF-16 surrogates; valid pairs (real emoji) are kept.
  static String _sanitizeUtf16(String s) {
    // Fast path: most strings have no surrogates at all.
    var hasSurrogate = false;
    for (var i = 0; i < s.length; i++) {
      final u = s.codeUnitAt(i);
      if (u >= 0xD800 && u <= 0xDFFF) {
        hasSurrogate = true;
        break;
      }
    }
    if (!hasSurrogate) return s;

    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final u = s.codeUnitAt(i);
      if (u >= 0xD800 && u <= 0xDBFF) {
        // High surrogate — keep only when a low surrogate follows.
        if (i + 1 < s.length) {
          final next = s.codeUnitAt(i + 1);
          if (next >= 0xDC00 && next <= 0xDFFF) {
            out.writeCharCode(u);
            out.writeCharCode(next);
            i++;
            continue;
          }
        }
        continue;
      }
      if (u >= 0xDC00 && u <= 0xDFFF) continue; // orphaned low surrogate
      out.writeCharCode(u);
    }
    return out.toString();
  }

  /// Recursively sanitise a Firestore payload. Sentinels such as
  /// FieldValue.serverTimestamp() are neither String, List nor Map, so
  /// they pass through untouched.
  static Map<String, dynamic> _clean(Map<String, dynamic> data) =>
      data.map((k, v) => MapEntry(k, _cleanValue(v)));

  static dynamic _cleanValue(dynamic v) {
    if (v is String) return _sanitizeUtf16(v);
    if (v is List) return v.map(_cleanValue).toList();
    if (v is Map) {
      return v.map<dynamic, dynamic>((k, val) => MapEntry(k, _cleanValue(val)));
    }
    return v;
  }

  /// Truncate without slicing a surrogate pair in half — a plain
  /// substring(0, n) is itself a way to manufacture the bad character.
  static String _truncateUtf16(String s, int max) {
    if (s.length <= max) return s;
    var end = max;
    final last = s.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--; // don't split the pair
    return s.substring(0, end);
  }

  // ─── Subscription State (read-side) ────────────────────────────
  //
  // The webhook (vedastro-rag-server -> /subscription/webhook) writes
  // subscription state to:
  //   users/{uid}/subscription/current
  // This method reads it back so the app can show the user their plan
  // and pass the real razorpaySubscriptionId to /subscription/cancel.
  //
  // Returns SubscriptionStatus.free if the user has no record yet
  // (e.g. brand new user, or doc was deleted on account deletion).

  /// Loads the current user's subscription state from Firestore.
  /// Safe to call frequently — reads one doc, single network round-trip.
  static Future<SubscriptionStatus> loadCurrentSubscription() async {
    if (_uid == null) return SubscriptionStatus.free;
    try {
      final doc = await _db
          .collection('users')
          .doc(_uid!)
          .collection('subscription')
          .doc('current')
          .get();

      if (!doc.exists || doc.data() == null) {
        return SubscriptionStatus.free;
      }
      final data = doc.data()!;
      // Firestore returns Timestamp objects; convert to ISO strings so
      // SubscriptionStatus.fromJson can parse them uniformly.
      final normalized = <String, dynamic>{
        ...data,
        'trialEndsAt': _tsToIso(data['trialEndsAt']),
        'currentPeriodEndsAt': _tsToIso(data['currentPeriodEndsAt']),
        'passExpiresAt': _tsToIso(data['passExpiresAt']),
        'cancelledAt': _tsToIso(data['cancelledAt']),
      };
      return SubscriptionStatus.fromJson(normalized);
    } catch (e) {
      // Network / permission failure -> conservative fallback. The app's
      // local isPremium flag still drives gating until cloud catches up.
      return SubscriptionStatus.free;
    }
  }

  /// Real-time stream of subscription state — useful for the Settings
  /// → Subscription screen so it updates the moment a webhook fires
  /// (e.g. user just paid, screen shows "Active" without manual refresh).
  static Stream<SubscriptionStatus> subscriptionStream() {
    if (_uid == null) {
      return Stream.value(SubscriptionStatus.free);
    }
    return _db
        .collection('users')
        .doc(_uid!)
        .collection('subscription')
        .doc('current')
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) {
        return SubscriptionStatus.free;
      }
      final data = snap.data()!;
      final normalized = <String, dynamic>{
        ...data,
        'trialEndsAt': _tsToIso(data['trialEndsAt']),
        'currentPeriodEndsAt': _tsToIso(data['currentPeriodEndsAt']),
        'passExpiresAt': _tsToIso(data['passExpiresAt']),
        'cancelledAt': _tsToIso(data['cancelledAt']),
      };
      return SubscriptionStatus.fromJson(normalized);
    });
  }

  static String? _tsToIso(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate().toIso8601String();
    if (raw is DateTime) return raw.toIso8601String();
    if (raw is String) return raw;
    return null;
  }

  // ─── User Profile ───────────────────────────────

  /// Save user profile to Firestore (auto-uses current UID)
  static Future<void> saveProfile(String uid, UserProfile profile) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _db.collection('users').doc(uid).set(_clean({
        ...profile.toJson(),
        'email': user?.email,
        'phoneNumber': user?.phoneNumber,
        'displayName': user?.displayName,
        'authProvider': _resolveAuthProvider(user),
        'updatedAt': FieldValue.serverTimestamp(),
      }), SetOptions(merge: true));
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
      await _db.collection('users').doc(_uid!).set(_clean({
        'familyProfiles': profiles.map((p) => p.toJson()).toList(),
        'familyUpdatedAt': FieldValue.serverTimestamp(),
      }), SetOptions(merge: true));
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
          .add(_clean({
        'text': text,
        'role': role,
        'timestamp': FieldValue.serverTimestamp(),
      }));
    } catch (_) {}
  }

  /// Save chat message using current user
  static void syncChatMessage(String text, String role) {
    if (_uid != null) {
      saveChatMessage(uid: _uid!, text: text, role: role);
    }
  }

  /// Flag an AI response as offensive / inappropriate. Required by Google
  /// Play's Generative AI policy: users must be able to report AI-generated
  /// content in-app. Reports land in a top-level `ai_reports` collection
  /// for moderation review.
  static Future<void> reportAiMessage({
    required String messageText,
    String reason = 'inappropriate',
  }) async {
    try {
      await _db.collection('ai_reports').add(_clean({
        'uid': _uid ?? 'anonymous',
        // substring(0, 2000) could cut an emoji in half and manufacture
        // the exact unpaired surrogate that crashes the channel.
        'messageText': _truncateUtf16(messageText, 2000),
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
      }));
    } catch (_) {}
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

  /// Set premium status (legacy flag in usage/{uid}). The canonical
  /// subscription doc lives at users/{uid}/subscription/current and is
  /// written by the Razorpay webhook on Render — clients can't write it
  /// (Firestore rules enforce server-only writes).
  static Future<void> setPremium(String uid, bool isPremium) async {
    try {
      await _db.collection('usage').doc(uid).set({
        'isPremium': isPremium,
        'premiumSince': isPremium ? FieldValue.serverTimestamp() : null,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Stamp the install source onto the user document.
  ///
  /// GA4 already carries it as a user property, but GA4 cannot be joined to
  /// the subscription records the admin dashboard reads. Writing it here is
  /// what lets /admin/api/subscriptions answer "how many of this creator's
  /// installs actually subscribed", which is the number creators get paid on.
  ///
  /// Written on sign-in rather than on purchase, because a user who never
  /// subscribes is still needed as the denominator.
  static Future<void> saveAttribution(
    String uid,
    Map<String, String> attribution,
  ) async {
    if (attribution.isEmpty) return;
    try {
      await _db.collection('users').doc(uid).set({
        'attribution': attribution,
        // Only set once. A later launch must not overwrite the original
        // source with 'organic' and quietly erase the credit.
        'attributionAt': FieldValue.serverTimestamp(),
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

  // ─── Feedback ───────────────────────────────────

  /// Save user feedback to Firestore.
  /// View in Firebase Console -> Firestore Database -> `feedback` collection.
  /// Works even for anonymous / logged-out users.
  ///
  /// Returns null on success, or a short error string on failure (e.g.
  /// "permission-denied", "unavailable", "deadline-exceeded"). Caller can
  /// show a friendly message to the user AND log the technical cause for
  /// admins instead of guessing "check your internet" for every failure.
  static Future<String?> saveFeedback({
    required String text,
    String? category,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _db.collection('feedback').add({
        'text': text,
        'category': category ?? 'general',
        'uid': user?.uid,
        'email': user?.email,
        'phoneNumber': user?.phoneNumber,
        'displayName': user?.displayName,
        'isAnonymous': user == null,
        'timestamp': FieldValue.serverTimestamp(),
      });
      return null;
    } on FirebaseException catch (e) {
      // Most likely cause: Firestore rules don't allow writes to
      // /feedback. The code is what we need to confirm it.
      return '${e.code}${e.message != null ? ': ${e.message}' : ''}';
    } catch (e) {
      return e.toString();
    }
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
