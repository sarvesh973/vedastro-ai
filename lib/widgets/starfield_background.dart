import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StarfieldBackground extends StatefulWidget {
  final Widget child;

  const StarfieldBackground({super.key, required this.child});

  @override
  State<StarfieldBackground> createState() => _StarfieldBackgroundState();
}

class _StarfieldBackgroundState extends State<StarfieldBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background gradient
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.3),
              radius: 1.2,
              colors: [
                Color(0xFF1A1030),
                AppColors.background,
              ],
            ),
          ),
        ),

        // Animated stars
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _StarPainter(_controller.value),
            );
          },
        ),

        // Content
        widget.child,
      ],
    );
  }
}

class _StarPainter extends CustomPainter {
  final double progress;
  static final List<_Star> _stars = _generateStars(60);

  _StarPainter(this.progress);

  static List<_Star> _generateStars(int count) {
    final random = Random(42); // Fixed seed for consistent stars
    return List.generate(count, (i) {
      return _Star(
        x: random.nextDouble(),
        y: random.nextDouble(),
        size: 0.5 + random.nextDouble() * 1.5,
        twinkleSpeed: 0.5 + random.nextDouble() * 2.0,
        twinkleOffset: random.nextDouble() * 2 * pi,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final star in _stars) {
      final opacity =
          0.3 + 0.7 * ((sin(progress * 2 * pi * star.twinkleSpeed + star.twinkleOffset) + 1) / 2);

      final paint = Paint()
        ..color = Colors.white.withOpacity(opacity * 0.6)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => true;
}

class _Star {
  final double x;
  final double y;
  final double size;
  final double twinkleSpeed;
  final double twinkleOffset;

  _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.twinkleSpeed,
    required this.twinkleOffset,
  });
}
