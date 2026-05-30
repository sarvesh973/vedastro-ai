import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Slowly rotating wheel showing the 12 zodiac glyphs around a double
/// ring. Designed as a low-attention decorative accent — pick a low
/// alpha colour and a long period (default 90s per revolution) so it
/// reads as atmosphere, not motion.
///
/// Uses CustomPainter (no image assets, no Lottie dep) and draws:
///   - outer ring
///   - inner ring
///   - 12 thin divider spokes between sectors
///   - the 12 Unicode zodiac symbols arranged around the inner ring
class ZodiacWheel extends StatefulWidget {
  final double size;
  final Color color;
  final Duration period;

  const ZodiacWheel({
    super.key,
    this.size = 84,
    this.color = const Color(0xFF6FA8FF),
    this.period = const Duration(seconds: 90),
  });

  @override
  State<ZodiacWheel> createState() => _ZodiacWheelState();
}

class _ZodiacWheelState extends State<ZodiacWheel>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.period)..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _ZodiacWheelPainter(color: widget.color),
        ),
      ),
    );
  }
}

class _ZodiacWheelPainter extends CustomPainter {
  static const _symbols = [
    '♈', // Aries
    '♉', // Taurus
    '♊', // Gemini
    '♋', // Cancer
    '♌', // Leo
    '♍', // Virgo
    '♎', // Libra
    '♏', // Scorpio
    '♐', // Sagittarius
    '♑', // Capricorn
    '♒', // Aquarius
    '♓', // Pisces
  ];

  final Color color;

  _ZodiacWheelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2 - 1;
    final innerR = outerR - 16;

    // Outer ring
    canvas.drawCircle(
      center,
      outerR,
      Paint()
        ..color = color.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Inner ring (where symbols live)
    canvas.drawCircle(
      center,
      innerR,
      Paint()
        ..color = color.withOpacity(0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );

    // 12 divider spokes between the rings
    final spokePaint = Paint()
      ..color = color.withOpacity(0.30)
      ..strokeWidth = 0.6;
    for (int i = 0; i < 12; i++) {
      final a = (i / 12) * 2 * math.pi - math.pi / 2;
      final p1 = Offset(
        center.dx + math.cos(a) * innerR,
        center.dy + math.sin(a) * innerR,
      );
      final p2 = Offset(
        center.dx + math.cos(a) * outerR,
        center.dy + math.sin(a) * outerR,
      );
      canvas.drawLine(p1, p2, spokePaint);
    }

    // Zodiac symbols — placed at the midpoint of each sector arc, on
    // the inner ring radius. Offset by half a sector so the glyph sits
    // BETWEEN the dividers, not on top of them.
    final symbolRadius = (innerR + outerR) / 2;
    for (int i = 0; i < 12; i++) {
      final a = ((i + 0.5) / 12) * 2 * math.pi - math.pi / 2;
      final x = center.dx + math.cos(a) * symbolRadius;
      final y = center.dy + math.sin(a) * symbolRadius;

      final tp = TextPainter(
        text: TextSpan(
          text: _symbols[i],
          style: TextStyle(
            color: color.withOpacity(0.85),
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    // Tiny central dot for visual anchor
    canvas.drawCircle(
      center,
      1.5,
      Paint()..color = color.withOpacity(0.6),
    );
  }

  @override
  bool shouldRepaint(_ZodiacWheelPainter old) => old.color != color;
}
