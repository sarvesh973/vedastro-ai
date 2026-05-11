import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'm_button.dart';

/// Standardised loading / empty / error visuals used across screens.
///
/// Three named widgets so a screen doesn't have to roll its own
/// "spinner + caption" / "icon + text + retry" combo. Single point of
/// edit for tone, motion, and copy patterns.

// ─── Loading ────────────────────────────────────────────────────────

class MLoadingState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final MTone tone;

  const MLoadingState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.tone = MTone.purple,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(tone.accent),
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: MTextStyles.cardTitle,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: Space.xs),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: MTextStyles.caption,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shimmer skeleton block — drop-in replacement for a CircularProgressIndicator
/// where there's a known content shape.
class MSkeleton extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;

  const MSkeleton({
    super.key,
    this.height = 16,
    this.width,
    this.radius = MRadius.sm,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceLight.withValues(alpha: Alpha.strong),
      highlightColor: AppColors.purpleAccent.withValues(alpha: Alpha.subtle),
      period: const Duration(milliseconds: 1400),
      child: Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

// ─── Empty ──────────────────────────────────────────────────────────

class MEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final MTone tone;

  const MEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.tone = MTone.purple,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tone.strong.withValues(alpha: Alpha.subtle),
                boxShadow: [
                  BoxShadow(
                    color: tone.strong.withValues(alpha: Alpha.subtle),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(icon, color: tone.accent, size: 32),
            )
                .animate()
                .fadeIn(duration: 400.ms)
                .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1)),
            const SizedBox(height: Space.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: MTextStyles.sectionTitle,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: MTextStyles.body,
              ),
            ],
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: Space.xl),
              MButton.primary(
                label: ctaLabel!,
                tone: tone,
                onPressed: onCta,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Error ──────────────────────────────────────────────────────────

class MErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String? supportHint;

  const MErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.supportHint = 'Or email support@vedastro.ai if it persists.',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                color: AppColors.error.withValues(alpha: Alpha.strong),
                size: 36),
            const SizedBox(height: Space.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: MTextStyles.body,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: Space.lg),
              MButton.secondary(
                label: 'Retry',
                icon: Icons.refresh,
                tone: MTone.purple,
                onPressed: onRetry,
                size: MButtonSize.sm,
              ),
            ],
            if (supportHint != null) ...[
              const SizedBox(height: Space.md),
              Text(
                supportHint!,
                textAlign: TextAlign.center,
                style: MTextStyles.caption,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
