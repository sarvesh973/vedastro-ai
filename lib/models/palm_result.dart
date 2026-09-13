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

  /// Fate line and mounts. Nullable because the server only guarantees the
  /// original three - it is told to omit a section rather than invent one
  /// when the photo does not show it clearly.
  final PalmLineResult? fateLine;
  final PalmLineResult? mounts;

  /// Server-side id for this reading. Follow-up questions post this instead
  /// of resending the whole reading.
  final String? readingId;

  /// True when the reading was cross-checked against the user's kundli.
  /// False means birth details were missing and this is an image-only read.
  final bool usedChart;

  const PalmReadingResult({
    required this.loveLine,
    required this.careerLine,
    required this.lifeLine,
    this.fateLine,
    this.mounts,
    this.readingId,
    this.usedChart = false,
  });

  List<PalmLineResult> get allLines => [
        loveLine,
        careerLine,
        lifeLine,
        if (fateLine != null) fateLine!,
        if (mounts != null) mounts!,
      ];

  /// Shape the server expects when we post the reading itself instead of an
  /// id. Keys are arbitrary; it picks out any value carrying a `title`.
  Map<String, dynamic> toJson() {
    Map<String, dynamic> line(PalmLineResult l) => {
          'title': l.title,
          'emoji': l.emoji,
          'insight': l.insight,
          'meaning': l.meaning,
          'advice': l.advice,
        };
    return {
      'loveLine': line(loveLine),
      'careerLine': line(careerLine),
      'lifeLine': line(lifeLine),
      if (fateLine != null) 'fateLine': line(fateLine!),
      if (mounts != null) 'mounts': line(mounts!),
    };
  }
}
