import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart';

/// Wraps Google Sign-In + Drive REST auth for Shutter.
///
/// Uses the `drive.file` scope only — non-sensitive, no Google verification
/// required for Play Store. The app can read/write only the Drive files it
/// created in the user's own Drive; everything else stays opaque.
///
/// One singleton instance per process. AuthNotifier sits on top of this and
/// exposes a ChangeNotifier-friendly view to the widget tree.
class AuthService {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  static const List<String> _scopes = <String>[drive.DriveApi.driveFileScope];

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  GoogleSignInAccount? _currentAccount;
  GoogleSignInAccount? get currentAccount => _currentAccount;
  bool get isSignedIn => _currentAccount != null;
  String? get email => _currentAccount?.email;
  String? get displayName => _currentAccount?.displayName;
  String? get photoUrl => _currentAccount?.photoUrl;

  /// Stream of signed-in account changes — null when signed out. Pipe directly
  /// to AuthNotifier for ChangeNotifier wiring.
  Stream<GoogleSignInAccount?> get onAccountChanged =>
      _googleSignIn.onCurrentUserChanged.map((account) {
        _currentAccount = account;
        return account;
      });

  /// Tries silent sign-in on app start so signed-in users skip the picker.
  /// Safe to call when no account exists; resolves to null silently.
  Future<GoogleSignInAccount?> trySilentSignIn() async {
    try {
      final account = await _googleSignIn.signInSilently();
      _currentAccount = account;
      return account;
    } catch (e) {
      debugPrint('AuthService.trySilentSignIn failed: $e');
      return null;
    }
  }

  /// Interactive sign-in. Returns the account on success, null if the user
  /// cancelled or sign-in failed (Cloud Console misconfig, network, etc.).
  Future<GoogleSignInAccount?> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      _currentAccount = account;
      return account;
    } catch (e) {
      debugPrint('AuthService.signIn failed: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('AuthService.signOut failed: $e');
    } finally {
      _currentAccount = null;
    }
  }

  /// Returns an authenticated REST client for the active Google account or
  /// null when signed out / token unavailable. The client refreshes its own
  /// access token on expiry; callers should hold a fresh one per sync run.
  Future<AuthClient?> driveClient() async {
    final acct = _currentAccount ?? await trySilentSignIn();
    if (acct == null) return null;
    try {
      return await _googleSignIn.authenticatedClient();
    } catch (e) {
      debugPrint('AuthService.driveClient failed: $e');
      return null;
    }
  }
}
