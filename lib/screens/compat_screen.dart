import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';
import '../services/analytics_service.dart';
import 'paywall_screen.dart';

/// Compatibility between the signed-in user and a partner.
///
/// The score, both archetypes and the eight dimension bars come back free —
/// that is the screenshot-able half, and putting it in front of people who
/// have not paid is the whole growth mechanic. The written reading is the
/// upsell.
///
/// Everything here describes the PAIR. Nothing in this screen renders a
/// judgement of the partner: they are not a user, have not consented, and
/// cannot answer back.
class CompatScreen extends ConsumerStatefulWidget {
  const CompatScreen({super.key});

  @override
  ConsumerState<CompatScreen> createState() => _CompatScreenState();
}

class _CompatScreenState extends ConsumerState<CompatScreen> {
  final _name = TextEditingController();
  final _date = TextEditingController();
  final _time = TextEditingController();
  final _place = TextEditingController();

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    for (final c in [_name, _date, _time, _place]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run() async {
    if (StorageService.currentProfile == null) {
      setState(() => _error = 'Add your own birth details first.');
      return;
    }
    if (_date.text.trim().isEmpty || _time.text.trim().isEmpty ||
        _place.text.trim().isEmpty) {
      setState(() => _error = 'Date, time and place are all needed for a real match.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    Analytics.compatChecked();

    final r = await AiService.compatReading(
      partnerName: _name.text.trim(),
      partnerBirthDate: _date.text.trim(),
      partnerBirthTime: _time.text.trim(),
      partnerPlace: _place.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = r;
      _error = r == null ? 'Could not read that match. Check the details and try again.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Match'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          if (_result == null) ..._form(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(_error!,
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
            ),
          if (_result != null) ..._resultView(_result!),
        ],
      ),
    );
  }

  List<Widget> _form() => [
        Text(
          'Who are you checking?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'We compare their Moon placement with yours across the eight '
          'traditional kutas. Birth time matters — a guess gives a guess.',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 20),
        _field(_name, 'Their name', 'optional'),
        _field(_date, 'Date of birth', 'DD/MM/YYYY'),
        _field(_time, 'Time of birth', 'e.g. 09:15 PM'),
        _field(_place, 'Place of birth', 'City'),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _run,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.purpleAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Check the match'),
          ),
        ),
      ];

  Widget _field(TextEditingController c, String label, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );

  List<Widget> _resultView(Map<String, dynamic> r) {
    final total = r['total'];
    final percent = r['percent'] ?? 0;
    final band = (r['band'] ?? '').toString();
    final arch = (r['archetypes'] ?? {}) as Map<String, dynamic>;
    final dims = (r['dimensions'] ?? []) as List<dynamic>;
    final reading = r['reading'] as String?;
    final locked = r['locked'] == true;

    return [
      // Score. The one thing that gets screenshotted, so it leads.
      Center(
        child: Column(
          children: [
            Text('$total / 36',
                style: TextStyle(
                  color: AppColors.goldLight,
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                )),
            Text('$percent%  ·  ${band.toUpperCase()}',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    letterSpacing: 1.2)),
          ],
        ),
      ),
      const SizedBox(height: 20),

      // Archetypes. People share an identity, not a number — this is the
      // line that travels.
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.purpleAccent.withOpacity(0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.purpleAccent.withOpacity(0.35)),
        ),
        child: Center(
          child: Text(
            "You're ${arch['you'] ?? '—'}.  They're ${arch['partner'] ?? '—'}.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      const SizedBox(height: 22),

      ...dims.map((d) => _dimensionRow(d as Map<String, dynamic>)),

      const SizedBox(height: 22),
      if (reading != null && reading.isNotEmpty)
        Text(reading,
            style: TextStyle(
                color: AppColors.textPrimary.withOpacity(0.92),
                fontSize: 14,
                height: 1.6))
      else if (locked)
        _unlock(),

      const SizedBox(height: 24),
      Center(
        child: TextButton(
          onPressed: () => setState(() {
            _result = null;
            _error = null;
          }),
          child: const Text('Check someone else'),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'This describes how two charts interact. It is not a judgement of '
        'either person, and it cannot tell you what someone will do.',
        textAlign: TextAlign.center,
        style: TextStyle(
            color: AppColors.textMuted.withOpacity(0.6),
            fontSize: 11,
            height: 1.5),
      ),
    ];
  }

  Widget _dimensionRow(Map<String, dynamic> d) {
    final points = (d['points'] as num?)?.toDouble() ?? 0;
    final max = (d['max'] as num?)?.toDouble() ?? 1;
    final verdict = (d['verdict'] ?? 'mixed').toString();
    final colour = verdict == 'strong'
        ? const Color(0xFF10B981)
        : verdict == 'friction'
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${d['friendly']}',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Text('${d['label']}',
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(width: 10),
              Text('${d['points']}/${d['max']}',
                  style: TextStyle(
                      color: colour,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: max == 0 ? 0 : (points / max).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.06),
              valueColor: AlwaysStoppedAnimation(colour),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unlock() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.goldLight.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            'Unlock the full reading',
            style: TextStyle(
                color: AppColors.goldLight,
                fontSize: 15,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'What each of you needs to feel secure, where you misread each '
            'other, and the one friction worth naming.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              // PaywallScreen logs paywall_viewed from its own trigger, so
              // firing it here too would double-count compat conversions.
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const PaywallScreen(trigger: 'compat'))),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.purpleAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Unlock'),
            ),
          ),
        ],
      ),
    );
  }
}
