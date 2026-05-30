import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Slowly rotating wheel showing all 12 zodiac signs drawn as monochrome
/// paths. Unicode zodiac glyphs (♈♉♊…) render as colored EMOJI on
/// Android — we draw them ourselves so the colour is consistent and
/// the size is fully controlled.
///
/// Center has a stylized 6-pointed star (shatkona / hexagram) plus a
/// dot, filling the otherwise-empty inner space without competing
/// with the surrounding glyphs.
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
  final Color color;

  _ZodiacWheelPainter({required this.color});

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
    final glyphStroke = Paint()
      ..color = color.withOpacity(0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final glyphFill = Paint()
      ..color = color.withOpacity(0.92);
    final innerDecorPaint = Paint()
      ..color = color.withOpacity(0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Outer + inner ring
    canvas.drawCircle(center, outerR, ringStroke);
    canvas.drawCircle(center, innerR, innerRingStroke);

    // 12 short dividers between sectors (live just outside inner ring)
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

    // 12 zodiac glyphs in the ring's mid-radius. Each sized to roughly
    // the available cell width.
    final symbolRadius = (innerR + outerR) / 2;
    final glyphSize = 10.5; // half-extent — full glyph fits in ~21px box
    for (int i = 0; i < 12; i++) {
      final a = ((i + 0.5) / 12) * 2 * math.pi - math.pi / 2;
      final x = center.dx + math.cos(a) * symbolRadius;
      final y = center.dy + math.sin(a) * symbolRadius;
      _drawGlyph(canvas, i, Offset(x, y), glyphSize, glyphStroke, glyphFill);
    }

    // Center decoration — 6-pointed star (two overlapping triangles).
    final starR = innerR - 6;
    _drawHexStar(canvas, center, starR, innerDecorPaint);
    // Small dot at the exact center
    canvas.drawCircle(center, 1.6, glyphFill);
  }

  void _drawHexStar(Canvas canvas, Offset c, double r, Paint p) {
    // Upward triangle
    final up = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r * 0.866, c.dy + r * 0.5)
      ..lineTo(c.dx - r * 0.866, c.dy + r * 0.5)
      ..close();
    // Downward triangle
    final down = Path()
      ..moveTo(c.dx, c.dy + r)
      ..lineTo(c.dx + r * 0.866, c.dy - r * 0.5)
      ..lineTo(c.dx - r * 0.866, c.dy - r * 0.5)
      ..close();
    canvas.drawPath(up, p);
    canvas.drawPath(down, p);
  }

  // ──────────── glyph paths ────────────
  // Each glyph is drawn relative to (x,y) using `s` as a half-extent.
  // Stylized minimal versions of the classical zodiac symbols.

  void _drawGlyph(
    Canvas canvas,
    int signIndex,
    Offset o,
    double s,
    Paint stroke,
    Paint fill,
  ) {
    switch (signIndex) {
      case 0:  return _aries(canvas, o, s, stroke);
      case 1:  return _taurus(canvas, o, s, stroke);
      case 2:  return _gemini(canvas, o, s, stroke);
      case 3:  return _cancer(canvas, o, s, stroke, fill);
      case 4:  return _leo(canvas, o, s, stroke);
      case 5:  return _virgo(canvas, o, s, stroke);
      case 6:  return _libra(canvas, o, s, stroke);
      case 7:  return _scorpio(canvas, o, s, stroke);
      case 8:  return _sagittarius(canvas, o, s, stroke);
      case 9:  return _capricorn(canvas, o, s, stroke);
      case 10: return _aquarius(canvas, o, s, stroke);
      case 11: return _pisces(canvas, o, s, stroke);
    }
  }

  // Aries (ram's horns) — two curves meeting at top center
  void _aries(Canvas c, Offset o, double s, Paint p) {
    final path = Path()
      ..moveTo(o.dx - s, o.dy + s)
      ..quadraticBezierTo(o.dx - s, o.dy - s * 0.4, o.dx, o.dy + s * 0.1)
      ..quadraticBezierTo(o.dx + s, o.dy - s * 0.4, o.dx + s, o.dy + s);
    c.drawPath(path, p);
  }

  // Taurus (bull) — circle with two curved horns above
  void _taurus(Canvas c, Offset o, double s, Paint p) {
    c.drawCircle(Offset(o.dx, o.dy + s * 0.35), s * 0.55, p);
    final horns = Path()
      ..moveTo(o.dx - s * 0.95, o.dy - s * 0.3)
      ..quadraticBezierTo(o.dx - s * 0.55, o.dy - s, o.dx, o.dy - s * 0.3)
      ..quadraticBezierTo(o.dx + s * 0.55, o.dy - s, o.dx + s * 0.95, o.dy - s * 0.3);
    c.drawPath(horns, p);
  }

  // Gemini (twins) — two vertical bars with caps top and bottom
  void _gemini(Canvas c, Offset o, double s, Paint p) {
    c.drawLine(Offset(o.dx - s * 0.5, o.dy - s), Offset(o.dx - s * 0.5, o.dy + s), p);
    c.drawLine(Offset(o.dx + s * 0.5, o.dy - s), Offset(o.dx + s * 0.5, o.dy + s), p);
    c.drawLine(Offset(o.dx - s * 0.85, o.dy - s), Offset(o.dx + s * 0.85, o.dy - s), p);
    c.drawLine(Offset(o.dx - s * 0.85, o.dy + s), Offset(o.dx + s * 0.85, o.dy + s), p);
  }

  // Cancer (crab) — two stylized circles with opposing tails (69 motif)
  void _cancer(Canvas c, Offset o, double s, Paint stroke, Paint fill) {
    final left = Path()
      ..moveTo(o.dx + s, o.dy - s * 0.5)
      ..quadraticBezierTo(o.dx, o.dy - s * 0.5, o.dx - s * 0.6, o.dy - s * 0.1)
      ..quadraticBezierTo(o.dx - s, o.dy + s * 0.1, o.dx - s * 0.4, o.dy + s * 0.1);
    final right = Path()
      ..moveTo(o.dx - s, o.dy + s * 0.5)
      ..quadraticBezierTo(o.dx, o.dy + s * 0.5, o.dx + s * 0.6, o.dy + s * 0.1)
      ..quadraticBezierTo(o.dx + s, o.dy - s * 0.1, o.dx + s * 0.4, o.dy - s * 0.1);
    c.drawPath(left, stroke);
    c.drawPath(right, stroke);
    c.drawCircle(Offset(o.dx - s * 0.4, o.dy + s * 0.2), 1.4, fill);
    c.drawCircle(Offset(o.dx + s * 0.4, o.dy - s * 0.2), 1.4, fill);
  }

  // Leo (lion) — stylized "Ω" with curl tail
  void _leo(Canvas c, Offset o, double s, Paint p) {
    final path = Path()
      ..addOval(Rect.fromCircle(center: Offset(o.dx - s * 0.2, o.dy - s * 0.3), radius: s * 0.5))
      ..moveTo(o.dx - s * 0.05, o.dy + s * 0.2)
      ..quadraticBezierTo(o.dx + s * 0.7, o.dy + s * 0.4, o.dx + s * 0.4, o.dy - s * 0.3);
    c.drawPath(path, p);
  }

  // Virgo (virgin) — "M" with curl off right leg
  void _virgo(Canvas c, Offset o, double s, Paint p) {
    final path = Path()
      ..moveTo(o.dx - s, o.dy + s)
      ..lineTo(o.dx - s, o.dy - s * 0.6)
      ..lineTo(o.dx - s * 0.3, o.dy + s)
      ..lineTo(o.dx - s * 0.3, o.dy - s * 0.6)
      ..lineTo(o.dx + s * 0.4, o.dy + s)
      ..lineTo(o.dx + s * 0.4, o.dy - s * 0.6)
      ..quadraticBezierTo(o.dx + s * 0.4, o.dy + s * 0.6, o.dx + s, o.dy);
    c.drawPath(path, p);
  }

  // Libra (scales) — horizontal line with arch on top
  void _libra(Canvas c, Offset o, double s, Paint p) {
    c.drawLine(Offset(o.dx - s, o.dy + s * 0.6), Offset(o.dx + s, o.dy + s * 0.6), p);
    c.drawLine(Offset(o.dx - s, o.dy + s * 0.1), Offset(o.dx - s * 0.35, o.dy + s * 0.1), p);
    c.drawLine(Offset(o.dx + s, o.dy + s * 0.1), Offset(o.dx + s * 0.35, o.dy + s * 0.1), p);
    final arch = Path()
      ..moveTo(o.dx - s * 0.35, o.dy + s * 0.1)
      ..arcToPoint(
        Offset(o.dx + s * 0.35, o.dy + s * 0.1),
        radius: Radius.circular(s * 0.5),
        clockwise: false,
      );
    c.drawPath(arch, p);
  }

  // Scorpio (scorpion) — "M" with an arrow flick at the right
  void _scorpio(Canvas c, Offset o, double s, Paint p) {
    final path = Path()
      ..moveTo(o.dx - s, o.dy + s)
      ..lineTo(o.dx - s, o.dy - s * 0.6)
      ..lineTo(o.dx - s * 0.3, o.dy + s)
      ..lineTo(o.dx - s * 0.3, o.dy - s * 0.6)
      ..lineTo(o.dx + s * 0.4, o.dy + s)
      ..lineTo(o.dx + s * 0.4, o.dy - s * 0.4)
      ..lineTo(o.dx + s, o.dy);
    c.drawPath(path, p);
    // arrowhead
    final arrow = Path()
      ..moveTo(o.dx + s, o.dy)
      ..lineTo(o.dx + s * 0.7, o.dy - s * 0.05)
      ..moveTo(o.dx + s, o.dy)
      ..lineTo(o.dx + s * 0.85, o.dy + s * 0.3);
    c.drawPath(arrow, p);
  }

  // Sagittarius (archer) — arrow with crossbar
  void _sagittarius(Canvas c, Offset o, double s, Paint p) {
    c.drawLine(Offset(o.dx - s * 0.9, o.dy + s * 0.9), Offset(o.dx + s * 0.7, o.dy - s * 0.7), p);
    // arrowhead
    final arrow = Path()
      ..moveTo(o.dx + s * 0.7, o.dy - s * 0.7)
      ..lineTo(o.dx + s * 0.2, o.dy - s * 0.6)
      ..moveTo(o.dx + s * 0.7, o.dy - s * 0.7)
      ..lineTo(o.dx + s * 0.6, o.dy - s * 0.2);
    c.drawPath(arrow, p);
    // crossbar
    c.drawLine(Offset(o.dx - s * 0.4, o.dy + s * 0.1), Offset(o.dx + s * 0.1, o.dy + s * 0.6), p);
  }

  // Capricorn (goat) — V with curl
  void _capricorn(Canvas c, Offset o, double s, Paint p) {
    final path = Path()
      ..moveTo(o.dx - s, o.dy - s * 0.6)
      ..lineTo(o.dx - s * 0.2, o.dy + s * 0.8)
      ..lineTo(o.dx + s * 0.3, o.dy - s * 0.4)
      ..lineTo(o.dx + s * 0.55, o.dy + s * 0.4)
      ..addOval(Rect.fromCircle(center: Offset(o.dx + s * 0.3, o.dy + s * 0.55), radius: s * 0.35));
    c.drawPath(path, p);
  }

  // Aquarius (water bearer) — two parallel zigzag waves
  void _aquarius(Canvas c, Offset o, double s, Paint p) {
    void wave(double yOffset) {
      final path = Path()
        ..moveTo(o.dx - s, o.dy + yOffset)
        ..lineTo(o.dx - s * 0.5, o.dy + yOffset - s * 0.35)
        ..lineTo(o.dx, o.dy + yOffset)
        ..lineTo(o.dx + s * 0.5, o.dy + yOffset - s * 0.35)
        ..lineTo(o.dx + s, o.dy + yOffset);
      c.drawPath(path, p);
    }
    wave(-s * 0.15);
    wave(s * 0.55);
  }

  // Pisces (fish) — two arcs back-to-back with a horizontal line through
  void _pisces(Canvas c, Offset o, double s, Paint p) {
    final left = Path()
      ..moveTo(o.dx - s, o.dy - s)
      ..quadraticBezierTo(o.dx - s * 0.1, o.dy, o.dx - s, o.dy + s);
    final right = Path()
      ..moveTo(o.dx + s, o.dy - s)
      ..quadraticBezierTo(o.dx + s * 0.1, o.dy, o.dx + s, o.dy + s);
    c.drawPath(left, p);
    c.drawPath(right, p);
    c.drawLine(Offset(o.dx - s * 0.85, o.dy), Offset(o.dx + s * 0.85, o.dy), p);
  }

  @override
  bool shouldRepaint(_ZodiacWheelPainter old) => old.color != color;
}
