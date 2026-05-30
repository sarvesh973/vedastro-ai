import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Slowly rotating wheel showing all 12 zodiac signs as monochrome
/// glyphs around a double ring, with a 6-pointed star (shatkona /
/// hexagram) in the center.
///
/// IMPLEMENTATION NOTE: zodiac glyphs are drawn from hand-built Path
/// shapes via CustomPainter, NOT from text/Unicode/icon fonts:
///   * Unicode zodiac codepoints ♈♉♊… are routed to the emoji font
///     on Android, even with U+FE0E and an explicit fontFamily — so
///     the wheel ended up rendering as colourful emoji, not the
///     monochrome blue we want.
///   * FontAwesome's zodiac glyphs are Pro-only (not in the Free
///     font_awesome_flutter package), and the package itself fights
///     newer Flutter SDKs by extending `IconData` (now sealed).
/// CustomPainter paths solve both problems at once — every stroke is
/// painted in `widget.color`, no font fallback can hijack it, no
/// external asset/font is required, and the build doesn't break on
/// every Flutter bump.
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
    final wheelColor = widget.color;
    final glyphColor = widget.color.withOpacity(0.92);
    final glyphSize = widget.size * 0.13; // ~12.5px @ 96px wheel

    // Geometry — same outer/inner ring layout as before so the
    // decorative rings + hexagram still anchor the design.
    final outerR = widget.size / 2 - 1;
    final innerR = outerR - 22;
    final symbolRadius = (innerR + outerR) / 2;

    return RotationTransition(
      turns: _ctrl,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Painted background — rings, spokes, hexagram, center dot.
            CustomPaint(
              size: Size.square(widget.size),
              painter: _WheelBackgroundPainter(color: wheelColor),
            ),
            // 12 zodiac glyphs positioned around the ring's mid-radius.
            for (int i = 0; i < 12; i++)
              _positionedGlyph(
                index: i,
                centerOffset: Offset(widget.size / 2, widget.size / 2),
                radius: symbolRadius,
                glyphSize: glyphSize,
                color: glyphColor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _positionedGlyph({
    required int index,
    required Offset centerOffset,
    required double radius,
    required double glyphSize,
    required Color color,
  }) {
    // Place each glyph at the midpoint of its sector arc, on the
    // ring mid-radius. Sectors start at the top (-pi/2) and go
    // clockwise. The half-offset (+0.5) puts the glyph BETWEEN
    // dividers, not on top of them.
    final angle = ((index + 0.5) / 12) * 2 * math.pi - math.pi / 2;
    final x = centerOffset.dx + math.cos(angle) * radius;
    final y = centerOffset.dy + math.sin(angle) * radius;
    return Positioned(
      left: x - glyphSize / 2 - 2,
      top: y - glyphSize / 2 - 2,
      width: glyphSize + 4,
      height: glyphSize + 4,
      child: CustomPaint(
        painter: _ZodiacGlyphPainter(signIndex: index, color: color),
      ),
    );
  }
}

class _WheelBackgroundPainter extends CustomPainter {
  final Color color;
  _WheelBackgroundPainter({required this.color});

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

    canvas.drawCircle(center, outerR, ringStroke);
    canvas.drawCircle(center, innerR, innerRingStroke);

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

    // Hexagram (Shatkona / Star of David) — kept; user approved.
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
  bool shouldRepaint(_WheelBackgroundPainter old) => old.color != color;
}

/// Draws one of the 12 zodiac glyphs as monochrome strokes inside the
/// painter's bounds. Each glyph is normalised to a 20×20 design grid
/// then scaled to the actual paint area so they render crisply at any
/// size. Strokes use round caps/joins so the small glyphs read cleanly.
class _ZodiacGlyphPainter extends CustomPainter {
  final int signIndex;
  final Color color;

  _ZodiacGlyphPainter({required this.signIndex, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // 20×20 design grid → scale into actual paint size.
    final scale = size.shortestSide / 20.0;
    canvas.save();
    canvas.translate((size.width - 20 * scale) / 2,
        (size.height - 20 * scale) / 2);
    canvas.scale(scale);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (signIndex) {
      case 0:
        _aries(canvas, paint);
        break;
      case 1:
        _taurus(canvas, paint);
        break;
      case 2:
        _gemini(canvas, paint);
        break;
      case 3:
        _cancer(canvas, paint);
        break;
      case 4:
        _leo(canvas, paint);
        break;
      case 5:
        _virgo(canvas, paint);
        break;
      case 6:
        _libra(canvas, paint);
        break;
      case 7:
        _scorpio(canvas, paint);
        break;
      case 8:
        _sagittarius(canvas, paint);
        break;
      case 9:
        _capricorn(canvas, paint);
        break;
      case 10:
        _aquarius(canvas, paint);
        break;
      case 11:
        _pisces(canvas, paint);
        break;
    }

    canvas.restore();
  }

  // ─── Glyph paths (20×20 design grid) ─────────────────────────
  //
  // Each glyph is a simplified, recognisable stroke version of the
  // traditional zodiac symbol. Designed at 20×20 with strokes ~1.6
  // so they read clearly at the 12-13px size used on the wheel.

  void _aries(Canvas c, Paint p) {
    // Ram horns: two outward-curling arcs meeting at the top.
    final path = Path()
      ..moveTo(10, 18)
      ..lineTo(10, 8)
      ..moveTo(10, 8)
      ..cubicTo(8, 4, 4, 4, 4, 8)
      ..moveTo(10, 8)
      ..cubicTo(12, 4, 16, 4, 16, 8);
    c.drawPath(path, p);
  }

  void _taurus(Canvas c, Paint p) {
    // Bull head: full circle with two upward horns.
    c.drawCircle(const Offset(10, 13), 4, p);
    final horns = Path()
      ..moveTo(6, 10)
      ..cubicTo(4, 6, 8, 4, 10, 6)
      ..cubicTo(12, 4, 16, 6, 14, 10);
    c.drawPath(horns, p);
  }

  void _gemini(Canvas c, Paint p) {
    // Roman numeral II with top + bottom caps (joined twins).
    final path = Path()
      ..moveTo(7, 4)
      ..lineTo(7, 16)
      ..moveTo(13, 4)
      ..lineTo(13, 16)
      ..moveTo(5, 4)
      ..lineTo(15, 4)
      ..moveTo(5, 16)
      ..lineTo(15, 16);
    c.drawPath(path, p);
  }

  void _cancer(Canvas c, Paint p) {
    // Two opposing curls (yin-yang of crab claws).
    final path = Path()
      ..moveTo(15, 8)
      ..cubicTo(11, 6, 5, 8, 5, 10)
      ..moveTo(5, 12)
      ..cubicTo(9, 14, 15, 12, 15, 10);
    c.drawPath(path, p);
    c.drawCircle(const Offset(13, 8), 1.4, Paint()..color = color);
    c.drawCircle(const Offset(7, 12), 1.4, Paint()..color = color);
  }

  void _leo(Canvas c, Paint p) {
    // Lion's tail: small circle, then a sweeping curl up + right.
    c.drawCircle(const Offset(7, 9), 3, p);
    final tail = Path()
      ..moveTo(9.5, 11)
      ..cubicTo(12, 14, 14, 18, 17, 16)
      ..cubicTo(18, 15, 17, 13, 15, 14);
    c.drawPath(tail, p);
  }

  void _virgo(Canvas c, Paint p) {
    // M-shape with a small inner loop on the right (the maiden).
    final path = Path()
      ..moveTo(3, 16)
      ..lineTo(3, 5)
      ..lineTo(8, 14)
      ..lineTo(13, 5)
      ..lineTo(13, 16)
      ..moveTo(13, 16)
      ..cubicTo(17, 16, 17, 11, 13, 11);
    c.drawPath(path, p);
  }

  void _libra(Canvas c, Paint p) {
    // Scales: base line + dome with a small flat segment on top.
    final path = Path()
      ..moveTo(3, 16)
      ..lineTo(17, 16)
      ..moveTo(4, 12)
      ..cubicTo(4, 6, 16, 6, 16, 12)
      ..moveTo(8, 11)
      ..lineTo(12, 11);
    c.drawPath(path, p);
  }

  void _scorpio(Canvas c, Paint p) {
    // M-shape with an arrow stinger tail going up-right.
    final path = Path()
      ..moveTo(3, 14)
      ..lineTo(3, 6)
      ..lineTo(7, 14)
      ..lineTo(11, 6)
      ..lineTo(11, 14)
      ..moveTo(11, 14)
      ..lineTo(15, 14)
      ..lineTo(15, 8)
      ..moveTo(13, 10)
      ..lineTo(15, 8)
      ..lineTo(17, 10);
    c.drawPath(path, p);
  }

  void _sagittarius(Canvas c, Paint p) {
    // Diagonal arrow with crossbar on the shaft.
    final path = Path()
      ..moveTo(4, 16)
      ..lineTo(16, 4)
      ..moveTo(10, 4)
      ..lineTo(16, 4)
      ..lineTo(16, 10)
      ..moveTo(7, 9)
      ..lineTo(11, 13);
    c.drawPath(path, p);
  }

  void _capricorn(Canvas c, Paint p) {
    // Stylised goat-fish: V into a curl at the bottom.
    final path = Path()
      ..moveTo(3, 5)
      ..lineTo(7, 14)
      ..lineTo(11, 5)
      ..lineTo(13, 14)
      ..cubicTo(13, 17, 17, 17, 17, 14)
      ..cubicTo(17, 12, 15, 12, 15, 14);
    c.drawPath(path, p);
  }

  void _aquarius(Canvas c, Paint p) {
    // Two parallel zigzags (water waves).
    final w1 = Path()
      ..moveTo(3, 8)
      ..lineTo(7, 6)
      ..lineTo(10, 8)
      ..lineTo(13, 6)
      ..lineTo(17, 8);
    final w2 = Path()
      ..moveTo(3, 13)
      ..lineTo(7, 11)
      ..lineTo(10, 13)
      ..lineTo(13, 11)
      ..lineTo(17, 13);
    c.drawPath(w1, p);
    c.drawPath(w2, p);
  }

  void _pisces(Canvas c, Paint p) {
    // Two arcs (fish) tethered by a horizontal line.
    final path = Path()
      ..moveTo(5, 4)
      ..cubicTo(2, 10, 2, 10, 5, 16)
      ..moveTo(15, 4)
      ..cubicTo(18, 10, 18, 10, 15, 16)
      ..moveTo(4, 10)
      ..lineTo(16, 10);
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_ZodiacGlyphPainter old) =>
      old.signIndex != signIndex || old.color != color;
}
