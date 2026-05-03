import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../config/vedic_system_prompt.dart';
import '../models/user_profile.dart';
import '../models/palm_result.dart';
import '../models/chat_message.dart';

/// Helper: get headers with Firebase Auth ID token for Cloud Function calls.
/// Cloud Functions reject unauthenticated requests.
Future<Map<String, String>> _authHeaders() async {
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

/// Response from AI service, including text and optional Vedic sources
class AiResponse {
  final String text;
  final List<VedicSource> sources;

  const AiResponse({required this.text, this.sources = const []});
}

class AiService {
  static GenerativeModel? _visionModel; // Only used for palm reading
  static GenerativeModel? _chatModel;   // Gemini fallback for chat
  static ChatSession? _currentChat;
  static UserProfile? _currentProfile;
  static final _random = Random();

  /// Last error from Gemini/server calls (for UI diagnostics)
  static String lastDiagnosticError = '';

  /// Initialize/reset the Gemini chat model (fallback when server is down)
  static void _initChatModel(UserProfile profile) {
    if (!ApiConfig.isConfigured) return;

    // Re-init if profile changed or model not created yet
    if (_chatModel == null || _currentProfile != profile) {
      _chatModel = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: ApiConfig.geminiApiKey,
        systemInstruction: Content.text(
          VedicSystemPrompt.build(userProfileSummary: profile.profileSummary),
        ),
        generationConfig: GenerationConfig(
          temperature: 0.9,
          maxOutputTokens: 1500,
        ),
      );
      _currentChat = _chatModel!.startChat();
      _currentProfile = profile;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CLOUD FUNCTIONS (RAG-powered, primary)
  // ─────────────────────────────────────────────────────────────

  static String _lastError = '';

  /// Try Cloud Functions RAG endpoint first
  static Future<AiResponse?> _tryCloudFunction({
    required UserProfile profile,
    required String userMessage,
    required List<String> chatHistory,
  }) async {
    try {
      final url = Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/chat');
      print('[RAG] Calling: $url');
      final headers = await _authHeaders();
      final response = await http
          .post(
            url,
            headers: headers,
            body: jsonEncode({
              'question': userMessage,
              'userProfile': profile.profileSummary,
              'birthDate': profile.dobFormatted,
              'birthTime': profile.timeOfBirth ?? '',
              'place': profile.placeOfBirth,
              'chatHistory': chatHistory.length > 10
                  ? chatHistory.sublist(chatHistory.length - 10)
                  : chatHistory,
            }),
          )
          .timeout(const Duration(seconds: 20));

      print('[RAG] Status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final answer = data['answer'] as String? ?? '';
        if (answer.isEmpty) {
          _lastError = 'RAG returned empty answer';
          return null;
        }

        final sourcesJson = data['sources'] as List<dynamic>? ?? [];
        final sources = sourcesJson
            .map((s) => VedicSource.fromJson(s as Map<String, dynamic>))
            .toList();

        print('[RAG] Success! chartUsed=${data['chartUsed']}, sources=${sources.length}');
        return AiResponse(text: answer, sources: sources);
      } else if (response.statusCode == 401) {
        // Token expired or invalid — surface user-friendly message and signal re-login
        _lastError = 'AUTH_EXPIRED';
        lastDiagnosticError = 'Your session expired. Please log in again.';
        print('[RAG] 401 Unauthorized — token expired or missing');
        // Force-refresh token in case it's just stale; let next call retry
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
        } catch (_) {}
      } else if (response.statusCode == 429) {
        // Rate limit hit — parse server's friendly message
        _lastError = 'RATE_LIMITED';
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          lastDiagnosticError = data['error'] as String? ??
              'Daily chat limit reached. Upgrade your plan for more questions.';
        } catch (_) {
          lastDiagnosticError = 'Daily chat limit reached. Upgrade your plan for more questions.';
        }
        print('[RAG] 429 Rate limited — $lastDiagnosticError');
        return AiResponse(text: lastDiagnosticError, sources: const []);
      } else if (response.statusCode == 503) {
        _lastError = 'SERVER_DOWN';
        lastDiagnosticError = 'Our astrology service is briefly unavailable. Please try again in a moment.';
        print('[RAG] 503 Service unavailable');
      } else {
        _lastError = 'RAG error ${response.statusCode}: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}';
        print('[RAG] $_lastError');
      }
    } catch (e) {
      _lastError = 'RAG exception: $e';
      print('[RAG] $_lastError');
    }
    return null;
  }

  /// Try server horoscope: cached first (fast), then live POST (real-time Gemini)
  static Future<Map<String, dynamic>?> _tryCloudHoroscope({
    required UserProfile profile,
    required String period,
  }) async {
    // Server now caches automatically per (sign × period × date), so we just
    // call /horoscope and the server returns cached or generates fresh.
    try {
      final liveUrl = Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/horoscope');
      print('[HOROSCOPE] Calling: $liveUrl');
      final headers = await _authHeaders();
      final liveResponse = await http
          .post(
            liveUrl,
            headers: headers,
            body: jsonEncode({
              'userProfile': {
                'sunSign': profile.sunSign,
                'westernSign': profile.westernSign,
              },
              'type': period,
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (liveResponse.statusCode == 200) {
        final data = jsonDecode(liveResponse.body) as Map<String, dynamic>;
        // Server returns full horoscope JSON
        if (data.containsKey('overall') &&
            (data['overall'] as String).isNotEmpty) {
          print('[HOROSCOPE] Live server HIT for ${profile.sunSign} $period');
          return data;
        }
      } else if (liveResponse.statusCode == 401) {
        print('[HOROSCOPE] 401 — refreshing token');
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
        } catch (_) {}
      } else if (liveResponse.statusCode == 429) {
        print('[HOROSCOPE] 429 — daily limit');
        try {
          final data = jsonDecode(liveResponse.body) as Map<String, dynamic>;
          return {
            'overall': data['error'] ?? 'Daily horoscope limit reached. Upgrade your plan for more.',
            'love': '', 'career': '', 'health': '',
            'luckyNumber': 7, 'luckyColor': 'Gold', 'luckyDay': 'Today',
            'rating': 0, '_rateLimited': true,
          };
        } catch (_) {}
      }
      print('[HOROSCOPE] Live server returned ${liveResponse.statusCode}');
    } catch (e) {
      print('[HOROSCOPE] Live server error: $e');
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // GEMINI VISION (palm reading only — stays client-side due to image size)
  // ─────────────────────────────────────────────────────────────

  /// Initialize the Gemini vision model for palm reading
  static void _initVisionModel() {
    if (!ApiConfig.isConfigured) return;

    _visionModel ??= GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: ApiConfig.geminiApiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 3000,
      ),
    );
  }

  /// Get AI astrology response. Server-first, direct Gemini backup, then templates.
  static Future<AiResponse> getAstrologyResponse({
    required UserProfile profile,
    required String userMessage,
    required List<String> chatHistory,
  }) async {
    // 1. Try server (RAG-powered with real Vedic sources, auth-protected, rate-limited)
    final cloudResponse = await _tryCloudFunction(
      profile: profile,
      userMessage: userMessage,
      chatHistory: chatHistory,
    );
    if (cloudResponse != null) return cloudResponse;

    // 2. Server failed. We deliberately DO NOT fall back to direct Gemini
    // anymore — bundling the Gemini key in the APK is a security risk
    // (decompilable in 5 minutes). Server-only path keeps the key safe.
    //
    // If the server returned a friendly auth/rate-limit error, that message
    // is already in lastDiagnosticError. Otherwise show a generic offline message.
    if (_lastError == 'AUTH_EXPIRED' ||
        _lastError == 'RATE_LIMITED' ||
        _lastError == 'SERVER_DOWN') {
      return AiResponse(text: lastDiagnosticError);
    }

    // 3. Network or unknown error — show template guidance
    print('[FALLBACK] Server unreachable, using template response');
    return AiResponse(text: _getFallbackResponse(profile, userMessage));
  }

  /// Get horoscope data. Tries cached endpoint -> live server -> direct Gemini -> static fallback.
  /// Build cache key for horoscope. Different key per sign/period/date-bucket
  /// so Today refreshes daily, Tomorrow daily, Weekly weekly, Monthly monthly.
  static String _horoscopeCacheKey(String sign, String period) {
    final now = DateTime.now();
    String bucket;
    switch (period) {
      case 'daily':
        bucket = '${now.year}-${now.month}-${now.day}';
        break;
      case 'tomorrow':
        final t = now.add(const Duration(days: 1));
        bucket = '${t.year}-${t.month}-${t.day}';
        break;
      case 'weekly':
        final weekStart = now.subtract(Duration(days: now.weekday % 7));
        bucket = 'w-${weekStart.year}-${weekStart.month}-${weekStart.day}';
        break;
      case 'monthly':
        bucket = 'm-${now.year}-${now.month}';
        break;
      default:
        bucket = '${now.year}-${now.month}-${now.day}';
    }
    return 'horoscope_${sign.toLowerCase()}_${period}_$bucket';
  }

  static Future<Map<String, dynamic>?> getHoroscope({
    required UserProfile profile,
    required String period,
  }) async {
    final cacheKey = _horoscopeCacheKey(profile.sunSign, period);

    // 0. Check local cache FIRST (avoid API calls on every tab switch)
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        final data = jsonDecode(cached) as Map<String, dynamic>;
        print('[HOROSCOPE-CACHE] Hit: $cacheKey');
        return data;
      }
    } catch (e) {
      print('[HOROSCOPE-CACHE] Read error: $e');
    }

    // 1. Try server (RAG, auth-protected, cached per sign × period × date)
    final cloudResult = await _tryCloudHoroscope(profile: profile, period: period);
    if (cloudResult != null) {
      _saveHoroscopeToCache(cacheKey, cloudResult);
      return cloudResult;
    }

    // 2. Server failed. Direct-Gemini fallback REMOVED for security
    // (the bundled API key was extractable from a decompiled APK,
    // letting attackers run Gemini calls on the user's bill).

    // 3. Show graceful template fallback
    // Quota message only shown if it was a rate-limit error
    final isQuotaError = lastDiagnosticError.contains('Daily AI quota');
    final noticeLine = isQuotaError
        ? '\n\n(Aaj ka quota pura ho gaya — kal fresh reading milegi.)'
        : '';
    return {
      'overall': 'Aaj ka din aapke liye mixed rahega. Subah thoda slow start hoga but dopahar ke baad positive energy badhegi. Stars aapke saath hain!$noticeLine',
      'love': 'Relationships mein harmony ka time hai. Partner ke saath quality time spend karein.',
      'career': 'Kaam mein naye opportunities aa sakte hain. Apni skills par focus rakhein aur networking badhayein.',
      'health': 'Health achhi rahegi. Bas hydration ka dhyan rakhein aur thoda walk zaroor karein.',
      'luckyNumber': 7,
      'luckyColor': 'Yellow',
      'luckyDay': 'Thursday',
      'rating': 4,
    };
  }

  /// Save horoscope to local SharedPreferences cache
  static Future<void> _saveHoroscopeToCache(
      String key, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(data));
      print('[HOROSCOPE-CACHE] Saved: $key');
    } catch (e) {
      print('[HOROSCOPE-CACHE] Save error: $e');
    }
  }

  /// Regex-based fallback when Gemini returns malformed JSON
  /// (unescaped newlines/quotes inside string values)
  static Map<String, dynamic>? _extractHoroscopeFields(String raw) {
    try {
      String extractString(String key) {
        // Match "key": "value" where value may span lines and contain escaped quotes
        final pattern = RegExp(
          '"' + key + r'"\s*:\s*"((?:\\.|[^"\\])*)"',
          dotAll: true,
        );
        final m = pattern.firstMatch(raw);
        if (m == null) return '';
        return m.group(1)!
            .replaceAll(r'\n', ' ')
            .replaceAll(r'\"', '"')
            .replaceAll(r'\\', r'\')
            .trim();
      }

      int extractInt(String key, int fallback) {
        final pattern = RegExp('"' + key + r'"\s*:\s*(\d+)');
        final m = pattern.firstMatch(raw);
        if (m == null) return fallback;
        return int.tryParse(m.group(1)!) ?? fallback;
      }

      final overall = extractString('overall');
      final love = extractString('love');
      final career = extractString('career');
      final health = extractString('health');

      // If at least overall was found, consider it a success
      if (overall.isEmpty) return null;

      return {
        'overall': overall,
        'love': love.isNotEmpty ? love : 'Relationships mein harmony ka time hai.',
        'career': career.isNotEmpty ? career : 'Kaam mein positive progress ke aasaar hain.',
        'health': health.isNotEmpty ? health : 'Health achhi rahegi.',
        'luckyNumber': extractInt('luckyNumber', 7),
        'luckyColor': extractString('luckyColor').isNotEmpty
            ? extractString('luckyColor')
            : 'Yellow',
        'luckyDay': extractString('luckyDay').isNotEmpty
            ? extractString('luckyDay')
            : 'Thursday',
        'rating': extractInt('rating', 4),
      };
    } catch (e) {
      print('[EXTRACT] Regex extraction failed: $e');
      return null;
    }
  }

  /// Palm reading using Gemini Vision
  static Future<PalmReadingResult> analyzePalm(String imagePath) async {
    try {
      // Read + base64-encode the image. Image picker is already capped at
      // 1200x1200 + 85% quality, so this is typically ~200-500 KB.
      final imageBytes = await File(imagePath).readAsBytes();
      if (imageBytes.length > 5 * 1024 * 1024) {
        throw PalmValidationException(
          'Image too large (max 5MB). Please retake or choose a smaller photo.',
        );
      }
      final mimeType = imagePath.toLowerCase().endsWith('.png')
          ? 'image/png'
          : imagePath.toLowerCase().endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
      final imageB64 = base64Encode(imageBytes);

      // Server-side palm analysis (was direct Gemini before — security risk)
      final url = Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/palm');
      final headers = await _authHeaders();
      print('[PALM] Calling: $url (${imageBytes.length} bytes)');
      final response = await http
          .post(
            url,
            headers: headers,
            body: jsonEncode({
              'imageBase64': imageB64,
              'mimeType': mimeType,
            }),
          )
          .timeout(const Duration(seconds: 90));

      print('[PALM] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // NOT_A_PALM short-circuit
        if (data['error'] == 'NOT_A_PALM') {
          throw PalmValidationException(
            (data['message'] as String?) ??
                'This image does not show a hand. Please upload a clear photo of your palm.',
          );
        }

        return PalmReadingResult(
          loveLine: _parsePalmLine(data['loveLine']),
          careerLine: _parsePalmLine(data['careerLine']),
          lifeLine: _parsePalmLine(data['lifeLine']),
        );
      } else if (response.statusCode == 401) {
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
        } catch (_) {}
        throw PalmValidationException(
          'Your session expired. Please log in again.',
        );
      } else if (response.statusCode == 429) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          throw PalmValidationException(
            (data['error'] as String?) ??
                'Daily palm reading limit reached. Upgrade your plan for more.',
          );
        } catch (_) {
          throw PalmValidationException('Daily palm reading limit reached.');
        }
      } else if (response.statusCode == 413) {
        throw PalmValidationException(
          'Image too large (max 5MB). Please retake with smaller resolution.',
        );
      } else {
        // Server error — fallback so user isn't blocked
        print('[PALM] Server error ${response.statusCode}: ${response.body}');
        return _getFallbackPalmReading();
      }
    } on PalmValidationException {
      rethrow; // Surface friendly errors to UI
    } catch (e) {
      // Network/timeout — graceful fallback
      print('[PALM] Network error: $e — using fallback');
      return _getFallbackPalmReading();
    }
  }

  /// Try to parse palm response, returns null if parsing fails
  static PalmReadingResult? _tryParsePalmResponse(String responseText) {
    try {
      var cleaned = responseText.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceAll(RegExp(r'^```\w*\n?'), '');
        cleaned = cleaned.replaceAll(RegExp(r'\n?```$'), '');
        cleaned = cleaned.trim();
      }
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      return PalmReadingResult(
        loveLine: _parsePalmLine(json['loveLine']),
        careerLine: _parsePalmLine(json['careerLine']),
        lifeLine: _parsePalmLine(json['lifeLine']),
      );
    } catch (e) {
      print('[PALM] Parse error: $e');
      return null;
    }
  }

  /// Parse the Gemini palm reading JSON response
  static PalmReadingResult _parsePalmResponse(String responseText) {
    try {
      // Clean up the response — remove markdown code blocks if present
      var cleaned = responseText.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceAll(RegExp(r'^```\w*\n?'), '');
        cleaned = cleaned.replaceAll(RegExp(r'\n?```$'), '');
        cleaned = cleaned.trim();
      }

      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      return PalmReadingResult(
        loveLine: _parsePalmLine(json['loveLine']),
        careerLine: _parsePalmLine(json['careerLine']),
        lifeLine: _parsePalmLine(json['lifeLine']),
      );
    } catch (e) {
      return _getFallbackPalmReading();
    }
  }

  static PalmLineResult _parsePalmLine(dynamic data) {
    // Defensive: handle null, wrong type, or missing fields without crashing.
    // This used to crash with `data as Map<String, dynamic>` when Gemini
    // returned null/string/list, taking down the palm reading screen.
    if (data == null || data is! Map) {
      return const PalmLineResult(
        title: 'Reading',
        emoji: '🔮',
        insight: 'Unable to read this line clearly. Please try again with a clearer photo.',
        meaning: '',
        advice: '',
      );
    }
    final map = Map<String, dynamic>.from(data);
    return PalmLineResult(
      title: (map['title'] ?? 'Reading').toString(),
      emoji: (map['emoji'] ?? '🔮').toString(),
      insight: (map['insight'] ?? '').toString(),
      meaning: (map['meaning'] ?? '').toString(),
      advice: (map['advice'] ?? '').toString(),
    );
  }

  /// Welcome message when chat starts
  static String getWelcomeMessage(UserProfile profile) {
    final first = profile.firstName;
    final opener = first.isNotEmpty ? 'Hello $first' : 'Hello';
    return '''$opener

I am your Vedic astrologer. Your birth details are saved with me.

Aap English, Hindi ya Hinglish mein baat kar sakte hain — I will reply in the same language.

Career, love, health, finance — jo bhi poochhna ho, puchiye.''';
  }

  // ─────────────────────────────────────────────────────────────
  // FALLBACK RESPONSES (used when API key not set or on error)
  // ─────────────────────────────────────────────────────────────

  static String _getFallbackResponse(UserProfile profile, String userMessage) {
    final query = userMessage.toLowerCase();

    if (query.contains('career') ||
        query.contains('job') ||
        query.contains('kaam') ||
        query.contains('naukri') ||
        query.contains('business') ||
        query.contains('kaarya')) {
      return _fallbackCareer[_random.nextInt(_fallbackCareer.length)];
    } else if (query.contains('love') ||
        query.contains('marriage') ||
        query.contains('shaadi') ||
        query.contains('relationship') ||
        query.contains('partner') ||
        query.contains('pyar') ||
        query.contains('pati') ||
        query.contains('patni') ||
        query.contains('boyfriend') ||
        query.contains('girlfriend')) {
      return _fallbackLove[_random.nextInt(_fallbackLove.length)];
    } else if (query.contains('health') ||
        query.contains('sehat') ||
        query.contains('body') ||
        query.contains('bimari') ||
        query.contains('doctor') ||
        query.contains('illness')) {
      return _fallbackHealth;
    } else if (query.contains('money') ||
        query.contains('finance') ||
        query.contains('paisa') ||
        query.contains('wealth') ||
        query.contains('dhan') ||
        query.contains('investment') ||
        query.contains('income')) {
      return _fallbackFinance;
    } else if (query.contains('education') ||
        query.contains('study') ||
        query.contains('padhai') ||
        query.contains('exam') ||
        query.contains('college') ||
        query.contains('school')) {
      return _fallbackEducation;
    } else if (query.contains('family') ||
        query.contains('ghar') ||
        query.contains('parents') ||
        query.contains('parivar') ||
        query.contains('mother') ||
        query.contains('father') ||
        query.contains('maa') ||
        query.contains('papa')) {
      return _fallbackFamily;
    } else if (query.contains('about me') ||
        query.contains('mere baare') ||
        query.contains('personality') ||
        query.contains('nature') ||
        query.contains('kaisa hoon') ||
        query.contains('kaisi hoon') ||
        query.contains('tell me about') ||
        query.contains('who am i') ||
        query.contains('mujhe batao')) {
      return _fallbackAboutSelf(profile);
    } else if (query.contains('future') ||
        query.contains('bhavishya') ||
        query.contains('aane wala') ||
        query.contains('kya hoga') ||
        query.contains('aage')) {
      return _fallbackFuture;
    } else {
      return _fallbackGeneral[_random.nextInt(_fallbackGeneral.length)];
    }
  }

  static const _fallbackCareer = [
    '''🔮 Insight
Aapki kundali mein dashmesh (10th lord) ki sthiti bahut achhi hai. Career mein growth ka time aa raha hai — khaas taur par agar aap leadership roles mein interest rakhte hain.

📖 Reason
Brihat Parashara Hora Shastra ke anusaar, jab dashmesh apne swagriha ya uchcha rashi mein hota hai, toh vyakti ko karm kshetra mein maan-sammaan milta hai.

🧘 Suggestion
Har Thursday ko peele vastra dharan karein aur guru mantra "Om Gurave Namah" ka 108 baar jaap karein. Apne seniors ke saath respect se pesh aayein.''',
    '''🔮 Insight
Abhi aapke career mein ek transitional phase chal raha hai. Yeh thoda challenging lag sakta hai, lekin yeh actually ek upgrading period hai.

📖 Reason
Phaladeepika mein likha hai ki Shani jab dashme bhav mein transit karta hai, toh vyakti ko pehle mehnat karni padti hai, phir success milti hai.

🧘 Suggestion
Saturday ko sarson ka tel diya jalayein Peepal ke ped ke neeche. Professional networking badhayein.''',
  ];

  static const _fallbackLove = [
    '''🔮 Insight
Aapke relationships mein ek naya phase shuru ho raha hai. Venus ki current position aapke 7th house ko positively influence kar rahi hai.

📖 Reason
Brihat Parashara ke anusaar, jab Shukra saptamesh se yuti ya drishti karta hai, toh vyakti ke jeevan mein prem aur sauhardya ka vaatavaran banta hai.

🧘 Suggestion
Friday ko safed phool Lakshmi ji ko arpan karein. Apne partner ke saath quality time spend karein.''',
    '''🔮 Insight
Aapki love life mein stability aa rahi hai. Jo bhi confusion thi, woh dheere dheere clear hone lagegi.

📖 Reason
Phaladeepika mein kaha gaya hai ki jab 7th lord navamsha mein shubh grahon ke saath ho, toh vivah sukh prabal hota hai.

🧘 Suggestion
"Om Shukraya Namah" ka 108 baar jaap karein Friday ko. Partner ke saath open communication rakhein.''',
  ];

  static const _fallbackHealth =
      '''🔮 Insight
Health wise aapko apne digestion aur stress levels par dhyan dena chahiye. Stars indicate ki minor issues aa sakte hain agar lifestyle balanced nahin rahi.

📖 Reason
Brihat Parashara ke anusaar, 6th house ke lord ki sthiti se rog aur shatru ka pata chalta hai.

🧘 Suggestion
Subah jaldi uthein aur surya namaskar karein — even 5 rounds enough hain. Haldi waala doodh raat ko peeyein. Har Sunday surya ko jal dein.''';

  static const _fallbackFinance =
      '''🔮 Insight
Financial growth ke signals achhe hain aapki kundali mein. Lekin impulsive spending se bachna zaroori hai.

📖 Reason
Phaladeepika ke anusaar, dwitiyesh aur ekadashesh ka sambandh dhan yoga banata hai. Aapke chart mein yeh yoga partially activated hai.

🧘 Suggestion
Wednesday ko green vastra pehnein aur Budh mantra ka jaap karein. Savings start karein chahe chhoti amount se. Locker mein thoda chandi rakhein.''';

  static const _fallbackEducation =
      '''🔮 Insight
Padhai aur knowledge ke mamle mein aapke stars bahut supportive hain. Concentration thoda kam ho sakti hai beech mein, but agar discipline rakhein toh results excellent aayenge.

📖 Reason
Brihat Parashara Hora Shastra mein 5th house ko vidya bhav kaha gaya hai. Budh (Mercury) ki achhi sthiti buddhi aur smriti shakti ko badhata hai. Jupiter ka aspect bhi knowledge growth support karta hai.

🧘 Suggestion
Padhai shuru karne se pehle Saraswati vandana padhein. Study table par Saraswati ji ki tasveer rakhein. Wednesday aur Thursday ko focused study karein — yeh din aapke liye best hain.''';

  static const _fallbackFamily =
      '''🔮 Insight
Family relationships mein harmony ka time aa raha hai. Agar koi purana tension tha toh woh resolve hoga. Ghar ka mahaul pleasant rahega — bas aapko thoda patience rakhna hoga.

📖 Reason
Phaladeepika ke anusaar, 4th house sukh aur maatri bhav hai. Jab Chandra (Moon) isse positively aspect karta hai, toh ghar mein sukh-shanti aati hai. Aapke chart mein yeh yoga active ho raha hai.

🧘 Suggestion
Monday ko doodh ka daan karein. Ghar mein Gangajal rakhein aur entrance par chhidkein. Maa ke saath zyada time spend karein — unki blessings aapke liye bahut powerful hain.''';

  static String _fallbackAboutSelf(UserProfile profile) {
    final name = profile.firstName.isNotEmpty ? profile.firstName : 'Aap';
    return '''🔮 Insight
$name, aapki kundali bahut interesting hai. Aapki personality mein depth hai — aap bahar se shant lagte hain lekin andar se bahut passionate hain. Aap mein leadership qualities hain aur aap logon ko naturally attract karte hain.

📖 Reason
Brihat Parashara Hora Shastra ke anusaar, lagna (1st house) aur lagnesh ki sthiti se vyakti ka swabhav aur personality pata chalta hai. Aapke chart mein lagnesh ki sthiti strong hai jo self-confidence aur determination dikhata hai. Phaladeepika mein bhi kaha gaya hai ki strong lagnesh wale vyakti apne kshetra mein naam kamate hain.

🧘 Suggestion
Apni strengths ko pehchanein aur unpe kaam karein. Har subah 5 minute meditation karein — isse aapka focus aur clarity badhegi. Apne birth day ke din (har mahine) kuch daan zaroor karein — yeh aapki positive energy ko multiply karega.''';
  }

  static const _fallbackFuture =
      '''🔮 Insight
Aane waale samay mein aapke liye kaafi positive changes aane waale hain. Kuch naye opportunities milenge jo aapki zindagi ki direction badal sakte hain. Bas thoda patience rakhein aur apne efforts continue rakhein.

📖 Reason
Phaladeepika ke anusaar, jab transit Jupiter aapke lagna ya 5th house ko aspect karta hai, toh naye avsar aate hain. Brighu Sanhita mein bhi likha hai ki karmic cycles har 2-3 saal mein shift hote hain aur abhi aapka cycle badal raha hai.

🧘 Suggestion
Important decisions lene ke liye Thursday ka din chunein — Guru ka din hai. "Om Gurave Namah" ka 108 baar jaap karein roz subah. Peela rang apni daily life mein shamil karein — yeh Guru ki kripa badhata hai.''';

  static const _fallbackGeneral = [
    '''🔮 Insight
Aapki kundali dekh kar keh sakta hoon ki overall trajectory positive hai. Abhi ek transformation ka phase chal raha hai — puraane patterns chhoot rahe hain aur naye doors khul rahe hain.

📖 Reason
Brihat Parashara Hora Shastra ke anusaar, jab transit planets natal chart ke kendra sthaan ko activate karte hain, toh jeewan mein significant changes aate hain. Yeh changes growth-oriented hain.

🧘 Suggestion
Har din 10 minute dhyan karein. "Om Namah Shivaya" ka jaap aapke liye bahut laabhdayak hoga. Subah jaldi uthne ki aadat banayein — positive energy flow hogi.''',
    '''🔮 Insight
Aapke stars keh rahe hain ki patience aur faith rakhein. Jo bhi challenges aa rahe hain, woh temporary hain. Agle kuch mahino mein clarity aayegi.

📖 Reason
Phaladeepika mein bataya gaya hai ki jab Guru apne transit mein lagna ya 9th house ko dekhe, toh bhagya udaya hota hai. Aapki kundali mein yeh dasha shuru hone waali hai.

🧘 Suggestion
Thursday ko mandir jaayein aur peela prasad chadhayein. Roz subah 5 minute gratitude practice karein — apni blessings count karein.''',
  ];

  static PalmReadingResult _getFallbackPalmReading() {
    final loveLines = [
      const PalmLineResult(
        title: 'Heart Line',
        emoji: '❤️',
        insight:
            'Aapki heart line deep aur curved hai — yeh ek passionate aur emotionally rich nature dikhata hai.',
        meaning:
            'Samudrik Shastra ke anusaar, gehri hridaya rekha wale vyakti prem mein poorna samarpan karte hain.',
        advice:
            'Apne emotions ko express karna seekhein openly. Friday ko safed phool arpan karein.',
      ),
      const PalmLineResult(
        title: 'Heart Line',
        emoji: '❤️',
        insight:
            'Heart line lambi aur straight hai — aap practical approach rakhte hain relationships mein.',
        meaning:
            'Samudrik Shastra mein seedhi heart line stability aur loyalty ko represent karti hai.',
        advice:
            'Thoda romantic side bhi dikhayein. Friday ko partner ke saath special time spend karein.',
      ),
    ];

    final careerLines = [
      const PalmLineResult(
        title: 'Head Line',
        emoji: '🧠',
        insight:
            'Buddhi rekha clear aur unbranched hai — yeh focused career path dikhata hai.',
        meaning:
            'Samudrik Shastra ke anusaar, jab buddhi rekha seedhi ho toh vyakti ek hi kshetra mein mastery haasil karta hai.',
        advice:
            'Apne core skill par focus rakhein. Guru ki salah lein — woh aapko sahi direction dikhayenge.',
      ),
      const PalmLineResult(
        title: 'Head Line',
        emoji: '🧠',
        insight:
            'Buddhi rekha mein ek branching point hai — yeh career change ya important decision indicate karta hai.',
        meaning:
            'Samudrik Shastra mein branched buddhi rekha multiple opportunities ka sanket hai.',
        advice:
            'Decision lene mein jaldi mat karein. Thursday ko important decisions lein — Guru ka din hai.',
      ),
    ];

    final lifeLines = [
      const PalmLineResult(
        title: 'Life Line',
        emoji: '🧬',
        insight:
            'Jeevan rekha deep aur lambi hai — yeh strong vitality aur resilience ka sign hai.',
        meaning:
            'Samudrik Shastra ke anusaar, gehri jeevan rekha strong immunity aur energy ka sanket hai.',
        advice:
            'Regular exercise aur pranayam se aur zyada vitality milegi. Surya Namaskar aapke liye best hai.',
      ),
      const PalmLineResult(
        title: 'Life Line',
        emoji: '🧬',
        insight:
            'Jeevan rekha curved aur well-defined hai — yeh balanced life aur emotional stability represent karta hai.',
        meaning:
            'Samudrik Shastra mein curved jeevan rekha emotional intelligence aur adaptability ka lakshan hai.',
        advice:
            'Apni adaptability ko strength banayein. Meditation se inner peace maintain karein.',
      ),
    ];

    return PalmReadingResult(
      loveLine: loveLines[_random.nextInt(loveLines.length)],
      careerLine: careerLines[_random.nextInt(careerLines.length)],
      lifeLine: lifeLines[_random.nextInt(lifeLines.length)],
    );
  }
}

class PalmValidationException implements Exception {
  final String message;
  PalmValidationException(this.message);
  @override
  String toString() => message;
}
