import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Slowly rotating wheel showing all 12 zodiac signs as monochrome
/// glyphs around a double ring, with a 6-pointed star (shatkona /
/// hexagram) in the center.
///
/// IMPLEMENTATION NOTE: We use FontAwesome icons (not Unicode zodiac
/// chars ♈♉♊…) because the Unicode zodiac codepoints render as
/// colored EMOJI on Android — the OS overrides any text font we
/// specify, even with the U+FE0E text-variation selector. FontAwesome
/// icons live in the Unicode Private Use Area (0xf640 etc), which
/// can't be routed to emoji rendering, so they always render in the
/// colour we ask for.
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

  static const _icons = <IconData>[
    FontAwesomeIcons.aries,
    FontAwesomeIcons.taurus,
    FontAwesomeIcons.gemini,
    FontAwesomeIcons.cancer,
    FontAwesomeIcons.leo,
    FontAwesomeIcons.virgo,
    FontAwesomeIcons.libra,
    FontAwesomeIcons.scorpio,
    FontAwesomeIcons.sagittarius,
    FontAwesomeIcons.capricorn,
    FontAwesomeIcons.aquarius,
    FontAwesomeIcons.pisces,
  ];

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
            // All monochrome; no zodiac chars in this painter.
            CustomPaint(
              size: Size.square(widget.size),
              painter: _WheelBackgroundPainter(color: wheelColor),
            ),
            // 12 zodiac icons positioned around the ring's mid-radius.
            for (int i = 0; i < 12; i++)
              _positionedIcon(
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

  Widget _positionedIcon({
    required int index,
    required Offset centerOffset,
    required double radius,
    required double glyphSize,
    required Color color,
  }) {
    // Place each icon at the midpoint of its sector arc, on the
    // ring mid-radius. Sectors start at the top (-pi/2) and go
    // clockwise. The half-offset (+0.5) puts the icon BETWEEN
    // dividers, not on top of them.
    final angle = ((index + 0.5) / 12) * 2 * math.pi - math.pi / 2;
    final x = centerOffset.dx + math.cos(angle) * radius;
    final y = centerOffset.dy + math.sin(angle) * radius;
    return Positioned(
      left: x - glyphSize / 2 - 2,
      top: y - glyphSize / 2 - 2,
      width: glyphSize + 4,
      height: glyphSize + 4,
      child: Center(
        child: FaIcon(
          _icons[index],
          color: color,
          size: glyphSize,
        ),
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
