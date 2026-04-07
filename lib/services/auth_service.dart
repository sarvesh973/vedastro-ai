import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
      return AuthResult(success: false, error: 'Something went wrong. Please try again.');
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
      return AuthResult(success: false, error: 'Something went wrong. Please try again.');
    }
  }

  // ─── Google Sign-In ──────────────────────────────

  /// Sign in with Google
  static Future<AuthResult> signInWithGoogle() async {
    try {
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
      return AuthResult(success: false, error: 'Google sign-in failed. Please try again.');
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

  /// Sign out from all providers
  static Future<void> signOut() async {
    await _googleSignIn.signOut();
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
