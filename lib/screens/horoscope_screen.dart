import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';
import '../services/ai_service.dart';

class HoroscopeScreen extends ConsumerStatefulWidget {
  const HoroscopeScreen({super.key});

  @override
  ConsumerState<HoroscopeScreen> createState() => _HoroscopeScreenState();
}

class _HoroscopeScreenState extends ConsumerState<HoroscopeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _horoscopeData;
  bool _isLoading = true;
  String _currentPeriod = 'daily';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final periods = ['daily', 'tomorrow', 'weekly', 'monthly'];
        _currentPeriod = periods[_tabController.index];
        _loadHoroscope();
      }
    });
    _loadHoroscope();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHoroscope() async {
    final profile = ref.read(userProfileProvider);
    if (profile == null) return;

    setState(() => _isLoading = true);

    final data = await AiService.getHoroscope(
      profile: profile,
      period: _currentPeriod,
    );

    if (mounted) {
      setState(() {
        _horoscopeData = data;
        _isLoading = false;
      });
    }
  }

  String _getDateLabel() {
    final now = DateTime.now();
    switch (_currentPeriod) {
      case 'daily':
        return DateFormat('EEEE, d MMMM yyyy').format(now);
      case 'tomorrow':
        final tomorrow = now.add(const Duration(days: 1));
        return DateFormat('EEEE, d MMMM yyyy').format(tomorrow);
      case 'weekly':
        final weekStart = now.subtract(Duration(days: now.weekday % 7));
        final weekEnd = weekStart.add(const Duration(days: 6));
        return '${DateFormat('d MMM').format(weekStart)} - ${DateFormat('d MMM yyyy').format(weekEnd)}';
      case 'monthly':
        return DateFormat('MMMM yyyy').format(now);
      default:
        return '';
    }
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
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: 'Today'),
                  Tab(text: 'Tomorrow'),
                  Tab(text: 'Weekly'),
                  Tab(text: 'Monthly'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _horoscopeData == null
              ? _buildErrorState()
              : _buildHoroscopeContent(sign),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: AppColors.purpleAccent,
            strokeWidth: 2.5,
          ),
          SizedBox(height: 16),
          Text(
            'Reading the stars...',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 16),
          const Text('Could not load horoscope',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
          const SizedBox(height: 12),
          TextButton(onPressed: _loadHoroscope, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildHoroscopeContent(String sign) {
    final zodiacEmoji = _getZodiacEmoji(sign);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // Sign header with date and star rating
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
              border: Border.all(color: AppColors.purpleAccent.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Text(zodiacEmoji, style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  sign,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                // Date label
                Text(
                  _getDateLabel(),
                  style: TextStyle(
                    color: AppColors.textMuted.withOpacity(0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final rating = (_horoscopeData?['rating'] as int?) ?? 4;
                    return Icon(
                      i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: AppColors.goldLight,
                      size: 24,
                    );
                  }),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .scaleXY(begin: 0.95, end: 1.0, duration: 500.ms),

          const SizedBox(height: 16),

          // Overall
          _buildCategoryCard(
            icon: Icons.auto_awesome,
            title: 'Overall',
            color: AppColors.purpleAccent,
            prediction: _horoscopeData?['overall'] ?? '',
            delay: 100,
          ),
          const SizedBox(height: 12),

          // Love
          _buildCategoryCard(
            icon: Icons.favorite_outline,
            title: 'Love & Relationships',
            color: const Color(0xFFE91E63),
            prediction: _horoscopeData?['love'] ?? '',
            delay: 200,
          ),
          const SizedBox(height: 12),

          // Career
          _buildCategoryCard(
            icon: Icons.work_outline,
            title: 'Career & Finance',
            color: AppColors.goldLight,
            prediction: _horoscopeData?['career'] ?? '',
            delay: 350,
          ),
          const SizedBox(height: 12),

          // Health
          _buildCategoryCard(
            icon: Icons.health_and_safety_outlined,
            title: 'Health & Wellness',
            color: AppColors.success,
            prediction: _horoscopeData?['health'] ?? '',
            delay: 500,
          ),
          const SizedBox(height: 16),

          // Lucky elements
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lucky Elements',
                  style: TextStyle(
                    color: AppColors.goldLight,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _buildLuckyItem('\u{1F522}', 'Number',
                        '${_horoscopeData?['luckyNumber'] ?? 7}'),
                    _buildLuckyItem('\u{1F3A8}', 'Color',
                        _horoscopeData?['luckyColor'] ?? 'Yellow'),
                    _buildLuckyItem('\u{1F4C5}', 'Day',
                        _horoscopeData?['luckyDay'] ?? 'Thursday'),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(duration: 500.ms, delay: 650.ms),

          // References footer — subtle list of cited Vedic texts.
          // Shown only when the AI response included a 'sources' field.
          if ((_horoscopeData?['sources'] as String?)?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.divider.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'References',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (_horoscopeData?['sources'] as String).trim(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 500.ms, delay: 700.ms),
          ],

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

  Widget _buildLuckyItem(String emoji, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
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
}
