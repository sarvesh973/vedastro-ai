import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../providers/providers.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import 'subscription_screen.dart';
import 'delete_account_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final isPremium = StorageService.isPremium;
    final chatUsed = StorageService.chatQuestionsUsed;
    final palmUsed = StorageService.palmReadingsUsed;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Card
            if (profile != null)
              _buildProfileCard(context, ref, profile)
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.1, end: 0, duration: 500.ms)
            else
              _buildNoProfileCard(context)
                  .animate()
                  .fadeIn(duration: 500.ms),

            const SizedBox(height: 24),

            // Premium Status
            _buildSectionTitle('Subscription'),
            const SizedBox(height: 8),
            _buildPremiumCard(context, isPremium)
                .animate()
                .fadeIn(duration: 500.ms, delay: 200.ms),

            const SizedBox(height: 24),

            // Usage Stats
            _buildSectionTitle('Usage'),
            const SizedBox(height: 8),
            _buildUsageCard(chatUsed, palmUsed, isPremium)
                .animate()
                .fadeIn(duration: 500.ms, delay: 300.ms),

            const SizedBox(height: 24),

            // App Info
            _buildSectionTitle('About'),
            const SizedBox(height: 8),
            _buildInfoTile(
              icon: Icons.info_outline,
              title: 'App Version',
              subtitle: 'v1.1.0 (Phase 3)',
              onTap: null,
            ).animate().fadeIn(duration: 500.ms, delay: 400.ms),

            _buildInfoTile(
              icon: Icons.menu_book_outlined,
              title: 'Knowledge Base',
              subtitle: 'BPHS, Phaladeepika, Brighu Sanhita',
              onTap: null,
            ).animate().fadeIn(duration: 500.ms, delay: 450.ms),

            _buildInfoTile(
              icon: Icons.star_outline,
              title: 'Rate Us',
              subtitle: 'Coming soon on Play Store',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Play Store listing coming soon!'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ).animate().fadeIn(duration: 500.ms, delay: 500.ms),

            _buildInfoTile(
              icon: Icons.share_outlined,
              title: 'Share App',
              subtitle: 'Tell your friends about VedAstro AI',
              onTap: () => _handleShare(context),
            ).animate().fadeIn(duration: 500.ms, delay: 550.ms),

            const SizedBox(height: 24),

            // ─── Subscription management ─────────────────────────
            _buildSectionTitle('Subscription'),
            const SizedBox(height: 8),
            _buildInfoTile(
              icon: Icons.card_membership_outlined,
              title: 'Manage Subscription',
              subtitle: 'View plan, cancel anytime',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const SubscriptionScreen()),
                );
              },
            ).animate().fadeIn(duration: 500.ms, delay: 600.ms),

            const SizedBox(height: 24),

            // ─── Account ─────────────────────────────────────────
            _buildSectionTitle('Account'),
            const SizedBox(height: 8),
            _buildInfoTile(
              icon: Icons.person_remove_outlined,
              title: 'Delete Account',
              subtitle: 'Permanently delete your data',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const DeleteAccountScreen()),
                );
              },
            ).animate().fadeIn(duration: 500.ms, delay: 650.ms),

            const SizedBox(height: 16),

            // Logout
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _handleLogout(context, ref),
                icon: const Icon(Icons.logout, color: AppColors.error, size: 20),
                label: const Text(
                  'Logout',
                  style: TextStyle(color: AppColors.error, fontSize: 15),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: AppColors.error.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            )
                .animate()
                .fadeIn(duration: 500.ms, delay: 600.ms),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, WidgetRef ref, dynamic profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.purpleAccent.withOpacity(0.15),
            AppColors.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.purpleAccent.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.purpleAccent, AppColors.purpleSoft],
                  ),
                ),
                child: Center(
                  child: Text(
                    profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name.isNotEmpty ? profile.name : 'User',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      StorageService.userEmail ?? '',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _profileRow('Date of Birth', profile.dobFormatted),
                if (profile.timeOfBirth != null && profile.timeOfBirth!.isNotEmpty)
                  _profileRow('Time of Birth', profile.timeOfBirth!),
                _profileRow('Place of Birth', profile.placeOfBirth),
                _profileRow('Western Sign', profile.westernSign),
                _profileRow('Vedic Sign', profile.sunSign),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(profile: profile),
                  ),
                );
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit Profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.purpleLight,
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: AppColors.purpleAccent.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildNoProfileCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Icon(Icons.person_outline, size: 48, color: AppColors.textMuted.withOpacity(0.5)),
          const SizedBox(height: 12),
          const Text(
            'No profile saved yet',
            style: TextStyle(color: AppColors.textMuted, fontSize: 15),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start a chat to create your profile',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumCard(BuildContext context, bool isPremium) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: isPremium
            ? LinearGradient(colors: [
                const Color(0xFF1A1530),
                AppColors.goldLight.withOpacity(0.1),
              ])
            : null,
        color: isPremium ? null : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPremium ? AppColors.gold.withOpacity(0.4) : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPremium
                  ? AppColors.gold.withOpacity(0.2)
                  : AppColors.surfaceLight,
            ),
            child: Icon(
              isPremium ? Icons.workspace_premium : Icons.lock_outline,
              color: isPremium ? AppColors.goldLight : AppColors.textMuted,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPremium ? 'Premium Active' : 'Free Plan',
                  style: TextStyle(
                    color: isPremium ? AppColors.goldLight : AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isPremium ? 'Unlimited access to all features' : 'Limited free questions',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageCard(int chatUsed, int palmUsed, bool isPremium) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _usageRow(
            'Chat Questions',
            isPremium ? 'Unlimited' : '$chatUsed / ${StorageService.freeChatLimit}',
            chatUsed / StorageService.freeChatLimit,
            isPremium,
          ),
          const SizedBox(height: 14),
          _usageRow(
            'Palm Readings',
            isPremium ? 'Unlimited' : '$palmUsed / ${StorageService.freePalmLimit}',
            palmUsed / StorageService.freePalmLimit,
            isPremium,
          ),
        ],
      ),
    );
  }

  Widget _usageRow(String label, String value, double progress, bool isPremium) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
        if (!isPremium) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: AppColors.surfaceLight,
              valueColor: AlwaysStoppedAnimation(
                progress >= 1.0 ? AppColors.error : AppColors.purpleAccent,
              ),
              minHeight: 5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider.withOpacity(0.5)),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.textMuted, size: 22),
        title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        trailing: onTap != null
            ? const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20)
            : null,
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  /// Share the app via the system share sheet (WhatsApp, Gmail, SMS, etc).
  /// Uses share_plus 10.x API. Key changes from the original broken version:
  ///  1. Actually awaits Share.share() so errors surface instead of silently failing
  ///  2. Provides sharePositionOrigin (no-op on Android, required on iPad)
  ///  3. Catches exceptions and shows a snackbar if the share sheet can't open
  ///  4. AndroidManifest now has ACTION_SEND intent queries so Android 11+ can
  ///     actually enumerate apps like WhatsApp/Gmail in the share chooser.
  Future<void> _handleShare(BuildContext context) async {
    // Once on Play Store, replace this URL with the actual Play Store link.
    const message =
        'Check out VedAstro AI — a personalized Vedic astrology app with daily horoscope, palm reading, and AI guru chat.\n\nhttps://github.com/sarvesh973/vedastro-ai';

    try {
      final box = context.findRenderObject() as RenderBox?;
      await Share.share(
        message,
        subject: 'VedAstro AI',
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open share sheet: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _handleLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Logout', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Are you sure you want to logout? You can sign back in anytime with the same email to get your profile back.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Firebase + Google sign out (revokes token, forces picker next time)
              await AuthService.signOut();
              // Nuke local cache so the next user (different email) starts clean
              await StorageService.clearAllLocalData();
              // Clear Riverpod state so UI doesn't briefly flash old profile
              ref.read(userProfileProvider.notifier).state = null;
              ref.read(chatMessagesProvider.notifier).clear();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              }
            },
            child: const Text('Logout', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
