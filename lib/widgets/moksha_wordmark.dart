import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Stylised "moksha" wordmark replicating the look of the user's
/// reference logo: lowercase wordmark + shirorekha (horizontal bar)
/// across the top + gold dots punctuating the line + a tagline
/// underneath with dot-line-dot dividers.
///
/// Uses Eczar from Google Fonts — a typeface specifically designed to
/// harmonise Latin and Devanagari, giving a similar scriptural feel
/// without needing the bespoke Samarkan font file. To swap to actual
/// Samarkan later: drop `assets/fonts/Samarkan.ttf`, register the
/// family in pubspec.yaml under `flutter.fonts`, and change the
/// `_titleStyle()` to use `TextStyle(fontFamily: 'Samarkan', ...)`.
///
/// `cream`: render with cream-ish text + gold accents (default — for
/// dark cosmic background). `dark`: dark text + gold accents (for a
/// hypothetical light card behind it).
enum MokshaTone { cream, dark }

class MokshaWordmark extends StatelessWidget {
  final double height;
  final bool showTagline;
  final MokshaTone tone;
  final String tagline;

  const MokshaWordmark({
    super.key,
    this.height = 88,
    this.showTagline = true,
    this.tone = MokshaTone.cream,
    this.tagline = 'align with dharma, awaken the soul',
  });

  Color get _textColor =>
      tone == MokshaTone.cream ? const Color(0xFFF5E6D3) : const Color(0xFF131326);
  Color get _accent =>
      tone == MokshaTone.cream ? AppColors.gold : AppColors.gold;
  Color get _taglineColor => tone == MokshaTone.cream
      ? const Color(0xFFE8C9A0)
      : const Color(0xFF2A2A3F);

  TextStyle _titleStyle(double fontSize) {
    return GoogleFonts.eczar(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      color: _textColor,
      letterSpacing: 0.5,
      height: 1.0,
    );
  }

  TextStyle _taglineStyle(double fontSize) {
    return GoogleFonts.eczar(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      color: _taglineColor,
      letterSpacing: 0.4,
      height: 1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Scale the title to about 60% of the wordmark height so the
    // shirorekha + dots have room above and the tagline below.
    final titleFontSize = (height * 0.55).clamp(28.0, 96.0);
    final taglineFontSize = (height * 0.13).clamp(11.0, 18.0);

    return SizedBox(
      height: showTagline ? height : (height * 0.78),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Wordmark(
            text: 'moksha',
            titleStyle: _titleStyle(titleFontSize),
            accent: _accent,
            textColor: _textColor,
          ),
          if (showTagline) ...[
            const SizedBox(height: 8),
            _Tagline(
              text: tagline,
              style: _taglineStyle(taglineFontSize),
              accent: _accent,
            ),
          ],
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  final String text;
  final TextStyle titleStyle;
  final Color accent;
  final Color textColor;

  const _Wordmark({
    required this.text,
    required this.titleStyle,
    required this.accent,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    // Measure the rendered width of the text so the shirorekha line
    // matches it exactly (with a small overhang on each side for the
    // end dots, mirroring the reference logo).
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: titleStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final textWidth = tp.width;
        final lineWidth = textWidth + 30; // overhang for end dots
        final dotSize = (titleStyle.fontSize ?? 32) * 0.13;
        final lineHeight = (titleStyle.fontSize ?? 32) * 0.06;

        return SizedBox(
          width: lineWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Shirorekha (top bar) with gold dots at each end.
              SizedBox(
                height: dotSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Bar
                    Container(
                      height: lineHeight.clamp(2.0, 4.0),
                      width: lineWidth - dotSize - 4,
                      decoration: BoxDecoration(
                        color: textColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Left gold dot
                    Positioned(
                      left: 0,
                      child: _Dot(size: dotSize, color: accent),
                    ),
                    // Right gold dot
                    Positioned(
                      right: 0,
                      child: _Dot(size: dotSize, color: accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              // The wordmark text. We overlay an extra gold accent dot
              // inside the "o" to mirror the reference where the o has
              // a coloured fill — sits roughly under the second character.
              Stack(
                alignment: Alignment.center,
                children: [
                  Text(text, style: titleStyle),
                  // Position a gold dot inside the "o" (third character).
                  // Approximate by offsetting from center — looks right
                  // for "moksha" specifically; if you change the wordmark
                  // text, retune the offset or remove the accent dot.
                  Positioned(
                    left: textWidth * 0.20,
                    top: (titleStyle.fontSize ?? 32) * 0.45,
                    child: _Dot(
                      size: (titleStyle.fontSize ?? 32) * 0.18,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Tagline extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color accent;

  const _Tagline({
    required this.text,
    required this.style,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final dotSize = (style.fontSize ?? 12) * 0.45;
    final lineWidth = (style.fontSize ?? 12) * 1.2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left divider: short line + dot
        Container(
          width: lineWidth,
          height: 1.2,
          color: style.color?.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 4),
        _Dot(size: dotSize, color: accent),
        const SizedBox(width: 8),
        Text(text, style: style),
        const SizedBox(width: 8),
        _Dot(size: dotSize, color: accent),
        const SizedBox(width: 4),
        Container(
          width: lineWidth,
          height: 1.2,
          color: style.color?.withValues(alpha: 0.6),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final double size;
  final Color color;
  const _Dot({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: size * 0.8,
            spreadRadius: 0,
          ),
        ],
      ),
    );
  }
}
