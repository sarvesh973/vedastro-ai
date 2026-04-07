import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';
import '../widgets/kundli_chart.dart';
import '../models/user_profile.dart';
import 'user_details_screen.dart';

class KundliScreen extends ConsumerWidget {
  const KundliScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);

    if (profile == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Kundli Chart'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline, size: 56, color: AppColors.textMuted.withOpacity(0.4)),
              const SizedBox(height: 16),
              const Text(
                'Birth details needed',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your birth details to generate\nyour Kundli chart',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const UserDetailsScreen()),
                  );
                },
                child: const Text('Enter Details'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Kundli Chart'),
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
            // User info header
            _buildInfoHeader(profile)
                .animate()
                .fadeIn(duration: 500.ms)
                .slideY(begin: 0.1, end: 0, duration: 500.ms),

            const SizedBox(height: 24),

            // Kundli Chart
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.purpleAccent.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.purpleAccent.withOpacity(0.05),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'Rashi Kundli (Birth Chart)',
                    style: TextStyle(
                      color: AppColors.goldLight,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'North Indian Style',
                    style: TextStyle(
                      color: AppColors.textMuted.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: MediaQuery.of(context).size.width - 72,
                    child: KundliChart(
                      ascendantIndex: profile.approxAscendantIndex,
                      sunSignIndex: profile.sunSignIndex,
                    ),
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(duration: 600.ms, delay: 200.ms)
                .scaleXY(begin: 0.95, end: 1.0, duration: 600.ms, delay: 200.ms),

            const SizedBox(height: 24),

            // Legend
            _buildLegend()
                .animate()
                .fadeIn(duration: 500.ms, delay: 400.ms),

            const SizedBox(height: 24),

            // Details cards
            _buildDetailCards(profile)
                .animate()
                .fadeIn(duration: 500.ms, delay: 500.ms),

            const SizedBox(height: 16),

            // Disclaimer
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.textMuted.withOpacity(0.6), size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Approximate chart based on birth date & time. '
                      'For precise Kundli with all planet positions, '
                      'consult a professional Jyotishi.',
                      style: TextStyle(
                        color: AppColors.textMuted.withOpacity(0.7),
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(duration: 500.ms, delay: 600.ms),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoHeader(UserProfile profile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.purpleAccent.withOpacity(0.1),
            Colors.transparent,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.purpleAccent.withOpacity(0.2),
            ),
            child: const Icon(Icons.auto_awesome, color: AppColors.goldLight, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name.isNotEmpty ? profile.name : 'User',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${profile.dobFormatted} | ${profile.placeOfBirth}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                if (profile.timeOfBirth != null && profile.timeOfBirth!.isNotEmpty)
                  Text(
                    'Birth time: ${profile.timeOfBirth}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Chart Legend',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _legendItem('Asc', 'Ascendant (Lagna)', AppColors.goldLight),
              _legendItem('Su', 'Sun Position', AppColors.goldLight),
              _legendItem('1-12', 'House Numbers', AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Sign abbreviations: Me=Mesha, Vr=Vrishabha, Mi=Mithuna, '
            'Ka=Karka, Si=Simha, Kn=Kanya, Tu=Tula, Vs=Vrishchika, '
            'Dh=Dhanu, Mk=Makara, Ku=Kumbha, Mn=Meena',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String symbol, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(symbol, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ],
    );
  }

  Widget _buildDetailCards(UserProfile profile) {
    final signs = KundliChart.signsFull;
    final ascIndex = profile.approxAscendantIndex;
    final sunIndex = profile.sunSignIndex;

    return Column(
      children: [
        _detailCard(
          icon: Icons.home_outlined,
          title: 'Lagna (Ascendant)',
          value: signs[ascIndex],
          description: 'Your rising sign at the time of birth determines\nyour personality and physical appearance.',
          color: AppColors.goldLight,
        ),
        const SizedBox(height: 10),
        _detailCard(
          icon: Icons.wb_sunny_outlined,
          title: 'Surya Rashi (Sun Sign)',
          value: signs[sunIndex],
          description: 'Your Sun sign represents your soul, ego,\nand core identity as per Vedic astrology.',
          color: AppColors.gold,
        ),
        const SizedBox(height: 10),
        _detailCard(
          icon: Icons.auto_awesome,
          title: 'Sun in House',
          value: 'House ${((sunIndex - ascIndex + 12) % 12) + 1}',
          description: 'The house where Sun is placed shows where\nyou shine brightest in life.',
          color: AppColors.purpleLight,
        ),
      ],
    );
  }

  Widget _detailCard({
    required IconData icon,
    required String title,
    required String value,
    required String description,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
