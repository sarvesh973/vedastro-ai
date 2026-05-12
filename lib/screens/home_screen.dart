import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../widgets/starfield_background.dart';
import '../widgets/shooting_star_overlay.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
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

                    const SizedBox(height: 16),

                    // Brand hero cluster — AI logo + Moksha wordmark +
                    // sun-sign chip read as one unit. Gaps deliberately
                    // tight so they don't feel like separate components.
                    Container(
                      width: 88,
                      height: 88,
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
                        size: 40,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 800.ms)
                        .scaleXY(
                          begin: 0.8,
                          end: 1.0,
                          duration: 800.ms,
                          curve: Curves.easeOut,
                        ),

                    // Wordmark sits flush against the logo. Crop bumped
                    // tighter so the asset's transparent margin doesn't
                    // reintroduce phantom whitespace.
                    const MokshaWordmarkImage(
                      widthFactor: 0.72,
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

                    // Daily astrology fact. Rotates once a day so the
                    // home screen always has fresh content but doesn't
                    // shuffle on every app open.
                    _buildDidYouKnowCard(),

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
          // No upgrade pitch once cancellation is in motion — they
          // should let it lapse before resubscribing (mirrors the
          // Subscription screen behaviour).
          final upgradeOptions = isCancelled
              ? const <SubscriptionPlan>[]
              : (localPlan?.upgradeOptions ?? const []);
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

      if (!canUpgrade) return activeBanner;

      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openUpgradePaywall(context, upgradeOptions),
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
    // Single accent (goldLight) shared across all three actions — the
    // three are peer features, no hierarchy between them. Each icon
    // sits inside a tinted chip so the buttons read as solid, tappable
    // surfaces rather than thin glyphs.
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        height: 82,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.28),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.16),
              blurRadius: 22,
              spreadRadius: 1,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            _bottomNavItem(
              icon: Icons.auto_awesome_mosaic_outlined,
              label: 'Kundli',
              onTap: () => Navigator.of(context)
                  .push(_buildPageRoute(const KundliScreen())),
            ),
            _bottomNavItem(
              icon: Icons.back_hand_outlined,
              label: 'Palm',
              onTap: () => Navigator.of(context)
                  .push(_buildPageRoute(const PalmUploadScreen())),
            ),
            _bottomNavItem(
              icon: Icons.stars_outlined,
              label: 'Horoscope',
              onTap: () => Navigator.of(context)
                  .push(_buildPageRoute(const HoroscopeScreen())),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomNavItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    const tone = AppColors.goldLight;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          splashColor: tone.withValues(alpha: 0.18),
          highlightColor: tone.withValues(alpha: 0.08),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon chip — gives each item visual weight without
              // overloading the bar. Subtle border, gold tint inside.
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: 0.14),
                  border: Border.all(color: tone.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, color: tone, size: 20),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: const TextStyle(
                  color: tone,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
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
