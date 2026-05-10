import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Screen-wide cosmic background.
///
/// Wraps page content with the gradient + twinkling stars used on Home,
/// but with an `intensity` knob so non-Home screens can carry the brand
/// without fighting their own content. Each screen gets a different
/// star arrangement via the `seed` parameter — same widget, just a
/// positional reseed so users feel "this screen has its own constellation."
///
/// Usage:
/// ```dart
/// CosmicBackground(
///   intensity: CosmicIntensity.subtle,
///   seed: 'kundli',
///   child: SafeArea(child: ...),
/// )
/// ```
enum CosmicIntensity { hero, subtle, whisper }

class CosmicBackground extends StatefulWidget {
  final Widget child;
  final CosmicIntensity intensity;
  final String? seed;

  const CosmicBackground({
    super.key,
    required this.child,
    this.intensity = CosmicIntensity.subtle,
    this.seed,
  });

  @override
  State<CosmicBackground> createState() => _CosmicBackgroundState();
}

class _CosmicBackgroundState extends State<CosmicBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
    _stars = _generateStars();
  }

  @override
  void didUpdateWidget(covariant CosmicBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed ||
        oldWidget.intensity != widget.intensity) {
      _stars = _generateStars();
    }
  }

  List<_Star> _generateStars() {
    final count = switch (widget.intensity) {
      CosmicIntensity.hero => 60,
      CosmicIntensity.subtle => 40,
      CosmicIntensity.whisper => 22,
    };
    final seedNum = widget.seed?.hashCode ?? 42;
    final random = Random(seedNum);
    return List.generate(count, (_) {
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _opacityScale {
    switch (widget.intensity) {
      case CosmicIntensity.hero:
        return 0.6;
      case CosmicIntensity.subtle:
        return 0.35;
      case CosmicIntensity.whisper:
        return 0.18;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background gradient — same vibe as the Home starfield, slightly
        // less saturated for non-hero contexts so foreground content reads.
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.3),
              radius: 1.2,
              colors: [
                widget.intensity == CosmicIntensity.hero
                    ? const Color(0xFF1A1030)
                    : const Color(0xFF12081E),
                AppColors.background,
              ],
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _StarPainter(
                progress: _controller.value,
                stars: _stars,
                opacityScale: _opacityScale,
              ),
            );
          },
        ),
        widget.child,
      ],
    );
  }
}

class _StarPainter extends CustomPainter {
  final double progress;
  final List<_Star> stars;
  final double opacityScale;

  _StarPainter({
    required this.progress,
    required this.stars,
    required this.opacityScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final star in stars) {
      final twinkle = 0.3 +
          0.7 *
              ((sin(progress * 2 * pi * star.twinkleSpeed +
                          star.twinkleOffset) +
                      1) /
                  2);
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: twinkle * opacityScale)
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
