import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../widgets/starfield_background.dart';
import 'signup_screen.dart';
import 'home_screen.dart';
import 'phone_login_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

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
      // Also save login state locally for offline access
      await StorageService.signUp(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      // Restore this email account's profile from cloud
      await StorageService.loadFromCloudForCurrentUser();
      setState(() => _isLoading = false);
      _navigateToHome();
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
      await StorageService.signUp(
        result.user?.email ?? '',
        'google_auth',
      );
      // Restore this account's profile + family profiles from Firestore.
      // If the user previously used this Google account on another device
      // or a fresh install, their profile reappears here.
      await StorageService.loadFromCloudForCurrentUser();
      setState(() => _isGoogleLoading = false);
      _navigateToHome();
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

  void _navigateToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
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
                      if (v == null || v.trim().isEmpty) return 'Enter your email';
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 400.ms)
                      .slideY(begin: 0.1, end: 0, duration: 500.ms, delay: 400.ms),

                  const SizedBox(height: 16),

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
                      if (v == null || v.trim().isEmpty) return 'Enter your password';
                      if (v.length < 6) return 'Password must be 6+ characters';
                      return null;
                    },
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 500.ms)
                      .slideY(begin: 0.1, end: 0, duration: 500.ms, delay: 500.ms),

                  const SizedBox(height: 12),

                  // Forgot password
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

                  const SizedBox(height: 20),

                  // Login button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
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
                              'Login',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 600.ms)
                      .slideY(begin: 0.1, end: 0, duration: 500.ms, delay: 600.ms),

                  const SizedBox(height: 24),

                  // OR divider
                  Row(
                    children: [
                      Expanded(child: Container(height: 1, color: AppColors.divider)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('OR', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ),
                      Expanded(child: Container(height: 1, color: AppColors.divider)),
                    ],
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 700.ms),

                  const SizedBox(height: 24),

                  // Google sign-in button (REAL)
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
                      .fadeIn(duration: 500.ms, delay: 800.ms),

                  const SizedBox(height: 16),

                  // Phone OTP login
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PhoneLoginScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.phone_android, color: AppColors.textSecondary, size: 20),
                      label: const Text(
                        'Continue with Phone',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.divider, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 900.ms),

                  const SizedBox(height: 32),

                  // Sign up link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account? ",
                        style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                      ),
                      GestureDetector(
                        onTap: _goToSignUp,
                        child: const Text(
                          'Sign Up',
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
                      .fadeIn(duration: 500.ms, delay: 1000.ms),

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
