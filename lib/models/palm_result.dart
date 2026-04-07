class PalmLineResult {
  final String title;
  final String emoji;
  final String insight;
  final String meaning;
  final String advice;

  const PalmLineResult({
    required this.title,
    required this.emoji,
    required this.insight,
    required this.meaning,
    required this.advice,
  });
}

class PalmReadingResult {
  final PalmLineResult loveLine;
  final PalmLineResult careerLine;
  final PalmLineResult lifeLine;

  const PalmReadingResult({
    required this.loveLine,
    required this.careerLine,
    required this.lifeLine,
  });

  List<PalmLineResult> get allLines => [loveLine, careerLine, lifeLine];
}
