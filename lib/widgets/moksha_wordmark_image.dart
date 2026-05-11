import 'package:flutter/material.dart';

/// Renders the bespoke moksha wordmark PNG with two refinements:
///
///   1. Colour-matrix invert. The asset is dark navy on transparent —
///      invisible on the dark cosmic background. We invert at runtime
///      so dark navy becomes cream and the gold dots flip to a cool
///      blue that reads as deliberately cosmic. Avoids needing a
///      separate light-on-dark variant of the PNG.
///
///   2. Visual crop. The exported PNG ships with a generous transparent
///      margin around the wordmark, so it floats with too much air
///      around it. We wrap in ClipRect + Align(heightFactor / widthFactor)
///      to render only the centred content area without modifying the
///      asset itself. Tune the factors here if a future re-export
///      changes the bbox.
///
/// Used on Home (under the AI logo) and on the post-splash transition
/// to keep the brand consistent.
class _MokshaWordmarkImage extends StatelessWidget {
  final double widthFactor;
  final double crop;

  const _MokshaWordmarkImage({
    this.widthFactor = 0.78,
    this.crop = 0.45,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final wordmarkWidth = (screenWidth * widthFactor).clamp(240.0, 460.0);

    return ClipRect(
      child: Align(
        alignment: Alignment.center,
        heightFactor: crop,
        widthFactor: 0.92,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            -1, 0, 0, 0, 255, //
            0, -1, 0, 0, 255, //
            0, 0, -1, 0, 255, //
            0, 0, 0, 1, 0,
          ]),
          child: Image.asset(
            'assets/icon/moksha_wordmark.png',
            width: wordmarkWidth,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

/// Public re-export so other screens can use the same wordmark
/// treatment without depending on home_screen internals.
class MokshaWordmarkImage extends StatelessWidget {
  final double widthFactor;
  final double crop;

  const MokshaWordmarkImage({
    super.key,
    this.widthFactor = 0.78,
    this.crop = 0.45,
  });

  @override
  Widget build(BuildContext context) =>
      _MokshaWordmarkImage(widthFactor: widthFactor, crop: crop);
}
