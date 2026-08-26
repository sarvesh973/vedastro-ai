import 'dart:ui';

/// One Mulank (Ank Jyotish numerology) reading returned by the backend
/// `/mulank/reading` endpoint. The numbers + [verdict] are deterministic
/// (always present); [reading] is the LLM prose and is null when the
/// period is locked behind the paywall (in which case [teaser] carries a
/// short free line) or when generation was unavailable.
class MulankReading {
  final int mulank;
  final String planet;
  final String period; // daily | weekly | monthly
  final String verdict; // favourable | neutral | caution
  final String? reading; // full prose (unlocked) or null
  final String? teaser; // short free line when locked
  final bool locked;
  final String? plan;
  final bool cached;

  const MulankReading({
    required this.mulank,
    required this.planet,
    required this.period,
    required this.verdict,
    this.reading,
    this.teaser,
    this.locked = false,
    this.plan,
    this.cached = false,
  });

  factory MulankReading.fromJson(Map<String, dynamic> j) {
    return MulankReading(
      mulank: (j['mulank'] ?? 0) as int,
      planet: (j['planet'] ?? '') as String,
      period: (j['period'] ?? 'daily') as String,
      verdict: (j['verdict'] ?? 'neutral') as String,
      reading: j['reading'] as String?,
      teaser: j['teaser'] as String?,
      locked: (j['locked'] ?? false) as bool,
      plan: j['plan'] as String?,
      cached: (j['cached'] ?? false) as bool,
    );
  }

  bool get isFavourable => verdict == 'favourable';
  bool get isCaution => verdict == 'caution';

  /// Emoji dot for the verdict — matches the deterministic 🟢/🟡/🔴 rating.
  String get emoji => isFavourable ? '🟢' : isCaution ? '🔴' : '🟡';

  /// Human label for the verdict chip.
  String get verdictLabel =>
      isFavourable ? 'Favourable' : isCaution ? 'Go gently' : 'Steady';

  /// Accent colour for the verdict (green / amber / red).
  Color get verdictColor => isFavourable
      ? const Color(0xFF10B981)
      : isCaution
          ? const Color(0xFFEF4444)
          : const Color(0xFFF59E0B);
}
