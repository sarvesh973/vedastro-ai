import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';

/// Text field that suggests real-world places as the user types — like
/// Uber / Ola / Swiggy. Uses the OpenStreetMap Nominatim API (free, no
/// API key, ~1 req/sec limit per IP — we debounce client-side so we
/// stay well under).
///
/// Why Nominatim:
///   • No API key, no billing setup, no quota tier games
///   • Decent coverage of small Indian towns (Gopalganj, Muzaffarpur,
///     Phalodi, etc.) — better than Google Places' free tier for
///     remote villages
///   • OSM Foundation policy: max 1 request per second, descriptive
///     User-Agent required, attribution recommended
///
/// Callback contract:
///   onChanged(text)             — text mutated (typing or selection)
///   onSelected(suggestion)      — user picked one of the dropdown rows;
///                                 caller can read .lat/.lon/.displayName
///                                 to short-circuit server-side geocoding
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
  final _layerLink = LayerLink();
  final _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  Timer? _debounce;
  List<LocationSuggestion> _suggestions = [];
  bool _loading = false;

  // Last query we sent to Nominatim. Used to discard out-of-order responses
  // (e.g. user types "del", "delh", "delhi" rapidly and the "del" response
  // comes back last — we don't want it overwriting suggestions for "delhi").
  String _lastQuery = '';

  // Suppress fetching once when the user just picked a suggestion. Without
  // this, programmatically writing the selected text back into the
  // controller would re-trigger a search and re-open the dropdown.
  bool _suppressNextFetch = false;

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
    _hideOverlay();
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
      setState(() {
        _suggestions = [];
        _loading = false;
      });
      _hideOverlay();
      return;
    }

    setState(() => _loading = true);
    _showOverlay(); // show loading state immediately

    // 400ms debounce — fast enough to feel responsive, slow enough to
    // skip every keystroke.
    _debounce = Timer(const Duration(milliseconds: 400), () => _fetch(text));
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // Defer so a tap on a dropdown row registers before the overlay closes.
      Future.delayed(const Duration(milliseconds: 150), _hideOverlay);
    } else if (_suggestions.isNotEmpty || _loading) {
      _showOverlay();
    }
  }

  Future<void> _fetch(String query) async {
    _lastQuery = query;
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(query)}'
        '&format=json'
        '&addressdetails=1'
        '&limit=6',
      );

      final resp = await http.get(
        uri,
        // Nominatim usage policy: a descriptive User-Agent is mandatory.
        headers: {'User-Agent': 'MokshaApp/1.0 (vedic astrology)'},
      ).timeout(const Duration(seconds: 8));

      if (query != _lastQuery || !mounted) return; // stale, skip

      if (resp.statusCode != 200) {
        setState(() {
          _suggestions = [];
          _loading = false;
        });
        _showOverlay();
        return;
      }

      final List<dynamic> raw = jsonDecode(resp.body) as List<dynamic>;
      final list = raw
          .map((j) => LocationSuggestion.fromNominatim(j as Map<String, dynamic>))
          .where((s) => s.primary.isNotEmpty)
          .toList();

      setState(() {
        _suggestions = list;
        _loading = false;
      });
      _showOverlay();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suggestions = [];
        _loading = false;
      });
      _showOverlay();
    }
  }

  void _showOverlay() {
    _hideOverlay();
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 12,
            color: Colors.transparent,
            child: _buildDropdown(),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onSuggestionTapped(LocationSuggestion s) {
    _suppressNextFetch = true;

    // Cancel any pending/in-flight search. Without this, a network
    // request started by earlier typing can complete a moment AFTER the
    // tap and call _showOverlay() again — re-opening the dropdown so the
    // selection looks like it "didn't take" and the user has to leave the
    // screen to dismiss it.
    //   - cancel the debounce timer (kills a not-yet-fired fetch)
    //   - set _lastQuery to the selected text so any ALREADY in-flight
    //     fetch fails its `query != _lastQuery` staleness check on return
    //   - clear suggestions + loading so the focus-regain path can't
    //     repopulate the overlay either
    _debounce?.cancel();
    _lastQuery = s.primary;
    setState(() {
      _suggestions = [];
      _loading = false;
    });

    widget.controller.text = s.primary;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: s.primary.length),
    );
    widget.onSelected?.call(s);
    _hideOverlay();
    _focusNode.unfocus();
  }

  Widget _buildDropdown() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.purpleAccent.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: Icon(widget.prefixIcon,
              color: AppColors.textMuted, size: 20),
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

/// One Nominatim suggestion: a place name + its coordinates + the
/// hierarchical context (state + country).
///
/// The lat/lon comes back from the geocoder for free, so callers can
/// store them with the user profile and skip the server's geocode round-trip
/// when the user submits.
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
    final primary = (addr['village'] ?? addr['town'] ?? addr['city'] ??
            addr['municipality'] ?? addr['suburb'] ?? addr['county'] ??
            json['name'] ?? '')
        .toString();
    final state = (addr['state'] ?? addr['region'] ?? '').toString();
    final country = (addr['country'] ?? '').toString();
    final secondary = [state, country].where((s) => s.isNotEmpty).join(', ');

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
