import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// Background overlay that flashes a shooting star across the screen
/// every 12 seconds. Lightweight: a single AnimationController + one
/// CustomPaint per cycle. Stack this on top of the home screen's
/// StarfieldBackground inside a Positioned.fill + IgnorePointer.
class ShootingStarOverlay extends StatefulWidget {
  /// How often a new shooting star spawns. Defaults to every 12s.
  final Duration interval;

  /// How long each star takes to traverse the screen.
  final Duration duration;

  const ShootingStarOverlay({
    super.key,
    this.interval = const Duration(seconds: 12),
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  State<ShootingStarOverlay> createState() => _ShootingStarOverlayState();
}

class _ShootingStarOverlayState extends State<ShootingStarOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _scheduler;
  final _random = Random();

  // Per-flight randomness — start point, angle, length. Recomputed each cycle.
  double _startX = 0.0;
  double _startY = 0.0;
  double _angleRad = 0.0;
  double _travel = 0.0; // distance traversed (relative to screen diagonal)

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.duration);
    // First star plays after 2s so the page has time to settle, then
    // every interval after that.
    _scheduler = Timer(const Duration(seconds: 2), _fireOne);
  }

  void _fireOne() {
    if (!mounted) return;
    _randomizeFlight();
    _controller.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      _scheduler = Timer(widget.interval, _fireOne);
    });
  }

  void _randomizeFlight() {
    // Stars come from the upper portion of the screen (more believable).
    _startX = _random.nextDouble() * 0.9 + 0.05; // 5–95% across
    _startY = _random.nextDouble() * 0.35;       // top 35%
    // Angle: 25–55° below horizontal, biased to whichever side has more room.
    final goingLeft = _startX > 0.5;
    final base = goingLeft ? pi - (pi / 6) : pi / 6; // ≈ 30° down
    _angleRad = base + (_random.nextDouble() * pi / 9 - pi / 18);
    // Travel ~70% of diagonal so the star clearly exits the visible area.
    _travel = 0.7;
  }

  @override
  void dispose() {
    _scheduler?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // When idle (between cycles) skip painting entirely — saves frames.
        if (!_controller.isAnimating && _controller.value == 0) {
          return const SizedBox.expand();
        }
        return CustomPaint(
          size: Size.infinite,
          painter: _ShootingStarPainter(
            progress: _controller.value,
            startX: _startX,
            startY: _startY,
            angleRad: _angleRad,
            travel: _travel,
          ),
        );
      },
    );
  }
}

class _ShootingStarPainter extends CustomPainter {
  final double progress;     // 0 → 1 over one flight
  final double startX;       // 0–1 of width
  final double startY;       // 0–1 of height
  final double angleRad;     // direction of travel
  final double travel;       // fraction of diagonal traversed end-to-end

  _ShootingStarPainter({
    required this.progress,
    required this.startX,
    required this.startY,
    required this.angleRad,
    required this.travel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    final diag = sqrt(size.width * size.width + size.height * size.height);
    final reach = diag * travel;

    final sx = startX * size.width;
    final sy = startY * size.height;

    // Head position eased so the star feels weighty
    final eased = Curves.easeInOutCubic.transform(progress);
    final dx = cos(angleRad) * reach * eased;
    final dy = sin(angleRad) * reach * eased;
    final headX = sx + dx;
    final headY = sy + dy;

    // Tail length tapers up at start and down at end so it fades in/out.
    // Bell curve peaking near 0.45 of progress.
    final lenFactor = sin(progress * pi); // 0 → 1 → 0
    final tailLength = 110 * lenFactor;

    final tailEndX = headX - cos(angleRad) * tailLength;
    final tailEndY = headY - sin(angleRad) * tailLength;

    // Tail — gradient stroke from transparent (back) to bright (head)
    final tailPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withOpacity(0),
          Colors.white.withOpacity(0.9 * lenFactor),
        ],
      ).createShader(
        Rect.fromPoints(
          Offset(tailEndX, tailEndY),
          Offset(headX, headY),
        ),
      )
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(tailEndX, tailEndY),
      Offset(headX, headY),
      tailPaint,
    );

    // Soft glow halo around the head
    final glowPaint = Paint()
      ..color = Colors.white.withOpacity(0.25 * lenFactor)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(headX, headY), 3.5, glowPaint);

    // Bright head
    final headPaint = Paint()
      ..color = Colors.white.withOpacity(0.95 * lenFactor)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(headX, headY), 1.6, headPaint);
  }

  @override
  bool shouldRepaint(covariant _ShootingStarPainter old) =>
      old.progress != progress ||
      old.startX != startX ||
      old.startY != startY;
}
