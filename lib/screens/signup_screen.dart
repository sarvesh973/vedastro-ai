import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../providers/providers.dart';
import '../widgets/starfield_background.dart';
import 'home_screen.dart';
import 'user_details_screen.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await AuthService.signUpWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      displayName: _nameController.text.trim(),
    );

    if (result.success && mounted) {
      // Clear any data from a previously-signed-in account before loading
      // cloud data for this new email (guarantees profile isolation).
      await StorageService.clearAllLocalData();
      // Also save locally for offline access
      await StorageService.signUp(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      // In case this email was used before (e.g. reinstall) — restore cloud
      await StorageService.loadFromCloudForCurrentUser();
      setState(() => _isLoading = false);
      _navigateAfterSignup();
    } else if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Sign up failed'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// After successful email signup, brand-new accounts won't have a profile
  /// yet -> route them to UserDetailsScreen to collect birth details.
  /// Returning users (e.g. re-installing) will already have profile loaded
  /// from cloud and skip straight to home.
  void _navigateAfterSignup() {
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
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: StarfieldBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  // Back button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Logo
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.goldLight.withOpacity(0.25),
                          AppColors.goldLight.withOpacity(0.05),
                        ],
                      ),
                      border: Border.all(
                        color: AppColors.goldLight.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(Icons.auto_awesome, color: AppColors.goldLight, size: 32),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms)
                      .scaleXY(begin: 0.8, end: 1.0, duration: 500.ms),

                  const SizedBox(height: 20),

                  const Text(
                    'Create Account',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 150.ms),

                  const SizedBox(height: 8),

                  const Text(
                    'Begin your Vedic astrology journey',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 250.ms),

                  const SizedBox(height: 36),

                  // Name
                  _buildField(
                    controller: _nameController,
                    hint: 'Full Name',
                    icon: Icons.person_outline,
                    delay: 350,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter your name';
                      return null;
                    },
                  ),

                  const SizedBox(height: 14),

                  // Email
                  _buildField(
                    controller: _emailController,
                    hint: 'Email address',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    delay: 450,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter your email';
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),

                  const SizedBox(height: 14),

                  // Password
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Password (6+ characters)',
                      prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: AppColors.textMuted, size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.purpleAccent, width: 1.5),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter a password';
                      if (v.length < 6) return 'Password must be 6+ characters';
                      return null;
                    },
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 550.ms)
                      .slideY(begin: 0.1, end: 0, duration: 500.ms, delay: 550.ms),

                  const SizedBox(height: 14),

                  // Confirm Password
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirm,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Confirm Password',
                      prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: AppColors.textMuted, size: 20,
                        ),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.purpleAccent, width: 1.5),
                      ),
                    ),
                    validator: (v) {
                      if (v != _passwordController.text) return 'Passwords do not match';
                      return null;
                    },
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 650.ms)
                      .slideY(begin: 0.1, end: 0, duration: 500.ms, delay: 650.ms),

                  const SizedBox(height: 28),

                  // Sign Up button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleSignUp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.purpleAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Text(
                              'Create Account',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 750.ms)
                      .slideY(begin: 0.1, end: 0, duration: 500.ms, delay: 750.ms),

                  const SizedBox(height: 24),

                  // Terms
                  Text(
                    'By signing up, you agree to our\nTerms of Service & Privacy Policy',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMuted.withOpacity(0.6),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 850.ms),

                  const SizedBox(height: 32),

                  // Login link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Already have an account? ',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text(
                          'Login',
                          style: TextStyle(
                            color: AppColors.purpleLight,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    required int delay,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
        filled: true,
        fillColor: AppColors.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.purpleAccent, width: 1.5),
        ),
      ),
      validator: validator,
    )
        .animate()
        .fadeIn(duration: 500.ms, delay: Duration(milliseconds: delay))
        .slideY(begin: 0.1, end: 0, duration: 500.ms, delay: Duration(milliseconds: delay));
  }
}
