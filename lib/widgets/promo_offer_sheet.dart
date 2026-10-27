import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/subscription_plan.dart';
import '../theme/app_theme.dart';

/// The content of a promotional offer sheet.
///
/// Data rather than hardcoded strings so the price and the framing can be
/// changed without touching the layout — and so [anchorPrice] is a
/// deliberate decision at the call site rather than something buried in a
/// widget.
class PromoOffer {
  /// Small gold label above the headline, e.g. 'STARTER PASS'.
  final String eyebrow;
  final String headline;
  final String body;

  /// The price actually charged now, e.g. '₹49'.
  final String price;

  /// Billing period as it reads after the price, e.g. 'a week'.
  final String period;

  /// A struck-through "before" price.
  ///
  /// MUST be a price that is genuinely charged — the standing rate of this
  /// plan, with [price] as a real introductory rate. A struck-through
  /// figure nobody has ever been charged is a fictitious reference price:
  /// it misrepresents pricing under Play's policies, and India's CCPA
  /// guidelines on misleading advertisements treat a fabricated "was"
  /// price as misleading by definition. This app bills real consumers in
  /// India through Razorpay, so that is not a theoretical risk.
  ///
  /// Null by default. Leave it null unless the higher price is live.
  final String? anchorPrice;

  /// What happens after the introductory period, e.g. 'then ₹99 a week'.
  /// Required alongside [anchorPrice]: showing a discount without saying
  /// what the user rolls onto is the other half of the same problem.
  final String? renewalNote;

  final List<String> points;
  final String ctaLabel;

  const PromoOffer({
    required this.eyebrow,
    required this.headline,
    required this.body,
    required this.price,
    required this.period,
    this.anchorPrice,
    this.renewalNote,
    this.points = const [],
    this.ctaLabel = 'See plans',
  }) : assert(anchorPrice == null || renewalNote != null,
            'An anchor price needs a renewal note — say what they roll onto');

  /// The honest framing of the CURRENT ₹49/week Pass, with no anchor
  /// because there is no higher price to anchor against yet.
  ///
  /// Per-question maths instead of a strikethrough: ₹49 ÷ 21 ≈ ₹2.33, so
  /// "about ₹2 each" does the comparison work a fake "was ₹100" was
  /// reaching for, and it is true.
  static const starterPass = PromoOffer(
    eyebrow: 'STARTER PASS',
    headline: 'Ask your chart\nanything',
    body: 'Twenty-one questions a week, answered from your own chart — '
        'about ₹2 each.',
    price: '₹49',
    period: 'a week',
    points: [
      '21 questions every week',
      'Grounded in your birth chart, not generic horoscopes',
      'Cancel anytime, in one tap',
    ],
    ctaLabel: 'Get the Starter Pass',
  );

  /// The variant to use IF the Pass standing rate is raised to ₹99/week
  /// and ₹49 becomes a genuine introductory price. Then — and only then —
  /// the strikethrough is accurate.
  ///
  /// Raising the Pass also fixes a real inversion in the ladder: at
  /// ₹49/week the Pass is ~₹212/month for ~91 chats, against Standard at
  /// ₹199/month for 50, so nobody who only chats should ever upgrade.
  static const starterPassIntro = PromoOffer(
    eyebrow: 'FIRST WEEK',
    headline: 'Ask your chart\nanything',
    body: 'Twenty-one questions a week, answered from your own chart.',
    price: '₹49',
    period: 'first week',
    anchorPrice: '₹99',
    renewalNote: 'then ₹99 a week · cancel anytime',
    points: [
      '21 questions every week',
      'Grounded in your birth chart, not generic horoscopes',
      'Cancel anytime, in one tap',
    ],
    ctaLabel: 'Start for ₹49',
  );

  /// The variant that matches what Razorpay will actually charge.
  ///
  /// Reading this rather than naming a variant at the call site is what
  /// stops the sheet advertising a discount the billing system is not
  /// applying. The strikethrough appears only when the ₹99 standing rate
  /// is live — see kPassIntroPricingLive.
  static PromoOffer get liveOffer =>
      kPassIntroPricingLive ? starterPassIntro : starterPass;
}

/// A premium, dismissible offer sheet.
///
/// Deliberately a centred card rather than a full-bleed takeover: a
/// full-screen interstitial on launch is the most review-damaging pattern
/// there is, and this app sits at 4.1 stars. A card over a dimmed
/// background reads as an offer; a full-screen one reads as a toll gate.
///
/// Motion is restrained on purpose — a fade, a small rise, and one slow
/// sweep across the price. No countdown, no pulsing, no confetti. Urgency
/// effects are what make a paid product feel cheap, and they are the same
/// pressure tactic the Play listing promises to avoid.
///
/// Returns true if the user took the offer, false or null if they
/// dismissed it. The caller decides what "took it" opens.
class PromoOfferSheet extends StatelessWidget {
  final PromoOffer offer;

  const PromoOfferSheet({super.key, required this.offer});

  static Future<bool?> show(BuildContext context, PromoOffer offer) {
    return Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.72),
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => PromoOfferSheet(offer: offer),
        transitionsBuilder: (_, animation, __, child) {
          final curve =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curve,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              // Capped so it stays a card on a tablet instead of
              // stretching into a billboard.
              constraints: const BoxConstraints(maxWidth: 380),
              child: _card(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        // Two-stop vertical gradient rather than a flat fill: it gives the
        // card depth without any border heavy enough to look like a dialog.
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B1630), AppColors.surface],
        ),
        border: Border.all(color: AppColors.gold.withOpacity(0.28)),
        boxShadow: [
          // The glow is the premium cue. Wide, low opacity, purple — it
          // reads as light coming off the card, not as a drop shadow.
          BoxShadow(
            color: AppColors.purpleGlow.withOpacity(0.28),
            blurRadius: 48,
            spreadRadius: -8,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // A soft radial bloom behind the mark, so the top of the card
            // feels lit rather than printed.
            Positioned(
              top: -90,
              left: -40,
              right: -40,
              height: 220,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      AppColors.purpleAccent.withOpacity(0.30),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _closeRow(context),
                  const SizedBox(height: 4),
                  _mark(),
                  const SizedBox(height: 20),
                  _eyebrow(),
                  const SizedBox(height: 10),
                  Text(
                    offer.headline,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 27,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    offer.body,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13.5,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _priceRow(),
                  if (offer.renewalNote != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      offer.renewalNote!,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                  if (offer.points.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _divider(),
                    const SizedBox(height: 16),
                    for (var i = 0; i < offer.points.length; i++) ...[
                      _point(offer.points[i], i),
                      if (i < offer.points.length - 1)
                        const SizedBox(height: 11),
                    ],
                  ],
                  const SizedBox(height: 24),
                  _cta(context),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                        minimumSize: const Size(0, 44),
                      ),
                      child: const Text('Not now',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dismissal lives top-right with a full 44dp hit area and no delay.
  /// A cross that is hard to find or slow to arm is the single clearest
  /// signal of a cheap paywall, and Play treats it as a dark pattern.
  Widget _closeRow(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Semantics(
        button: true,
        label: 'Dismiss offer',
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).pop(false);
          },
          borderRadius: BorderRadius.circular(22),
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Icon(Icons.close_rounded,
                  size: 20, color: AppColors.textMuted),
            ),
          ),
        ),
      ),
    );
  }

  /// The app's own mandala, the same image the splash uses, so the sheet
  /// is recognisably Moksha rather than a generic sale card.
  Widget _mark() {
    return Center(
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.gold.withOpacity(0.35)),
          boxShadow: [
            BoxShadow(
              color: AppColors.purpleGlow.withOpacity(0.35),
              blurRadius: 24,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          'assets/icon/app_splash_logo.png',
          fit: BoxFit.cover,
          // The sheet must still render if the asset is ever renamed.
          errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome,
              color: AppColors.goldLight, size: 26),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 500.ms)
        .scale(begin: const Offset(0.92, 0.92), end: const Offset(1, 1),
            duration: 500.ms, curve: Curves.easeOutBack);
  }

  Widget _eyebrow() {
    return Text(
      offer.eyebrow.toUpperCase(),
      style: const TextStyle(
        color: AppColors.goldLight,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        // Wide tracking on a small gold label is the cheapest way to make
        // a line read as considered rather than as a sticker.
        letterSpacing: 2.2,
      ),
    );
  }

  Widget _priceRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          offer.price,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 42,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.2,
            height: 1,
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            offer.period,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
        if (offer.anchorPrice != null) ...[
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              offer.anchorPrice!,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 16,
                decoration: TextDecoration.lineThrough,
                decorationColor: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ],
    )
        .animate()
        .fadeIn(duration: 450.ms, delay: 120.ms)
        // One slow sweep across the price, once. Shimmer that loops is
        // what makes a card look like an advert.
        .shimmer(
            duration: 1400.ms,
            delay: 420.ms,
            color: AppColors.goldLight.withOpacity(0.5));
  }

  Widget _divider() => Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            AppColors.divider.withOpacity(0.9),
            AppColors.divider.withOpacity(0.1),
          ]),
        ),
      );

  Widget _point(String text, int index) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.check_rounded,
              size: 16, color: AppColors.goldLight.withOpacity(0.9)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    ).animate().fadeIn(
        duration: 400.ms, delay: (220 + index * 90).ms);
  }

  Widget _cta(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.purpleAccent.withOpacity(0.45),
              blurRadius: 22,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop(true);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.purpleAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(
            offer.ctaLabel,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 420.ms, delay: 320.ms);
  }
}
