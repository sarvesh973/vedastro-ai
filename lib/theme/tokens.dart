import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';

// ─── Spacing ────────────────────────────────────────────────────────
//
// Replace ad-hoc `8`, `12`, `16`, `20`, `24` literals with these
// tokens so the eye doesn't pick up drift between screens. Pick the
// nearest token rather than a magic number — rounded to a 4dp grid.
class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double xxxl = 40;
}

// ─── Border radius ──────────────────────────────────────────────────
class MRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
  static const double xxl = 28;
  static const double pill = 999;
}

// ─── Opacity / alpha ────────────────────────────────────────────────
//
// The codebase had 30+ unique `withOpacity()` literals; reducing to
// these named tones makes overlays feel coherent across screens.
class Alpha {
  /// barely-there tint (5%) — backgrounds, faint chip fills
  static const double whisper = 0.05;

  /// subtle (12%) — card surface accents, inactive borders
  static const double subtle = 0.12;

  /// soft (20%) — selected card fills, glow halos
  static const double soft = 0.20;

  /// medium (35%) — visible borders, active states
  static const double mid = 0.35;

  /// strong (60%) — overlays, modal scrims
  static const double strong = 0.60;
}

// ─── Elevation tokens ───────────────────────────────────────────────
//
// We don't use Material elevation (it tints the surface in dark mode
// in ways we don't want). Instead, soft tinted shadows that match the
// purple cosmic theme.
class MShadows {
  /// Resting card — barely-there depth
  static List<BoxShadow> card({Color tint = AppColors.purpleAccent}) => [
        BoxShadow(
          color: tint.withValues(alpha: Alpha.whisper),
          blurRadius: 12,
          spreadRadius: 1,
          offset: const Offset(0, 4),
        ),
      ];

  /// Hovered / pressed / "this card is alive" — visible glow
  static List<BoxShadow> glow({Color tint = AppColors.purpleAccent}) => [
        BoxShadow(
          color: tint.withValues(alpha: Alpha.soft),
          blurRadius: 24,
          spreadRadius: 2,
          offset: const Offset(0, 6),
        ),
      ];

  /// Plan-card / paywall / "premium" surfaces
  static List<BoxShadow> premium = [
    BoxShadow(
      color: AppColors.gold.withValues(alpha: Alpha.subtle),
      blurRadius: 32,
      spreadRadius: 3,
      offset: const Offset(0, 8),
    ),
  ];
}

// ─── Tone (semantic palette for components) ─────────────────────────
//
// GlassCard / MButton / MEmptyState etc. take a `MTone` instead of
// raw colors so a single tone change ripples consistently.
enum MTone { neutral, purple, gold, success, error, pink }

extension MToneColors on MTone {
  Color get accent {
    switch (this) {
      case MTone.neutral:
        return AppColors.textSecondary;
      case MTone.purple:
        return AppColors.purpleLight;
      case MTone.gold:
        return AppColors.goldLight;
      case MTone.success:
        return AppColors.success;
      case MTone.error:
        return AppColors.error;
      case MTone.pink:
        return const Color(0xFFE91E63);
    }
  }

  Color get strong {
    switch (this) {
      case MTone.neutral:
        return AppColors.textPrimary;
      case MTone.purple:
        return AppColors.purpleAccent;
      case MTone.gold:
        return AppColors.gold;
      case MTone.success:
        return AppColors.success;
      case MTone.error:
        return AppColors.error;
      case MTone.pink:
        return const Color(0xFFE91E63);
    }
  }
}

// ─── Typography helpers ─────────────────────────────────────────────
//
// Names by *purpose*, not size — so screens stay coherent even when
// the underlying scale changes. Always wraps with the Devanagari
// fallback so Hindi text renders cleanly (Inter alone falls back to
// the system font for Devanagari which can look rough on stock
// Android).
class MTextStyles {
  static TextStyle _withDevanagari(TextStyle style) {
    return style.copyWith(
      fontFamilyFallback: [
        // Noto Sans Devanagari — the de facto fallback Google ships.
        // Loaded via google_fonts so it's bundled at build time without
        // an extra asset declaration.
        GoogleFonts.notoSansDevanagari().fontFamily ?? 'NotoSansDevanagari',
      ],
    );
  }

  // Big, on-screen brand moments
  static TextStyle display = _withDevanagari(const TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.6,
    height: 1.15,
  ));

  // Screen title (within the page body, not appbar)
  static TextStyle screenTitle = _withDevanagari(const TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  ));

  // Section header (e.g. "Your Personality")
  static TextStyle sectionTitle = _withDevanagari(const TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  ));

  // Card title (smaller, inside a card)
  static TextStyle cardTitle = _withDevanagari(const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  ));

  // Standard body copy
  static TextStyle body = _withDevanagari(const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.55,
  ));

  // Smaller secondary copy
  static TextStyle bodySmall = _withDevanagari(const TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  ));

  // Muted helper text / captions
  static TextStyle caption = _withDevanagari(const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 1.45,
  ));

  // Eyebrow / section-label (UPPERCASE small letter-spaced)
  static TextStyle eyebrow = _withDevanagari(const TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    color: AppColors.textMuted,
    letterSpacing: 1.2,
  ));

  // Numeric / data display (current usage 4 / 5, dasha years etc)
  static TextStyle numeric = _withDevanagari(const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.goldLight,
    fontFeatures: [FontFeature.tabularFigures()],
  ));

  // Button label
  static TextStyle button = _withDevanagari(const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  ));
}
