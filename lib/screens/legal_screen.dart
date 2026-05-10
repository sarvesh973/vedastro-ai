import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import 'legal_document_screen.dart';
import '../theme/m_page_route.dart';
import '../widgets/cosmic_background.dart';

/// Hub screen reachable from the hamburger drawer's "Legal" entry.
/// Lists the three policy documents the app is required to surface
/// for Play Store + India DPDP / CCPA compliance:
///   - Privacy Policy
///   - Terms & Conditions
///   - Refund Policy
///
/// Each tile opens the actual document in [LegalDocumentScreen]. The
/// document content lives in `assets/legal/*.md` so updating a policy
/// is just an edit to the markdown file — no code change.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Legal'),
      ),
      body: CosmicBackground(
        intensity: CosmicIntensity.whisper,
        seed: 'legal',
        child: SafeArea(
          child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 4),
          Text(
            "These documents explain how Moksha handles your data, what "
            "you agree to by using the app, and the refund policy for "
            "subscriptions.",
            style: TextStyle(
              color: AppColors.textMuted.withOpacity(0.85),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _LegalTile(
            icon: Icons.shield_outlined,
            title: 'Privacy Policy',
            subtitle: 'What data we collect and how we use it',
            assetPath: 'assets/legal/privacy-policy.md',
            tone: AppColors.purpleLight,
          ).animate().fadeIn(duration: 400.ms).slideY(
                begin: 0.05,
                end: 0,
                duration: 400.ms,
              ),
          const SizedBox(height: 12),
          _LegalTile(
            icon: Icons.gavel_outlined,
            title: 'Terms & Conditions',
            subtitle: "What you agree to by using Moksha",
            assetPath: 'assets/legal/terms-of-service.md',
            tone: AppColors.goldLight,
          ).animate().fadeIn(duration: 400.ms, delay: 80.ms).slideY(
                begin: 0.05,
                end: 0,
                duration: 400.ms,
                delay: 80.ms,
              ),
          const SizedBox(height: 12),
          _LegalTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Refund Policy',
            subtitle: 'How cancellations and refunds work',
            assetPath: 'assets/legal/refund-policy.md',
            tone: AppColors.success,
          ).animate().fadeIn(duration: 400.ms, delay: 160.ms).slideY(
                begin: 0.05,
                end: 0,
                duration: 400.ms,
                delay: 160.ms,
              ),
          const SizedBox(height: 24),
          Text(
            "Need to contact us? Email support@vedastro.ai with your "
            "registered email and we'll get back within 24 hours.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted.withOpacity(0.6),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
        ),
      ),
    );
  }
}

class _LegalTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String assetPath;
  final Color tone;

  const _LegalTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.assetPath,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MPageRoute(
              page: LegalDocumentScreen(title: title, assetPath: assetPath),
              transition: MTransition.push,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tone.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withOpacity(0.15),
                ),
                child: Icon(icon, color: tone, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
