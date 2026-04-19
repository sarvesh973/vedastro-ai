import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';
import '../widgets/result_card.dart';

class PalmResultScreen extends ConsumerWidget {
  const PalmResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(palmResultProvider);

    if (result == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Text(
            'No results available',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            backgroundColor: AppColors.background,
            floating: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () {
                // Pop back to home
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
            title: const Text('Palm Reading'),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 22),
                onPressed: () {
                  // Build shareable summary of the palm reading
                  final buf = StringBuffer();
                  buf.writeln('My VedAstro AI Palm Reading');
                  buf.writeln('');
                  for (final line in result.allLines) {
                    buf.writeln('${line.emoji} ${line.title}');
                    if (line.insight.isNotEmpty) buf.writeln(line.insight);
                    if (line.meaning.isNotEmpty) buf.writeln(line.meaning);
                    if (line.advice.isNotEmpty) {
                      buf.writeln('Advice: ${line.advice}');
                    }
                    buf.writeln('');
                  }
                  buf.writeln('Get yours at VedAstro AI:');
                  buf.writeln('https://github.com/sarvesh973/vedastro-ai');
                  Share.share(buf.toString(),
                      subject: 'My Palm Reading — VedAstro AI');
                },
              ),
              const SizedBox(width: 8),
            ],
          ),

          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.purpleAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.back_hand,
                          color: AppColors.purpleAccent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Palm Analysis',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Based on Samudrik Shastra',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  )
                      .animate()
                      .fadeIn(duration: 500.ms)
                      .slideX(begin: -0.1, end: 0, duration: 500.ms),
                ],
              ),
            ),
          ),

          // Result Cards
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final lines = result.allLines;
                  if (index >= lines.length) return null;
                  return ResultCard(
                    result: lines[index],
                    index: index,
                  );
                },
                childCount: result.allLines.length,
              ),
            ),
          ),

          // Bottom spacing
          const SliverToBoxAdapter(
            child: SizedBox(height: 32),
          ),

          // Disclaimer
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              child: Text(
                'This reading is for guidance and entertainment purposes.\nAlways trust your own intuition and wisdom.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted.withOpacity(0.5),
                  fontSize: 11,
                  height: 1.5,
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 800.ms),
            ),
          ),
        ],
      ),
    );
  }
}
