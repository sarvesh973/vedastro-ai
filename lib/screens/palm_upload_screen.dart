import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';
import '../widgets/palm_guide_overlay.dart';
import 'palm_result_screen.dart';
import 'paywall_screen.dart';

class PalmUploadScreen extends ConsumerStatefulWidget {
  const PalmUploadScreen({super.key});

  @override
  ConsumerState<PalmUploadScreen> createState() => _PalmUploadScreenState();
}

class _PalmUploadScreenState extends ConsumerState<PalmUploadScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  bool _isAnalyzing = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    // Check free limit
    if (!StorageService.canDoPalmReading) {
      _showPaywall();
      return;
    }

    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isAnalyzing = true);
      ref.read(palmImagePathProvider.notifier).state = image.path;

      // Analyze palm
      final result = await AiService.analyzePalm(image.path);
      ref.read(palmResultProvider.notifier).state = result;

      await StorageService.incrementPalmReadings();
      ref.read(palmReadingsUsedProvider.notifier).state =
          StorageService.palmReadingsUsed;

      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const PalmResultScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurvedAnimation(
                    parent: animation, curve: Curves.easeInOut),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } catch (e) {
      setState(() => _isAnalyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showPaywall() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const PaywallScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Palm Reading'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: _isAnalyzing ? _buildAnalyzing() : _buildUploadUI(),
    );
  }

  Widget _buildAnalyzing() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated scanning effect with multiple rings
          SizedBox(
            width: 160,
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer ring
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.purpleAccent.withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .scaleXY(begin: 0.8, end: 1.3, duration: 2000.ms, curve: Curves.easeInOut)
                    .fadeOut(duration: 2000.ms),

                // Middle ring
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.goldLight.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .scaleXY(begin: 1.0, end: 1.4, duration: 1800.ms, curve: Curves.easeInOut)
                    .fadeOut(duration: 1800.ms),

                // Inner circle
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.purpleAccent.withOpacity(0.15),
                        AppColors.purpleAccent.withOpacity(0.05),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.back_hand_outlined,
                    size: 36,
                    color: AppColors.purpleLight,
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(begin: 0.95, end: 1.05, duration: 1000.ms),
              ],
            ),
          ),

          const SizedBox(height: 36),

          const Text(
            'Analyzing your palm...',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(duration: 800.ms)
              .then()
              .fadeOut(duration: 800.ms),

          const SizedBox(height: 12),

          Text(
            'Reading life lines, heart lines,\nand career insights',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted.withOpacity(0.7),
              fontSize: 14,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 32),

          // Progress steps
          _buildProgressSteps(),
        ],
      ),
    );
  }

  Widget _buildProgressSteps() {
    return Column(
      children: [
        _progressStep('Detecting palm lines', true)
            .animate()
            .fadeIn(duration: 400.ms, delay: 500.ms),
        _progressStep('Analyzing patterns', true)
            .animate()
            .fadeIn(duration: 400.ms, delay: 1500.ms),
        _progressStep('Generating insights', false)
            .animate()
            .fadeIn(duration: 400.ms, delay: 2500.ms),
      ],
    );
  }

  Widget _progressStep(String text, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 40),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            color: done ? AppColors.success : AppColors.textMuted,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              color: done ? AppColors.textSecondary : AppColors.textMuted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadUI() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Info banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.purpleAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.purpleAccent.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.purpleLight, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Based on Samudrik Shastra - ancient palm analysis',
                    style: TextStyle(
                      color: AppColors.purpleLight.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms),

          const Spacer(flex: 1),

          // Palm guide
          const PalmGuideOverlay()
              .animate()
              .fadeIn(duration: 600.ms, delay: 100.ms)
              .scaleXY(begin: 0.9, end: 1.0, duration: 600.ms, delay: 100.ms),

          const SizedBox(height: 28),

          // Instructions
          Text(
            'Place your palm clearly',
            style: Theme.of(context).textTheme.titleLarge,
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 200.ms),

          const SizedBox(height: 8),

          Text(
            'Keep palm open and well-lit\nRight hand for males, Left for females',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 300.ms),

          const Spacer(flex: 1),

          // Camera button (primary)
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_rounded, size: 22),
              label: const Text(
                'Take Photo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.purpleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 400.ms)
              .slideY(begin: 0.2, end: 0, duration: 500.ms, delay: 400.ms),

          const SizedBox(height: 12),

          // Gallery button (secondary)
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 20),
              label: const Text(
                'Choose from Gallery',
                style: TextStyle(fontSize: 15),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(
                  color: AppColors.purpleAccent.withOpacity(0.4),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 500.ms)
              .slideY(begin: 0.2, end: 0, duration: 500.ms, delay: 500.ms),

          const SizedBox(height: 16),

          // Free readings counter
          Text(
            StorageService.isPremium
                ? 'Unlimited palm readings'
                : '${StorageService.freePalmLimit - StorageService.palmReadingsUsed} free readings left',
            style: TextStyle(
              color: AppColors.textMuted.withOpacity(0.6),
              fontSize: 12,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 600.ms),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
