import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../providers/providers.dart';
import '../widgets/starfield_background.dart';
import 'home_screen.dart';
import 'user_details_screen.dart';

/// Phone + OTP login screen. Two-step flow:
/// 1. Enter phone number -> send OTP
/// 2. Enter OTP -> verify & sign in
class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  String _countryCode = '+91';
  String? _verificationId;
  bool _otpSent = false;
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.isEmpty || rawPhone.length < 6) {
      _showError('Enter a valid phone number');
      return;
    }

    setState(() => _loading = true);
    final fullNumber = '$_countryCode$rawPhone';

    await AuthService.sendOtp(
      phoneNumber: fullNumber,
      onCodeSent: (verificationId, _) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _otpSent = true;
          _loading = false;
        });
        _showInfo('OTP sent to $fullNumber');
      },
      onFailed: (error) {
        if (!mounted) return;
        setState(() => _loading = false);
        _showError(error);
      },
      onAutoVerified: (_) async {
        if (!mounted) return;
        // Android auto-retrieved SMS — already signed in.
        // Clear any stale profile from a previous login before loading the
        // cloud data tied to THIS phone number's Firebase UID.
        await StorageService.clearAllLocalData();
        await StorageService.signUp(fullNumber, 'phone_auth');
        await StorageService.loadFromCloudForCurrentUser();
        if (mounted) _navigateAfterLogin();
      },
    );
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length < 4 || _verificationId == null) {
      _showError('Enter the OTP you received');
      return;
    }

    setState(() => _loading = true);
    final result = await AuthService.verifyOtp(
      verificationId: _verificationId!,
      smsCode: code,
    );

    if (!mounted) return;

    if (result.success) {
      final phoneFull = '$_countryCode${_phoneController.text.trim()}';
      // Wipe cached data from any previous account so we only show THIS
      // phone number's profile after we load it from the cloud.
      await StorageService.clearAllLocalData();
      await StorageService.signUp(phoneFull, 'phone_auth');
      // Restore this phone number's profile from cloud (works across devices)
      await StorageService.loadFromCloudForCurrentUser();
      if (mounted) {
        setState(() => _loading = false);
        _navigateAfterLogin();
      }
    } else {
      setState(() => _loading = false);
      _showError(result.error ?? 'OTP verification failed');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showInfo(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// After successful phone OTP login, route based on whether THIS phone
  /// number's account already has a profile in cloud (returning user) or not
  /// (first-time signup -> collect birth details next).
  /// Also re-syncs Riverpod state so the next screen sees fresh data.
  void _navigateAfterLogin() async {
    // Founder/admin auto-unlock (only matters if admin signs in via phone
    // AND has linked their admin email — rare but possible).
    if (AuthService.isAdmin && !StorageService.isPremium) {
      await StorageService.upgradeToPremium();
    }

    ref.read(userProfileProvider.notifier).state = StorageService.currentProfile;
    ref.read(familyProfilesProvider.notifier).state =
        List.from(StorageService.familyProfiles);
    ref.read(activeProfileIndexProvider.notifier).state =
        StorageService.activeProfileIndex;
    ref.read(isPremiumProvider.notifier).state = StorageService.isPremium;
    ref.read(chatQuestionsUsedProvider.notifier).state =
        StorageService.chatQuestionsUsed;
    ref.read(palmReadingsUsedProvider.notifier).state =
        StorageService.palmReadingsUsed;
    ref.read(chatMessagesProvider.notifier).clear();

    final hasProfile = StorageService.hasProfile;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => hasProfile
            ? const HomeScreen()
            : const UserDetailsScreen(fromOnboarding: true),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: StarfieldBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.purpleAccent.withOpacity(0.3),
                        AppColors.purpleAccent.withOpacity(0.05),
                      ],
                    ),
                    border: Border.all(
                      color: AppColors.purpleAccent.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(Icons.phone_android,
                      color: AppColors.goldLight, size: 36),
                ).animate().fadeIn(duration: 500.ms),
                const SizedBox(height: 20),
                Text(
                  _otpSent ? 'Enter OTP' : 'Continue with Phone',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ).animate().fadeIn(duration: 400.ms),
                const SizedBox(height: 8),
                Text(
                  _otpSent
                      ? 'We sent a code to $_countryCode${_phoneController.text.trim()}'
                      : 'Your profile is saved to your phone number — works across devices',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 14),
                ),
                const SizedBox(height: 40),

                if (!_otpSent) ...[
                  // Phone input with country code picker
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 18),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: DropdownButton<String>(
                          value: _countryCode,
                          dropdownColor: AppColors.surfaceLight,
                          underline: const SizedBox(),
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 15),
                          items: const [
                            DropdownMenuItem(value: '+91', child: Text('+91')),
                            DropdownMenuItem(value: '+1', child: Text('+1')),
                            DropdownMenuItem(value: '+44', child: Text('+44')),
                            DropdownMenuItem(value: '+971', child: Text('+971')),
                            DropdownMenuItem(value: '+61', child: Text('+61')),
                            DropdownMenuItem(value: '+65', child: Text('+65')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _countryCode = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(15),
                          ],
                          style:
                              const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Phone number',
                            filled: true,
                            fillColor: AppColors.surfaceLight,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _sendOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.purpleAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Text('Send OTP',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                    ),
                  ),
                ] else ...[
                  // OTP input
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        letterSpacing: 8,
                        fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: '------',
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _verifyOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.purpleAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Text('Verify & Sign In',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _otpSent = false;
                              _otpController.clear();
                              _verificationId = null;
                            });
                          },
                    child: const Text('Change phone number',
                        style:
                            TextStyle(color: AppColors.purpleLight, fontSize: 14)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
