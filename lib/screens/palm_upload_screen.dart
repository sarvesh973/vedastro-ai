import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';
import 'dart:ui';
import '../widgets/palm_guide_overlay.dart';
import 'palm_result_screen.dart';
import 'paywall_screen.dart';

class PalmUploadScreen extends ConsumerStatefulWidget {
  const PalmUploadScreen({super.key});

  @override
  ConsumerState<PalmUploadScreen> createState() => _PalmUploadScreenState();
}

class _PalmUploadScreenState extends ConsumerState<PalmUploadScreen>
    with TickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  bool _isAnalyzing = false;
  String? _capturedImagePath;

  // Scanner animations
  late AnimationController _scanLineController;
  late AnimationController _pulseController;
  late AnimationController _gridController;
  int _scanPhase = 0;
  final List<_DetectionPoint> _detectionPoints = [];

  static const _phaseTexts = [
    'Scanning palm surface...',
    'Detecting heart line...',
    'Tracing life line...',
    'Analyzing head line...',
    'Reading fate line...',
    'Generating insights...',
  ];

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _gridController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _pulseController.dispose();
    _gridController.dispose();
    super.dispose();
  }

  void _startScanAnimation() {
    _detectionPoints.clear();
    _scanPhase = 0;

    // Start scan line loop
    _scanLineController.repeat();
    _gridController.forward();

    // Add detection points progressively
    final random = Random();
    for (int i = 0; i < 12; i++) {
      Future.delayed(Duration(milliseconds: 800 + i * 600), () {
        if (!mounted || !_isAnalyzing) return;
        setState(() {
          _detectionPoints.add(_DetectionPoint(
            x: 0.15 + random.nextDouble() * 0.7,
            y: 0.15 + random.nextDouble() * 0.7,
            label: _getPointLabel(i),
          ));
        });
      });
    }

    // Cycle through scan phases
    for (int i = 0; i < _phaseTexts.length; i++) {
      Future.delayed(Duration(milliseconds: 1500 * i), () {
        if (!mounted || !_isAnalyzing) return;
        setState(() => _scanPhase = i);
      });
    }
  }

  String _getPointLabel(int index) {
    const labels = ['H', 'L', 'Hd', 'F', 'S', 'M', 'H', 'L', 'Hd', 'F', 'S', 'M'];
    return labels[index % labels.length];
  }

  Future<void> _pickImage(ImageSource source) async {
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

      setState(() {
        _isAnalyzing = true;
        _capturedImagePath = image.path;
      });
      ref.read(palmImagePathProvider.notifier).state = image.path;

      // Start scanner animation
      _startScanAnimation();

      // Analyze palm in background
      final result = await AiService.analyzePalm(image.path);
      ref.read(palmResultProvider.notifier).state = result;

      await StorageService.incrementPalmReadings();
      ref.read(palmReadingsUsedProvider.notifier).state =
          StorageService.palmReadingsUsed;

      if (mounted) {
        // Small delay so user sees the "complete" state
        await Future.delayed(const Duration(milliseconds: 500));
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
    } on PalmValidationException catch (e) {
      // Show validation error clearly — NOT a palm or bad image
      setState(() {
        _isAnalyzing = false;
        _capturedImagePath = null;
      });
      _scanLineController.stop();
      _scanLineController.reset();
      if (mounted) {
        _showErrorDialog(e.message);
      }
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _capturedImagePath = null;
      });
      _scanLineController.stop();
      _scanLineController.reset();
      if (mounted) {
        _showErrorDialog(
          e.toString().replaceAll('Exception: ', ''),
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

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.error.withOpacity(0.1),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: const Icon(Icons.back_hand_outlined, color: AppColors.error, size: 28),
              ),
              const SizedBox(height: 18),
              const Text(
                'Palm Not Detected',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _tipRow(Icons.pan_tool_outlined, 'Open palm facing camera'),
                    const SizedBox(height: 8),
                    _tipRow(Icons.light_mode_outlined, 'Good lighting, no shadows'),
                    const SizedBox(height: 8),
                    _tipRow(Icons.center_focus_strong, 'Hold steady & close up'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purpleAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tipRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.purpleLight),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
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
      body: _isAnalyzing ? _buildScannerView() : _buildUploadUI(),
    );
  }

  // ═══════════════════════════════════════════
  // SCANNER VIEW — premium sci-fi scanning overlay
  // ═══════════════════════════════════════════

  Widget _buildScannerView() {
    const cyan = Color(0xFF00E5FF);
    const neonPurple = Color(0xFFBB86FC);

    return Column(
      children: [
        const SizedBox(height: 12),

        // Scanner container
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Palm image ──
                  if (_capturedImagePath != null)
                    Image.file(
                      File(_capturedImagePath!),
                      fit: BoxFit.cover,
                    ),

                  // ── Vignette + tint overlay ──
                  Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.85,
                        colors: [
                          Colors.transparent,
                          AppColors.background.withOpacity(0.3),
                          AppColors.background.withOpacity(0.7),
                        ],
                        stops: const [0.3, 0.7, 1.0],
                      ),
                    ),
                  ),
                  // Subtle purple tint
                  Container(
                    color: const Color(0xFF7C3AED).withOpacity(0.08),
                  ),

                  // ── Radial circles (concentric rings) ──
                  AnimatedBuilder(
                    animation: _gridController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _RadialGridPainter(
                          opacity: _gridController.value * 0.25,
                        ),
                      );
                    },
                  ),

                  // ── Scan line with trailing glow ──
                  AnimatedBuilder(
                    animation: _scanLineController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _ScanLinePainter(
                          progress: _scanLineController.value,
                        ),
                      );
                    },
                  ),

                  // ── Detection points with crosshairs + pulse rings ──
                  ..._detectionPoints.asMap().entries.map((entry) {
                    final i = entry.key;
                    final point = entry.value;
                    return Positioned(
                      left: 0, top: 0, right: 0, bottom: 0,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            children: [
                              Positioned(
                                left: constraints.maxWidth * point.x - 22,
                                top: constraints.maxHeight * point.y - 22,
                                child: _buildDetectionMarker(point.label, i),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  }),

                  // ── Corner brackets with glow ──
                  Positioned(top: 14, left: 14, child: _cornerBracket(0)),
                  Positioned(top: 14, right: 14, child: _cornerBracket(1)),
                  Positioned(bottom: 14, left: 14, child: _cornerBracket(2)),
                  Positioned(bottom: 14, right: 14, child: _cornerBracket(3)),

                  // ── Top: Frosted "ANALYZING" badge ──
                  Positioned(
                    top: 18, left: 0, right: 0,
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.background.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: cyan.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Pulsing dot
                                Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: cyan,
                                    boxShadow: [
                                      BoxShadow(
                                        color: cyan.withOpacity(0.6),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                )
                                    .animate(onPlay: (c) => c.repeat(reverse: true))
                                    .scaleXY(begin: 0.8, end: 1.3, duration: 800.ms),
                                const SizedBox(width: 10),
                                Text(
                                  'ANALYZING',
                                  style: TextStyle(
                                    color: cyan,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ).animate().fadeIn(duration: 600.ms),
                  ),

                  // ── Bottom-left: Data readout ──
                  Positioned(
                    bottom: 16, left: 16,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.background.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: neonPurple.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'DETECTED',
                                style: TextStyle(
                                  color: neonPurple.withOpacity(0.6),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_detectionPoints.length} points',
                                style: TextStyle(
                                  color: cyan,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Bottom-right: Line type readout ──
                  Positioned(
                    bottom: 16, right: 16,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.background.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: neonPurple.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'SAMUDRIK',
                                style: TextStyle(
                                  color: neonPurple.withOpacity(0.6),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Shastra AI',
                                style: TextStyle(
                                  color: cyan,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── Phase info card ──
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.divider),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Phase text with icon
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getPhaseIcon(),
                    color: const Color(0xFF00E5FF),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.3),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      _phaseTexts[_scanPhase.clamp(0, _phaseTexts.length - 1)],
                      key: ValueKey(_scanPhase),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AnimatedBuilder(
                  animation: _scanLineController,
                  builder: (context, child) {
                    final progress = (_scanPhase + _scanLineController.value) / _phaseTexts.length;
                    return Stack(
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7C3AED), Color(0xFF00E5FF)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF).withOpacity(0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Samudrik Shastra • Deep Analysis',
                style: TextStyle(
                  color: AppColors.textMuted.withOpacity(0.5),
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  IconData _getPhaseIcon() {
    switch (_scanPhase) {
      case 0: return Icons.document_scanner_outlined;
      case 1: return Icons.favorite_outline;
      case 2: return Icons.spa_outlined;
      case 3: return Icons.psychology_outlined;
      case 4: return Icons.timeline_outlined;
      case 5: return Icons.auto_awesome;
      default: return Icons.document_scanner_outlined;
    }
  }

  Widget _buildDetectionMarker(String label, int index) {
    const cyan = Color(0xFF00E5FF);
    const neonPurple = Color(0xFFBB86FC);

    // Alternate cyan and purple for visual variety
    final color = index % 2 == 0 ? cyan : neonPurple;

    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Expanding pulse ring
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.3), width: 1),
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .scaleXY(begin: 0.5, end: 1.5, duration: 1500.ms)
              .fadeOut(duration: 1500.ms),

          // Second ring (offset timing)
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.2), width: 1),
            ),
          )
              .animate(onPlay: (c) => c.repeat(), delay: 500.ms)
              .scaleXY(begin: 0.5, end: 1.4, duration: 1500.ms)
              .fadeOut(duration: 1500.ms),

          // Crosshair lines
          CustomPaint(
            size: const Size(28, 28),
            painter: _CrosshairPainter(color: color),
          ),

          // Center dot with glow
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.6),
                  blurRadius: 10,
                  spreadRadius: 3,
                ),
              ],
            ),
          ),

          // Label
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.background.withOpacity(0.7),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .scaleXY(begin: 0.0, end: 1.0, duration: 500.ms, curve: Curves.elasticOut);
  }

  Widget _cornerBracket(int corner) {
    return SizedBox(
      width: 32,
      height: 32,
      child: CustomPaint(
        painter: _CornerBracketPainter(corner: corner),
      ),
    )
        .animate().fadeIn(duration: 600.ms, delay: 200.ms)
        .then()
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(begin: 0.6, duration: 2000.ms);
  }

  // ═══════════════════════════════════════════
  // UPLOAD UI
  // ═══════════════════════════════════════════

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

// ═══════════════════════════════════════════
// DETECTION POINT MODEL
// ═══════════════════════════════════════════

class _DetectionPoint {
  final double x; // 0.0 - 1.0
  final double y; // 0.0 - 1.0
  final String label;

  const _DetectionPoint({required this.x, required this.y, required this.label});
}

// ═══════════════════════════════════════════
// SCAN LINE PAINTER — neon glow with trailing gradient
// ═══════════════════════════════════════════

class _ScanLinePainter extends CustomPainter {
  final double progress;

  _ScanLinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    const cyan = Color(0xFF00E5FF);
    const purple = Color(0xFF7C3AED);

    // Wide trailing glow zone ABOVE the scan line
    final trailHeight = size.height * 0.12;
    final trailPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          cyan.withOpacity(0.03),
          cyan.withOpacity(0.08),
          cyan.withOpacity(0.15),
        ],
      ).createShader(Rect.fromLTWH(0, y - trailHeight, size.width, trailHeight));
    canvas.drawRect(Rect.fromLTWH(0, y - trailHeight, size.width, trailHeight), trailPaint);

    // Soft glow zone around scan line
    final glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          purple.withOpacity(0.15),
          cyan.withOpacity(0.25),
          purple.withOpacity(0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, y - 20, size.width, 40));
    canvas.drawRect(Rect.fromLTWH(0, y - 20, size.width, 40), glowPaint);

    // Main scan line — bright cyan
    final linePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          cyan.withOpacity(0.5),
          cyan.withOpacity(0.9),
          cyan,
          cyan.withOpacity(0.9),
          cyan.withOpacity(0.5),
          Colors.transparent,
        ],
        stops: const [0.0, 0.1, 0.3, 0.5, 0.7, 0.9, 1.0],
      ).createShader(Rect.fromLTWH(0, y - 1, size.width, 2))
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);

    // Secondary thinner line slightly below
    final line2Paint = Paint()
      ..color = purple.withOpacity(0.3)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, y + 4), Offset(size.width, y + 4), line2Paint);

    // Bright hotspot that moves along the scan line
    final dotX = size.width * ((progress * 3) % 1.0);
    final dotPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(dotX, y), 4, dotPaint);

    // Secondary hotspot (opposite direction)
    final dot2X = size.width * (1.0 - ((progress * 2.3) % 1.0));
    final dot2Paint = Paint()
      ..color = cyan.withOpacity(0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(dot2X, y), 3, dot2Paint);
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ═══════════════════════════════════════════
// RADIAL GRID PAINTER — concentric circles + crosshair
// ═══════════════════════════════════════════

class _RadialGridPainter extends CustomPainter {
  final double opacity;

  _RadialGridPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width * 0.45;
    const cyan = Color(0xFF00E5FF);
    const purple = Color(0xFF7C3AED);

    // Concentric circles
    final circlePaint = Paint()
      ..color = purple.withOpacity(opacity * 0.4)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (int i = 1; i <= 5; i++) {
      canvas.drawCircle(center, maxR * (i / 5), circlePaint);
    }

    // Vertical + horizontal crosshair through center
    final crossPaint = Paint()
      ..color = cyan.withOpacity(opacity * 0.2)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(center.dx, 0), Offset(center.dx, size.height), crossPaint,
    );
    canvas.drawLine(
      Offset(0, center.dy), Offset(size.width, center.dy), crossPaint,
    );

    // Diagonal lines (subtle)
    final diagPaint = Paint()
      ..color = purple.withOpacity(opacity * 0.12)
      ..strokeWidth = 0.3;
    canvas.drawLine(Offset(0, 0), Offset(size.width, size.height), diagPaint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), diagPaint);
  }

  @override
  bool shouldRepaint(covariant _RadialGridPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}

// ═══════════════════════════════════════════
// CROSSHAIR PAINTER — for detection markers
// ═══════════════════════════════════════════

class _CrosshairPainter extends CustomPainter {
  final Color color;

  _CrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;
    const gap = 5.0;
    const arm = 10.0;

    // Top
    canvas.drawLine(Offset(cx, cy - gap - arm), Offset(cx, cy - gap), paint);
    // Bottom
    canvas.drawLine(Offset(cx, cy + gap), Offset(cx, cy + gap + arm), paint);
    // Left
    canvas.drawLine(Offset(cx - gap - arm, cy), Offset(cx - gap, cy), paint);
    // Right
    canvas.drawLine(Offset(cx + gap, cy), Offset(cx + gap + arm, cy), paint);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ═══════════════════════════════════════════
// CORNER BRACKET PAINTER — glowing viewfinder
// ═══════════════════════════════════════════

class _CornerBracketPainter extends CustomPainter {
  final int corner;

  _CornerBracketPainter({required this.corner});

  @override
  void paint(Canvas canvas, Size size) {
    const cyan = Color(0xFF00E5FF);

    // Glow layer
    final glowPaint = Paint()
      ..color = cyan.withOpacity(0.3)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Main line
    final mainPaint = Paint()
      ..color = cyan.withOpacity(0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 14.0;

    for (final paint in [glowPaint, mainPaint]) {
      final path = Path();
      switch (corner) {
        case 0:
          path.moveTo(0, len);
          path.lineTo(0, 0);
          path.lineTo(len, 0);
          break;
        case 1:
          path.moveTo(size.width - len, 0);
          path.lineTo(size.width, 0);
          path.lineTo(size.width, len);
          break;
        case 2:
          path.moveTo(0, size.height - len);
          path.lineTo(0, size.height);
          path.lineTo(len, size.height);
          break;
        case 3:
          path.moveTo(size.width - len, size.height);
          path.lineTo(size.width, size.height);
          path.lineTo(size.width, size.height - len);
          break;
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) => false;
}
