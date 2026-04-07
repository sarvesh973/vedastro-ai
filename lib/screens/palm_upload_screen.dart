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

class _PalmUploadScreenState extends ConsumerState<PalmUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isAnalyzing = false;

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

      StorageService.incrementPalmReadings();
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
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Palm Reading'),
      ),
      body: _isAnalyzing ? _buildAnalyzing() : _buildUploadUI(),
    );
  }

  Widget _buildAnalyzing() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated scanning effect
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.purpleAccent.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .scaleXY(
                      begin: 0.8,
                      end: 1.2,
                      duration: 1500.ms,
                      curve: Curves.easeInOut,
                    )
                    .fadeOut(duration: 1500.ms),
                const Icon(
                  Icons.back_hand_outlined,
                  size: 44,
                  color: AppColors.purpleAccent,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          const Text(
            'Analyzing your palm...',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(duration: 800.ms)
              .then()
              .fadeOut(duration: 800.ms),

          const SizedBox(height: 12),

          Text(
            'Reading life lines, heart lines, and more',
            style: TextStyle(
              color: AppColors.textMuted.withOpacity(0.7),
              fontSize: 14,
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
          const Spacer(flex: 1),

          // Palm guide
          const PalmGuideOverlay()
              .animate()
              .fadeIn(duration: 600.ms)
              .scaleXY(begin: 0.9, end: 1.0, duration: 600.ms),

          const SizedBox(height: 32),

          // Instructions
          Text(
            'Place your palm clearly',
            style: Theme.of(context).textTheme.titleLarge,
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 200.ms),

          const SizedBox(height: 8),

          Text(
            'Keep palm open and clear\nGood lighting helps accuracy',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 300.ms),

          const Spacer(flex: 1),

          // Camera button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined, size: 20),
              label: const Text('Take Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.purpleAccent,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 400.ms)
              .slideY(begin: 0.2, end: 0, duration: 500.ms, delay: 400.ms),

          const SizedBox(height: 14),

          // Gallery button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 20),
              label: const Text('Choose from Gallery'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                side: BorderSide(
                  color: AppColors.purpleAccent.withOpacity(0.5),
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

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
