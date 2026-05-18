import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';
import '../services/storage_service.dart';
import '../widgets/starfield_background.dart';
import 'home_screen.dart';

/// Shown once during onboarding, right after the birth-details page.
/// The user picks the language Moksha speaks in — Pure English or
/// Hinglish — and that choice drives every AI surface: chat, kundli
/// insights, horoscope.
class LanguageSelectionScreen extends ConsumerStatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  ConsumerState<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState
    extends ConsumerState<LanguageSelectionScreen> {
  // Default highlighted choice = hinglish (India-first, matches prior
  // server behaviour). The user still taps Continue to confirm.
  String _selected = 'hinglish';

  Future<void> _continue() async {
    await StorageService.setLanguagePreference(_selected);
    ref.read(languageProvider.notifier).state = _selected;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 450),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: StarfieldBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),

                // ─── Heading ──────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.purpleAccent.withValues(alpha: 0.35),
                            AppColors.purpleAccent.withValues(alpha: 0.05),
                          ],
                        ),
                        border: Border.all(
                          color: AppColors.purpleAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Icon(Icons.translate_rounded,
                          color: AppColors.goldLight, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Choose your language',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                )
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: 0.15, end: 0, duration: 500.ms),

                const SizedBox(height: 10),

                Text(
                  'How should Moksha speak to you? This sets the language '
                  'for your chat, kundli readings and horoscope.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ).animate().fadeIn(duration: 500.ms, delay: 150.ms),

                const SizedBox(height: 32),

                // ─── Choice cards ────────────────────────────────
                _LanguageCard(
                  selected: _selected == 'english',
                  onTap: () => setState(() => _selected = 'english'),
                  icon: Icons.public_rounded,
                  title: 'Pure English',
                  subtitle: 'Clear, universal English throughout.',
                  sample:
                      'Your tenth house shows steady career growth this year.',
                  accent: AppColors.purpleLight,
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 300.ms)
                    .slideY(
                        begin: 0.1, end: 0, duration: 500.ms, delay: 300.ms),

                const SizedBox(height: 16),

                _LanguageCard(
                  selected: _selected == 'hinglish',
                  onTap: () => setState(() => _selected = 'hinglish'),
                  icon: Icons.chat_bubble_rounded,
                  title: 'Hinglish',
                  subtitle: 'Hindi + English mix, apnapan ke saath.',
                  sample:
                      'Aapke 10th house mein iss saal acchi career growth '
                      'dikh rahi hai.',
                  accent: AppColors.goldLight,
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 420.ms)
                    .slideY(
                        begin: 0.1, end: 0, duration: 500.ms, delay: 420.ms),

                const Spacer(),

                Center(
                  child: Text(
                    'You can change this later in Settings.',
                    style: TextStyle(
                      color: AppColors.textMuted.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ).animate().fadeIn(duration: 500.ms, delay: 600.ms),

                const SizedBox(height: 14),

                // ─── Continue ────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _continue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.purpleAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 680.ms)
                    .slideY(
                        begin: 0.2, end: 0, duration: 500.ms, delay: 680.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────

class _LanguageCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;
  final String sample;
  final Color accent;

  const _LanguageCard({
    required this.selected,
    required this.onTap,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.sample,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.16),
                    AppColors.surface.withValues(alpha: 0.4),
                  ],
                )
              : null,
          color: selected ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.75)
                : AppColors.divider.withValues(alpha: 0.6),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.18),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: selected ? 0.22 : 0.12),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                // Radio / check indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? accent : Colors.transparent,
                    border: Border.all(
                      color:
                          selected ? accent : AppColors.textMuted,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check,
                          size: 15, color: Color(0xFF1A1030))
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Sample-style preview chip — makes the choice tangible.
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.divider.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote_rounded,
                      color: accent.withValues(alpha: 0.7), size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sample,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.45,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
