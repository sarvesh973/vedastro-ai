/// Static "who you are" numerology profile for a mulank, from the
/// backend `/mulank/profile` endpoint. All fields are traditional
/// associations computed deterministically server-side.
class MulankProfile {
  final int mulank;
  final String planet;
  final String title;
  final List<String> traits;
  final List<String> strengths;
  final List<String> watch;
  final String luckyDay;
  final List<String> luckyColours;
  final List<int> luckyNumbers;
  final String gem;
  final List<String> favoursAreas;
  final int? bhagyank;

  const MulankProfile({
    required this.mulank,
    required this.planet,
    required this.title,
    this.traits = const [],
    this.strengths = const [],
    this.watch = const [],
    this.luckyDay = '',
    this.luckyColours = const [],
    this.luckyNumbers = const [],
    this.gem = '',
    this.favoursAreas = const [],
    this.bhagyank,
  });

  static List<String> _strs(dynamic v) =>
      (v as List?)?.map((e) => e.toString()).toList() ?? const [];
  static List<int> _ints(dynamic v) =>
      (v as List?)?.map((e) => (e as num).toInt()).toList() ?? const [];

  factory MulankProfile.fromJson(Map<String, dynamic> j) {
    return MulankProfile(
      mulank: (j['mulank'] ?? 0) as int,
      planet: (j['planet'] ?? '') as String,
      title: (j['title'] ?? '') as String,
      traits: _strs(j['traits']),
      strengths: _strs(j['strengths']),
      watch: _strs(j['watch']),
      luckyDay: (j['luckyDay'] ?? '') as String,
      luckyColours: _strs(j['luckyColours']),
      luckyNumbers: _ints(j['luckyNumbers']),
      gem: (j['gem'] ?? '') as String,
      favoursAreas: _strs(j['favoursAreas']),
      bhagyank: j['bhagyank'] as int?,
    );
  }
}
