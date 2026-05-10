import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../config/api_config.dart';
import '../providers/providers.dart';
import '../widgets/kundli_chart.dart';
import '../models/user_profile.dart';
import '../services/ai_service.dart';
import 'user_details_screen.dart';

/// Build Firebase-authed headers for the kundli/chart API.
/// Server's `/chart` endpoint now requires a Bearer token (security backport)
/// — without this header it returns 401 and the screen shows "retry".
Future<Map<String, String>> _kundliAuthHeaders() async {
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

class KundliScreen extends ConsumerStatefulWidget {
  const KundliScreen({super.key});

  @override
  ConsumerState<KundliScreen> createState() => _KundliScreenState();
}

class _KundliScreenState extends ConsumerState<KundliScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _chartData;
  bool _isLoading = true;
  String? _error;

  // Personalized insights — main D1 reading split into 5 sections.
  Map<String, String> _insights = {};
  bool _insightsLoading = false;
  String? _insightsError;

  // Dedicated D9 (Navamsha) and D10 (Career) readings.
  // The previous build reused the main D1 response and parsed it for
  // RELATIONSHIPS / CAREER sections. When the AI used different headings
  // or skipped a section, those tabs were empty. Fetching them
  // independently with chart-specific prompts guarantees content even
  // when the main parse fails, AND gives the AI Navamsha/Dasamsa
  // positions to actually reason about.
  String? _navamshaInsight;
  bool _navamshaLoading = false;
  String? _navamshaError;

  String? _careerInsight;
  bool _careerLoading = false;
  String? _careerError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Lazy-load divisional-chart insights only when the user actually
    // opens those tabs. Prevents burning rate-limit budget on tabs the
    // user never visits — the previous build kicked off all three AI
    // calls in parallel, which on free/trial plans was tripping the
    // server's daily rate limit and causing the screen to fall back
    // to canned template responses (the "pre-written text" complaint).
    _tabController.addListener(_onTabChanged);
    _loadChart();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_chartData == null) return;
    final idx = _tabController.index;
    if (idx == 1 &&
        _navamshaInsight == null &&
        !_navamshaLoading &&
        _navamshaError == null) {
      _loadNavamshaInsight();
    } else if (idx == 2 &&
        _careerInsight == null &&
        !_careerLoading &&
        _careerError == null) {
      _loadCareerInsight();
    }
  }

  // ─── Insight cache ────────────────────────────────────────────
  // Once a reading lands, persist it per profile so re-opening the
  // Kundli screen doesn't burn a /chat rate-limit slot. Each profile
  // gets at most 3 chat-quota calls ever (D1 + D9 + D10), instead of
  // 3 per chart-view. Cache key derives from birth details so editing
  // the profile invalidates the old reading.
  String _cacheKeyFor(UserProfile p, String section) {
    final dob = p.dateOfBirth;
    final iso = '${dob.year}-${dob.month}-${dob.day}';
    return 'kundli_insight::${p.name}::$iso::${p.timeOfBirth ?? ""}'
        '::${p.placeOfBirth}::$section';
  }

  Future<String?> _readCachedInsight(UserProfile p, String section) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKeyFor(p, section));
      if (raw == null || raw.isEmpty) return null;
      return raw;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedInsight(
      UserProfile p, String section, String text) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKeyFor(p, section), text);
    } catch (_) {}
  }

  Future<void> _loadChart() async {
    final profile = ref.read(userProfileProvider);
    if (profile == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final url = Uri.parse('${ApiConfig.cloudFunctionBaseUrl}/chart');
      // Server expects YYYY-MM-DD; profile.dobFormatted is DD/MM/YYYY,
      // so format here directly from the DateTime to avoid the mismatch.
      final dob = profile.dateOfBirth;
      final dobIso =
          '${dob.year.toString().padLeft(4, '0')}-${dob.month.toString().padLeft(2, '0')}-${dob.day.toString().padLeft(2, '0')}';
      final headers = await _kundliAuthHeaders();
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'birthDate': dobIso,
          'birthTime': profile.timeOfBirth ?? '',
          'place': profile.placeOfBirth,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _chartData = data;
            _isLoading = false;
          });
          // Only kick off the D1 main reading on chart load. D9 and D10
          // readings are lazy-loaded via _onTabChanged when the user
          // actually opens those tabs.
          _loadInsights();
        }
      } else {
        // Surface the actual server response so issues like rate-limit
        // (429), auth (401), bad-input (400) and server errors (5xx)
        // are diagnosable without USB-attached debug. The previous
        // "Could not calculate chart" message hid all of these.
        String detail = '${response.statusCode}';
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final err = body['error']?.toString();
          if (err != null && err.isNotEmpty) detail = '$detail: $err';
        } catch (_) {
          // Body wasn't JSON — include first chunk of raw body.
          final raw = response.body;
          if (raw.isNotEmpty) {
            detail = '$detail: ${raw.length > 120 ? raw.substring(0, 120) : raw}';
          }
        }
        print('[CHART] Non-200 from /chart — $detail');
        if (mounted) {
          setState(() {
            _error = 'Could not calculate chart ($detail)';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('[CHART] Network/timeout: $e');
      if (mounted) {
        setState(() {
          _error = 'Connection error: $e';
          _isLoading = false;
        });
      }
    }
  }

  // Build house planets map for D1 chart from server data
  Map<int, List<ChartPlanet>> _buildD1Planets() {
    if (_chartData == null) return {};
    final planets = _chartData!['planets'] as Map<String, dynamic>? ?? {};
    final Map<int, List<ChartPlanet>> result = {};

    for (final entry in planets.entries) {
      final name = entry.key;
      final data = entry.value as Map<String, dynamic>;
      final house = data['house'] as int? ?? 0;
      if (house < 1 || house > 12) continue;

      final abbr = KundliChart.planetAbbr[name] ?? name.substring(0, 2);
      final isRetro = data['isRetrograde'] == true;

      result.putIfAbsent(house, () => []);
      result[house]!.add(ChartPlanet(abbr, isRetrograde: isRetro));
    }
    return result;
  }

  // Build house planets map for divisional charts (D9, D10, D20)
  Map<int, List<ChartPlanet>> _buildDivisionalPlanets(String key) {
    if (_chartData == null) return {};
    final divData = _chartData![key] as Map<String, dynamic>? ?? {};
    if (divData.isEmpty) return {};

    // Get ascendant sign for this divisional chart
    final ascSign = divData['Ascendant']?.toString() ?? '';
    if (ascSign.isEmpty) return {};

    final ascIndex = KundliChart.signToIndex(ascSign);
    final Map<int, List<ChartPlanet>> result = {};

    for (final entry in divData.entries) {
      if (entry.key == 'Ascendant') continue;
      final planetName = entry.key;
      final signName = entry.value?.toString() ?? '';
      if (signName.isEmpty) continue;

      final planetSignIndex = KundliChart.signToIndex(signName);
      final house = ((planetSignIndex - ascIndex + 12) % 12) + 1;

      final abbr = KundliChart.planetAbbr[planetName] ?? planetName.substring(0, 2);
      result.putIfAbsent(house, () => []);
      result[house]!.add(ChartPlanet(abbr));
    }
    return result;
  }

  int _getDivisionalAscendant(String key) {
    if (_chartData == null) return 0;
    final divData = _chartData![key] as Map<String, dynamic>? ?? {};
    final ascSign = divData['Ascendant']?.toString() ?? '';
    if (ascSign.isEmpty) return 0;
    return KundliChart.signToIndex(ascSign);
  }

  /// Helper: format a single planet's D1 position concisely.
  /// Returns empty string if the planet isn't in the chart data.
  String _planetLine(String planetName) {
    final planets = _chartData?['planets'] as Map<String, dynamic>?;
    final m = planets?[planetName] as Map<String, dynamic>?;
    if (m == null) return '';
    final retro = m['isRetrograde'] == true ? ' (R)' : '';
    return '$planetName in ${m['sign']} (House ${m['house']}, '
        '${m['nakshatra'] ?? '-'} nakshatra)$retro';
  }

  /// Helper: D9 sign for a planet, or empty if unavailable.
  String _d9Line(String planetName) {
    final d9 = _chartData?['d9Navamsha'] as Map<String, dynamic>?;
    final sign = d9?[planetName]?.toString() ?? '';
    return sign.isEmpty ? '' : '$planetName in $sign';
  }

  /// Helper: D10 sign for a planet.
  String _d10Line(String planetName) {
    final d10 = _chartData?['d10Dasamsa'] as Map<String, dynamic>?;
    final sign = d10?[planetName]?.toString() ?? '';
    return sign.isEmpty ? '' : '$planetName in $sign';
  }

  /// Compact, AI-friendly summary of this user's actual computed chart.
  /// Without this in the prompt, the AI was producing generic readings
  /// from birthdate alone — the user called it "pre-written data."
  String _buildChartContext() {
    final sb = StringBuffer();
    final asc = _chartData?['ascendant'] as Map<String, dynamic>?;
    if (asc != null) {
      final degree = asc['degree']?.toString() ?? '';
      sb.writeln('Ascendant (Lagna): ${asc['sign']}'
          '${degree.isNotEmpty ? ' at $degree°' : ''}'
          ', Nakshatra: ${asc['nakshatra'] ?? '-'}'
          ', Lord: ${asc['lord'] ?? '-'}.');
    }
    final birthNak = _chartData?['birthNakshatra']?.toString();
    if (birthNak != null && birthNak.isNotEmpty) {
      sb.writeln('Birth Nakshatra (Moon): $birthNak.');
    }

    final planets = _chartData?['planets'] as Map<String, dynamic>?;
    if (planets != null && planets.isNotEmpty) {
      sb.writeln('\nD1 Rashi (Birth Chart) Planet Positions:');
      planets.forEach((name, raw) {
        final m = raw as Map<String, dynamic>;
        final retro = m['isRetrograde'] == true ? ' (Retrograde)' : '';
        sb.writeln('  $name: ${m['sign']}, House ${m['house']}, '
            'Nakshatra ${m['nakshatra'] ?? '-'}$retro.');
      });
    }

    final dasha = _chartData?['dasha'] as Map<String, dynamic>?;
    if (dasha != null && dasha.isNotEmpty) {
      sb.writeln('\nCurrent Vimshottari Dasha:');
      sb.writeln('  Mahadasha: ${dasha['mahadasha']}'
          ' (until ${dasha['mahadashaEnd'] ?? '-'}).');
      sb.writeln('  Antardasha: ${dasha['antardasha']}'
          ' (until ${dasha['antardashaEnd'] ?? '-'}).');
      final pratyantar = dasha['pratyantar']?.toString();
      if (pratyantar != null && pratyantar.isNotEmpty) {
        sb.writeln('  Pratyantar: $pratyantar.');
      }
    }

    final d9 = _chartData?['d9Navamsha'] as Map<String, dynamic>?;
    if (d9 != null && d9.isNotEmpty) {
      sb.writeln('\nD9 Navamsha (Marriage / Dharma) Positions:');
      d9.forEach((planet, sign) => sb.writeln('  $planet: $sign.'));
    }

    final d10 = _chartData?['d10Dasamsa'] as Map<String, dynamic>?;
    if (d10 != null && d10.isNotEmpty) {
      sb.writeln('\nD10 Dasamsa (Career) Positions:');
      d10.forEach((planet, sign) => sb.writeln('  $planet: $sign.'));
    }

    return sb.toString();
  }

  Future<void> _loadInsights({bool forceRefresh = false}) async {
    final profile = ref.read(userProfileProvider);
    if (profile == null || _chartData == null) return;

    // Cache hit? Use it. Saves a /chat rate-limit slot.
    if (!forceRefresh) {
      final cached = await _readCachedInsight(profile, 'main');
      if (cached != null && cached.isNotEmpty && mounted) {
        setState(() {
          _insights = _parseInsights(cached);
          _insightsLoading = false;
          _insightsError = null;
        });
        return;
      }
    }

    setState(() {
      _insightsLoading = true;
      _insightsError = null;
    });

    // Focused, embedding-friendly prompt. The previous version sent a
    // huge dump of every planet position alongside 5 different topics —
    // the resulting embedding matched nothing well in the Vedic
    // knowledge base, so RAG returned no source verses. This prompt
    // leads with the topical question keywords (personality, career,
    // marriage, strengths, challenges) and includes only the most
    // chart-defining placements (Lagna, Moon, key houses' planets,
    // current dasha) to keep the embedding focused on the topics
    // actually being asked about.
    final asc = _chartData?['ascendant'] as Map<String, dynamic>?;
    final dasha = _chartData?['dasha'] as Map<String, dynamic>?;
    final lagnaSign = asc?['sign']?.toString() ?? '';
    final lagnaLord = asc?['lord']?.toString() ?? '';
    final birthNak = _chartData?['birthNakshatra']?.toString() ?? '';

    final insightPrompt = StringBuffer()
      ..writeln('Personalized Vedic birth chart reading covering '
          'personality, career, marriage and relationships, strengths, '
          'and challenges.')
      ..writeln()
      ..writeln('My key placements:');
    if (lagnaSign.isNotEmpty) {
      insightPrompt.writeln(
          '- Lagna (Ascendant): $lagnaSign, ruled by $lagnaLord.');
    }
    if (birthNak.isNotEmpty) {
      insightPrompt.writeln('- Janma Nakshatra: $birthNak.');
    }
    for (final p in const ['Sun', 'Moon', 'Mars', 'Mercury', 'Jupiter',
      'Venus', 'Saturn', 'Rahu', 'Ketu']) {
      final line = _planetLine(p);
      if (line.isNotEmpty) insightPrompt.writeln('- $line.');
    }
    if (dasha != null && dasha.isNotEmpty) {
      insightPrompt.writeln('- Current Mahadasha: ${dasha['mahadasha']}, '
          'Antardasha: ${dasha['antardasha']}.');
    }
    insightPrompt
      ..writeln()
      ..writeln('Write a 2-3 line reading for each of these 5 sections, '
          'referencing my actual placements above. Use Hinglish, warm tone.')
      ..writeln('PERSONALITY: ')
      ..writeln('CAREER: ')
      ..writeln('RELATIONSHIPS: ')
      ..writeln('STRENGTHS: ')
      ..writeln('CHALLENGES: ');

    try {
      final response = await AiService.getAstrologyResponse(
        profile: profile,
        userMessage: insightPrompt.toString(),
        chatHistory: const [],
      );

      if (!mounted) return;

      final answer = response.text.trim();
      // Note: an earlier version of this check rejected responses with
      // empty `sources` as "template fallbacks." That was wrong — the
      // hardcoded templates in AiService are CLIENT-SIDE and only fire
      // when the server call returns null. A 200 with empty sources is
      // a real Gemini reading, just without matched Vedic verses. So
      // we only reject genuinely empty answers here.
      if (answer.isEmpty) {
        setState(() {
          _insightsLoading = false;
          _insightsError =
              'Could not generate your reading right now. Please try again.';
        });
        return;
      }

      final parsed = _parseInsights(answer);
      setState(() {
        _insights = parsed;
        _insightsLoading = false;
        // Even if parsing didn't split into 5 sections, _parseInsights falls
        // back to dumping everything into PERSONALITY — so a non-empty answer
        // always produces at least one card.
        _insightsError = parsed.isEmpty
            ? 'Reading was empty. Tap retry to try again.'
            : null;
      });
      if (parsed.isNotEmpty) {
        _writeCachedInsight(profile, 'main', answer);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _insightsLoading = false;
        _insightsError = 'Connection issue. Tap retry to load your reading.';
      });
    }
  }

  /// Dedicated D9 Navamsha reading. The previous build pulled this out
  /// of the main response by parsing the "RELATIONSHIPS:" section — when
  /// the AI used different wording or skipped that section, the D9 tab
  /// was silent. A focused prompt with the actual D9 positions
  /// guarantees content and is far more chart-specific.
  Future<void> _loadNavamshaInsight({bool forceRefresh = false}) async {
    final profile = ref.read(userProfileProvider);
    if (profile == null || _chartData == null) return;

    if (!forceRefresh) {
      final cached = await _readCachedInsight(profile, 'navamsha');
      if (cached != null && cached.isNotEmpty && mounted) {
        setState(() {
          _navamshaInsight = cached;
          _navamshaLoading = false;
          _navamshaError = null;
        });
        return;
      }
    }

    setState(() {
      _navamshaLoading = true;
      _navamshaError = null;
    });

    // Focused D9 / Navamsha question — embedding-friendly so RAG
    // matches verses on marriage, 7th house, Venus, Jupiter and dharma.
    final d9Asc = (_chartData?['d9Navamsha']
        as Map<String, dynamic>?)?['Ascendant']?.toString() ?? '';
    final prompt = StringBuffer()
      ..writeln('Navamsha D9 chart reading focused on marriage, '
          'partnership, 7th house, Venus, and dharma / soul purpose.')
      ..writeln()
      ..writeln('My placements:');
    final d1Venus = _planetLine('Venus');
    final d1Jupiter = _planetLine('Jupiter');
    if (d1Venus.isNotEmpty) prompt.writeln('- D1 $d1Venus.');
    if (d1Jupiter.isNotEmpty) prompt.writeln('- D1 $d1Jupiter.');
    if (d9Asc.isNotEmpty) prompt.writeln('- D9 Ascendant: $d9Asc.');
    for (final p in const ['Sun', 'Moon', 'Mars', 'Mercury', 'Jupiter',
      'Venus', 'Saturn']) {
      final line = _d9Line(p);
      if (line.isNotEmpty) prompt.writeln('- D9 $line.');
    }
    prompt
      ..writeln()
      ..writeln('Write a 4-5 line reading covering my marriage and '
          'partnership style, dharma / soul purpose, and how the D9 '
          'strengthens or weakens my D1 chart. Hinglish, warm tone.');

    try {
      final response = await AiService.getAstrologyResponse(
        profile: profile,
        userMessage: prompt.toString(),
        chatHistory: const [],
      );
      if (!mounted) return;
      final answer = response.text.trim();
      setState(() {
        _navamshaLoading = false;
        if (answer.isEmpty) {
          _navamshaError = 'Could not generate Navamsha reading. Tap retry.';
        } else {
          _navamshaInsight = answer;
        }
      });
      if (answer.isNotEmpty) {
        _writeCachedInsight(profile, 'navamsha', answer);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _navamshaLoading = false;
        _navamshaError = 'Connection issue. Tap retry to load Navamsha.';
      });
    }
  }

  /// Dedicated D10 Dasamsa (career) reading — see _loadNavamshaInsight
  /// for why this is a separate fetch instead of parsing the main one.
  Future<void> _loadCareerInsight({bool forceRefresh = false}) async {
    final profile = ref.read(userProfileProvider);
    if (profile == null || _chartData == null) return;

    if (!forceRefresh) {
      final cached = await _readCachedInsight(profile, 'career');
      if (cached != null && cached.isNotEmpty && mounted) {
        setState(() {
          _careerInsight = cached;
          _careerLoading = false;
          _careerError = null;
        });
        return;
      }
    }

    setState(() {
      _careerLoading = true;
      _careerError = null;
    });

    // Focused D10 / career question — embedding-friendly so RAG
    // matches verses on career, profession, 10th house, Sun and Saturn.
    final d10Asc = (_chartData?['d10Dasamsa']
        as Map<String, dynamic>?)?['Ascendant']?.toString() ?? '';
    final prompt = StringBuffer()
      ..writeln('Dasamsa D10 chart reading focused on career, profession, '
          'work, 10th house, Sun, and Saturn.')
      ..writeln()
      ..writeln('My placements:');
    final d1Sun = _planetLine('Sun');
    final d1Saturn = _planetLine('Saturn');
    final d1Mercury = _planetLine('Mercury');
    if (d1Sun.isNotEmpty) prompt.writeln('- D1 $d1Sun.');
    if (d1Saturn.isNotEmpty) prompt.writeln('- D1 $d1Saturn.');
    if (d1Mercury.isNotEmpty) prompt.writeln('- D1 $d1Mercury.');
    if (d10Asc.isNotEmpty) prompt.writeln('- D10 Ascendant: $d10Asc.');
    for (final p in const ['Sun', 'Moon', 'Mars', 'Mercury', 'Jupiter',
      'Venus', 'Saturn']) {
      final line = _d10Line(p);
      if (line.isNotEmpty) prompt.writeln('- D10 $line.');
    }
    prompt
      ..writeln()
      ..writeln('Write a 4-5 line reading on my natural career direction, '
          'professional strengths, likely areas of achievement, and what '
          'to watch out for at work. Hinglish, warm tone.');

    try {
      final response = await AiService.getAstrologyResponse(
        profile: profile,
        userMessage: prompt.toString(),
        chatHistory: const [],
      );
      if (!mounted) return;
      final answer = response.text.trim();
      setState(() {
        _careerLoading = false;
        if (answer.isEmpty) {
          _careerError = 'Could not generate career reading. Tap retry.';
        } else {
          _careerInsight = answer;
        }
      });
      if (answer.isNotEmpty) {
        _writeCachedInsight(profile, 'career', answer);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _careerLoading = false;
        _careerError = 'Connection issue. Tap retry to load career reading.';
      });
    }
  }

  Map<String, String> _parseInsights(String text) {
    final Map<String, String> result = {};
    final sections = ['PERSONALITY', 'CAREER', 'RELATIONSHIPS', 'STRENGTHS', 'CHALLENGES'];

    for (int i = 0; i < sections.length; i++) {
      final key = sections[i];
      final pattern = RegExp('${key}[:\\s]*', caseSensitive: false);
      final match = pattern.firstMatch(text);
      if (match != null) {
        final startPos = match.end;
        // Find the next section or end of text
        int endPos = text.length;
        for (int j = i + 1; j < sections.length; j++) {
          final nextPattern = RegExp('${sections[j]}[:\\s]*', caseSensitive: false);
          final nextMatch = nextPattern.firstMatch(text.substring(startPos));
          if (nextMatch != null) {
            endPos = startPos + nextMatch.start;
            break;
          }
        }
        result[key] = text.substring(startPos, endPos).trim();
      }
    }

    // If parsing failed, just put the whole response as personality
    if (result.isEmpty && text.isNotEmpty) {
      result['PERSONALITY'] = text;
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);

    if (profile == null) {
      return _buildNoProfileScreen(context);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Kundli Chart'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Column(
            children: [
              Container(height: 1, color: AppColors.divider),
              TabBar(
                controller: _tabController,
                indicatorColor: AppColors.purpleAccent,
                indicatorWeight: 3,
                labelColor: AppColors.purpleLight,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: 'D1 Rashi'),
                  Tab(text: 'D9 Navamsha'),
                  Tab(text: 'D10 Career'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _error != null
              ? _buildErrorState()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildChartTab(profile, 'D1', 'Rashi\nKundli'),
                    _buildChartTab(profile, 'D9', 'Navamsha\nD9'),
                    _buildChartTab(profile, 'D10', 'Dasamsa\nD10'),
                  ],
                ),
    );
  }

  Widget _buildChartTab(UserProfile profile, String chartType, String label) {
    int ascIndex;
    Map<int, List<ChartPlanet>> planets;

    if (chartType == 'D1') {
      final ascSign = (_chartData?['ascendant'] as Map<String, dynamic>?)?['sign']?.toString() ?? 'Aries';
      ascIndex = KundliChart.signToIndex(ascSign);
      planets = _buildD1Planets();
    } else if (chartType == 'D9') {
      ascIndex = _getDivisionalAscendant('d9Navamsha');
      planets = _buildDivisionalPlanets('d9Navamsha');
    } else {
      ascIndex = _getDivisionalAscendant('d10Dasamsa');
      planets = _buildDivisionalPlanets('d10Dasamsa');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info header
          _buildInfoHeader(profile)
              .animate().fadeIn(duration: 500.ms),

          const SizedBox(height: 20),

          // The Chart
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.purpleAccent.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.purpleAccent.withOpacity(0.05),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  chartType == 'D1' ? 'Rashi Kundli (Birth Chart)'
                      : chartType == 'D9' ? 'Navamsha Chart (Marriage/Dharma)'
                      : 'Dasamsa Chart (Career)',
                  style: const TextStyle(
                    color: AppColors.goldLight,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'North Indian Style',
                  style: TextStyle(
                    color: AppColors.textMuted.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: MediaQuery.of(context).size.width - 72,
                  child: KundliChart(
                    ascendantSignIndex: ascIndex,
                    housePlanets: planets,
                    chartLabel: label,
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 600.ms, delay: 200.ms)
              .scaleXY(begin: 0.95, end: 1.0, duration: 600.ms, delay: 200.ms),

          const SizedBox(height: 20),

          // Planet legend
          _buildPlanetLegend()
              .animate().fadeIn(duration: 500.ms, delay: 300.ms),

          const SizedBox(height: 20),

          // Show insights and details only for D1
          if (chartType == 'D1') ...[
            // Personalized Insights (the main value for users)
            _buildInsightsSection()
                .animate().fadeIn(duration: 500.ms, delay: 350.ms),

            const SizedBox(height: 16),

            // Dasha info
            _buildDashaCard()
                .animate().fadeIn(duration: 500.ms, delay: 400.ms),

            const SizedBox(height: 16),

            // Ascendant details
            _buildAscendantCard()
                .animate().fadeIn(duration: 500.ms, delay: 450.ms),

            const SizedBox(height: 16),

            // Planet details list
            _buildPlanetDetailsCard()
                .animate().fadeIn(duration: 500.ms, delay: 500.ms),

            const SizedBox(height: 32),
          ],

          if (chartType == 'D9') ...[
            _buildDivisionalInfo(
              'Navamsha reveals the deeper soul purpose, marriage compatibility, and dharmic path. '
              'A strong Navamsha can elevate a weak Rashi chart, and vice versa.',
              Icons.favorite_outline,
            ).animate().fadeIn(duration: 500.ms, delay: 400.ms),
            const SizedBox(height: 12),
            _buildDivisionalReadingCard(
              title: 'Your Navamsha Reading',
              icon: Icons.auto_awesome,
              accent: const Color(0xFFE91E63),
              insight: _navamshaInsight,
              loading: _navamshaLoading,
              error: _navamshaError,
              onRetry: _loadNavamshaInsight,
            ).animate().fadeIn(duration: 500.ms, delay: 500.ms),
            const SizedBox(height: 32),
          ],

          if (chartType == 'D10') ...[
            _buildDivisionalInfo(
              'Dasamsa reveals your career potential, professional achievements, and public reputation. '
              'The 10th house lord placement here is crucial for career success.',
              Icons.work_outline,
            ).animate().fadeIn(duration: 500.ms, delay: 400.ms),
            const SizedBox(height: 12),
            _buildDivisionalReadingCard(
              title: 'Your Career Reading',
              icon: Icons.auto_awesome,
              accent: AppColors.goldLight,
              insight: _careerInsight,
              loading: _careerLoading,
              error: _careerError,
              onRetry: _loadCareerInsight,
            ).animate().fadeIn(duration: 500.ms, delay: 500.ms),
            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoHeader(UserProfile profile) {
    final asc = _chartData?['ascendant'] as Map<String, dynamic>?;
    final nakshatra = _chartData?['birthNakshatra']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.purpleAccent.withOpacity(0.1),
            Colors.transparent,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.purpleAccent.withOpacity(0.2),
            ),
            child: const Icon(Icons.auto_awesome, color: AppColors.goldLight, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name.isNotEmpty ? profile.name : 'User',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${profile.dobFormatted} | ${profile.placeOfBirth}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                if (asc != null)
                  Text(
                    'Lagna: ${asc['sign']} | Nakshatra: $nakshatra',
                    style: const TextStyle(color: AppColors.goldLight, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsSection() {
    if (_insightsLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.purpleAccent.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(
                color: AppColors.purpleAccent,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Analyzing your chart...',
              style: TextStyle(color: AppColors.textMuted.withOpacity(0.8), fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Error state — show a friendly retry card instead of silent emptiness.
    // Without this branch the user just sees a blank chart screen after the
    // server fails or the user is offline.
    if (_insights.isEmpty) {
      if (_insightsError != null) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.error.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Icon(Icons.cloud_off_outlined,
                  color: AppColors.error.withOpacity(0.8), size: 28),
              const SizedBox(height: 10),
              Text(
                _insightsError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 38,
                child: ElevatedButton.icon(
                  onPressed: _loadInsights,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purpleAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }

    const insightConfig = {
      'PERSONALITY': {
        'icon': Icons.person_outline,
        'title': 'Your Personality',
        'color': 'purple',
      },
      'CAREER': {
        'icon': Icons.work_outline,
        'title': 'Career & Profession',
        'color': 'gold',
      },
      'RELATIONSHIPS': {
        'icon': Icons.favorite_outline,
        'title': 'Love & Relationships',
        'color': 'pink',
      },
      'STRENGTHS': {
        'icon': Icons.star_outline,
        'title': 'Your Strengths',
        'color': 'green',
      },
      'CHALLENGES': {
        'icon': Icons.shield_outlined,
        'title': 'Challenges & Remedies',
        'color': 'orange',
      },
    };

    Color _getColor(String colorName) {
      switch (colorName) {
        case 'purple': return AppColors.purpleLight;
        case 'gold': return AppColors.goldLight;
        case 'pink': return const Color(0xFFE91E63);
        case 'green': return AppColors.success;
        case 'orange': return const Color(0xFFF59E0B);
        default: return AppColors.purpleLight;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.purpleAccent.withOpacity(0.15),
              ),
              child: const Icon(Icons.auto_awesome, color: AppColors.purpleLight, size: 18),
            ),
            const SizedBox(width: 12),
            const Text(
              'Your Chart Reading',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: Text(
            'Personalized insights from your birth chart',
            style: TextStyle(color: AppColors.textMuted.withOpacity(0.7), fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),

        // Insight cards
        ..._insights.entries.map((entry) {
          final config = insightConfig[entry.key];
          if (config == null) return const SizedBox.shrink();

          final iconData = config['icon'] as IconData;
          final title = config['title'] as String;
          final color = _getColor(config['color'] as String);

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withOpacity(0.15),
                        ),
                        child: Icon(iconData, color: color, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        title,
                        style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    entry.value,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPlanetLegend() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Planet Abbreviations',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _legendChip('Su', 'Sun'),
              _legendChip('Mo', 'Moon'),
              _legendChip('Ma', 'Mars'),
              _legendChip('Me', 'Mercury'),
              _legendChip('Ju', 'Jupiter'),
              _legendChip('Ve', 'Venus'),
              _legendChip('Sa', 'Saturn'),
              _legendChip('Ra', 'Rahu'),
              _legendChip('Ke', 'Ketu'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '(R) = Retrograde | Asc = Ascendant',
            style: TextStyle(color: AppColors.textMuted.withOpacity(0.7), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _legendChip(String abbr, String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.purpleAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$abbr ',
              style: const TextStyle(color: AppColors.purpleLight, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: name,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashaCard() {
    final dasha = _chartData?['dasha'] as Map<String, dynamic>? ?? {};
    final maha = dasha['mahadasha']?.toString() ?? 'Unknown';
    final mahaEnd = dasha['mahadashaEnd']?.toString() ?? '';
    final antar = dasha['antardasha']?.toString() ?? 'Unknown';
    final antarEnd = dasha['antardashaEnd']?.toString() ?? '';
    final pratyantar = dasha['pratyantar']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.goldLight.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.goldLight.withOpacity(0.15),
                ),
                child: const Icon(Icons.timeline, color: AppColors.goldLight, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Current Dasha Period',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _dashaRow('Mahadasha', maha, mahaEnd),
          const SizedBox(height: 8),
          _dashaRow('Antardasha', antar, antarEnd),
          if (pratyantar.isNotEmpty) ...[
            const SizedBox(height: 8),
            _dashaRow('Pratyantar', pratyantar, ''),
          ],
          const SizedBox(height: 10),
          Text(
            'Dasha periods influence major life themes and events based on Vimshottari Dasha system.',
            style: TextStyle(color: AppColors.textMuted.withOpacity(0.7), fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _dashaRow(String label, String planet, String endDate) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Text(
            planet,
            style: const TextStyle(color: AppColors.purpleLight, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        if (endDate.isNotEmpty)
          Text(
            'until $endDate',
            style: TextStyle(color: AppColors.textMuted.withOpacity(0.7), fontSize: 11),
          ),
      ],
    );
  }

  Widget _buildAscendantCard() {
    final asc = _chartData?['ascendant'] as Map<String, dynamic>? ?? {};
    final sign = asc['sign']?.toString() ?? 'Unknown';
    final degree = asc['degree']?.toString() ?? '';
    final nakshatra = asc['nakshatra']?.toString() ?? '';
    final lord = asc['lord']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.goldLight.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.goldLight.withOpacity(0.15),
                ),
                child: const Icon(Icons.home_outlined, color: AppColors.goldLight, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Lagna (Ascendant)',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _infoChip('Sign', sign, AppColors.goldLight),
              const SizedBox(width: 8),
              if (degree.isNotEmpty)
                _infoChip('Degree', '$degree\u00B0', AppColors.purpleLight),
              const SizedBox(width: 8),
              if (nakshatra.isNotEmpty)
                _infoChip('Nakshatra', nakshatra, AppColors.purpleLight),
            ],
          ),
          if (lord.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Lagna Lord: $lord',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: AppColors.textMuted.withOpacity(0.7), fontSize: 9)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPlanetDetailsCard() {
    final planets = _chartData?['planets'] as Map<String, dynamic>? ?? {};
    if (planets.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.purpleAccent.withOpacity(0.15),
                ),
                child: const Icon(Icons.public, color: AppColors.purpleLight, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Planetary Positions',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                SizedBox(width: 70, child: Text('Planet', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
                SizedBox(width: 70, child: Text('Sign', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
                SizedBox(width: 40, child: Text('House', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
                Expanded(child: Text('Nakshatra', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ...planets.entries.map((entry) {
            final name = entry.key;
            final data = entry.value as Map<String, dynamic>;
            final sign = data['sign']?.toString() ?? '';
            final house = data['house']?.toString() ?? '';
            final nak = data['nakshatra']?.toString() ?? '';
            final isRetro = data['isRetrograde'] == true;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Row(
                      children: [
                        Text(
                          name,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                        if (isRetro)
                          Text(
                            ' R',
                            style: TextStyle(color: AppColors.error.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(sign, style: const TextStyle(color: AppColors.purpleLight, fontSize: 12)),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(house, style: const TextStyle(color: AppColors.goldLight, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Text(nak, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDivisionalInfo(String description, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.purpleLight, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  /// Reading card for D9 / D10 tabs. Renders one of: spinner while
  /// loading, error + Retry button on failure, or the actual reading
  /// text. Shared between Navamsha and Career tabs to keep their
  /// behaviour identical.
  Widget _buildDivisionalReadingCard({
    required String title,
    required IconData icon,
    required Color accent,
    required String? insight,
    required bool loading,
    required String? error,
    required VoidCallback onRetry,
  }) {
    Widget body;
    if (loading) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
            const SizedBox(width: 12),
            Text(
              'Reading your chart...',
              style: TextStyle(
                  color: AppColors.textMuted.withOpacity(0.8), fontSize: 13),
            ),
          ],
        ),
      );
    } else if (insight != null && insight.isNotEmpty) {
      body = Text(
        insight,
        style: const TextStyle(
            color: AppColors.textSecondary, fontSize: 13, height: 1.6),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error ?? 'Reading not available yet.',
            style: TextStyle(
                color: AppColors.textMuted.withOpacity(0.9),
                fontSize: 13,
                height: 1.5),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 16),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: AppColors.purpleAccent,
            strokeWidth: 2.5,
          ),
          SizedBox(height: 16),
          Text(
            'Calculating your birth chart...',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
          SizedBox(height: 6),
          Text(
            'Analyzing planetary positions',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 16),
          Text(_error ?? 'Error loading chart',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _loadChart,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoProfileScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Kundli Chart'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 56, color: AppColors.textMuted.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text(
              'Birth details needed',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your birth details to generate\nyour Kundli chart',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UserDetailsScreen()),
                );
              },
              child: const Text('Enter Details'),
            ),
          ],
        ),
      ),
    );
  }
}
