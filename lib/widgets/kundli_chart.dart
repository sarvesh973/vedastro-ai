import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Planet info for display in a house
class ChartPlanet {
  final String abbr; // Su, Mo, Ma, etc.
  final bool isRetrograde;

  const ChartPlanet(this.abbr, {this.isRetrograde = false});
}

/// North Indian style Kundli (birth chart) widget
class KundliChart extends StatelessWidget {
  final int ascendantSignIndex; // 0=Aries ... 11=Pisces
  final Map<int, List<ChartPlanet>> housePlanets; // house 1-12 -> planets
  final String chartLabel; // center label e.g. "D1", "D9"

  static const List<String> signs = [
    'Ar', 'Ta', 'Ge', 'Cn', 'Le', 'Vi', 'Li', 'Sc', 'Sg', 'Cp', 'Aq', 'Pi'
  ];

  static const List<String> signsFull = [
    'Aries', 'Taurus', 'Gemini', 'Cancer', 'Leo', 'Virgo',
    'Libra', 'Scorpio', 'Sagittarius', 'Capricorn', 'Aquarius', 'Pisces'
  ];

  static const List<String> signsHindi = [
    'Mesha', 'Vrishabha', 'Mithuna', 'Karka', 'Simha', 'Kanya',
    'Tula', 'Vrishchika', 'Dhanu', 'Makara', 'Kumbha', 'Meena'
  ];

  /// Map English planet names to abbreviations
  static const Map<String, String> planetAbbr = {
    'Sun': 'Su', 'Moon': 'Mo', 'Mars': 'Ma',
    'Mercury': 'Me', 'Jupiter': 'Ju', 'Venus': 'Ve',
    'Saturn': 'Sa', 'Rahu': 'Ra', 'Ketu': 'Ke',
  };

  /// Convert sign name (English or Hindi) to index
  static int signToIndex(String name) {
    final lower = name.toLowerCase().trim();
    for (int i = 0; i < signsFull.length; i++) {
      if (signsFull[i].toLowerCase() == lower) return i;
    }
    for (int i = 0; i < signsHindi.length; i++) {
      if (signsHindi[i].toLowerCase() == lower) return i;
    }
    return 0;
  }

  const KundliChart({
    super.key,
    required this.ascendantSignIndex,
    this.housePlanets = const {},
    this.chartLabel = 'Rashi\nKundli',
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _KundliPainter(
          ascendantSignIndex: ascendantSignIndex,
          housePlanets: housePlanets,
          chartLabel: chartLabel,
        ),
      ),
    );
  }
}

class _KundliPainter extends CustomPainter {
  final int ascendantSignIndex;
  final Map<int, List<ChartPlanet>> housePlanets;
  final String chartLabel;

  _KundliPainter({
    required this.ascendantSignIndex,
    required this.housePlanets,
    required this.chartLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final linePaint = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.fill;

    // Outer square
    final rect = Rect.fromLTWH(0, 0, s, s);
    canvas.drawRect(rect, fillPaint);
    canvas.drawRect(rect, linePaint);

    // Inner diamond (connecting midpoints)
    final diamondPath = Path()
      ..moveTo(s / 2, 0)
      ..lineTo(s, s / 2)
      ..lineTo(s / 2, s)
      ..lineTo(0, s / 2)
      ..close();
    canvas.drawPath(diamondPath, linePaint);

    // Diagonals (corner to corner)
    canvas.drawLine(const Offset(0, 0), Offset(s, s), linePaint);
    canvas.drawLine(Offset(s, 0), Offset(0, s), linePaint);

    // House center positions (for sign abbreviation placement).
    //
    // North Indian convention: H1 is the top diamond, and houses run
    // ANTI-CLOCKWISE — H2 to the top-LEFT, H4 is the LEFT diamond,
    // H7 the bottom diamond, H10 the RIGHT diamond. The earlier layout
    // ran clockwise (H2 top-right, H4 right, H10 left), which mirrored
    // every chart vs. how it appears in any printed kundli or other
    // astrology app. Real-user feedback flagged this as a credibility
    // bug. Underlying house assignments are unaffected; this is purely
    // a placement swap of the on-screen slots.
    final signPositions = [
      Offset(s * 0.50, s * 0.14), // H1  - top diamond
      Offset(s * 0.24, s * 0.07), // H2  - top-left upper
      Offset(s * 0.08, s * 0.24), // H3  - top-left lower
      Offset(s * 0.15, s * 0.50), // H4  - left diamond
      Offset(s * 0.08, s * 0.76), // H5  - bottom-left upper
      Offset(s * 0.24, s * 0.92), // H6  - bottom-left lower
      Offset(s * 0.50, s * 0.86), // H7  - bottom diamond
      Offset(s * 0.76, s * 0.92), // H8  - bottom-right lower
      Offset(s * 0.92, s * 0.76), // H9  - bottom-right upper
      Offset(s * 0.85, s * 0.50), // H10 - right diamond
      Offset(s * 0.92, s * 0.24), // H11 - top-right lower
      Offset(s * 0.76, s * 0.07), // H12 - top-right upper
    ];

    // Planet text positions — pushed deeper into each house's "fat" zone
    // (away from where diagonals converge) so multi-planet stacks don't
    // bleed into neighbouring houses or sign labels.
    final planetPositions = [
      Offset(s * 0.50, s * 0.27), // H1 - top diamond
      Offset(s * 0.32, s * 0.16), // H2
      Offset(s * 0.16, s * 0.32), // H3
      Offset(s * 0.23, s * 0.50), // H4 - left diamond
      Offset(s * 0.16, s * 0.68), // H5
      Offset(s * 0.32, s * 0.84), // H6
      Offset(s * 0.50, s * 0.73), // H7 - bottom diamond
      Offset(s * 0.68, s * 0.84), // H8
      Offset(s * 0.84, s * 0.68), // H9
      Offset(s * 0.77, s * 0.50), // H10 - right diamond
      Offset(s * 0.84, s * 0.32), // H11
      Offset(s * 0.68, s * 0.16), // H12
    ];

    // Draw each house
    for (int i = 0; i < 12; i++) {
      final signIndex = (ascendantSignIndex + i) % 12;
      final signText = KundliChart.signs[signIndex];
      final isAscendant = i == 0;

      // Draw sign abbreviation
      _drawText(
        canvas,
        signText,
        signPositions[i],
        fontSize: 11,
        color: isAscendant ? AppColors.goldLight : AppColors.textMuted,
        fontWeight: isAscendant ? FontWeight.w700 : FontWeight.w400,
      );

      // Draw planets in this house. Each planet gets its own row so they
      // never visually collide. Font is small (8pt) and rows are tight
      // (9px) so even a 6-planet house fits inside the diamond without
      // bleeding into neighbouring houses or the sign label.
      final planets = housePlanets[i + 1] ?? [];
      if (planets.isNotEmpty) {
        // Drop the "(R)" suffix in the chart cells — was tripling planet
        // width and causing overlap. Retrograde is still shown in the
        // planet-abbreviations legend below the chart; here we keep it
        // minimal so 6 planets in one house still fit.
        final planetTexts = planets.map((p) => p.abbr).toList();

        const fontSize = 8.5;
        const rowHeight = 9.5;
        final totalRows = planetTexts.length;
        // Centre the stack vertically around planetPositions[i].
        final startY =
            planetPositions[i].dy - (totalRows - 1) * rowHeight / 2;

        for (int p = 0; p < planetTexts.length; p++) {
          _drawText(
            canvas,
            planetTexts[p],
            Offset(planetPositions[i].dx, startY + p * rowHeight),
            fontSize: fontSize,
            color: AppColors.purpleLight,
            fontWeight: FontWeight.w600,
          );
        }
      }
    }

    // Draw "Asc" label for House 1
    _drawText(
      canvas,
      'Asc',
      Offset(s * 0.50, s * 0.30),
      fontSize: 9,
      color: AppColors.gold,
    );

    // Draw center label
    final lines = chartLabel.split('\n');
    for (int i = 0; i < lines.length; i++) {
      _drawText(
        canvas,
        lines[i],
        Offset(s * 0.50, s * 0.48 + (i * 14)),
        fontSize: 12,
        color: AppColors.textMuted,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position, {
    double fontSize = 12,
    Color color = AppColors.textPrimary,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(position.dx - textPainter.width / 2, position.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _KundliPainter oldDelegate) {
    return oldDelegate.ascendantSignIndex != ascendantSignIndex ||
        oldDelegate.housePlanets != housePlanets ||
        oldDelegate.chartLabel != chartLabel;
  }
}
