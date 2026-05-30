import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Slowly rotating wheel showing all 12 zodiac signs as monochrome
/// glyphs around a double ring, with a 6-pointed star (shatkona /
/// hexagram) in the center.
///
/// The zodiac Unicode glyphs ♈♉♊… normally render as colored emoji
/// on Android (Noto Color Emoji fallback). We force monochrome
/// rendering by using Noto Sans Symbols 2, which has these characters
/// as proper text glyphs — fetched once via the google_fonts package
/// and cached locally afterwards.
///
/// Designed as a low-attention decorative accent — pick a low alpha
/// colour and a long period (default 90s/rev) so it reads as
/// atmosphere, not motion.
class ZodiacWheel extends StatefulWidget {
  final double size;
  final Color color;
  final Duration period;

  const ZodiacWheel({
    super.key,
    this.size = 96,
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
    // Resolve the glyph text style ONCE — GoogleFonts.notoSansSymbols2
    // gives us a TextStyle wired to the proper fontFamily so Android's
    // text engine renders these as monochrome glyphs instead of falling
    // back to the colored emoji font.
    final glyphStyle = GoogleFonts.notoSansSymbols2(
      color: widget.color.withOpacity(0.92),
      fontSize: widget.size * 0.16, // ~15px for a 96px wheel
      fontWeight: FontWeight.w500,
      height: 1.0,
    );

    return RotationTransition(
      turns: _ctrl,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _ZodiacWheelPainter(
            color: widget.color,
            glyphStyle: glyphStyle,
          ),
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
  final TextStyle glyphStyle;

  _ZodiacWheelPainter({required this.color, required this.glyphStyle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2 - 1;
    final innerR = outerR - 22;

    final ringStroke = Paint()
      ..color = color.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final innerRingStroke = Paint()
      ..color = color.withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    final spokeStroke = Paint()
      ..color = color.withOpacity(0.28)
      ..strokeWidth = 0.6;
    final innerDecorPaint = Paint()
      ..color = color.withOpacity(0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final centerDotFill = Paint()..color = color.withOpacity(0.85);

    // Outer + inner ring
    canvas.drawCircle(center, outerR, ringStroke);
    canvas.drawCircle(center, innerR, innerRingStroke);

    // 12 dividers between sectors
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
      canvas.drawLine(p1, p2, spokeStroke);
    }

    // 12 zodiac glyphs — monochrome via Noto Sans Symbols 2
    final symbolRadius = (innerR + outerR) / 2;
    for (int i = 0; i < 12; i++) {
      final a = ((i + 0.5) / 12) * 2 * math.pi - math.pi / 2;
      final x = center.dx + math.cos(a) * symbolRadius;
      final y = center.dy + math.sin(a) * symbolRadius;

      final tp = TextPainter(
        text: TextSpan(text: _symbols[i], style: glyphStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    // Center decoration — 6-pointed star (kept; user approved)
    final starR = innerR - 6;
    _drawHexStar(canvas, center, starR, innerDecorPaint);
    canvas.drawCircle(center, 1.6, centerDotFill);
  }

  void _drawHexStar(Canvas canvas, Offset c, double r, Paint p) {
    final up = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r * 0.866, c.dy + r * 0.5)
      ..lineTo(c.dx - r * 0.866, c.dy + r * 0.5)
      ..close();
    final down = Path()
      ..moveTo(c.dx, c.dy + r)
      ..lineTo(c.dx + r * 0.866, c.dy - r * 0.5)
      ..lineTo(c.dx - r * 0.866, c.dy - r * 0.5)
      ..close();
    canvas.drawPath(up, p);
    canvas.drawPath(down, p);
  }

  @override
  bool shouldRepaint(_ZodiacWheelPainter old) =>
      old.color != color || old.glyphStyle != glyphStyle;
}
