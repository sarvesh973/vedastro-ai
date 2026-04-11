import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';

class HoroscopeScreen extends ConsumerStatefulWidget {
  const HoroscopeScreen({super.key});

  @override
  ConsumerState<HoroscopeScreen> createState() => _HoroscopeScreenState();
}

class _HoroscopeScreenState extends ConsumerState<HoroscopeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final sign = profile?.westernSign ?? 'Aries';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Horoscope'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            children: [
              Container(height: 1, color: AppColors.divider),
              TabBar(
                controller: _tabController,
                indicatorColor: AppColors.purpleAccent,
                indicatorWeight: 3,
                labelColor: AppColors.purpleLight,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: 'Daily'),
                  Tab(text: 'Weekly'),
                  Tab(text: 'Monthly'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHoroscopeTab(sign, 'daily'),
          _buildHoroscopeTab(sign, 'weekly'),
          _buildHoroscopeTab(sign, 'monthly'),
        ],
      ),
    );
  }

  Widget _buildHoroscopeTab(String sign, String period) {
    final zodiacEmoji = _getZodiacEmoji(sign);
    final periodLabel = period == 'daily'
        ? 'Today'
        : period == 'weekly'
            ? 'This Week'
            : 'This Month';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // Sign header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.purpleAccent.withOpacity(0.15),
                  AppColors.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.purpleAccent.withOpacity(0.2),
              ),
            ),
            child: Column(
              children: [
                Text(
                  zodiacEmoji,
                  style: const TextStyle(fontSize: 48),
                ),
                const SizedBox(height: 12),
                Text(
                  sign,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  periodLabel,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .scaleXY(begin: 0.95, end: 1.0, duration: 500.ms),

          const SizedBox(height: 20),

          // Horoscope categories
          _buildCategoryCard(
            icon: Icons.favorite_outline,
            title: 'Love & Relationships',
            color: const Color(0xFFE91E63),
            prediction: _getPrediction(sign, period, 'love'),
            delay: 200,
          ),

          const SizedBox(height: 12),

          _buildCategoryCard(
            icon: Icons.work_outline,
            title: 'Career & Finance',
            color: AppColors.goldLight,
            prediction: _getPrediction(sign, period, 'career'),
            delay: 350,
          ),

          const SizedBox(height: 12),

          _buildCategoryCard(
            icon: Icons.health_and_safety_outlined,
            title: 'Health & Wellness',
            color: AppColors.success,
            prediction: _getPrediction(sign, period, 'health'),
            delay: 500,
          ),

          const SizedBox(height: 12),

          _buildCategoryCard(
            icon: Icons.auto_awesome_outlined,
            title: 'Lucky Elements',
            color: AppColors.purpleLight,
            prediction: _getLuckyElements(sign, period),
            delay: 650,
          ),

          const SizedBox(height: 24),

          // Coming soon note
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.goldLight.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.goldLight.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: AppColors.goldLight.withOpacity(0.7),
                  size: 18,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'AI-powered personalized predictions coming soon',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 800.ms),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCategoryCard({
    required IconData icon,
    required String title,
    required Color color,
    required String prediction,
    required int delay,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.15),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            prediction,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 500.ms, delay: Duration(milliseconds: delay))
        .slideY(
          begin: 0.1,
          end: 0,
          duration: 500.ms,
          delay: Duration(milliseconds: delay),
        );
  }

  String _getZodiacEmoji(String sign) {
    const emojis = {
      'Aries': '\u2648',
      'Taurus': '\u2649',
      'Gemini': '\u264A',
      'Cancer': '\u264B',
      'Leo': '\u264C',
      'Virgo': '\u264D',
      'Libra': '\u264E',
      'Scorpio': '\u264F',
      'Sagittarius': '\u2650',
      'Capricorn': '\u2651',
      'Aquarius': '\u2652',
      'Pisces': '\u2653',
    };
    return emojis[sign] ?? '\u2728';
  }

  String _getPrediction(String sign, String period, String category) {
    if (category == 'love') {
      if (period == 'daily') {
        return 'Venus is influencing your relationship sector today. Express your feelings openly and listen to your partner with empathy. Singles may find an unexpected connection.';
      } else if (period == 'weekly') {
        return 'This week brings warmth to your relationships. The planetary alignment encourages deeper bonds. Mid-week is ideal for important conversations with loved ones.';
      } else {
        return 'This month favors romantic growth. The stars encourage you to strengthen existing bonds and remain open to new connections. Communication is your greatest asset.';
      }
    } else if (category == 'career') {
      if (period == 'daily') {
        return 'Mercury supports clear thinking at work today. A good day to present ideas and negotiate deals. Financial decisions made today will have positive outcomes.';
      } else if (period == 'weekly') {
        return 'Professional growth is highlighted this week. Jupiter brings expansion opportunities. Stay focused on your goals and avoid distractions mid-week.';
      } else {
        return 'Career prospects look strong this month. Saturn rewards discipline and hard work. A promotion or new opportunity may arise in the second half of the month.';
      }
    } else {
      if (period == 'daily') {
        return 'Focus on rest and hydration today. The Moon suggests a calm routine will benefit your energy. Evening walks or light yoga are recommended.';
      } else if (period == 'weekly') {
        return 'Your energy levels fluctuate this week. Prioritize sleep and balanced meals. Mid-week is ideal for starting a new fitness routine or wellness practice.';
      } else {
        return 'Health and wellness take center stage this month. The stars encourage you to build sustainable habits. Pay attention to your mental health alongside physical fitness.';
      }
    }
  }

  String _getLuckyElements(String sign, String period) {
    final day = DateTime.now().weekday;
    final colors = ['Red', 'Blue', 'Green', 'Yellow', 'Purple', 'White', 'Orange'];
    final numbers = [3, 7, 9, 11, 14, 18, 21];

    final luckyColor = colors[day % colors.length];
    final luckyNumber = numbers[day % numbers.length];

    if (period == 'daily') {
      return 'Lucky Color: $luckyColor\nLucky Number: $luckyNumber\nFavorable Direction: East';
    } else if (period == 'weekly') {
      return 'Lucky Colors: $luckyColor, ${colors[(day + 2) % colors.length]}\nLucky Numbers: $luckyNumber, ${numbers[(day + 3) % numbers.length]}\nBest Day: Wednesday';
    } else {
      return 'Lucky Colors: $luckyColor, ${colors[(day + 1) % colors.length]}, ${colors[(day + 3) % colors.length]}\nLucky Numbers: $luckyNumber, ${numbers[(day + 2) % numbers.length]}, ${numbers[(day + 4) % numbers.length]}\nFavorable Gem: Yellow Sapphire';
    }
  }
}
