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
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _capturedImagePath = null;
      });
      _scanLineController.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
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
      body: _isAnalyzing ? _buildScannerView() : _buildUploadUI(),
    );
  }

  // ═══════════════════════════════════════════
  // SCANNER VIEW — shows palm image with scan overlay
  // ═══════════════════════════════════════════

  Widget _buildScannerView() {
    return Column(
      children: [
        const SizedBox(height: 20),

        // Scanner container with palm image
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Palm image
                  if (_capturedImagePath != null)
                    Image.file(
                      File(_capturedImagePath!),
                      fit: BoxFit.cover,
                    ),

                  // Dark overlay
                  Container(
                    color: AppColors.background.withOpacity(0.4),
                  ),

                  // Grid overlay
                  AnimatedBuilder(
                    animation: _gridController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _GridPainter(
                          opacity: _gridController.value * 0.3,
                        ),
                      );
                    },
                  ),

                  // Scan line
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

                  // Detection points
                  ..._detectionPoints.asMap().entries.map((entry) {
                    final i = entry.key;
                    final point = entry.value;
                    return Positioned(
                      left: 0,
                      top: 0,
                      right: 0,
                      bottom: 0,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            children: [
                              Positioned(
                                left: constraints.maxWidth * point.x - 12,
                                top: constraints.maxHeight * point.y - 12,
                                child: _buildDetectionDot(point.label, i),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  }),

                  // Corner brackets (viewfinder)
                  Positioned(
                    top: 12, left: 12,
                    child: _cornerBracket(0),
                  ),
                  Positioned(
                    top: 12, right: 12,
                    child: _cornerBracket(1),
                  ),
                  Positioned(
                    bottom: 12, left: 12,
                    child: _cornerBracket(2),
                  ),
                  Positioned(
                    bottom: 12, right: 12,
                    child: _cornerBracket(3),
                  ),

                  // "SCANNING" badge top center
                  Positioned(
                    top: 16,
                    left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.background.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.purpleAccent.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.success,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.success.withOpacity(0.5),
                                    blurRadius: 6,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            )
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .fadeIn(duration: 600.ms)
                                .then()
                                .fadeOut(duration: 600.ms),
                            const SizedBox(width: 8),
                            const Text(
                              'SCANNING',
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ).animate().fadeIn(duration: 500.ms),
                  ),

                  // Detection count bottom left
                  Positioned(
                    bottom: 16, left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.background.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Points: ${_detectionPoints.length}',
                        style: const TextStyle(
                          color: AppColors.purpleLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
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

        // Phase text
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Text(
            _phaseTexts[_scanPhase.clamp(0, _phaseTexts.length - 1)],
            key: ValueKey(_scanPhase),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 60),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: AnimatedBuilder(
              animation: _scanLineController,
              builder: (context, child) {
                final progress = (_scanPhase + _scanLineController.value) / _phaseTexts.length;
                return LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: AppColors.surfaceLight,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.purpleAccent),
                );
              },
            ),
          ),
        ),

        const SizedBox(height: 8),

        Text(
          'Samudrik Shastra Analysis',
          style: TextStyle(
            color: AppColors.textMuted.withOpacity(0.6),
            fontSize: 12,
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildDetectionDot(String label, int index) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.purpleAccent.withOpacity(0.3),
        border: Border.all(color: AppColors.purpleLight, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.purpleAccent.withOpacity(0.4),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    )
        .animate()
        .scaleXY(begin: 0.0, end: 1.0, duration: 400.ms, curve: Curves.elasticOut)
        .then()
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 1.0, end: 1.2, duration: 800.ms);
  }

  Widget _cornerBracket(int corner) {
    // corner: 0=topLeft, 1=topRight, 2=bottomLeft, 3=bottomRight
    return SizedBox(
      width: 28,
      height: 28,
      child: CustomPaint(
        painter: _CornerBracketPainter(corner: corner),
      ),
    ).animate().fadeIn(duration: 600.ms, delay: 200.ms);
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
// SCAN LINE PAINTER — horizontal glowing line
// ═══════════════════════════════════════════

class _ScanLinePainter extends CustomPainter {
  final double progress; // 0.0 - 1.0

  _ScanLinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;

    // Glow effect (wider, faded)
    final glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          const Color(0xFF7C3AED).withOpacity(0.15),
          const Color(0xFF7C3AED).withOpacity(0.3),
          const Color(0xFF7C3AED).withOpacity(0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, y - 30, size.width, 60));
    canvas.drawRect(Rect.fromLTWH(0, y - 30, size.width, 60), glowPaint);

    // Main scan line
    final linePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          const Color(0xFFBB86FC).withOpacity(0.8),
          const Color(0xFFBB86FC),
          const Color(0xFFBB86FC).withOpacity(0.8),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, y - 1, size.width, 2))
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);

    // Bright center dot on scan line
    final dotPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(size.width * progress, y), 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ═══════════════════════════════════════════
// GRID PAINTER — subtle scanning grid
// ═══════════════════════════════════════════

class _GridPainter extends CustomPainter {
  final double opacity;

  _GridPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF7C3AED).withOpacity(opacity)
      ..strokeWidth = 0.5;

    // Vertical lines
    const spacing = 40.0;
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Horizontal lines
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}

// ═══════════════════════════════════════════
// CORNER BRACKET PAINTER — viewfinder corners
// ═══════════════════════════════════════════

class _CornerBracketPainter extends CustomPainter {
  final int corner; // 0=TL, 1=TR, 2=BL, 3=BR

  _CornerBracketPainter({required this.corner});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFBB86FC)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    const len = 12.0;

    switch (corner) {
      case 0: // Top-left
        path.moveTo(0, len);
        path.lineTo(0, 0);
        path.lineTo(len, 0);
        break;
      case 1: // Top-right
        path.moveTo(size.width - len, 0);
        path.lineTo(size.width, 0);
        path.lineTo(size.width, len);
        break;
      case 2: // Bottom-left
        path.moveTo(0, size.height - len);
        path.lineTo(0, size.height);
        path.lineTo(len, size.height);
        break;
      case 3: // Bottom-right
        path.moveTo(size.width - len, size.height);
        path.lineTo(size.width, size.height);
        path.lineTo(size.width, size.height - len);
        break;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) => false;
}
