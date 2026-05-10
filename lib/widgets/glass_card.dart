import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// A frosted-glass surface card.
///
/// One reusable component to replace ~40 ad-hoc Container+BoxDecoration
/// blocks across the app. Once everything routes through this, a tweak
/// to `MTone.purple` (border tint, glow color, fill) ripples to every
/// purple-toned card automatically.
///
/// Usage:
/// ```dart
/// GlassCard(
///   tone: MTone.gold,
///   premium: true,            // 1px gold→purple gradient border
///   onTap: _openSomething,    // wraps in InkWell with ripple + haptics
///   child: ...
/// )
/// ```
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final MTone tone;
  final bool premium;
  final bool selected;
  final bool glow;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final EdgeInsetsGeometry? margin;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.tone = MTone.neutral,
    this.premium = false,
    this.selected = false,
    this.glow = false,
    this.onTap,
    this.onLongPress,
    this.radius = MRadius.lg,
    this.margin,
  });

  Color get _borderColor => premium ? AppColors.gold : tone.accent;

  Color get _selectedFill => tone.strong.withValues(alpha: Alpha.subtle);

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);

    final decoration = BoxDecoration(
      borderRadius: shape,
      gradient: selected
          ? LinearGradient(
              colors: [
                _selectedFill,
                AppColors.surface.withValues(alpha: 0.92),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : LinearGradient(
              colors: [
                AppColors.surface.withValues(alpha: 0.85),
                AppColors.surface.withValues(alpha: 0.65),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
      border: Border.all(
        color: selected
            ? tone.strong.withValues(alpha: Alpha.mid)
            : _borderColor.withValues(alpha: Alpha.subtle),
        width: selected ? 1.5 : 1,
      ),
      boxShadow: glow
          ? MShadows.glow(tint: tone.strong)
          : MShadows.card(tint: tone.strong),
    );

    Widget body = Container(
      padding: padding,
      decoration: decoration,
      child: child,
    );

    // BackdropFilter is expensive — only enable when actually composited
    // over content (Home + Kundli where the starfield is behind the card).
    // For solid-bg screens the gradient alone reads as "glass" enough.
    body = ClipRRect(
      borderRadius: shape,
      child: body,
    );

    // Premium gradient stroke — purple → gold subtle outline. We
    // achieve it by wrapping a thin gradient container around the card.
    if (premium) {
      body = Container(
        padding: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          borderRadius: shape,
          gradient: const LinearGradient(
            colors: [
              AppColors.purpleAccent,
              AppColors.gold,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: MShadows.premium,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 1),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(radius - 1),
            ),
            padding: padding,
            child: child,
          ),
        ),
      );
    }

    if (onTap != null || onLongPress != null) {
      body = Material(
        color: Colors.transparent,
        borderRadius: shape,
        child: InkWell(
          borderRadius: shape,
          splashColor: tone.strong.withValues(alpha: Alpha.subtle),
          highlightColor: tone.strong.withValues(alpha: Alpha.whisper),
          onTap: onTap,
          onLongPress: onLongPress,
          child: body,
        ),
      );
    }

    if (margin != null) {
      body = Padding(padding: margin!, child: body);
    }

    return body;
  }
}

