import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../core/app_config.dart';
import 'package:gotrue/gotrue.dart' show OAuthProvider;
import 'revenuecat_service.dart';
import '../core/ui_messenger.dart';
import '../core/auth_diagnostics.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '1038373651011-aajl0k8goi5hknl4l0sqsnb78m7lnrfj.apps.googleusercontent.com',
  );

  firebase_auth.User? _currentUser;
  firebase_auth.User? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  AuthStatus _status = AuthStatus.loading;
  AuthStatus get status => _status;

  StreamSubscription<firebase_auth.User?>? _authStateSubscription;
  final Completer<firebase_auth.User?> _initialAuthStateComplete =
      Completer<firebase_auth.User?>();

  Future<firebase_auth.User?> get initialAuthState =>
      _initialAuthStateComplete.future;

  AuthService._internal() {
    _authStateSubscription = _auth.authStateChanges().listen((user) {
      _currentUser = user;
      _status = user != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;

      if (!_initialAuthStateComplete.isCompleted) {
        _initialAuthStateComplete.complete(user);
      }

      if (user != null) {
        unawaited(_restoreExternalSessions(user));
      }

      notifyListeners();
    });
  }

  Future<void> waitForInitialAuth() async {
    if (_initialAuthStateComplete.isCompleted) return;
    try {
      await _initialAuthStateComplete.future
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      _status = _auth.currentUser != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  Future<firebase_auth.User?> signInWithGoogle() async {
    try {
      GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
      googleUser ??= await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = firebase_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final firebase_auth.UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      // AUTH-DIAG (temporary)
      unawaited(authDiag('signin_done', details: {
        'uid': user?.uid,
        'currentUserAfterSignIn': _auth.currentUser?.uid,
      }));
      // AUTH-DIAG (temporary)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('debug_login_marker', DateTime.now().toIso8601String());
      } catch (_) {}

      // AUTH-DIAG (temporary)
      Future.delayed(const Duration(seconds: 2), () {
        authDiag('signin_recheck_2s', details: {'uid': _auth.currentUser?.uid});
      });
      // AUTH-DIAG (temporary)
      Future.delayed(const Duration(seconds: 10), () {
        authDiag('signin_recheck_10s', details: {'uid': _auth.currentUser?.uid});
      });
      // AUTH-DIAG (temporary)
      if (user != null) {
        unawaited(user.getIdToken().then((token) {
          if (token != null) {
            authDiag('idtoken_success', details: {'tokenLength': token.length});
          }
        }).catchError((_) {}));
      }

      // RevenueCat linking + Supabase session sync run in the background so
      // navigation is never blocked by slow network calls. The router picks
      // up the premium status via revenueCatService's notifyListeners.
      if (user != null) {
        unawaited(_postSignInSync(user));
      }

      return user;
    } on firebase_auth.FirebaseAuthException catch (e) {
      // AUTH-DIAG (temporary)
      unawaited(authDiag('signin_error', details: {'code': e.code, 'message': e.message}));
      rethrow;
    } catch (e) {
      showUiLog('Google sign-in failed: $e');
      return null;
    }
  }

  Future<void> _postSignInSync(firebase_auth.User user) async {
    try {
      await RevenueCatService().linkToUser(user.uid);
    } catch (e) {
      showUiLog('RevenueCat link failed: $e');
    }

    if (!AppConfig.isSupabaseConfigured) return;
    try {
      final idToken = await user.getIdToken();
      if (idToken != null) {
        await supabase.Supabase.instance.client.auth.signInWithIdToken(
          provider: const OAuthProvider('custom:firebase'),
          idToken: idToken,
        );
        showUiLog('Supabase sign-in successful');
      }
    } catch (e) {
      showUiLog('Supabase sign-in failed: $e');
    }
  }

  Future<void> _restoreExternalSessions(firebase_auth.User user) async {
    await _postSignInSync(user);
  }

  Future<void> signOut() async {
    // AUTH-DIAG (temporary)
    unawaited(authDiag('signout_called', details: {'stack': StackTrace.current.toString()}));
    showUiLog('🚪 [AUTH-OUT] signOut called from:\n${StackTrace.current}');
    try {
      await RevenueCatService().logout();
      await _googleSignIn.signOut();
      await _auth.signOut();
      if (AppConfig.isSupabaseConfigured) {
        await supabase.Supabase.instance.client.auth.signOut();
      }
    } catch (e) {
      showUiLog('Sign-out failed: $e');
    }
  }

  Future<void> deleteAccount() async {
    // AUTH-DIAG (temporary)
    unawaited(authDiag('deleteaccount_called', details: {'stack': StackTrace.current.toString()}));
    showUiLog('🚪 [AUTH-OUT] deleteAccount called from:\n${StackTrace.current}');
    try {
      await _auth.currentUser?.delete();
      await _googleSignIn.signOut();
      if (AppConfig.isSupabaseConfigured) {
        await supabase.Supabase.instance.client.auth.signOut();
      }
    } catch (e) {
      showUiLog('Account deletion failed: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }
}