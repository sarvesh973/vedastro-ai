import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';

/// Text field that suggests real-world places as the user types — like
/// Uber / Ola / Swiggy. Uses the OpenStreetMap Nominatim API (free, no
/// API key, ~1 req/sec — we debounce client-side so we stay well under).
///
/// IMPLEMENTATION NOTE — inline list, NOT a floating overlay.
/// An earlier version rendered the dropdown in an `OverlayEntry`. That
/// caused a stubborn bug: tapping a suggestion filled the field but the
/// dropdown wouldn't dismiss (overlay lifecycle races). This version
/// renders the suggestion list as an ordinary widget directly below the
/// text field. The list is purely a function of the `_suggestions` array:
/// clear the array + setState and it is gone — "dropdown won't close" is
/// structurally impossible.
///
/// Public API is unchanged, so the screens that embed it need no edits.
class LocationAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final void Function(String text)? onChanged;
  final void Function(LocationSuggestion suggestion)? onSelected;

  const LocationAutocompleteField({
    super.key,
    required this.controller,
    this.hintText = 'Enter city, town or village',
    this.prefixIcon = Icons.location_on_outlined,
    this.onChanged,
    this.onSelected,
  });

  @override
  State<LocationAutocompleteField> createState() =>
      _LocationAutocompleteFieldState();
}

class _LocationAutocompleteFieldState extends State<LocationAutocompleteField> {
  final _focusNode = FocusNode();
  Timer? _debounce;

  List<LocationSuggestion> _suggestions = [];
  bool _loading = false;
  bool _noResults = false; // last search completed with zero matches

  // Last query sent to Nominatim — used to discard out-of-order responses
  // (type "del", "delh", "delhi" fast; the "del" response must not
  // overwrite suggestions meant for "delhi").
  String _lastQuery = '';

  // Set true right before we programmatically write the selected place
  // back into the controller, so the controller listener doesn't treat
  // that write as the user typing and kick off a fresh search.
  bool _suppressNextFetch = false;

  bool get _panelVisible => _loading || _suggestions.isNotEmpty || _noResults;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    widget.onChanged?.call(text);

    if (_suppressNextFetch) {
      _suppressNextFetch = false;
      return;
    }

    _debounce?.cancel();

    if (text.trim().length < 3) {
      if (_panelVisible) {
        setState(() {
          _suggestions = [];
          _loading = false;
          _noResults = false;
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _noResults = false;
    });

    // 400ms debounce — responsive but skips every keystroke.
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _fetch(text.trim()),
    );
  }

  void _onFocusChanged() {
    // When the field loses focus, tidy the panel away — but only after a
    // short delay so a tap currently landing on a suggestion still
    // registers first. (With an inline list the tap would register
    // anyway, but the delay keeps the panel from flickering shut under
    // the user's finger.)
    if (!_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted || _focusNode.hasFocus) return;
        if (_panelVisible) {
          setState(() {
            _suggestions = [];
            _loading = false;
            _noResults = false;
          });
        }
      });
    }
  }

  Future<void> _fetch(String query) async {
    _lastQuery = query;
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(query)}'
        '&format=json&addressdetails=1&limit=6',
      );
      final resp = await http.get(
        uri,
        // Nominatim usage policy: a descriptive User-Agent is mandatory.
        headers: {'User-Agent': 'MokshaApp/1.0 (vedic astrology)'},
      ).timeout(const Duration(seconds: 8));

      // Stale response (user kept typing) or widget gone — discard.
      if (query != _lastQuery || !mounted) return;

      if (resp.statusCode != 200) {
        setState(() {
          _suggestions = [];
          _loading = false;
          _noResults = true;
        });
        return;
      }

      final raw = jsonDecode(resp.body) as List<dynamic>;
      final list = raw
          .map((j) =>
              LocationSuggestion.fromNominatim(j as Map<String, dynamic>))
          .where((s) => s.primary.isNotEmpty)
          .toList();

      setState(() {
        _suggestions = list;
        _loading = false;
        _noResults = list.isEmpty;
      });
    } catch (_) {
      if (!mounted || query != _lastQuery) return;
      setState(() {
        _suggestions = [];
        _loading = false;
        _noResults = true;
      });
    }
  }

  void _onSuggestionTapped(LocationSuggestion s) {
    _debounce?.cancel();
    _suppressNextFetch = true;
    _lastQuery = s.primary; // any in-flight fetch becomes stale + is dropped

    widget.controller.text = s.primary;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: s.primary.length),
    );
    widget.onSelected?.call(s);

    // Clear the panel — it's just a function of these fields, so this
    // makes the suggestion list vanish immediately and for good.
    setState(() {
      _suggestions = [];
      _loading = false;
      _noResults = false;
    });
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon:
                Icon(widget.prefixIcon, color: AppColors.textMuted, size: 20),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                : null,
          ),
        ),
        if (_panelVisible) ...[
          const SizedBox(height: 6),
          _buildPanel(),
        ],
      ],
    );
  }

  Widget _buildPanel() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.purpleAccent.withValues(alpha: 0.3),
        ),
      ),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.purpleAccent,
                  ),
                ),
              ),
            )
          : _suggestions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  child: Text(
                    'No matches — keep typing or check spelling',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: AppColors.divider.withValues(alpha: 0.5),
                  ),
                  itemBuilder: (_, i) => _SuggestionTile(
                    suggestion: _suggestions[i],
                    onTap: () => _onSuggestionTapped(_suggestions[i]),
                  ),
                ),
    );
  }
}

// ─── Suggestion tile ───────────────────────────────────────────────────

class _SuggestionTile extends StatelessWidget {
  final LocationSuggestion suggestion;
  final VoidCallback onTap;

  const _SuggestionTile({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.purpleAccent.withValues(alpha: 0.12),
              ),
              child: const Icon(
                Icons.place_outlined,
                color: AppColors.purpleLight,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.primary,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (suggestion.secondary.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      suggestion.secondary,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Data model ────────────────────────────────────────────────────────

/// One Nominatim suggestion: a place name + coordinates + region context.
/// lat/lon come back for free, so callers can store them and skip the
/// server's geocode round-trip when the user picks a suggestion.
class LocationSuggestion {
  /// Short city name, e.g. "Gopalganj"
  final String primary;

  /// Region context, e.g. "Bihar, India"
  final String secondary;

  /// Full Nominatim display_name for fallback rendering
  final String displayName;

  /// Geographic centroid of the place
  final double lat;
  final double lon;

  /// Two-letter ISO country code (lowercase), useful for timezone lookup
  final String? countryCode;

  const LocationSuggestion({
    required this.primary,
    required this.secondary,
    required this.displayName,
    required this.lat,
    required this.lon,
    this.countryCode,
  });

  factory LocationSuggestion.fromNominatim(Map<String, dynamic> json) {
    final addr = (json['address'] as Map<String, dynamic>?) ?? const {};
    // Prefer the most-specific name first — village > town > city > county.
    final primary = (addr['village'] ??
            addr['town'] ??
            addr['city'] ??
            addr['municipality'] ??
            addr['suburb'] ??
            addr['county'] ??
            json['name'] ??
            '')
        .toString();
    final state = (addr['state'] ?? addr['region'] ?? '').toString();
    final country = (addr['country'] ?? '').toString();
    final secondary =
        [state, country].where((s) => s.isNotEmpty).join(', ');

    return LocationSuggestion(
      primary: primary,
      secondary: secondary,
      displayName: (json['display_name'] ?? '').toString(),
      lat: double.tryParse((json['lat'] ?? '0').toString()) ?? 0,
      lon: double.tryParse((json['lon'] ?? '0').toString()) ?? 0,
      countryCode: (addr['country_code'] as String?)?.toLowerCase(),
    );
  }
}
