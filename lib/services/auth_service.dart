import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/api_config.dart';

/// Firebase Authentication Service
class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// Current logged-in user
  static User? get currentUser => _auth.currentUser;

  /// Is user logged in?
  static bool get isLoggedIn => _auth.currentUser != null;

  /// User email
  static String? get userEmail => _auth.currentUser?.email;

  /// Is the currently signed-in user a founder / admin / staff?
  /// Checked via [ApiConfig.adminEmails]. Admins bypass:
  ///   - Paywall (always treated as premium)
  ///   - Chat / palm reading caps
  ///   - Razorpay subscription flow
  /// SECURITY: server-side check is the source of truth — this is for UX only.
  /// The server verifies the Firebase ID token's email claim, so a malicious
  /// actor can't fake admin by editing the APK.
  static bool get isAdmin => ApiConfig.isAdminEmail(userEmail);

  /// User display name
  static String? get userName => _auth.currentUser?.displayName;

  /// User photo URL
  static String? get userPhoto => _auth.currentUser?.photoURL;

  /// Auth state changes stream
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ─── Email & Password ────────────────────────────

  /// Sign up with email and password
  static Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Set display name if provided
      if (displayName != null && displayName.isNotEmpty) {
        await credential.user?.updateDisplayName(displayName);
      }

      return AuthResult(success: true, user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult(success: false, error: 'Sign up error: $e');
    }
  }

  /// Sign in with email and password
  static Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return AuthResult(success: true, user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult(success: false, error: 'Login error: $e');
    }
  }

  // ─── Google Sign-In ──────────────────────────────

  /// Sign in with Google.
  /// Always forces the Google account picker (by signing out of Google first)
  /// so users can switch between multiple Gmail accounts on the same device.
  /// Each Gmail account gets a unique Firebase UID, so profiles stay separate.
  static Future<AuthResult> signInWithGoogle() async {
    try {
      // Force fresh account picker — without this Google silently reuses the
      // last-used account and the user can't switch emails.
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // best-effort; ignore if nothing was signed in
      }

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return AuthResult(success: false, error: 'Google sign-in cancelled');
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      return AuthResult(success: true, user: userCredential.user);
    } catch (e) {
      return AuthResult(success: false, error: 'Google error: $e');
    }
  }

  // ─── Phone OTP Sign-In ──────────────────────────
  // Firebase Phone Auth requires SHA-1/SHA-256 configured in Firebase Console.
  // Flow: (1) sendOtp() -> Firebase sends SMS -> (2) verifyOtp(code) -> signs in.

  /// Send OTP to a phone number. onCodeSent receives the verificationId
  /// which must be passed back to verifyOtp() along with the code the user enters.
  /// phoneNumber MUST include country code, e.g. '+919876543210'.
  static Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId, int? forceResendToken) onCodeSent,
    required void Function(String error) onFailed,
    void Function(PhoneAuthCredential)? onAutoVerified,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          // Android auto-retrieval: Firebase already has the code
          try {
            await _auth.signInWithCredential(credential);
            if (onAutoVerified != null) onAutoVerified(credential);
          } catch (e) {
            onFailed('Auto sign-in failed: $e');
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          onFailed(_getErrorMessage(e.code));
        },
        codeSent: (verificationId, forceResendToken) {
          onCodeSent(verificationId, forceResendToken);
        },
        codeAutoRetrievalTimeout: (_) {
          // No action — user will enter code manually
        },
      );
    } catch (e) {
      onFailed('Failed to send OTP: $e');
    }
  }

  /// Verify OTP and sign in
  static Future<AuthResult> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      return AuthResult(success: true, user: userCredential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult(success: false, error: 'OTP verification error: $e');
    }
  }

  // ─── Password Reset ──────────────────────────────

  /// Send password reset email
  static Future<AuthResult> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return AuthResult(success: true);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _getErrorMessage(e.code));
    } catch (e) {
      return AuthResult(success: false, error: 'Failed to send reset email.');
    }
  }

  // ─── Sign Out ────────────────────────────────────

  /// Sign out from all providers.
  /// Uses disconnect() on Google so the token is revoked — next sign-in will
  /// show the full account picker instead of silently re-using the previous
  /// account. This is what lets users truly switch between different Gmails.
  ///
  /// Note: Caller should ALSO call StorageService.clearAllLocalData() so the
  /// previous user's cached profile doesn't leak into the next session.
  static Future<void> signOut() async {
    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      // disconnect can throw if not currently signed in with Google — ignore
    }
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  // ─── Error Messages ──────────────────────────────

  static String _getErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered. Try logging in.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password is too weak. Use 6+ characters.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Try again.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try later.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'invalid-phone-number':
        return 'Invalid phone number format. Use +91XXXXXXXXXX.';
      case 'invalid-verification-code':
        return 'Wrong OTP. Please check and try again.';
      case 'invalid-verification-id':
        return 'OTP expired. Please request a new one.';
      case 'session-expired':
        return 'OTP session expired. Request a new code.';
      case 'quota-exceeded':
        return 'Too many OTP requests. Try again later.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}

/// Result model for auth operations
class AuthResult {
  final bool success;
  final User? user;
  final String? error;

  const AuthResult({
    required this.success,
    this.user,
    this.error,
  });
}
