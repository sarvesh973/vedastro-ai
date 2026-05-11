import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

enum MButtonVariant { primary, secondary, ghost }

enum MButtonSize { sm, md, lg }

/// Single button component covering primary actions across the app.
/// Replaces the mix of ElevatedButton / OutlinedButton / GestureDetector
/// + Container that drifted between screens.
///
/// Has built-in:
///   - Haptic selection-click on tap
///   - Loading state (spinner replaces label, button auto-disabled)
///   - Three variants × three sizes
///   - Tone-aware (purple by default, can be MTone.gold etc.)
class MButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final MButtonVariant variant;
  final MButtonSize size;
  final MTone tone;
  final bool loading;
  final bool fullWidth;

  const MButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = MButtonVariant.primary,
    this.size = MButtonSize.md,
    this.tone = MTone.purple,
    this.loading = false,
    this.fullWidth = false,
  });

  /// Convenience for the most common case.
  const MButton.primary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.size = MButtonSize.md,
    this.tone = MTone.purple,
    this.loading = false,
    this.fullWidth = false,
  }) : variant = MButtonVariant.primary;

  const MButton.secondary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.size = MButtonSize.md,
    this.tone = MTone.purple,
    this.loading = false,
    this.fullWidth = false,
  }) : variant = MButtonVariant.secondary;

  const MButton.ghost({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.size = MButtonSize.md,
    this.tone = MTone.purple,
    this.loading = false,
    this.fullWidth = false,
  }) : variant = MButtonVariant.ghost;

  double get _height {
    switch (size) {
      case MButtonSize.sm:
        return 38;
      case MButtonSize.md:
        return 48;
      case MButtonSize.lg:
        return 56;
    }
  }

  EdgeInsetsGeometry get _padding {
    switch (size) {
      case MButtonSize.sm:
        return const EdgeInsets.symmetric(horizontal: Space.md);
      case MButtonSize.md:
        return const EdgeInsets.symmetric(horizontal: Space.xl);
      case MButtonSize.lg:
        return const EdgeInsets.symmetric(horizontal: Space.xxl);
    }
  }

  double get _fontSize {
    switch (size) {
      case MButtonSize.sm:
        return 13;
      case MButtonSize.md:
        return 15;
      case MButtonSize.lg:
        return 16;
    }
  }

  void _onTap() {
    if (onPressed == null || loading) return;
    HapticFeedback.selectionClick();
    onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;

    final baseColor = tone.strong;
    final foreground = variant == MButtonVariant.primary
        ? Colors.white
        : baseColor.withValues(alpha: disabled ? Alpha.mid : 1);

    BoxDecoration decoration;
    switch (variant) {
      case MButtonVariant.primary:
        decoration = BoxDecoration(
          gradient: disabled
              ? null
              : LinearGradient(
                  colors: [
                    baseColor,
                    Color.lerp(baseColor, AppColors.purpleGlow, 0.4)!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: disabled ? AppColors.surfaceLight : null,
          borderRadius: BorderRadius.circular(MRadius.lg),
          boxShadow: disabled ? null : MShadows.glow(tint: baseColor),
        );
        break;
      case MButtonVariant.secondary:
        decoration = BoxDecoration(
          color: baseColor.withValues(alpha: Alpha.subtle),
          borderRadius: BorderRadius.circular(MRadius.lg),
          border: Border.all(
            color: baseColor.withValues(alpha: disabled ? Alpha.subtle : Alpha.mid),
            width: 1.2,
          ),
        );
        break;
      case MButtonVariant.ghost:
        decoration = BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(MRadius.lg),
        );
        break;
    }

    final labelStyle = MTextStyles.button.copyWith(
      fontSize: _fontSize,
      color: foreground,
    );

    final inner = loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(foreground),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: _fontSize + 3, color: foreground),
                const SizedBox(width: Space.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  style: labelStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    final button = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(MRadius.lg),
      child: InkWell(
        onTap: disabled ? null : _onTap,
        borderRadius: BorderRadius.circular(MRadius.lg),
        splashColor: baseColor.withValues(alpha: Alpha.subtle),
        highlightColor: baseColor.withValues(alpha: Alpha.whisper),
        child: Container(
          height: _height,
          padding: _padding,
          decoration: decoration,
          alignment: Alignment.center,
          child: inner,
        ),
      ),
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
