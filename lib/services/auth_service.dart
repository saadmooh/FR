import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../core/app_config.dart';
import 'package:gotrue/gotrue.dart' show OAuthProvider;

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '1038373651011-aajl0k8goi5hknl4l0sqsnb78m7lnrfj.apps.googleusercontent.com',
  );

  firebase_auth.User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;

  Stream<firebase_auth.User?> get authStateChanges => _auth.authStateChanges();

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

      // Also sign into Supabase using Firebase ID token
      if (user != null && AppConfig.isSupabaseConfigured) {
        try {
          final idToken = await user.getIdToken();
          if (idToken != null) {
            await supabase.Supabase.instance.client.auth.signInWithIdToken(
              provider: const OAuthProvider('custom:firebase'),
              idToken: idToken,
            );
            debugPrint('Supabase sign-in successful');
          }
        } catch (e) {
          debugPrint('Supabase sign-in failed: $e');
        }
      }

      return user;
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
      if (AppConfig.isSupabaseConfigured) {
        await supabase.Supabase.instance.client.auth.signOut();
      }
    } catch (e) {
      debugPrint('Sign-out failed: $e');
    }
  }

  Future<void> deleteAccount() async {
    try {
      await _auth.currentUser?.delete();
      await _googleSignIn.signOut();
      if (AppConfig.isSupabaseConfigured) {
        await supabase.Supabase.instance.client.auth.signOut();
      }
    } catch (e) {
      debugPrint('Account deletion failed: $e');
      rethrow;
    }
  }
}