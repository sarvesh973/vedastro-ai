import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/promo_config.dart';
import '../theme/app_theme.dart';

/// Full-creative promo sheet: the artwork carries the headline, the price
/// and the CTA, and this supplies the behaviour.
///
/// WHY THE WHOLE IMAGE IS TAPPABLE. Mapping an invisible hotspot onto the
/// baked button was the alternative, and it is strictly worse: it has to
/// be measured per creative, it drifts the moment artwork changes, and a
/// rect that is slightly off produces a dead button. Treating everything
/// above the dismiss strip as "take the offer" removes the alignment
/// problem entirely, and matches how people actually use a promo card —
/// they tap the price, the headline, the picture, not only the button.
///
/// WHY THERE IS A DISMISS STRIP. Both creatives render "Not now" beneath
/// their button. A visual "Not now" that opens a checkout is a dark
/// pattern, a reliable source of refunds, and something Play treats as a
/// policy issue. The cut sits at [RemoteCreative.dismissTop],
/// measured from the pixels: variant A's button ends at 0.9225 of the
/// image height and B's at 0.9220, so 0.93 clears both with room.
///
/// NOTHING IS DRAWN OVER THE ARTWORK except the close control. The tap
/// targets are GestureDetectors with no child, so they paint nothing —
/// the only button anyone sees is the one in the image, and it cannot
/// look pasted on, because nothing is.
///
/// Accepting opens the paywall rather than charging, so even a stray tap
/// costs nothing and backs out in one gesture.
class PromoOfferSheet extends StatelessWidget {
  final RemoteCreative creative;

  /// Draws the tap regions. Admin preview only.
  final bool debugOverlay;

  const PromoOfferSheet({
    super.key,
    required this.creative,
    this.debugOverlay = false,
  });

  /// Returns true if the user took the offer, false or null if dismissed.
  static Future<bool?> show(
    BuildContext context,
    RemoteCreative creative, {
    bool debugOverlay = false,
  }) {
    return Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.78),
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) =>
            PromoOfferSheet(creative: creative, debugOverlay: debugOverlay),
        transitionsBuilder: (_, animation, __, child) {
          final curve =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curve,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(curve),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  // The creatives are 1600x2000. Pinning the box to their
                  // own ratio means the image box IS the widget box — no
                  // letterboxing, no BoxFit.cover crop — so a fraction of
                  // the widget is the same fraction of the artwork at
                  // every screen size. That is what puts the dismiss cut
                  // in the right place on every device.
                  aspectRatio: 0.8,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _image(context),
                      _taps(context),
                      if (debugOverlay) _debug(),
                      _close(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _image(BuildContext context) {
    // cacheWidth decodes at display size instead of the native 1600px.
    // File size is beside the point here — 1600x2000 decoded costs ~12.8MB
    // of RAM whatever the file weighs — and halving that matters on the
    // low-end Android hardware many of these users are on.
    final media = MediaQuery.of(context);
    final logicalWidth = media.size.width.clamp(0.0, 420.0);
    final target =
        (logicalWidth * media.devicePixelRatio).round().clamp(360, 1600);
    // Remote artwork when the server supplies it, so a new creative is a
    // config edit rather than a release. The bundled asset is the floor:
    // a first launch, an offline launch, or a dead URL must produce a
    // usable banner or none at all, never a broken one.
    final url = creative.imageUrl;
    if (url != null) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.fill,
        memCacheWidth: target,
        filterQuality: FilterQuality.medium,
        // No spinner. A promo that shows a loading state has already lost
        // the moment — the bundled creative stands in until the remote
        // one is cached, and from the second launch it is instant.
        placeholder: (_, __) => _bundled(target),
        errorWidget: (_, __, ___) => _bundled(target),
      );
    }
    return _bundled(target);
  }

  Widget _bundled(int target) {
    return Image.asset(
      creative.bundledAsset,
      fit: BoxFit.fill,
      cacheWidth: target,
      filterQuality: FilterQuality.medium,
      // A missing or corrupt asset must not leave a blank modal the user
      // cannot interpret. The taps still work, so this stays usable.
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.surface,
        alignment: Alignment.center,
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Starter Pass\n₹49 first week',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 20),
          ),
        ),
      ),
    );
  }

  /// Two stacked regions, neither of which paints anything. Flex weights
  /// rather than Positioned fractions, so they divide the box exactly and
  /// cannot leave a one-pixel dead seam between them.
  Widget _taps(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: (creative.dismissTop * 1000).round(),
          child: Semantics(
            button: true,
            label: 'Start for ₹49',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop(true);
              },
            ),
          ),
        ),
        Expanded(
          flex: ((1 - creative.dismissTop) * 1000).round(),
          child: Semantics(
            button: true,
            label: 'Not now',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop(false);
              },
            ),
          ),
        ),
      ],
    );
  }

  /// A real close control, last in the Stack so it always wins the tap.
  /// Armed immediately and a full 40dp — a cross that is hard to find or
  /// slow to work is the clearest signal of a cheap paywall.
  Widget _close(BuildContext context) {
    return Positioned(
      top: 6,
      left: creative.closeOnLeft ? 6 : null,
      right: creative.closeOnLeft ? null : 6,
      child: Semantics(
        button: true,
        label: 'Dismiss offer',
        child: Material(
          // A faint scrim behind it: both creatives are busy up there and
          // a bare white glyph disappears against the bokeh.
          color: Colors.black.withOpacity(0.28),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(false);
            },
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child:
                    Icon(Icons.close_rounded, size: 19, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _debug() {
    return IgnorePointer(
      child: Column(
        children: [
          Expanded(
            flex: (creative.dismissTop * 1000).round(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.success, width: 2),
                color: AppColors.success.withOpacity(0.10),
              ),
              child: const Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: 54),
                  child: Text('TAP → paywall',
                      style: TextStyle(
                          color: AppColors.success,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
          Expanded(
            flex: ((1 - creative.dismissTop) * 1000).round(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.error, width: 2),
                color: AppColors.error.withOpacity(0.18),
              ),
              child: const Center(
                child: Text('TAP → dismiss',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
