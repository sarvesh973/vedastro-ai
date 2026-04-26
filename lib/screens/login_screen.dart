import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../providers/providers.dart';
import '../widgets/starfield_background.dart';
import 'signup_screen.dart';
import 'home_screen.dart';
import 'phone_login_screen.dart';
import 'user_details_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  // Email login is hidden by default — Indian users overwhelmingly prefer
  // phone OTP (industry standard for AstroTalk, AstroSage, AstroYogi, etc).
  // Email stays as a quiet fallback under "More options".
  bool _showEmailForm = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await AuthService.signInWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );

    if (result.success && mounted) {
      // Wipe any cached profile data from a previous account before loading
      // this account's cloud data. Without this, a stale profile from the
      // last email can leak into the new session.
      await StorageService.clearAllLocalData();
      // Also save login state locally for offline access
      await StorageService.signUp(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      // Restore this email account's profile from cloud
      await StorageService.loadFromCloudForCurrentUser();
      setState(() => _isLoading = false);
      _navigateAfterLogin();
    } else if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Login failed'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);

    final result = await AuthService.signInWithGoogle();

    if (result.success && mounted) {
      // Clear any cached profile from a previous Gmail account — each Gmail
      // maps to its own Firebase UID and should see only its own data.
      await StorageService.clearAllLocalData();
      await StorageService.signUp(
        result.user?.email ?? '',
        'google_auth',
      );
      // Restore this account's profile + family profiles from Firestore.
      // If the user previously used this Google account on another device
      // or a fresh install, their profile reappears here.
      await StorageService.loadFromCloudForCurrentUser();
      setState(() => _isGoogleLoading = false);
      _navigateAfterLogin();
    } else if (mounted) {
      setState(() => _isGoogleLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Google sign-in failed'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your email first, then tap Forgot Password'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final result = await AuthService.sendPasswordReset(email);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success
              ? 'Password reset email sent to $email'
              : result.error ?? 'Failed'),
          backgroundColor: result.success ? AppColors.success : AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// After a successful login, decide where to go:
  ///  - If this account has a profile in cloud (loaded into StorageService) -> Home
  ///  - If brand-new account with no profile yet -> UserDetailsScreen to collect it
  /// Also re-syncs Riverpod providers so the new screen sees fresh state.
  void _navigateAfterLogin() async {
    // Founder/admin auto-unlock: if signed-in email is on the admin list,
    // mark them premium so they bypass all paywalls + caps. No payment needed.
    if (AuthService.isAdmin && !StorageService.isPremium) {
      await StorageService.upgradeToPremium();
    }

    // Push the latest StorageService state into Riverpod so home_screen / etc.
    // see the right profile/usage data immediately, not the previous user's.
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

  void _goToSignUp() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SignupScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
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
      body: StarfieldBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),

                  // Logo
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
                    child: const Icon(
                      Icons.auto_awesome,
                      color: AppColors.goldLight,
                      size: 36,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .scaleXY(begin: 0.8, end: 1.0, duration: 600.ms),

                  const SizedBox(height: 20),

                  const Text(
                    'Welcome Back',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 200.ms),

                  const SizedBox(height: 8),

                  const Text(
                    'Sign in to continue your cosmic journey',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 300.ms),

                  const SizedBox(height: 48),

                  // ═══ PRIMARY: Phone OTP (hero button, purple) ════════
                  // Phone is the default login for Indian astrology apps —
                  // matches user expectation and has the highest conversion.
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PhoneLoginScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.phone_android, color: Colors.white, size: 22),
                      label: const Text(
                        'Continue with Phone',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.purpleAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 400.ms)
                      .slideY(begin: 0.1, end: 0, duration: 500.ms, delay: 400.ms),

                  const SizedBox(height: 14),

                  // ═══ SECONDARY: Google (outlined) ════════════════════
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _isGoogleLoading ? null : _handleGoogleSignIn,
                      icon: _isGoogleLoading
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
                            )
                          : const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                      label: Text(
                        _isGoogleLoading ? 'Signing in...' : 'Continue with Google',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.divider, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 500.ms),

                  const SizedBox(height: 28),

                  // ═══ TERTIARY: Collapsed email option ═══════════════
                  // Hidden by default. Small text link to expand.
                  if (!_showEmailForm)
                    TextButton(
                      onPressed: () => setState(() => _showEmailForm = true),
                      child: const Text(
                        'Use email instead',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ).animate().fadeIn(duration: 500.ms, delay: 600.ms),

                  // Expanded email form — only visible if user explicitly opens it
                  if (_showEmailForm) ...[
                    // Divider above
                    Row(
                      children: [
                        Expanded(child: Container(height: 1, color: AppColors.divider)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('EMAIL LOGIN', style: TextStyle(color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.2)),
                        ),
                        Expanded(child: Container(height: 1, color: AppColors.divider)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Email field
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Email address',
                        prefixIcon: const Icon(Icons.email_outlined, color: AppColors.textMuted, size: 20),
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
                        if (!_showEmailForm) return null;
                        if (v == null || v.trim().isEmpty) return 'Enter your email';
                        if (!v.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),

                    const SizedBox(height: 14),

                    // Password field
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppColors.textMuted,
                            size: 20,
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
                        if (!_showEmailForm) return null;
                        if (v == null || v.trim().isEmpty) return 'Enter your password';
                        if (v.length < 6) return 'Password must be 6+ characters';
                        return null;
                      },
                    ),

                    const SizedBox(height: 8),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _handleForgotPassword,
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(color: AppColors.purpleLight, fontSize: 13),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceLight,
                          foregroundColor: AppColors.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: AppColors.divider),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
                              )
                            : const Text(
                                'Login with Email',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),

                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() => _showEmailForm = false),
                        child: const Text(
                          'Hide',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ),
                    ),
                  ].map((w) => w.animate().fadeIn(duration: 400.ms)).toList(),

                  const SizedBox(height: 32),

                  // Sign up link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "New here? ",
                        style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                      ),
                      GestureDetector(
                        onTap: _goToSignUp,
                        child: const Text(
                          'Create an account',
                          style: TextStyle(
                            color: AppColors.purpleLight,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 700.ms),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
