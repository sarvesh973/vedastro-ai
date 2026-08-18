import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/mulank_reading.dart';
import '../models/mulank_profile.dart';
import '../services/mulank_service.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import 'paywall_screen.dart';

/// Full Mulank (Ank Jyotish) screen — opened from the home card.
///
/// Shows the personality profile, a Today / Week / Month segmented view of
/// readings, and a paid "ask about my day" box. Locked periods (free plan)
/// show a teaser + Unlock CTA that routes to the paywall.
class MulankScreen extends StatefulWidget {
  const MulankScreen({super.key});

  @override
  State<MulankScreen> createState() => _MulankScreenState();
}

class _MulankScreenState extends State<MulankScreen> {
  MulankProfile? _profile;
  bool _profileLoading = true;

  String _period = 'daily';
  final Map<String, MulankReading?> _readings = {};
  final Set<String> _loadingPeriods = {};

  final _askController = TextEditingController();
  bool _asking = false;
  String? _answer;

  static const _periods = ['daily', 'weekly', 'monthly'];
  static const _periodLabels = {
    'daily': 'Today',
    'weekly': 'This Week',
    'monthly': 'This Month',
  };

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadPeriod('daily');
  }

  @override
  void dispose() {
    _askController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final p = await MulankService.getProfile();
    if (!mounted) return;
    setState(() {
      _profile = p;
      _profileLoading = false;
    });
  }

  Future<void> _loadPeriod(String period) async {
    if (_readings.containsKey(period) || _loadingPeriods.contains(period)) return;
    setState(() => _loadingPeriods.add(period));
    final r = await MulankService.getReading(period: period);
    if (!mounted) return;
    setState(() {
      _readings[period] = r;
      _loadingPeriods.remove(period);
    });
    if (r != null) {
      Analytics.mulankPeriodViewed(period: period, locked: r.locked);
    }
  }

  void _selectPeriod(String period) {
    HapticFeedback.selectionClick();
    setState(() => _period = period);
    _loadPeriod(period);
  }

  void _openPaywall(String source) {
    HapticFeedback.selectionClick();
    Analytics.mulankUnlockTapped(source: source); // 'daily'|'weekly'|'monthly'|'ask'
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PaywallScreen(trigger: 'mulank')),
    );
  }

  bool get _isPaid {
    final daily = _readings['daily'];
    return daily != null && !daily.locked;
  }

  Future<void> _submitAsk() async {
    final q = _askController.text.trim();
    if (q.isEmpty || _asking) return;
    HapticFeedback.selectionClick();
    Analytics.mulankAsked(promptLen: q.length);
    setState(() {
      _asking = true;
      _answer = null;
    });
    final a = await MulankService.ask(q);
    if (!mounted) return;
    setState(() {
      _asking = false;
      _answer = a ?? 'Could not reach the stars right now. Please try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Your Mulank'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _profileCard(),
          const SizedBox(height: 20),
          _segmentedControl(),
          const SizedBox(height: 14),
          _readingCard(),
          const SizedBox(height: 20),
          _askSection(),
        ],
      ),
    );
  }

  // ── profile ──────────────────────────────────────────────
  Widget _profileCard() {
    if (_profileLoading) {
      return _card(child: const SizedBox(
        height: 90,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }
    final p = _profile;
    if (p == null) return const SizedBox.shrink();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _bigBadge(p.mulank),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Mulank ${p.mulank} · ${p.planet}'
                      '${p.bhagyank != null ? '   ·   Bhagyank ${p.bhagyank}' : ''}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (p.traits.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: p.traits.map((t) => _chip(t)).toList(),
            ),
          ],
          if (p.luckyDay.isNotEmpty || p.luckyColours.isNotEmpty) ...[
            const SizedBox(height: 14),
            if (p.luckyDay.isNotEmpty)
              _factLine('Lucky day', p.luckyDay),
            if (p.luckyColours.isNotEmpty)
              _factLine('Lucky colours', p.luckyColours.join(', ')),
            if (p.gem.isNotEmpty) _factLine('Gemstone', p.gem),
          ],
        ],
      ),
    );
  }

  Widget _factLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label:  ',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── segmented control ────────────────────────────────────
  Widget _segmentedControl() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purpleAccent.withOpacity(0.18)),
      ),
      child: Row(
        children: _periods.map((p) {
          final selected = p == _period;
          return Expanded(
            child: GestureDetector(
              onTap: () => _selectPeriod(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: selected
                      ? LinearGradient(colors: [
                          AppColors.purpleAccent.withOpacity(0.85),
                          AppColors.purpleAccent.withOpacity(0.55),
                        ])
                      : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  _periodLabels[p]!,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── reading ──────────────────────────────────────────────
  Widget _readingCard() {
    if (_loadingPeriods.contains(_period) && !_readings.containsKey(_period)) {
      return _card(child: const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }
    final r = _readings[_period];
    if (r == null) {
      return _card(child: Text(
        'Reading unavailable right now.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      ));
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _verdictChip(r),
          const SizedBox(height: 12),
          if (!r.locked && (r.reading?.isNotEmpty ?? false))
            Text(
              r.reading!,
              style: TextStyle(
                color: AppColors.textPrimary.withOpacity(0.92),
                fontSize: 14,
                height: 1.5,
              ),
            )
          else ...[
            Text(
              r.teaser ?? 'Unlock this reading to see the full guidance.',
              style: TextStyle(
                color: AppColors.textPrimary.withOpacity(0.82),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            _unlockButton(),
          ],
        ],
      ),
    );
  }

  Widget _unlockButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _openPaywall(_period),
        icon: const Icon(Icons.lock_open_rounded, size: 16),
        label: const Text('Unlock full reading'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.purpleAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // ── ask ──────────────────────────────────────────────────
  Widget _askSection() {
    if (!_isPaid) {
      return _card(
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded,
                size: 18, color: AppColors.goldLight.withOpacity(0.9)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Ask about your day',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => _openPaywall('ask'),
              child: const Text('Unlock'),
            ),
          ],
        ),
      );
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ask about your day',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _askController,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submitAsk(),
                  decoration: InputDecoration(
                    hintText: 'e.g. Is today good for a big decision?',
                    hintStyle:
                        TextStyle(color: AppColors.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _asking ? null : _submitAsk,
                icon: _asking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                color: AppColors.purpleAccent,
              ),
            ],
          ),
          if (_answer != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.purpleAccent.withOpacity(0.2)),
              ),
              child: Text(
                _answer!,
                style: TextStyle(
                  color: AppColors.textPrimary.withOpacity(0.92),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── shared bits ──────────────────────────────────────────
  Widget _verdictChip(MulankReading r) {
    final c = r.verdictColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.5), width: 0.8),
      ),
      child: Text(
        '${r.emoji}  ${r.verdictLabel}',
        style: TextStyle(color: c, fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _bigBadge(int n) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.purpleAccent.withOpacity(0.6),
            const Color(0xFF13101F).withOpacity(0.6),
          ],
        ),
        border: Border.all(color: AppColors.goldLight.withOpacity(0.5)),
      ),
      alignment: Alignment.center,
      child: Text(
        '$n',
        style: const TextStyle(
          color: AppColors.goldLight,
          fontSize: 26,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.purpleAccent.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.purpleAccent.withOpacity(0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: child,
      ),
    );
  }
}
