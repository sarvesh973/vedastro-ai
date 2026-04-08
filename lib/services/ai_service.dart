import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../config/api_config.dart';
import '../config/vedic_system_prompt.dart';
import '../models/user_profile.dart';
import '../models/palm_result.dart';

class AiService {
  static GenerativeModel? _chatModel;
  static GenerativeModel? _visionModel;
  static ChatSession? _currentChat;
  static UserProfile? _currentProfile;
  static final _random = Random();

  /// Initialize the Gemini chat model with Vedic astrology system prompt
  static void _initChatModel(UserProfile profile) {
    if (!ApiConfig.isConfigured) return;

    // Reinitialize if profile changed
    if (_currentProfile?.profileSummary != profile.profileSummary ||
        _chatModel == null) {
      _chatModel = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: ApiConfig.geminiApiKey,
        systemInstruction: Content.text(
          VedicSystemPrompt.build(userProfileSummary: profile.profileSummary),
        ),
        generationConfig: GenerationConfig(
          temperature: 0.7,
          topP: 0.9,
          maxOutputTokens: 4096,
        ),
      );
      _currentChat = _chatModel!.startChat();
      _currentProfile = profile;
    }
  }

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

  /// Get real AI astrology response via Gemini
  static Future<String> getAstrologyResponse({
    required UserProfile profile,
    required String userMessage,
    required List<String> chatHistory,
  }) async {
    // If API key not configured, use fallback
    if (!ApiConfig.isConfigured) {
      return _getFallbackResponse(profile, userMessage);
    }

    try {
      _initChatModel(profile);

      final response = await _currentChat!.sendMessage(
        Content.text(userMessage),
      );

      final text = response.text;
      if (text != null && text.isNotEmpty) {
        return text;
      }

      return _getFallbackResponse(profile, userMessage);
    } catch (e) {
      // If Gemini fails, try once more with a fresh chat session
      try {
        _chatModel = null;
        _currentChat = null;
        _initChatModel(profile);

        // Include user context in the message itself as backup
        final contextMessage =
            'User birth details: ${profile.profileSummary}\n\nUser question: $userMessage';

        final response = await _currentChat!.sendMessage(
          Content.text(contextMessage),
        );

        final text = response.text;
        if (text != null && text.isNotEmpty) {
          return text;
        }
      } catch (_) {
        // Both attempts failed
      }

      // Show fallback without scary error message
      return _getFallbackResponse(profile, userMessage);
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
      if (text != null && text.isNotEmpty) {
        // Check if AI detected non-palm image
        if (text.contains("NOT_A_PALM")) {
          try {
            var cleaned = text.trim();
            if (cleaned.startsWith('''''')) {
              cleaned = cleaned.replaceAll(RegExp(r'''^w*n?''), ''''');
              cleaned = cleaned.trim();
            }
            final errJson = jsonDecode(cleaned);
            throw Exception(errJson['message'] ?? 'Please upload a clear palm photo');
          } catch (e) {
            if (e is Exception) rethrow;
            throw Exception('Please upload a clear photo of your palm');
          }
        }
        return _parsePalmResponse(text);
      }

      return _getFallbackPalmReading();
    } catch (e) {
      return _getFallbackPalmReading();
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
    final name = profile.name.isNotEmpty ? profile.name : 'ji';
    return '''🙏 Namaste $name!

Main aapka Vedic astrologer hoon. Aapki birth details dekh li hain maine.

Aap mujhse kuch bhi pooch sakte hain — career, love, health, finance, family ya koi bhi sawaal jo aapke mann mein ho.

Bataiye, aaj kya jaanna chahenge? ✨''';
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
