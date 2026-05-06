import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart';

/// Wraps Google Sign-In + Drive REST auth + the optional FirebaseAuth bridge.
///
/// Drive scope (`drive.file`) is non-sensitive — no Google verification
/// needed for Play Store. The FirebaseAuth bridge is best-effort: if the
/// app boots without Firebase configured (no `flutterfire configure` run
/// yet), Google sign-in still works for Drive but [firebaseUid] returns
/// null and Firestore-backed features stay disabled.
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

  /// Firebase UID for the active account, or null if Firebase isn't
  /// initialized or the credential exchange failed. Use this as the document
  /// key for `users/{uid}` and as the value to drop into `collaboratorUids`.
  String? get firebaseUid => _firebaseAuthAvailable
      ? fb.FirebaseAuth.instance.currentUser?.uid
      : null;

  bool get _firebaseAuthAvailable => Firebase.apps.isNotEmpty;

  /// Stream of signed-in account changes — null when signed out. Pipe directly
  /// to AuthNotifier for ChangeNotifier wiring.
  Stream<GoogleSignInAccount?> get onAccountChanged =>
      _googleSignIn.onCurrentUserChanged.map((account) {
        _currentAccount = account;
        if (account != null) {
          // Background-link to FirebaseAuth so Firestore-backed features work.
          // Errors are non-fatal and surface in debug logs.
          unawaited(_linkFirebase(account));
        }
        return account;
      });

  /// Tries silent sign-in on app start so signed-in users skip the picker.
  /// Safe to call when no account exists; resolves to null silently.
  Future<GoogleSignInAccount?> trySilentSignIn() async {
    try {
      final account = await _googleSignIn.signInSilently();
      _currentAccount = account;
      if (account != null) {
        await _linkFirebase(account);
        await _upsertUserDoc();
      }
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
      if (account != null) {
        await _linkFirebase(account);
        await _upsertUserDoc();
      }
      return account;
    } catch (e) {
      debugPrint('AuthService.signIn failed: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      if (_firebaseAuthAvailable) {
        await fb.FirebaseAuth.instance.signOut();
      }
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

  // --- Firebase bridge -----------------------------------------------------

  /// Exchanges the Google access + ID tokens for a FirebaseAuth credential
  /// so server-side rules on Firestore can use `request.auth.uid`. Best
  /// effort — if Firebase isn't initialized this is a no-op.
  Future<void> _linkFirebase(GoogleSignInAccount account) async {
    if (!_firebaseAuthAvailable) return;
    try {
      final googleAuth = await account.authentication;
      final credential = fb.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await fb.FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      debugPrint('AuthService._linkFirebase failed: $e');
    }
  }

  /// Maintains the `users/{uid}` row used for email→uid lookup during
  /// sharing flows. Idempotent — every sign-in re-stamps the email field
  /// so collaborator address-book changes propagate.
  Future<void> _upsertUserDoc() async {
    if (!_firebaseAuthAvailable) return;
    final uid = firebaseUid;
    final em = email;
    if (uid == null || em == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'email': em,
          'displayName': displayName,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('AuthService._upsertUserDoc failed: $e');
    }
  }
}
