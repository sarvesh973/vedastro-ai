import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/vedic_system_prompt.dart';
import '../models/user_profile.dart';
import '../models/palm_result.dart';
import '../models/chat_message.dart';

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
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
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

  /// Try CACHED horoscope (pre-generated on server), quick timeout only
  static Future<Map<String, dynamic>?> _tryCloudHoroscope({
    required UserProfile profile,
    required String period,
  }) async {
    // Only try cached endpoint — short timeout so we fail fast to Gemini
    try {
      final cachedUrl = Uri.parse(
        '${ApiConfig.cloudFunctionBaseUrl}/horoscope/cached?sign=${Uri.encodeComponent(profile.sunSign)}&period=${Uri.encodeComponent(period)}',
      );
      print('[HOROSCOPE] Trying cached: $cachedUrl');
      final cachedResponse = await http.get(cachedUrl).timeout(const Duration(seconds: 5));

      if (cachedResponse.statusCode == 200) {
        final data = jsonDecode(cachedResponse.body) as Map<String, dynamic>;
        if (data['_cached'] == true) {
          print('[HOROSCOPE] Cache HIT for ${profile.sunSign} $period');
          return data;
        }
      }
    } catch (e) {
      print('[HOROSCOPE] Cache miss/error: $e');
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
    // 1. Try Cloud Function (RAG-powered with real Vedic sources)
    final cloudResponse = await _tryCloudFunction(
      profile: profile,
      userMessage: userMessage,
      chatHistory: chatHistory,
    );
    if (cloudResponse != null) return cloudResponse;

    // 2. Server down (free tier sleeping?) — try direct Gemini as backup
    print('[FALLBACK] Server unavailable ($_lastError), trying direct Gemini...');
    try {
      _initChatModel(profile);
      if (_currentChat != null) {
        final geminiResponse = await _currentChat!
            .sendMessage(Content.text(userMessage))
            .timeout(const Duration(seconds: 45));
        final text = geminiResponse.text;
        if (text != null && text.isNotEmpty) {
          print('[GEMINI-DIRECT] Success! ${text.length} chars');
          return AiResponse(text: text);
        }
      }
    } catch (e) {
      print('[GEMINI-DIRECT] Also failed: $e');
    }

    // 3. Everything failed — use smart template fallback (FREE, no API cost)
    print('[FALLBACK] All AI failed, using template response');
    return AiResponse(text: _getFallbackResponse(profile, userMessage));
  }

  /// Get horoscope data. Tries cached endpoint -> live server -> direct Gemini -> static fallback.
  static Future<Map<String, dynamic>?> getHoroscope({
    required UserProfile profile,
    required String period,
  }) async {
    // 1. Try Cloud Function (cached first, then live)
    final cloudResult = await _tryCloudHoroscope(profile: profile, period: period);
    if (cloudResult != null) return cloudResult;

    // 2. Server down — try direct Gemini for unique horoscope
    print('[HOROSCOPE] Server unavailable, trying direct Gemini...');
    try {
      if (!ApiConfig.isConfigured) {
        lastDiagnosticError = 'API key not configured (key=${ApiConfig.geminiApiKey.length} chars, starts with ${ApiConfig.geminiApiKey.length > 4 ? ApiConfig.geminiApiKey.substring(0, 4) : "??"})';
        throw Exception(lastDiagnosticError);
      }

      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: ApiConfig.geminiApiKey,
        generationConfig: GenerationConfig(
          temperature: 0.9,
          maxOutputTokens: 1000,
        ),
      );

      final periodLabel = period == 'daily'
          ? 'today'
          : period == 'tomorrow'
              ? 'tomorrow'
              : period == 'weekly'
                  ? 'this week'
                  : 'this month';

      final prompt = '''You are VedAstro Guruji, a Vedic astrologer. Generate a ${period} horoscope for ${profile.sunSign} sign for $periodLabel.

CRITICAL: Return ONLY valid compact JSON on a single line. No markdown, no code blocks, no newlines inside string values, no unescaped quotes.

{"overall":"3-4 sentence Hinglish overview with Vedic reference","love":"2-3 sentences about relationships","career":"2-3 sentences about work","health":"2-3 sentences about health","luckyNumber":7,"luckyColor":"Yellow","luckyDay":"Thursday","rating":4}

Rules:
- All string values must be single-line (no \\n inside)
- Do not use quotes " inside string values — use single quotes ' instead
- Be specific to ${profile.sunSign}. Reference BPHS or Phaladeepika.
- Speak in warm Hinglish.''';

      final response = await model
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 30));

      final text = response.text;
      if (text != null && text.isNotEmpty) {
        var cleaned = text.trim();
        if (cleaned.startsWith('```')) {
          cleaned = cleaned.replaceAll(RegExp(r'^```\w*\n?'), '');
          cleaned = cleaned.replaceAll(RegExp(r'\n?```$'), '');
          cleaned = cleaned.trim();
        }

        // Try strict JSON parse first
        try {
          final data = jsonDecode(cleaned) as Map<String, dynamic>;
          print('[GEMINI-DIRECT] Horoscope success for ${profile.sunSign} $period');
          return data;
        } catch (_) {
          // Fallback: extract fields with regex when Gemini returns malformed JSON
          // (common: unescaped newlines/quotes inside string values)
          print('[GEMINI-DIRECT] Strict JSON failed, trying regex extraction');
          final extracted = _extractHoroscopeFields(cleaned);
          if (extracted != null) {
            print('[GEMINI-DIRECT] Regex extraction succeeded for ${profile.sunSign} $period');
            return extracted;
          }
          rethrow;
        }
      }
    } catch (e) {
      final errStr = e.toString();
      lastDiagnosticError = errStr.length > 300 ? errStr.substring(0, 300) : errStr;
      print('[GEMINI-DIRECT] Horoscope also failed: $e');
    }

    // 3. Everything failed — static fallback with diagnostic info embedded
    final debugInfo = lastDiagnosticError.isNotEmpty
        ? '\n\n[DEBUG: $lastDiagnosticError]'
        : '';
    return {
      'overall': '[$period] Aaj ka din aapke liye mixed rahega. Subah thoda slow start hoga but dopahar ke baad positive energy badhegi. Stars aapke saath hain!$debugInfo',
      'love': 'Relationships mein harmony ka time hai. Partner ke saath quality time spend karein.',
      'career': 'Kaam mein naye opportunities aa sakte hain. Apni skills par focus rakhein aur networking badhayein.',
      'health': 'Health achhi rahegi. Bas hydration ka dhyan rakhein aur thoda walk zaroor karein.',
      'luckyNumber': 7,
      'luckyColor': 'Yellow',
      'luckyDay': 'Thursday',
      'rating': 4,
    };
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
    if (!ApiConfig.isConfigured) {
      return _getFallbackPalmReading();
    }

    try {
      _initVisionModel();

      // Read the image file
      final imageBytes = await File(imagePath).readAsBytes();
      final mimeType = imagePath.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';

      final response = await _visionModel!.generateContent([
        Content.multi([
          TextPart(VedicSystemPrompt.palmReadingPrompt),
          DataPart(mimeType, imageBytes),
        ]),
      ]);

      final text = response.text;
      print('[PALM] Response length: ${text?.length ?? 0}');

      if (text == null || text.isEmpty) {
        // API returned nothing — use fallback, don't block user
        print('[PALM] Empty response, using fallback');
        return _getFallbackPalmReading();
      }

      // ONLY reject if AI explicitly says NOT_A_PALM
      if (text.contains('NOT_A_PALM')) {
        var cleaned = text.trim();
        if (cleaned.startsWith('```')) {
          cleaned = cleaned.replaceAll(RegExp(r'^```\w*\n?'), '');
          cleaned = cleaned.replaceAll(RegExp(r'\n?```$'), '');
          cleaned = cleaned.trim();
        }
        String errorMsg = 'Yeh ek palm ki photo nahi lag rahi. Please apni hatheli ki clear photo upload karein.';
        try {
          final errJson = jsonDecode(cleaned) as Map<String, dynamic>;
          errorMsg = errJson['message'] as String? ?? errorMsg;
        } catch (_) {}
        throw PalmValidationException(errorMsg);
      }

      // Try to parse the real AI response
      final parsed = _tryParsePalmResponse(text);
      if (parsed != null) {
        print('[PALM] Successfully parsed AI analysis');
        return parsed;
      }

      // Parse failed — use fallback silently
      print('[PALM] Parse failed, using fallback');
      return _getFallbackPalmReading();
    } on PalmValidationException {
      rethrow; // Only NOT_A_PALM errors reach the UI
    } catch (e) {
      // Network error, timeout, API error — use fallback, don't block user
      print('[PALM] Error: $e — using fallback');
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
    final map = data as Map<String, dynamic>;
    return PalmLineResult(
      title: map['title'] ?? 'Reading',
      emoji: map['emoji'] ?? '🔮',
      insight: map['insight'] ?? '',
      meaning: map['meaning'] ?? '',
      advice: map['advice'] ?? '',
    );
  }

  /// Welcome message when chat starts
static String getWelcomeMessage(UserProfile profile) {
    final name = profile.name.isNotEmpty ? profile.name : '';
    final greeting = name.isNotEmpty ? 'Namaste $name!' : 'Namaste!';
    return '''🙏 $greeting

I am your personal Vedic astrologer. I have noted your birth details.

You can talk to me in English, Hindi, or Hinglish — I will reply in your language.

Ask me about career, love, health, finance, or any life question. ✨''';
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
    final name = profile.name.isNotEmpty ? profile.name : 'Aap';
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
