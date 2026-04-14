import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../widgets/starfield_background.dart';
import '../services/storage_service.dart';
import '../providers/providers.dart';
import 'user_details_screen.dart';
import 'chat_screen.dart';
import 'palm_upload_screen.dart';
import 'kundli_screen.dart';
import 'settings_screen.dart';
import 'horoscope_screen.dart';
import 'paywall_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  double _overscrollAmount = 0.0;

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
      body: StarfieldBackground(
        child: SafeArea(
          child: Stack(
            children: [
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

                    const SizedBox(height: 32),

                    // Logo / Icon
                    Container(
                      width: 100,
                      height: 100,
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
                        size: 44,
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

                    const SizedBox(height: 24),

                    // Title
                    Text(
                      'VedAstro AI',
                      style:
                          Theme.of(context).textTheme.displayLarge?.copyWith(
                                letterSpacing: 1,
                                color: AppColors.textPrimary,
                              ),
                    )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 200.ms)
                        .slideY(
                          begin: 0.2,
                          end: 0,
                          duration: 600.ms,
                          delay: 200.ms,
                        ),

                    const SizedBox(height: 8),

                    Text(
                      'Your personal Vedic astrologer',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textMuted,
                                fontSize: 15,
                                letterSpacing: 0.3,
                              ),
                    )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 400.ms),

                    // Sun sign badge (if profile exists)
                    if (profile != null) ...[
                      const SizedBox(height: 12),
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

                    const SizedBox(height: 32),

                    // Feature buttons grid
                    Row(
                      children: [
                        Expanded(
                          child: _buildFeatureCard(
                            context: context,
                            icon: Icons.chat_bubble_outline_rounded,
                            label: 'Astrology\nChat',
                            color: AppColors.purpleAccent,
                            delay: 600,
                            onTap: () {
                              if (profile != null) {
                                Navigator.of(context).push(
                                  _buildPageRoute(const ChatScreen()),
                                );
                              } else {
                                Navigator.of(context).push(
                                  _buildPageRoute(const UserDetailsScreen()),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildFeatureCard(
                            context: context,
                            icon: Icons.back_hand_outlined,
                            label: 'Palm\nReading',
                            color: AppColors.purpleSoft,
                            delay: 700,
                            onTap: () {
                              Navigator.of(context).push(
                                _buildPageRoute(const PalmUploadScreen()),
                              );
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _buildFeatureCard(
                            context: context,
                            icon: Icons.auto_awesome_mosaic_outlined,
                            label: 'Kundli\nChart',
                            color: AppColors.gold,
                            delay: 800,
                            onTap: () {
                              Navigator.of(context).push(
                                _buildPageRoute(const KundliScreen()),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildFeatureCard(
                            context: context,
                            icon: Icons.stars_outlined,
                            label: 'Daily\nHoroscope',
                            color: const Color(0xFFD4A574),
                            delay: 900,
                            onTap: () {
                              Navigator.of(context).push(
                                _buildPageRoute(const HoroscopeScreen()),
                              );
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

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
                    'VedAstro AI',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Vedic Astrology & AI',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            Container(height: 1, color: AppColors.divider),

            const SizedBox(height: 8),

            // Menu items
            _buildDrawerItem(
              icon: Icons.workspace_premium,
              label: StorageService.isPremium ? 'Premium (Active)' : 'Upgrade to Premium',
              color: AppColors.goldLight,
              onTap: () {
                Navigator.pop(context);
                if (!StorageService.isPremium) {
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
                }
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
      onTap: onTap,
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
            onPressed: () {
              Navigator.pop(ctx);
              controller.dispose();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      const Text('Thanks for your feedback!'),
                  backgroundColor: AppColors.success,
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

  Widget _buildPremiumBanner(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider);
    final chatsUsed = ref.watch(chatQuestionsUsedProvider);
    final palmsUsed = ref.watch(palmReadingsUsedProvider);

    if (isPremium) {
      // Premium active badge
      return Container(
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
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Premium Active',
                    style: TextStyle(
                      color: AppColors.goldLight,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Unlimited access to all features',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.check_circle, color: AppColors.success, size: 22),
          ],
        ),
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

  PageRouteBuilder _buildPageRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity:
              CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 400),
    );
  }
}
