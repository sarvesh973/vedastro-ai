import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/mulank_reading.dart';
import '../services/mulank_service.dart';
import '../services/storage_service.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../screens/mulank_screen.dart';

/// Home-screen "Today's Mulank" card. Sits just below Today's Cosmic Mood.
///
/// Shows the deterministic daily verdict (🟢/🟡/🔴) for the active
/// profile's mulank. For paid users it shows the full LLM reading; for
/// free users it shows the short teaser + an "Unlock" CTA that opens the
/// paywall (this is the feature's daily upsell hook). Fully self-fetching;
/// if there is no profile or the request fails it renders nothing, so it
/// can never break the home layout.
class MulankCard extends StatefulWidget {
  const MulankCard({super.key});

  @override
  State<MulankCard> createState() => _MulankCardState();
}

class _MulankCardState extends State<MulankCard> {
  MulankReading? _reading;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await MulankService.getReading(period: 'daily');
    if (!mounted) return;
    setState(() {
      _reading = r;
      _loading = false;
    });
    if (r != null) {
      Analytics.mulankCardViewed(
        mulank: r.mulank,
        verdict: r.verdict,
        locked: r.locked,
      );
    }
  }

  void _openDetail() {
    HapticFeedback.selectionClick();
    Analytics.mulankOpened(source: 'home_card');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MulankScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No profile → nothing to compute against; stay invisible.
    if (StorageService.currentProfile == null) return const SizedBox.shrink();
    if (_loading) return _shell(child: _skeleton());
    final r = _reading;
    if (r == null) return const SizedBox.shrink(); // silent failure

    final locked = r.locked;
    return GestureDetector(
      onTap: _openDetail,
      child: _shell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(r),
            const SizedBox(height: 12),
            if (!locked && (r.reading?.isNotEmpty ?? false))
              Text(
                r.reading!,
                style: TextStyle(
                  color: AppColors.textPrimary.withOpacity(0.92),
                  fontSize: 13.5,
                  height: 1.45,
                  letterSpacing: 0.1,
                ),
              )
            else ...[
              Text(
                r.teaser ?? 'Your numbers are ready for today.',
                style: TextStyle(
                  color: AppColors.textPrimary.withOpacity(0.82),
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              _unlockRow(),
            ],
          ],
        ),
      ),
    );
  }

  // ── pieces ──────────────────────────────────────────────

  Widget _header(MulankReading r) {
    return Row(
      children: [
        _numberBadge(r.mulank),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "TODAY'S MULANK",
              style: TextStyle(
                color: AppColors.goldLight.withOpacity(0.85),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Number ${r.mulank} · ${r.planet}',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const Spacer(),
        _verdictChip(r),
      ],
    );
  }

  Widget _numberBadge(int n) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.purpleAccent.withOpacity(0.55),
            const Color(0xFF13101F).withOpacity(0.6),
          ],
        ),
        border: Border.all(
          color: AppColors.goldLight.withOpacity(0.45),
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '$n',
        style: TextStyle(
          color: AppColors.goldLight,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _verdictChip(MulankReading r) {
    final c = r.verdictColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.5), width: 0.8),
      ),
      child: Text(
        '${r.emoji}  ${r.verdictLabel}',
        style: TextStyle(
          color: c,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _unlockRow() {
    return Row(
      children: [
        Icon(Icons.lock_outline_rounded,
            size: 14, color: AppColors.goldLight.withOpacity(0.85)),
        const SizedBox(width: 7),
        Text(
          'Unlock your full reading',
          style: TextStyle(
            color: AppColors.goldLight.withOpacity(0.9),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Icon(Icons.arrow_forward_ios_rounded,
            size: 12, color: AppColors.goldLight.withOpacity(0.7)),
      ],
    );
  }

  // Shared container chrome — mirrors the Cosmic Mood card so the two
  // read as a set.
  Widget _shell({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF13101F).withOpacity(0.35),
            const Color(0xFF0B0912).withOpacity(0.45),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.purpleAccent.withOpacity(0.22),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: child,
      ),
    );
  }

  Widget _skeleton() {
    Widget bar(double w) => Container(
          height: 11,
          width: w,
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.textPrimary.withOpacity(0.06),
            ),
          ),
          const SizedBox(width: 12),
          bar(120),
        ]),
        const SizedBox(height: 14),
        bar(double.infinity),
        const SizedBox(height: 8),
        bar(180),
      ],
    );
  }
}
