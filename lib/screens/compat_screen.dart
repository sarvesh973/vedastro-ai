import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';
import '../services/analytics_service.dart';
import '../widgets/location_autocomplete_field.dart';
import 'paywall_screen.dart';

/// The two wire formats this screen sends, kept as free functions so the
/// client/server contract can be tested without pumping a widget.
///
/// The server parses a birth time with
/// `/(\d{1,2}):(\d{2})\s*(AM|PM)?/` and, on no match, leaves its default
/// of 12:00 standing — an unreadable time produces a NOON CHART, not an
/// error. So the one thing that must never happen is sending a string
/// that regex cannot read. 24-hour HH:mm has no AM/PM to lose and no
/// locale to depend on, unlike TimeOfDay.format(context).
@visibleForTesting
String compatTimeString(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// DD/MM/YYYY, matching UserProfile.dobFormatted. The server only swaps
/// day and month when the SECOND field exceeds 12, so a zero-padded
/// day-first date is unambiguous for every real birth date.
@visibleForTesting
String compatDateString(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

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
  final _place = TextEditingController();

  // Date and time are PICKED, never typed. These were free-text fields
  // hinting "DD/MM/YYYY" and "e.g. 09:15 PM", validated only on being
  // non-empty — so "9/7/03", "July 9th" and "abc" all reached the server.
  // Worse than the 400s that produced: the chart parser falls back to
  // 12:00 noon when it cannot read a time, so a typo did not fail, it
  // quietly returned a reading for the wrong birth time.
  DateTime? _dob;
  TimeOfDay? _tob;

  /// Set only when the user picks a place out of the suggestion list.
  /// Typing a city and never selecting one leaves this null — the case
  /// "location validation is not there" was about. The raw text went to
  /// the server, which geocoded it to whatever came back first, or to
  /// nothing at all.
  LocationSuggestion? _placePick;

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    for (final c in [_name, _place]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _dobText => _dob == null ? '' : compatDateString(_dob!);

  String get _tobText => _tob == null ? '' : compatTimeString(_tob!);

  Future<void> _run() async {
    final me = StorageService.currentProfile;
    if (me == null) {
      setState(() => _error = 'Add your own birth details first.');
      return;
    }
    // Both charts are needed, so an incomplete profile of YOUR OWN fails
    // the match just as surely as an incomplete partner. This used to
    // surface as the same generic "check the details", pointing the user
    // at the partner fields they had just filled in correctly.
    if ((me.timeOfBirth ?? '').trim().isEmpty) {
      setState(() => _error =
          'Your own birth time is missing. Add it in Settings, Edit profile, '
          'then come back — the match is built on both Moon positions.');
      return;
    }
    if (_dob == null) {
      setState(() => _error = 'Pick their date of birth.');
      return;
    }
    if (_tob == null) {
      setState(() => _error =
          'Pick their time of birth. A guessed time moves the Moon, which is '
          'the whole basis of the match.');
      return;
    }
    if (_placePick == null) {
      final typed = _place.text.trim();
      setState(() => _error = typed.isEmpty
          ? 'Pick their place of birth.'
          : 'Choose a place from the suggestions — "$typed" has not been '
              'matched to a real location yet.');
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
      partnerBirthDate: _dobText,
      partnerBirthTime: _tobText,
      partnerPlace: _placePick!.displayName,
      partnerLat: _placePick!.lat,
      partnerLon: _placePick!.lon,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r == null) {
        _result = null;
        _error =
            'Could not reach the server. Check your connection and try again.';
      } else if (r['error'] != null) {
        _result = null;
        _error = _humanError(r['error'].toString());
      } else {
        _result = r;
        _error = null;
      }
    });
  }

  /// The server's rejections are accurate but written for a log, not for
  /// someone holding a phone.
  String _humanError(String raw) {
    final e = raw.toLowerCase();
    if (e.contains('date and time')) {
      return 'One of the two birth times is missing. Check your own profile '
          'under Settings, Edit profile.';
    }
    if (e.contains('place') || e.contains('lat')) {
      return 'That place could not be located. Try picking a larger nearby '
          'town from the suggestions.';
    }
    if (e.contains('chart calculation')) {
      return 'That date and time could not be turned into a chart. Check the '
          'year is right.';
    }
    if (e.startsWith('http_429')) {
      return 'You have run a lot of matches just now. Give it a minute.';
    }
    if (e.startsWith('http_')) {
      return 'The server could not complete the match. Please try again.';
    }
    return 'Could not read that match. Please try again.';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      locale: const Locale('en', 'IN'),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.purpleAccent,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
          dialogTheme:
              const DialogThemeData(backgroundColor: AppColors.surface),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _error = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _tob ?? const TimeOfDay(hour: 6, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.purpleAccent,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _tob = picked;
        _error = null;
      });
    }
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
        _picker(
          label: 'Date of birth',
          value: _dobText,
          placeholder: 'Select their date of birth',
          icon: Icons.calendar_today_outlined,
          onTap: _pickDate,
        ),
        _picker(
          label: 'Time of birth',
          value: _tob == null ? '' : _tob!.format(context),
          placeholder: 'Select their time of birth',
          icon: Icons.access_time_outlined,
          onTap: _pickTime,
        ),
        // Same autocomplete the profile screen uses. onSelected is what
        // makes this validated rather than decorative: it is the only way
        // _placePick gets set, so a half-typed city cannot be submitted.
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text('Place of birth',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ),
              LocationAutocompleteField(
                controller: _place,
                hintText: 'Search city, town or village',
                // Editing after a pick invalidates it. Without this, a
                // user could select "Patna", add " Bihar" to the text and
                // submit coordinates that no longer match what they see.
                onChanged: (_) {
                  if (_placePick != null) setState(() => _placePick = null);
                },
                onSelected: (s) => setState(() {
                  _placePick = s;
                  _error = null;
                }),
              ),
              if (_placePick != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Color(0xFF22C55E), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _placePick!.secondary.isNotEmpty
                              ? '${_placePick!.primary}, ${_placePick!.secondary}'
                              : _placePick!.primary,
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
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

  /// A read-only row that opens a picker. Matches the profile screen's
  /// date/time rows so the two forms do not feel like different apps.
  Widget _picker({
    required String label,
    required String value,
    required String placeholder,
    required IconData icon,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(label,
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: value.isNotEmpty
                      ? Border.all(
                          color: AppColors.purpleAccent.withOpacity(0.3))
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(icon, color: AppColors.textMuted, size: 19),
                    const SizedBox(width: 12),
                    Text(
                      value.isNotEmpty ? value : placeholder,
                      style: TextStyle(
                        color: value.isNotEmpty
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

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
            // Clear the partner out too. Leaving the previous person's
            // date, time and place in the form while the heading says
            // "Who are you checking?" invites a match run against a
            // half-replaced set of details.
            _name.clear();
            _place.clear();
            _dob = null;
            _tob = null;
            _placePick = null;
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
