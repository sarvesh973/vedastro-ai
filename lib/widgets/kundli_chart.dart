import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// North Indian style Kundli (birth chart) widget
class KundliChart extends StatelessWidget {
  final int ascendantIndex; // 0 = Aries, 1 = Taurus, etc.
  final int sunSignIndex;
  final Map<String, int>? planetPositions; // planet name -> house number (1-12)

  static const List<String> signs = [
    'Me', 'Vr', 'Mi', 'Ka', 'Si', 'Kn', 'Tu', 'Vs', 'Dh', 'Mk', 'Ku', 'Mn'
  ];

  static const List<String> signsFull = [
    'Mesha', 'Vrishabha', 'Mithuna', 'Karka', 'Simha', 'Kanya',
    'Tula', 'Vrishchika', 'Dhanu', 'Makara', 'Kumbha', 'Meena'
  ];

  const KundliChart({
    super.key,
    required this.ascendantIndex,
    required this.sunSignIndex,
    this.planetPositions,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _KundliPainter(
          ascendantIndex: ascendantIndex,
          sunSignIndex: sunSignIndex,
          planetPositions: planetPositions,
        ),
      ),
    );
  }
}

class _KundliPainter extends CustomPainter {
  final int ascendantIndex;
  final int sunSignIndex;
  final Map<String, int>? planetPositions;

  _KundliPainter({
    required this.ascendantIndex,
    required this.sunSignIndex,
    this.planetPositions,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.fill;

    // Outer square
    final rect = Rect.fromLTWH(0, 0, s, s);
    canvas.drawRect(rect, fillPaint);
    canvas.drawRect(rect, paint);

    // Midpoints
    final top = Offset(s / 2, 0);
    final right = Offset(s, s / 2);
    final bottom = Offset(s / 2, s);
    final left = Offset(0, s / 2);
    // Draw inner diamond (connecting midpoints)
    final diamondPath = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(left.dx, left.dy)
      ..close();
    canvas.drawPath(diamondPath, paint);

    // Draw diagonals (corner to corner) — these split the corners into 2 houses each
    canvas.drawLine(const Offset(0, 0), Offset(s, s), paint);
    canvas.drawLine(Offset(s, 0), Offset(0, s), paint);

    // House positions for text (approximate centers of each region)
    // North Indian: House 1 is always at top-center diamond
    final housePositions = [
      Offset(s * 0.50, s * 0.18), // House 1 - top diamond
      Offset(s * 0.74, s * 0.11), // House 2 - top-right upper
      Offset(s * 0.88, s * 0.28), // House 3 - top-right lower
      Offset(s * 0.82, s * 0.50), // House 4 - right diamond
      Offset(s * 0.88, s * 0.72), // House 5 - bottom-right upper
      Offset(s * 0.74, s * 0.88), // House 6 - bottom-right lower
      Offset(s * 0.50, s * 0.82), // House 7 - bottom diamond
      Offset(s * 0.26, s * 0.88), // House 8 - bottom-left lower
      Offset(s * 0.12, s * 0.72), // House 9 - bottom-left upper
      Offset(s * 0.18, s * 0.50), // House 10 - left diamond
      Offset(s * 0.12, s * 0.28), // House 11 - top-left lower
      Offset(s * 0.26, s * 0.11), // House 12 - top-left upper
    ];

    // Draw zodiac signs in houses
    // In North Indian chart, the sign in house 1 = ascendant
    for (int i = 0; i < 12; i++) {
      final signIndex = (ascendantIndex + i) % 12;
      final pos = housePositions[i];
      final signText = KundliChart.signs[signIndex];

      // Draw house number (small, muted)
      _drawText(
        canvas,
        '${i + 1}',
        Offset(pos.dx, pos.dy - 12),
        fontSize: 10,
        color: AppColors.textMuted,
      );

      // Draw zodiac sign abbreviation
      _drawText(
        canvas,
        signText,
        Offset(pos.dx, pos.dy + 4),
        fontSize: 13,
        color: i == 0
            ? AppColors.goldLight // Ascendant house in gold
            : AppColors.purpleLight,
        fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
      );

      // Draw Sun position
      final sunHouse = (sunSignIndex - ascendantIndex + 12) % 12;
      if (i == sunHouse) {
        _drawText(
          canvas,
          'Su',
          Offset(pos.dx, pos.dy + 20),
          fontSize: 11,
          color: AppColors.goldLight,
          fontWeight: FontWeight.w600,
        );
      }
    }

    // Draw "Asc" label for House 1
    _drawText(
      canvas,
      'Asc',
      Offset(s * 0.50, s * 0.28),
      fontSize: 9,
      color: AppColors.gold,
    );

    // Draw center text
    _drawText(
      canvas,
      'Rashi',
      Offset(s * 0.50, s * 0.46),
      fontSize: 12,
      color: AppColors.textMuted,
    );
    _drawText(
      canvas,
      'Kundli',
      Offset(s * 0.50, s * 0.54),
      fontSize: 12,
      color: AppColors.textMuted,
    );
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
    return oldDelegate.ascendantIndex != ascendantIndex ||
        oldDelegate.sunSignIndex != sunSignIndex;
  }
}
