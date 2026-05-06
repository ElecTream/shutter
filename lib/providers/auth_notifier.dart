import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/auth_service.dart';

/// Bridges [AuthService] into the Provider tree as a ChangeNotifier so
/// widgets can rebuild on sign-in / sign-out. Holds no auth state of its
/// own — everything is delegated to the singleton.
class AuthNotifier extends ChangeNotifier {
  final AuthService _auth = AuthService();
  StreamSubscription<GoogleSignInAccount?>? _sub;
  StreamSubscription<fb.User?>? _firebaseSub;

  AuthNotifier() {
    _sub = _auth.onAccountChanged.listen((_) => notifyListeners());
    // FirebaseAuth credential exchange is async and finishes after the
    // GoogleSignIn account event. Listening to authStateChanges fires once
    // firebaseUid is actually available so consumers (e.g. SyncOrchestrator
    // attaching the Firestore lists stream) can react.
    if (Firebase.apps.isNotEmpty) {
      _firebaseSub = fb.FirebaseAuth.instance
          .authStateChanges()
          .listen((_) => notifyListeners());
    }
    // Best-effort silent restore on startup — no user-visible UI runs first,
    // so a failure is invisible (and AuthService logs it).
    unawaited(_auth.trySilentSignIn().then((_) => notifyListeners()));
  }

  bool get signedIn => _auth.isSignedIn;
  String? get email => _auth.email;
  String? get displayName => _auth.displayName;
  String? get photoUrl => _auth.photoUrl;
  String? get firebaseUid => _auth.firebaseUid;
  AuthService get service => _auth;

  Future<bool> signIn() async {
    final account = await _auth.signIn();
    notifyListeners();
    return account != null;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _firebaseSub?.cancel();
    super.dispose();
  }
}
