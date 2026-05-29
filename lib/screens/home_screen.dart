import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../widgets/starfield_background.dart';
import '../widgets/shooting_star_overlay.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../providers/providers.dart';
import 'user_details_screen.dart';
import 'chat_screen.dart';
import 'palm_upload_screen.dart';
import 'kundli_screen.dart';
import 'settings_screen.dart';
import 'horoscope_screen.dart';
import 'paywall_screen.dart';
import 'legal_screen.dart';
import 'subscription_screen.dart';
import '../models/subscription_plan.dart';
import '../models/subscription_status.dart';
import '../models/user_profile.dart';
import '../theme/m_page_route.dart';
import '../widgets/moksha_wordmark_image.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  double _overscrollAmount = 0.0;

  // Tracks which bottom-nav item the user just pushed into. -1 = none
  // active (sitting on home). Glow persists on that button while the
  // pushed screen is up, fades back when the user pops to home.
  int _activeNavIndex = -1;

  // Daily Vibe card state — 3 short snippets pulled from today's
  // horoscope. Cached aggressively (AiService.getHoroscope already
  // checks SharedPreferences first) so this is effectively instant
  // after the first launch of the day.
  List<String>? _dailyVibePoints;
  bool _dailyVibeLoading = false;

  // Rotates daily by day-of-year. Same fact for the full 24h so users
  // who reopen the app don't see it shuffle on every launch.
  static const List<String> _astroFacts = [
    'The 12 zodiac signs originated from Babylonian astronomers around 500 BCE.',
    'Vedic astrology uses 27 nakshatras (lunar mansions) instead of just 12 signs.',
    'Your Vedic Moon sign is often considered more revealing than your Sun sign.',
    'Brihat Parashara Hora Shastra is the foundational text of Vedic astrology.',
    "Mercury 'retrograde' is an optical illusion — the planet only appears to move backward.",
    'Saturn (Shani) takes ~29.5 years to orbit the Sun — once per "Saturn return".',
    'Jupiter expands wherever it sits in your chart — career, love, knowledge.',
    'A nakshatra is 13°20\' of the zodiac — the Moon transits one each day.',
    "Rahu and Ketu are 'shadow planets' — lunar nodes where eclipses occur.",
    'Mangal Dosha is a Mars placement believed to affect marriage compatibility.',
    'The word "zodiac" comes from the Greek "zōidiakos" — "circle of little animals".',
    "Your rising sign (Lagna) changes every ~2 hours — that's why birth time matters.",
    'Sade Sati is Saturn\'s 7.5-year transit affecting your Moon — a major life chapter.',
    'Venus rules both Taurus and Libra — earth grounding + air harmony.',
    'The Sun spends about 30 days in each tropical zodiac sign.',
    'Vedic charts use the sidereal zodiac, ~23° offset from the Western tropical one.',
    'Dasha periods (planetary time cycles) span up to 20 years for a single planet.',
    'A perfect "Raj Yoga" placement is said to confer royal-level success and fame.',
    'The Moon governs the mind in Vedic astrology — emotions, instincts, mother.',
    "Mars in the 7th house in Vedic tradition is 'Manglik' — often discussed in matchmaking.",
    'Astronomy and astrology were the same science until ~17th-century Europe.',
    'Each nakshatra has a ruling deity, planet, and symbol shaping its meaning.',
    "Ashlesha nakshatra is known as 'the entwiner' — intensity, intuition, transformation.",
    'The full Moon amplifies emotions because it fully reflects solar energy.',
    'Vedic astrology classifies you into one of 9 planetary "mahadashas" at birth.',
    'A solar return chart maps the year ahead from your exact birthday moment.',
    'The Lunar New Year aligns with the Sun-Moon conjunction in your birth nakshatra.',
    'Kuja (Mars) gives drive; Shukra (Venus) gives charm — both shape relationships.',
    'Your 10th house describes career; the 4th house describes home and roots.',
    'Eclipses in Vedic tradition mark karmic turning points — never to be ignored.',
    'The 7-day week mirrors the 7 visible "planets" of antiquity, each ruling a day.',
    'Brihaspati (Jupiter) is the guru of the gods — he teaches the cosmic order.',
    'Your Janma Nakshatra is the constellation the Moon was in when you were born.',
    'Aries to Pisces forms an arc from raw initiation to spiritual completion.',
    'Vedic gemstones are prescribed to strengthen weak or supportive planets.',
    'A "kundli" is your full natal chart — planets mapped to 12 houses at birth.',
    'Pluto wasn\'t known until 1930 — Vedic astrology was complete without it.',
    'Each planet rules a body part — Sun: heart; Moon: lungs; Mars: blood; etc.',
    'Saturn rewards patience and discipline more than any other planet.',
    'Your strongest planet (atmakaraka) reveals your soul\'s deepest mission.',
  ];

  String _factOfTheDay() {
    final now = DateTime.now();
    final dayOfYear =
        now.difference(DateTime(now.year, 1, 1)).inDays;
    return _astroFacts[dayOfYear % _astroFacts.length];
  }

  @override
  void initState() {
    super.initState();
    // Kick off the daily vibe load after first frame so build() returns
    // immediately. AiService.getHoroscope() will hit the local cache
    // first (instant if cached today) before calling the server.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDailyVibe();
    });
  }

  Future<void> _loadDailyVibe() async {
    final profile = ref.read(userProfileProvider);
    if (profile == null || _dailyVibeLoading) return;
    setState(() => _dailyVibeLoading = true);
    try {
      final data = await AiService.getHoroscope(
        profile: profile,
        period: 'daily',
      );
      if (!mounted) return;
      if (data != null) {
        // Pull 3 short snippets from the horoscope shape. Server returns
        // a richer object (overall/love/career/health). We pick 3 with
        // labels and truncate each to the first sentence so the card
        // reads as bite-sized "today's vibe" hits, not paragraphs.
        final picks = <String>[];
        for (final key in ['overall', 'career', 'love', 'health']) {
          final v = data[key];
          if (v is String && v.trim().isNotEmpty) {
            picks.add(_shortPoint(v));
            if (picks.length == 3) break;
          }
        }
        if (picks.isNotEmpty) {
          setState(() => _dailyVibePoints = picks);
        }
      }
    } catch (_) {
      // Silent — card just keeps showing the shimmer/placeholder.
    } finally {
      if (mounted) setState(() => _dailyVibeLoading = false);
    }
  }

  /// Short bullet point — punchy, no explanations. Reads as a clean
  /// thought, not a paragraph fragment. Strategy:
  ///   1. Try first sentence (.!?) — ideal stop.
  ///   2. If no sentence break in first 70 chars, stop at last
  ///      comma before 60 chars — preserves clause integrity.
  ///   3. If neither works, hard-trim at last word boundary
  ///      under 55 chars so we never cut mid-word.
  /// Drops em-dashes per user preference.
  String _shortPoint(String raw) {
    final clean = raw.replaceAll('—', ',').replaceAll('–', ',').trim();

    // Strategy 1: first sentence end
    final dotIdx = clean.indexOf(RegExp(r'[.!?]'));
    if (dotIdx > 10 && dotIdx < 70) {
      return clean.substring(0, dotIdx).trim();
    }

    // Strategy 2: last comma before 60 chars (clean clause boundary)
    if (clean.length > 55) {
      final head = clean.substring(0, clean.length > 60 ? 60 : clean.length);
      final lastComma = head.lastIndexOf(',');
      if (lastComma > 18) {
        return head.substring(0, lastComma).trim();
      }
    }

    // Strategy 3: hard trim at last word boundary under 55
    if (clean.length > 55) {
      final cut = clean.substring(0, 55);
      final lastSpace = cut.lastIndexOf(' ');
      return (lastSpace > 30 ? cut.substring(0, lastSpace) : cut).trim();
    }
    return clean;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);

    // Load saved profile on first build
    if (profile == null && StorageService.currentProfile != null) {
      Future.microtask(() {
        ref.read(userProfileProvider.notifier).state =
            StorageService.currentProfile;
      });
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(context),
      // Fixed bottom rail — primary feature destinations (Kundli /
      // Palm / Horoscope) reachable from anywhere in the home flow.
      bottomNavigationBar: _buildBottomNav(context),
      extendBody: true,
      body: StarfieldBackground(
        child: SafeArea(
          child: Stack(
            children: [
              // Shooting star — fires every 12s. Sits behind the content
              // (first child of the Stack) so it never blocks taps and
              // never covers UI.
              const Positioned.fill(
                child: IgnorePointer(child: ShootingStarOverlay()),
              ),

              // Hidden "Made in India" — revealed on overscroll
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: (_overscrollAmount / 50.0).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.85 + 0.15 * (_overscrollAmount / 50.0).clamp(0.0, 1.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Made in India ',
                          style: TextStyle(
                            color: AppColors.textMuted.withOpacity(0.6),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Text(
                          '\uD83C\uDDEE\uD83C\uDDF3',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Main scrollable content
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  final overscroll = notification.metrics.pixels -
                      notification.metrics.maxScrollExtent;
                  final clamped = overscroll.clamp(0.0, 60.0);
                  if (clamped != _overscrollAmount) {
                    setState(() => _overscrollAmount = clamped);
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                    const SizedBox(height: 8),

                    // Top bar: hamburger + profiles + greeting
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Hamburger menu
                        GestureDetector(
                          onTap: () {
                            _scaffoldKey.currentState?.openDrawer();
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.surfaceLight,
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: const Icon(
                              Icons.menu_rounded,
                              color: AppColors.textSecondary,
                              size: 22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Profile switcher (takes remaining space)
                        Expanded(
                          child: _buildProfileSwitcher(context, ref),
                        ),
                        // Greeting on right
                        if (profile != null) ...[
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _getGreeting(),
                                style: const TextStyle(
                                  color: AppColors.goldLight,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                profile.name.split(' ').first,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    )
                        .animate()
                        .fadeIn(duration: 500.ms),

                    const SizedBox(height: 28),

                    // Brand hero — Moksha wordmark sits on its own now
                    // (AI sparkle logo removed per user request, the
                    // wordmark IS the brand). Sun-sign chip ("sunshine
                    // bar") sits flush beneath as a single identity unit.
                    const MokshaWordmarkImage(
                      widthFactor: 0.78,
                      crop: 0.34,
                    )
                        .animate()
                        .fadeIn(duration: 700.ms, delay: 200.ms)
                        .slideY(
                          begin: 0.2,
                          end: 0,
                          duration: 700.ms,
                          delay: 200.ms,
                        ),

                    // Sun-sign chip locked to the wordmark — no breathing
                    // room, deliberate (it's part of the identity block).
                    if (profile != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.goldLight.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.goldLight.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wb_sunny_outlined,
                                color: AppColors.goldLight, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${profile.westernSign} (Vedic: ${profile.sunSign})',
                              style: const TextStyle(
                                color: AppColors.goldLight,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 500.ms, delay: 500.ms),
                    ],

                    const SizedBox(height: 18),

                    // Hero "Astrology Chat" bar — the headline action,
                    // gets the premium purple→gold gradient treatment.
                    // Replaces the old 2x2 grid; Kundli / Palm /
                    // Horoscope now live in the fixed bottom nav.
                    _buildChatHeroBar(context, profile)
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 600.ms)
                        .slideY(
                          begin: 0.15,
                          end: 0,
                          duration: 600.ms,
                          delay: 600.ms,
                        ),

                    const SizedBox(height: 18),

                    // Daily Vibe card — 3 short snippets from today's
                    // horoscope, tappable to open the full horoscope
                    // screen. Cool gold-glow border, drifting stars,
                    // rotating zodiac glyph in the corner. Replaces the
                    // old Did-You-Know card.
                    _buildDailyVibeCard(context),

                    // Email verification banner — only renders for
                    // email/password users with unverified addresses.
                    // No-op widget otherwise (zero layout impact).
                    _buildEmailVerificationBanner(context),

                    // Premium banner
                    _buildPremiumBanner(context, ref)
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 950.ms)
                        .slideY(begin: 0.15, end: 0, duration: 600.ms, delay: 950.ms),

                    const SizedBox(height: 24),

                    // Indian Vedic Wisdom tagline
                    Text(
                      'Indian Vedic Wisdom',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.goldLight.withOpacity(0.7),
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        height: 1.4,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 800.ms, delay: 1000.ms),

                    const SizedBox(height: 8),

                    // Sub-text
                    Text(
                      'Based on Brihat Parashara Hora Shastra\n& Phaladeepika',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textMuted.withOpacity(0.6),
                                fontSize: 11,
                                height: 1.5,
                              ),
                    )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 1100.ms),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSwitcher(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(familyProfilesProvider);
    final activeIndex = ref.watch(activeProfileIndexProvider);

    return SizedBox(
      height: 68,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: profiles.length + 1, // +1 for "Add" button
        itemBuilder: (context, index) {
                if (index == profiles.length) {
                  // Add profile button
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          _buildPageRoute(const UserDetailsScreen()),
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.surfaceLight,
                              border: Border.all(
                                color: AppColors.divider,
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.add,
                              color: AppColors.textMuted,
                              size: 22,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Add',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final p = profiles[index];
                final isActive = index == activeIndex;
                final initials = p.name.isNotEmpty
                    ? p.name.substring(0, p.name.length >= 2 ? 2 : 1).toUpperCase()
                    : '?';

                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () async {
                      await StorageService.switchToProfile(index);
                      ref.read(userProfileProvider.notifier).state =
                          StorageService.currentProfile;
                      ref.read(activeProfileIndexProvider.notifier).state = index;
                      // Clear chat when switching profiles
                      ref.read(chatMessagesProvider.notifier).clear();
                    },
                    onLongPress: () {
                      if (profiles.length > 1) {
                        _showDeleteProfileDialog(context, ref, index, p.name);
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: isActive
                                ? const LinearGradient(
                                    colors: [AppColors.purpleAccent, AppColors.purpleSoft],
                                  )
                                : null,
                            color: isActive ? null : AppColors.surfaceLight,
                            border: Border.all(
                              color: isActive
                                  ? AppColors.purpleAccent
                                  : AppColors.divider,
                              width: isActive ? 2 : 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: TextStyle(
                                color: isActive
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 56,
                          child: Text(
                            p.name.isNotEmpty
                                ? p.name.split(' ').first
                                : 'Profile',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive
                                  ? AppColors.textPrimary
                                  : AppColors.textMuted,
                              fontSize: 10,
                              fontWeight:
                                  isActive ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
      ),
    );
  }

  void _showDeleteProfileDialog(
      BuildContext context, WidgetRef ref, int index, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Remove Profile',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Remove $name from your family profiles?',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageService.removeFamilyProfile(index);
              ref.read(familyProfilesProvider.notifier).state =
                  List.from(StorageService.familyProfiles);
              ref.read(activeProfileIndexProvider.notifier).state =
                  StorageService.activeProfileIndex;
              ref.read(userProfileProvider.notifier).state =
                  StorageService.currentProfile;
              ref.read(chatMessagesProvider.notifier).clear();
            },
            child: const Text('Remove',
                style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.purpleAccent.withOpacity(0.15),
                    AppColors.background,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.purpleAccent.withOpacity(0.3),
                          AppColors.purpleAccent.withOpacity(0.05),
                        ],
                      ),
                      border: Border.all(
                        color: AppColors.purpleAccent.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: AppColors.goldLight,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Moksha',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'align with dharma, awaken the soul',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            Container(height: 1, color: AppColors.divider),

            const SizedBox(height: 8),

            // Menu items
            //
            // Plan-aware premium row. Mirrors the home banner's logic so the
            // user always sees their specific tier (Trial / Standard / Premium)
            // and can tap to upgrade if a higher tier exists. Premium users
            // (no upgrades left) are routed to the Subscription screen so
            // they can manage / cancel.
            Builder(
              builder: (context) {
                final isPremium = StorageService.isPremium;
                final localPlanId = StorageService.lastPurchasedPlan;
                final localPlan = localPlanId == null
                    ? null
                    : SubscriptionPlanInfo.fromId(localPlanId);
                final upgradeOptions = localPlan?.upgradeOptions ?? const [];
                final canUpgrade = isPremium && upgradeOptions.isNotEmpty;

                String label;
                if (!isPremium) {
                  label = 'Upgrade to Premium';
                } else if (localPlan == null || localPlan == SubscriptionPlan.free) {
                  label = 'Subscription Active';
                } else {
                  label = '${localPlan.displayName} — Active';
                }

                return _buildDrawerItem(
                  icon: Icons.workspace_premium,
                  label: label,
                  color: AppColors.goldLight,
                  onTap: () {
                    Navigator.pop(context);
                    if (!isPremium) {
                      Navigator.of(context).push(
                        _buildPageRoute(const PaywallScreen()),
                      );
                    } else if (canUpgrade) {
                      _openUpgradePaywall(context, upgradeOptions);
                    } else {
                      Navigator.of(context).push(
                        _buildPageRoute(const SubscriptionScreen()),
                      );
                    }
                  },
                );
              },
            ),

            _buildDrawerItem(
              icon: Icons.feedback_outlined,
              label: 'Feedback',
              onTap: () {
                Navigator.pop(context);
                _showFeedbackDialog(context);
              },
            ),

            _buildDrawerItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  _buildPageRoute(const SettingsScreen()),
                );
              },
            ),

            _buildDrawerItem(
              icon: Icons.shield_outlined,
              label: 'Legal',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  _buildPageRoute(const LegalScreen()),
                );
              },
            ),

            const Spacer(),

            // App version at bottom
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'v1.1.0',
                style: TextStyle(
                  color: AppColors.textMuted.withOpacity(0.4),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.textSecondary, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: color ?? AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      // Subtle selection-click on every drawer tap so the menu feels
      // physical. ~5ms haptic, no UX cost on devices that don't support
      // haptics (Android skips it silently).
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  void _showFeedbackDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Send Feedback',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tell us what you think or report a bug',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 4,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Your feedback...',
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: AppColors.purpleAccent, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please write something first'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              // Save to Firestore 'feedback' collection
              // Viewable at Firebase Console -> Firestore -> feedback
              final ok = await FirestoreService.saveFeedback(text: text);
              controller.dispose();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? 'Thanks! Your feedback has been sent.'
                      : 'Could not send. Please check your internet.'),
                  backgroundColor:
                      ok ? AppColors.success : AppColors.error,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            child: const Text('Send',
                style: TextStyle(color: AppColors.purpleLight)),
          ),
        ],
      ),
    );
  }

  void _openUpgradePaywall(BuildContext context, List<SubscriptionPlan> options) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            PaywallScreen(availablePlans: options),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  /// "Did You Know?" daily astrology fact. Sits between the chat bar
  /// and the subscription banner — visible to all users, free or paid,
  /// every day. Picked by day-of-year so it stays stable across the
  /// day but feels fresh on a new visit.
  /// Daily Vibe card — 3 short snippets from today's horoscope.
  /// Tappable to open the full horoscope screen. Loaded async via
  /// _loadDailyVibe(); shows shimmer rows until data lands.
  ///
  /// Dark, minimal aesthetic. No rotating sun, no drifting stars —
  /// the card should read as a quiet ritual, not a casino. Deep
  /// charcoal surface with a thin gold accent stroke on the left edge
  /// and a single small gold dot per bullet. One subtle fade-in on
  /// mount and nothing else animates.
  Widget _buildDailyVibeCard(BuildContext context) {
    final points = _dailyVibePoints;
    final isReady = points != null && points.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(
            _buildPageRoute(const HoroscopeScreen()),
          );
        },
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            // Deep charcoal with the faintest warm tint — sits dark
            // against the starfield without going black, picks up
            // a whisper of gold so it feels intentional not flat.
            color: const Color(0xFF0E0D14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.gold.withOpacity(0.14),
              width: 0.6,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left gold accent stripe — single deliberate stroke,
              // does all the visual identity work on this card.
              Container(
                width: 2.5,
                margin: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.gold.withOpacity(0.0),
                      AppColors.goldLight.withOpacity(0.85),
                      AppColors.gold.withOpacity(0.0),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header — label only, no icon, no date. Just
                      // type. Chevron on the right hints tappability.
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              "TODAY'S COSMIC MOOD",
                              style: TextStyle(
                                color: AppColors.goldLight.withOpacity(0.78),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2.2,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: AppColors.goldLight.withOpacity(0.55),
                            size: 14,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // 3 points — punchy bullets, no explanations.
                      if (isReady)
                        ...List.generate(points.length, (i) {
                          return Padding(
                            padding: EdgeInsets.only(
                                bottom: i == points.length - 1 ? 0 : 9),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 7),
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        AppColors.goldLight.withOpacity(0.85),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    points[i],
                                    style: TextStyle(
                                      color: AppColors.textPrimary
                                          .withOpacity(0.88),
                                      fontSize: 13.5,
                                      height: 1.4,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        })
                      else
                        // Shimmer placeholder while loading. Stays dark.
                        Column(
                          children: List.generate(3, (i) {
                            return Padding(
                              padding:
                                  EdgeInsets.only(bottom: i == 2 ? 0 : 9),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 7),
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.goldLight
                                          .withOpacity(0.35),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Container(
                                      height: 10,
                                      width: i == 1 ? 200 : double.infinity,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.06),
                                        borderRadius:
                                            BorderRadius.circular(5),
                                      ),
                                    )
                                        .animate(onPlay: (c) => c.repeat())
                                        .shimmer(
                                          duration: 1800.ms,
                                          color: AppColors.goldLight
                                              .withOpacity(0.14),
                                        ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 700.ms, delay: 750.ms);
  }

  Widget _buildDidYouKnowCard() {
    final fact = _factOfTheDay();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.purpleAccent.withOpacity(0.16),
              AppColors.gold.withOpacity(0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withOpacity(0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.goldLight.withOpacity(0.18),
                  ),
                  child: const Icon(Icons.lightbulb_outline,
                      color: AppColors.goldLight, size: 16),
                ),
                const SizedBox(width: 10),
                Text(
                  'Did You Know?',
                  style: TextStyle(
                    color: AppColors.goldLight,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                Text(
                  'Daily fact',
                  style: TextStyle(
                    color: AppColors.textMuted.withOpacity(0.7),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              fact,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 600.ms, delay: 850.ms).slideY(
            begin: 0.12,
            end: 0,
            duration: 600.ms,
            delay: 850.ms,
          ),
    );
  }

  /// Soft-gate banner shown to email/password users until they click
  /// the verification link. Tappable to resend; updates in place when
  /// the user reports having verified.
  Widget _buildEmailVerificationBanner(BuildContext context) {
    if (!AuthService.needsEmailVerification) return const SizedBox.shrink();

    Future<void> handleResend() async {
      final result = await AuthService.sendVerificationEmail();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success
              ? 'Verification email sent — check your inbox.'
              : (result.error ?? 'Could not send.')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    Future<void> handleVerified() async {
      final verified = await AuthService.refreshEmailVerificationStatus();
      if (!context.mounted) return;
      if (verified) {
        // Force a rebuild — the banner's own visibility check will
        // remove it now that needsEmailVerification is false.
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email verified — thanks!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "We still don't see a verification. Tap the link in the email, then try again."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.gold.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.gold.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mark_email_unread_outlined,
                    color: AppColors.goldLight, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Verify your email',
                    style: const TextStyle(
                      color: AppColors.goldLight,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "We sent a link to ${AuthService.userEmail ?? 'your inbox'}. "
              "You need to verify before you can subscribe.",
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: handleVerified,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text("I've verified",
                      style: TextStyle(
                          color: AppColors.goldLight, fontSize: 13)),
                ),
                TextButton(
                  onPressed: handleResend,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Resend',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumBanner(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider);
    final chatsUsed = ref.watch(chatQuestionsUsedProvider);
    final palmsUsed = ref.watch(palmReadingsUsedProvider);

    if (isPremium) {
      // Active subscriber banner. Wrapped in a StreamBuilder so the
      // banner reflects state changes in real time — in particular the
      // 'cancelledPending' flip needs to land on Home immediately, even
      // though isPremium stays true through the paid-up period.
      return StreamBuilder<SubscriptionStatus>(
        stream: FirestoreService.subscriptionStream(),
        builder: (context, snap) {
          final sub = snap.data;
          final isCancelled =
              sub?.state == SubscriptionState.cancelledPending;
          final periodEnds = sub?.currentPeriodEndsAt;

          final localPlanId = StorageService.lastPurchasedPlan;
          final localPlan = localPlanId == null
              ? null
              : SubscriptionPlanInfo.fromId(localPlanId);
          // Upgrade options are based on the user's plan tier — not
          // suppressed by cancellation. A cancelled-trial user who taps
          // the banner clearly wants to upgrade/resubscribe, not be
          // routed to a passive management screen.
          final upgradeOptions = localPlan?.upgradeOptions ?? const [];
          final canUpgrade = upgradeOptions.isNotEmpty;

          final String headlineText;
          if (isCancelled) {
            headlineText = (localPlan != null && localPlan != SubscriptionPlan.free)
                ? '${localPlan.displayName} — Cancelled'
                : 'Subscription Cancelled';
          } else if (localPlan == null || localPlan == SubscriptionPlan.free) {
            headlineText = 'Subscription Active';
          } else {
            headlineText = '${localPlan.displayName} — Active';
          }

          final String subText;
          if (isCancelled) {
            subText = periodEnds != null
                ? 'Access until ${periodEnds.day}/${periodEnds.month}/${periodEnds.year}'
                : 'Access until your paid period ends';
          } else if (canUpgrade) {
            subText = 'Tap to upgrade your plan';
          } else {
            subText = 'Unlimited access to all features';
          }

      final activeBanner = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.gold.withOpacity(0.15),
              AppColors.gold.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withOpacity(0.2),
              ),
              child: const Icon(Icons.workspace_premium, color: AppColors.goldLight, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headlineText,
                    style: const TextStyle(
                      color: AppColors.goldLight,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subText,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              canUpgrade ? Icons.chevron_right : Icons.check_circle,
              color: canUpgrade ? AppColors.goldLight : AppColors.success,
              size: 22,
            ),
          ],
        ),
      );

      // Banner is always tappable. Where it leads depends on state:
      //  - canUpgrade (e.g. Trial / Standard with higher tiers available)
      //    -> Paywall pre-filtered to those tiers
      //  - cancelled OR top-tier active -> Subscription screen so the
      //    user can manage / cancel / see the cancellation timeline.
      final VoidCallback onTap = canUpgrade
          ? () => _openUpgradePaywall(context, upgradeOptions)
          : () => Navigator.of(context).push(
                _buildPageRoute(const SubscriptionScreen()),
              );

      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: activeBanner,
        ),
      );
        },
      );
    }

    // Free tier — show upgrade banner with usage
    final chatsLeft = StorageService.freeChatLimit - chatsUsed;
    final palmsLeft = StorageService.freePalmLimit - palmsUsed;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const PaywallScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.purpleAccent.withOpacity(0.15),
              AppColors.gold.withOpacity(0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.gold.withOpacity(0.3),
                        AppColors.purpleAccent.withOpacity(0.2),
                      ],
                    ),
                  ),
                  child: const Icon(Icons.workspace_premium, color: AppColors.goldLight, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Upgrade to Premium',
                        style: TextStyle(
                          color: AppColors.goldLight,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Unlimited chats, palm readings & more',
                        style: TextStyle(color: AppColors.textMuted.withOpacity(0.8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.gold, AppColors.goldLight],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'PRO',
                    style: TextStyle(
                      color: AppColors.background,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Usage indicators
            Row(
              children: [
                Expanded(
                  child: _usageIndicator(
                    'Chats',
                    chatsUsed,
                    StorageService.freeChatLimit,
                    chatsLeft <= 1,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _usageIndicator(
                    'Palm Reads',
                    palmsUsed,
                    StorageService.freePalmLimit,
                    palmsLeft <= 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _usageIndicator(String label, int used, int total, bool isLow) {
    final progress = (used / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            Text(
              '$used/$total used',
              style: TextStyle(
                color: isLow ? AppColors.error : AppColors.textMuted,
                fontSize: 11,
                fontWeight: isLow ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: AppColors.surfaceLight,
            valueColor: AlwaysStoppedAnimation<Color>(
              isLow ? AppColors.error : AppColors.purpleAccent,
            ),
          ),
        ),
      ],
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  /// Full-width "Astrology Chat" hero bar that sits under the rashi
  /// badge. Two-color gradient (purple → gold) so the headline action
  /// reads as premium even at a glance. Tapping it navigates to
  /// chat (after enforcing profile completion).
  Widget _buildChatHeroBar(BuildContext context, UserProfile? profile) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        splashColor: AppColors.gold.withValues(alpha: 0.15),
        highlightColor: AppColors.purpleAccent.withValues(alpha: 0.05),
        onTap: () {
          HapticFeedback.selectionClick();
          if (profile != null) {
            Navigator.of(context)
                .push(_buildPageRoute(const ChatScreen()));
          } else {
            Navigator.of(context)
                .push(_buildPageRoute(const UserDetailsScreen()));
          }
        },
        child: Container(
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFF6D28D9), // purple-soft (left)
                Color(0xFF7C3AED), // purple-accent (mid)
                Color(0xFFD4A574), // gold (right)
              ],
              stops: [0.0, 0.55, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.purpleAccent.withValues(alpha: 0.35),
                blurRadius: 22,
                spreadRadius: 1,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.18),
                blurRadius: 26,
                spreadRadius: 1,
                offset: const Offset(6, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon medallion with frosted white tint over the gradient
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.18),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.32), width: 1),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Astrology Chat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ask anything about your chart',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.22),
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fixed bottom navigation bar pinned to the home Scaffold. Three
  /// destinations: Kundli, Palm, Horoscope. These were the lower three
  /// tiles of the old 2×2 grid — promoting them to the bottom rail
  /// makes them reachable from anywhere in the home flow with one
  /// thumb tap.
  Widget _buildBottomNav(BuildContext context) {
    // Frosted glass bar — BackdropFilter blurs whatever is behind
    // (scroll content, starfield, etc.). A thin tinted overlay (8%
    // alpha) gives the bar just enough body to read against bright
    // content without feeling boxed. Top hairline (subtle gold edge)
    // gives a soft visual handoff so the bar doesn't float weirdly.
    //
    // Active button (whichever screen the user is currently inside)
    // gets a glowing gold pill behind its icon + label. Inactive
    // buttons are plain icon + label, no chip.
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.08),
            border: Border(
              top: BorderSide(
                color: AppColors.gold.withValues(alpha: 0.18),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: SizedBox(
                height: 70,
                child: Row(
                  children: [
                    _bottomNavItem(
                      index: 0,
                      icon: Icons.auto_awesome_mosaic_outlined,
                      label: 'Kundli',
                      destination: const KundliScreen(),
                    ),
                    _bottomNavItem(
                      index: 1,
                      icon: Icons.back_hand_outlined,
                      label: 'Palm',
                      destination: const PalmUploadScreen(),
                    ),
                    _bottomNavItem(
                      index: 2,
                      icon: Icons.stars_outlined,
                      label: 'Horoscope',
                      destination: const HoroscopeScreen(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomNavItem({
    required int index,
    required IconData icon,
    required String label,
    required Widget destination,
  }) {
    const tone = AppColors.goldLight;
    final isActive = _activeNavIndex == index;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          splashColor: tone.withValues(alpha: 0.18),
          highlightColor: tone.withValues(alpha: 0.08),
          onTap: () async {
            HapticFeedback.selectionClick();
            // Set this item active, push the screen, clear when popped.
            // setState is safe here — we own the state class.
            setState(() => _activeNavIndex = index);
            await Navigator.of(context).push(_buildPageRoute(destination));
            if (mounted) {
              setState(() => _activeNavIndex = -1);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: isActive
                  ? tone.withValues(alpha: 0.20)
                  : Colors.transparent,
              border: isActive
                  ? Border.all(color: tone.withValues(alpha: 0.45), width: 1)
                  : Border.all(color: Colors.transparent, width: 1),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: tone.withValues(alpha: 0.35),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: tone.withValues(alpha: isActive ? 1.0 : 0.78),
                  size: 22,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: tone.withValues(alpha: isActive ? 1.0 : 0.78),
                    fontSize: 11.5,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required int delay,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.15),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(
            duration: 500.ms, delay: Duration(milliseconds: delay))
        .slideY(
            begin: 0.2,
            end: 0,
            duration: 500.ms,
            delay: Duration(milliseconds: delay));
  }

  // Now delegates to the shared MPageRoute so all drawer + feature
  // navigation gets the same theme transitions as the rest of the app.
  PageRoute _buildPageRoute(Widget page) =>
      MPageRoute(page: page, transition: MTransition.push);
}
