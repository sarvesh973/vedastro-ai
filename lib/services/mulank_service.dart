import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/mulank_reading.dart';
import '../models/mulank_profile.dart';
import 'storage_service.dart';

/// Client for the Mulank (Ank Jyotish) backend endpoints.
///
/// The heavy lifting (deterministic numerology + daily-cached LLM prose)
/// lives on the server. This just posts the active profile's birth date +
/// language and parses the reply. Birth date is sent as unambiguous
/// `YYYY-MM-DD` (built from the DateTime) so the server never has to guess
/// DD/MM vs MM/DD.
class MulankService {
  static Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    String token = '';
    if (user != null) {
      try {
        token = await user.getIdToken() ?? '';
      } catch (_) {}
    }
    return {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Map the app's language preference to the server's mulank language
  /// codes (which the pre-warm cron uses): english -> 'en', hinglish stays.
  static String _lang() =>
      StorageService.languagePreference == 'hinglish' ? 'hinglish' : 'en';

  /// Fetch a reading for [period] (daily | weekly | monthly). Returns null
  /// on any failure so callers can degrade gracefully (hide the card).
  static Future<MulankReading?> getReading({
    String period = 'daily',
    DateTime? date,
  }) async {
    final profile = StorageService.currentProfile;
    if (profile == null) return null;
    try {
      final url = Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/mulank/reading');
      final resp = await http
          .post(
            url,
            headers: await _authHeaders(),
            body: jsonEncode({
              'birthDate': _iso(profile.dateOfBirth),
              'period': period,
              'language': _lang(),
              if (date != null) 'date': _iso(date),
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        return MulankReading.fromJson(
            jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  /// Fetch the static personality profile for the active mulank.
  static Future<MulankProfile?> getProfile() async {
    final profile = StorageService.currentProfile;
    if (profile == null) return null;
    try {
      final url = Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/mulank/profile');
      final resp = await http
          .post(
            url,
            headers: await _authHeaders(),
            body: jsonEncode({'birthDate': _iso(profile.dateOfBirth)}),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        return MulankProfile.fromJson(
            jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  /// Paid interactive "ask about my day". Returns the answer text or null.
  static Future<String?> ask(String question, {DateTime? date}) async {
    final profile = StorageService.currentProfile;
    if (profile == null) return null;
    try {
      final url = Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/mulank/ask');
      final resp = await http
          .post(
            url,
            headers: await _authHeaders(),
            body: jsonEncode({
              'birthDate': _iso(profile.dateOfBirth),
              'question': question,
              'language': _lang(),
              if (date != null) 'date': _iso(date),
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        return (jsonDecode(resp.body) as Map<String, dynamic>)['answer']
            as String?;
      }
    } catch (_) {}
    return null;
  }
}
