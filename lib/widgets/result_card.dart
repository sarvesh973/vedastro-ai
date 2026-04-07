import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/palm_result.dart';

class ResultCard extends StatelessWidget {
  final PalmLineResult result;
  final int index;

  const ResultCard({
    super.key,
    required this.result,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.purpleAccent.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text(
                  result.emoji,
                  style: const TextStyle(fontSize: 28),
                ),
                const SizedBox(width: 12),
                Text(
                  result.title,
                  style: const TextStyle(
                    color: AppColors.goldLight,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Insight
            _buildSection(
              icon: '🔮',
              label: 'Insight',
              text: result.insight,
            ),

            const SizedBox(height: 14),

            // Meaning
            _buildSection(
              icon: '📖',
              label: 'Meaning',
              text: result.meaning,
            ),

            const SizedBox(height: 14),

            // Advice
            _buildSection(
              icon: '🧘',
              label: 'Advice',
              text: result.advice,
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(
          duration: 500.ms,
          delay: Duration(milliseconds: index * 200),
          curve: Curves.easeOut,
        )
        .slideY(
          begin: 0.15,
          end: 0,
          duration: 500.ms,
          delay: Duration(milliseconds: index * 200),
          curve: Curves.easeOut,
        );
  }

  Widget _buildSection({
    required String icon,
    required String label,
    required String text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$icon $label',
          style: TextStyle(
            color: AppColors.purpleLight.withOpacity(0.9),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14.5,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}
