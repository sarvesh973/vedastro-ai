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

    // House center positions (for sign abbreviation placement)
    // North Indian: House 1 is top diamond, going clockwise
    final signPositions = [
      Offset(s * 0.50, s * 0.14), // H1 - top diamond
      Offset(s * 0.76, s * 0.07), // H2 - top-right upper
      Offset(s * 0.92, s * 0.24), // H3 - top-right lower
      Offset(s * 0.85, s * 0.50), // H4 - right diamond
      Offset(s * 0.92, s * 0.76), // H5 - bottom-right upper
      Offset(s * 0.76, s * 0.92), // H6 - bottom-right lower
      Offset(s * 0.50, s * 0.86), // H7 - bottom diamond
      Offset(s * 0.24, s * 0.92), // H8 - bottom-left lower
      Offset(s * 0.08, s * 0.76), // H9 - bottom-left upper
      Offset(s * 0.15, s * 0.50), // H10 - left diamond
      Offset(s * 0.08, s * 0.24), // H11 - top-left lower
      Offset(s * 0.24, s * 0.07), // H12 - top-left upper
    ];

    // Planet text positions (slightly below sign abbreviation)
    final planetPositions = [
      Offset(s * 0.50, s * 0.22), // H1
      Offset(s * 0.74, s * 0.14), // H2
      Offset(s * 0.88, s * 0.30), // H3
      Offset(s * 0.82, s * 0.50), // H4
      Offset(s * 0.88, s * 0.70), // H5
      Offset(s * 0.74, s * 0.86), // H6
      Offset(s * 0.50, s * 0.78), // H7
      Offset(s * 0.26, s * 0.86), // H8
      Offset(s * 0.12, s * 0.70), // H9
      Offset(s * 0.18, s * 0.50), // H10
      Offset(s * 0.12, s * 0.30), // H11
      Offset(s * 0.26, s * 0.14), // H12
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

      // Draw planets in this house
      final planets = housePlanets[i + 1] ?? [];
      if (planets.isNotEmpty) {
        // Build planet text: "Su Mo" or "Su(R) Ma"
        final planetTexts = planets.map((p) {
          return p.isRetrograde ? '${p.abbr}(R)' : p.abbr;
        }).toList();

        // Split into rows if too many planets
        if (planetTexts.length <= 3) {
          _drawText(
            canvas,
            planetTexts.join(' '),
            planetPositions[i],
            fontSize: 10,
            color: AppColors.purpleLight,
            fontWeight: FontWeight.w600,
          );
        } else {
          // Split into two rows
          final row1 = planetTexts.sublist(0, 3).join(' ');
          final row2 = planetTexts.sublist(3).join(' ');
          _drawText(
            canvas, row1,
            Offset(planetPositions[i].dx, planetPositions[i].dy - 6),
            fontSize: 10, color: AppColors.purpleLight, fontWeight: FontWeight.w600,
          );
          _drawText(
            canvas, row2,
            Offset(planetPositions[i].dx, planetPositions[i].dy + 6),
            fontSize: 10, color: AppColors.purpleLight, fontWeight: FontWeight.w600,
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
