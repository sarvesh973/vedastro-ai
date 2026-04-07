import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PalmGuideOverlay extends StatelessWidget {
  const PalmGuideOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 320,
      decoration: BoxDecoration(
        border: Border.all(
          color: AppColors.purpleAccent.withOpacity(0.5),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Palm outline hint
          Icon(
            Icons.back_hand_outlined,
            size: 120,
            color: AppColors.purpleAccent.withOpacity(0.15),
          ),
          // Corner markers
          ..._buildCornerMarkers(),
        ],
      ),
    );
  }

  List<Widget> _buildCornerMarkers() {
    return [
      Positioned(top: 0, left: 0, child: _corner(true, true)),
      Positioned(top: 0, right: 0, child: _corner(true, false)),
      Positioned(bottom: 0, left: 0, child: _corner(false, true)),
      Positioned(bottom: 0, right: 0, child: _corner(false, false)),
    ];
  }

  Widget _corner(bool isTop, bool isLeft) {
    return SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(
        painter: _CornerPainter(
          isTop: isTop,
          isLeft: isLeft,
          color: AppColors.purpleAccent,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool isTop;
  final bool isLeft;
  final Color color;

  _CornerPainter({
    required this.isTop,
    required this.isLeft,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    if (isTop && isLeft) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (isTop && !isLeft) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!isTop && isLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
