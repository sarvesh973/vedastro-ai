import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

/// Loading bubble shown while waiting for the AI's reply.
///
/// Replaces the plain bouncing-dots indicator with a contextual line that
/// tells the user what's actually being analyzed — e.g. "Reading your
/// career line in your kundli..." for a question about jobs.
///
/// Topic detection is a simple keyword match on the user's question
/// (cheap, runs locally, no extra API call). Falls back to a generic
/// "Consulting your kundli..." if no specific topic matches.
class ContextualLoader extends StatefulWidget {
  /// The user's question — used to pick the relevant loader copy.
  final String userQuestion;

  const ContextualLoader({super.key, required this.userQuestion});

  @override
  State<ContextualLoader> createState() => _ContextualLoaderState();
}

class _ContextualLoaderState extends State<ContextualLoader> {
  late List<String> _phrases;
  int _phraseIndex = 0;
  Timer? _rotationTimer;

  @override
  void initState() {
    super.initState();
    _phrases = _phrasesFor(widget.userQuestion);
    // Rotate through phrases every 2.5s so the user sees progress even on
    // a slow response. The bubble feels alive instead of frozen.
    _rotationTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!mounted) return;
      setState(() {
        _phraseIndex = (_phraseIndex + 1) % _phrases.length;
      });
    });
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    super.dispose();
  }

  /// Pick 2-3 contextual phrases based on the topic detected in [question].
  /// Order: more specific first (career, marriage) before broad (life).
  static List<String> _phrasesFor(String question) {
    final q = question.toLowerCase();

    // Career / job / business
    if (RegExp(r'career|job|naukri|business|kaam|work|promotion|salary')
        .hasMatch(q)) {
      return [
        'Reading your career line in your kundli...',
        'Checking the 10th house and Saturn placement...',
        'Looking at your dasha for career timing...',
      ];
    }

    // Love / marriage / relationship
    if (RegExp(r'love|marriage|shaadi|partner|girl|boy|relationship|pyaar|wife|husband|prem')
        .hasMatch(q)) {
      return [
        'Examining your 7th house — house of partnership...',
        'Studying Venus and Jupiter for love insights...',
        'Looking at marriage timing in your dasha...',
      ];
    }

    // Money / finance / wealth
    if (RegExp(r'money|paisa|wealth|finance|loan|debt|crore|lakh|amir|rich|kismat')
        .hasMatch(q)) {
      return [
        'Calculating wealth indicators in your chart...',
        'Reading the 2nd and 11th houses for income...',
        'Checking Jupiter and Mercury for prosperity...',
      ];
    }

    // Health / illness / fitness
    if (RegExp(r'health|illness|disease|bimari|sick|body|fitness|sehat|tabiyat')
        .hasMatch(q)) {
      return [
        'Analyzing the 6th house for health patterns...',
        'Checking Mars and Sun for vitality...',
        'Looking at remedies in Brighu Sanhita...',
      ];
    }

    // Family / parents / siblings / kids
    if (RegExp(r'family|parent|mother|father|brother|sister|child|maa|papa|bachcha|ghar')
        .hasMatch(q)) {
      return [
        'Reading your 4th house — your home and mother...',
        'Studying your 9th house — father and dharma...',
        'Looking at family karma in your chart...',
      ];
    }

    // Education / studies / exam
    if (RegExp(r'study|exam|education|college|school|padhai|knowledge|degree|admission')
        .hasMatch(q)) {
      return [
        'Reading the 5th house — your wisdom and learning...',
        'Checking Mercury and Jupiter for studies...',
        'Looking at your dasha for academic success...',
      ];
    }

    // Travel / abroad / foreign
    if (RegExp(r'travel|foreign|abroad|videsh|trip|visa|america|usa|canada|uk')
        .hasMatch(q)) {
      return [
        'Checking the 12th house — long-distance travel...',
        'Looking for foreign settlement yogas...',
        'Reading Rahu placement for unusual journeys...',
      ];
    }

    // Spiritual / dharma / meditation
    if (RegExp(r'spiritual|moksha|dharma|god|bhagwan|meditat|yog|sadhana')
        .hasMatch(q)) {
      return [
        'Looking at your 9th house — your spiritual path...',
        'Reading Ketu for past-life karma...',
        'Checking Jupiter for dharmic guidance...',
      ];
    }

    // Generic fallback
    return [
      'Consulting your kundli...',
      'Reading the planets in your birth chart...',
      'Cross-referencing with BPHS and Phaladeepika...',
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(right: 48, bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: AppColors.aiBubble,
          border: Border.all(color: AppColors.divider, width: 0.5),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Three pulsing dots — same as old indicator, kept as a
            // visual cue that something IS happening.
            _buildDot(0),
            const SizedBox(width: 4),
            _buildDot(1),
            const SizedBox(width: 4),
            _buildDot(2),
            const SizedBox(width: 12),
            // Rotating contextual phrase
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: Text(
                  _phrases[_phraseIndex],
                  key: ValueKey(_phraseIndex),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _buildDot(int index) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: AppColors.purpleLight.withValues(alpha: 0.7),
        shape: BoxShape.circle,
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .scaleXY(
          begin: 0.6,
          end: 1.0,
          duration: 600.ms,
          delay: Duration(milliseconds: index * 200),
          curve: Curves.easeInOut,
        )
        .then()
        .scaleXY(
          begin: 1.0,
          end: 0.6,
          duration: 600.ms,
          curve: Curves.easeInOut,
        );
  }
}
