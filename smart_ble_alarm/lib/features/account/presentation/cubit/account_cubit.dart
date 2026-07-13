// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:smart_ble_alarm/core/firebase/app_firebase.dart';
import 'package:smart_ble_alarm/core/observability/app_analytics.dart';
import 'package:smart_ble_alarm/core/observability/crash_reporting_service.dart';
import 'package:smart_ble_alarm/firebase_options.dart';

class AccountState extends Equatable {
  final bool isInitializing;
  final bool firebaseReady;
  final bool isBusy;
  final String? uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String? message;

  const AccountState({
    this.isInitializing = true,
    this.firebaseReady = false,
    this.isBusy = false,
    this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.message,
  });

  bool get isSignedIn => uid != null;

  AccountState copyWith({
    bool? isInitializing,
    bool? firebaseReady,
    bool? isBusy,
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    String? message,
    bool clearUser = false,
    bool clearMessage = false,
  }) {
    return AccountState(
      isInitializing: isInitializing ?? this.isInitializing,
      firebaseReady: firebaseReady ?? this.firebaseReady,
      isBusy: isBusy ?? this.isBusy,
      uid: clearUser ? null : (uid ?? this.uid),
      email: clearUser ? null : (email ?? this.email),
      displayName: clearUser ? null : (displayName ?? this.displayName),
      photoUrl: clearUser ? null : (photoUrl ?? this.photoUrl),
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props => [
    isInitializing,
    firebaseReady,
    isBusy,
    uid,
    email,
    displayName,
    photoUrl,
    message,
  ];
}

class AccountCubit extends Cubit<AccountState> {
  // Injectable handles keep widget tests from needing live Firebase instances.
  AccountCubit({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _auth = auth,
       _firestore = firestore,
       _storage = storage,
       super(const AccountState());

  static Future<void>? _googleSignInInitialization;
  static final Random _secureRandom = Random.secure();

  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;
  FirebaseStorage? _storage;
  StreamSubscription<User?>? _authSubscription;

  Future<void> start() async {
    emit(
      state.copyWith(isInitializing: true, isBusy: false, clearMessage: true),
    );

    try {
      final firebaseReady = await AppFirebase.ensureInitialized();
      if (!firebaseReady) {
        emit(
          const AccountState(
            isInitializing: false,
            firebaseReady: false,
            message: 'Firebase is not available on this device yet.',
          ),
        );
        return;
      }
      _auth ??= FirebaseAuth.instance;
      _firestore ??= FirebaseFirestore.instance;
      _storage ??= FirebaseStorage.instance;
      await _authSubscription?.cancel();
      _authSubscription = _auth!.authStateChanges().listen(_onAuthChanged);
    } on UnsupportedError catch (error) {
      emit(
        AccountState(
          isInitializing: false,
          firebaseReady: false,
          message: error.message,
        ),
      );
    } catch (error) {
      emit(
        AccountState(
          isInitializing: false,
          firebaseReady: false,
          message: 'Firebase could not start: $error',
        ),
      );
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    if (!_canUseAuth) return;
    emit(state.copyWith(isBusy: true, clearMessage: true));
    try {
      await _auth!.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      emit(state.copyWith(isBusy: false, message: _authMessage(error)));
    } catch (error) {
      emit(state.copyWith(isBusy: false, message: 'Sign in failed: $error'));
    }
  }

  Future<void> createAccount({
    required String email,
    required String password,
  }) async {
    if (!_canUseAuth) return;
    emit(state.copyWith(isBusy: true, clearMessage: true));
    try {
      final credential = await _auth!.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user != null) {
        await _tryUpsertProfile(user, created: true);
      }
    } on FirebaseAuthException catch (error) {
      emit(state.copyWith(isBusy: false, message: _authMessage(error)));
    } catch (error) {
      emit(
        state.copyWith(
          isBusy: false,
          message: 'Account creation failed: $error',
        ),
      );
    }
  }

  Future<void> signInWithGoogle() async {
    if (!_canUseAuth) return;
    emit(state.copyWith(isBusy: true, clearMessage: true));
    try {
      await _ensureGoogleSignInInitialized();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        emit(
          state.copyWith(
            isBusy: false,
            message: 'Google sign-in is not available on this device.',
          ),
        );
        return;
      }

      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw FirebaseAuthException(
          code: 'missing-google-id-token',
          message: 'Google did not return an ID token.',
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final userCredential = await _auth!.signInWithCredential(credential);
      final user = userCredential.user;
      if (user != null) {
        await _tryUpsertProfile(
          user,
          created: userCredential.additionalUserInfo?.isNewUser ?? false,
        );
      }
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        emit(state.copyWith(isBusy: false, clearMessage: true));
        return;
      }
      emit(state.copyWith(isBusy: false, message: _googleMessage(error)));
    } on FirebaseAuthException catch (error) {
      emit(state.copyWith(isBusy: false, message: _authMessage(error)));
    } catch (error) {
      emit(
        state.copyWith(isBusy: false, message: 'Google sign-in failed: $error'),
      );
    }
  }

  Future<void> signInWithApple() async {
    if (!_canUseAuth) return;
    emit(state.copyWith(isBusy: true, clearMessage: true));
    try {
      final isAvailable = await SignInWithApple.isAvailable();
      if (!isAvailable) {
        emit(
          state.copyWith(
            isBusy: false,
            message: 'Apple sign-in is not available on this device.',
          ),
        );
        return;
      }

      final rawNonce = _generateNonce();
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: _sha256(rawNonce),
      );

      final idToken = appleCredential.identityToken;
      if (idToken == null) {
        throw FirebaseAuthException(
          code: 'missing-apple-id-token',
          message: 'Apple did not return an identity token.',
        );
      }

      final credential = OAuthProvider(
        'apple.com',
      ).credential(idToken: idToken, rawNonce: rawNonce);
      final userCredential = await _auth!.signInWithCredential(credential);
      final user = userCredential.user;
      final displayName = _appleDisplayName(appleCredential);
      if (user != null) {
        if (displayName != null &&
            (user.displayName == null || user.displayName!.trim().isEmpty)) {
          await user.updateDisplayName(displayName);
          await user.reload();
        }
        await _tryUpsertProfile(
          _auth!.currentUser ?? user,
          created: userCredential.additionalUserInfo?.isNewUser ?? false,
        );
      }
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        emit(state.copyWith(isBusy: false, clearMessage: true));
        return;
      }
      emit(
        state.copyWith(
          isBusy: false,
          message: 'Apple sign-in failed: ${error.message}',
        ),
      );
    } on SignInWithAppleNotSupportedException catch (error) {
      emit(state.copyWith(isBusy: false, message: error.message));
    } on FirebaseAuthException catch (error) {
      emit(state.copyWith(isBusy: false, message: _authMessage(error)));
    } catch (error) {
      emit(
        state.copyWith(isBusy: false, message: 'Apple sign-in failed: $error'),
      );
    }
  }

  Future<void> sendPasswordReset(String email) async {
    if (!_canUseAuth) return;
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      emit(state.copyWith(message: 'Enter your email first.'));
      return;
    }
    emit(state.copyWith(isBusy: true, clearMessage: true));
    try {
      await _auth!.sendPasswordResetEmail(email: trimmed);
      emit(
        state.copyWith(isBusy: false, message: 'Password reset email sent.'),
      );
    } on FirebaseAuthException catch (error) {
      emit(state.copyWith(isBusy: false, message: _authMessage(error)));
    } catch (error) {
      emit(
        state.copyWith(isBusy: false, message: 'Password reset failed: $error'),
      );
    }
  }

  Future<void> updateProfile({
    required String displayName,
    Uint8List? photoBytes,
    String? photoExtension,
    String? photoContentType,
  }) async {
    if (!_canUseAuth) return;
    final user = _auth!.currentUser;
    if (user == null) {
      emit(state.copyWith(message: 'Sign in before editing your profile.'));
      return;
    }

    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty) {
      emit(state.copyWith(message: 'Enter a name for your profile.'));
      return;
    }
    if (photoBytes != null && photoBytes.length > 5 * 1024 * 1024) {
      emit(state.copyWith(message: 'Choose a profile photo under 5 MB.'));
      return;
    }

    emit(state.copyWith(isBusy: true, clearMessage: true));
    try {
      if (trimmedName != user.displayName) {
        await user.updateDisplayName(trimmedName);
      }

      String? photoUrl = user.photoURL;
      if (photoBytes != null) {
        final storage = _storage;
        if (storage == null) {
          emit(
            state.copyWith(
              isBusy: false,
              message: 'Firebase Storage is not configured yet.',
            ),
          );
          return;
        }
        final extension = _normalizedImageExtension(photoExtension);
        final contentType =
            photoContentType ?? _contentTypeForExtension(extension);
        final ref = storage.ref('users/${user.uid}/profile/avatar.$extension');
        await ref.putData(
          photoBytes,
          SettableMetadata(
            contentType: contentType,
            cacheControl: 'public,max-age=3600',
          ),
        );
        photoUrl = await ref.getDownloadURL();
        await user.updatePhotoURL(photoUrl);
      }

      await user.reload();
      final updatedUser = _auth!.currentUser ?? user;
      final syncMessage = await _tryUpsertProfile(updatedUser);
      emit(
        AccountState(
          isInitializing: false,
          firebaseReady: true,
          uid: updatedUser.uid,
          email: updatedUser.email,
          displayName: updatedUser.displayName,
          photoUrl: updatedUser.photoURL ?? photoUrl,
          message: syncMessage ?? 'Profile updated.',
        ),
      );
    } on FirebaseException catch (error) {
      emit(state.copyWith(isBusy: false, message: _storageMessage(error)));
    } catch (error) {
      emit(
        state.copyWith(isBusy: false, message: 'Profile update failed: $error'),
      );
    }
  }

  Future<void> signOut() async {
    if (!_canUseAuth) return;
    emit(state.copyWith(isBusy: true, clearMessage: true));
    try {
      await _auth!.signOut();
      await _trySignOutGoogle();
    } catch (error) {
      emit(state.copyWith(isBusy: false, message: 'Sign out failed: $error'));
    }
  }

  bool get _canUseAuth {
    if (_auth != null && state.firebaseReady) return true;
    emit(
      state.copyWith(
        isInitializing: false,
        isBusy: false,
        message: 'Firebase is not configured yet.',
      ),
    );
    return false;
  }

  Future<void> _onAuthChanged(User? user) async {
    if (user == null) {
      await AppAnalytics.instance.setUserId(null);
      emit(
        state.copyWith(
          isInitializing: false,
          firebaseReady: true,
          isBusy: false,
          clearUser: true,
          clearMessage: true,
        ),
      );
      return;
    }

    await AppAnalytics.instance.setUserId(user.uid);
    await CrashReportingService.setUserId(user.uid);
    final syncMessage = await _tryUpsertProfile(user);
    emit(
      AccountState(
        isInitializing: false,
        firebaseReady: true,
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        photoUrl: user.photoURL,
        message: syncMessage,
      ),
    );
  }

  Future<String?> _tryUpsertProfile(User user, {bool created = false}) async {
    try {
      await _upsertProfile(user, created: created);
      return null;
    } on FirebaseException catch (error) {
      return _profileSyncMessage(error);
    } catch (_) {
      return 'Signed in, but profile sync is not ready yet.';
    }
  }

  Future<void> _upsertProfile(User user, {bool created = false}) async {
    final firestore = _firestore;
    if (firestore == null) return;

    final profile = <String, Object?>{
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'photoUrl': user.photoURL,
      'updatedAt': FieldValue.serverTimestamp(),
      if (created) 'createdAt': FieldValue.serverTimestamp(),
    };

    await firestore
        .collection('users')
        .doc(user.uid)
        .set(profile, SetOptions(merge: true));
  }

  Future<void> _ensureGoogleSignInInitialized() {
    final existing = _googleSignInInitialization;
    if (existing != null) return existing;
    final options = DefaultFirebaseOptions.currentPlatform;
    final initialization = GoogleSignIn.instance.initialize(
      clientId: options.iosClientId,
      serverClientId: options.androidClientId,
    );
    _googleSignInInitialization = initialization;
    return initialization;
  }

  Future<void> _trySignOutGoogle() async {
    try {
      await _ensureGoogleSignInInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Firebase sign-out already happened; a Google SDK cleanup failure should
      // not keep the app in a signed-in state.
    }
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    return List<String>.generate(
      length,
      (_) => charset[_secureRandom.nextInt(charset.length)],
    ).join();
  }

  String _sha256(String input) => sha256.convert(utf8.encode(input)).toString();

  String? _appleDisplayName(AuthorizationCredentialAppleID credential) {
    final parts = <String>[
      if (credential.givenName != null) credential.givenName!.trim(),
      if (credential.familyName != null) credential.familyName!.trim(),
    ]..removeWhere((part) => part.isEmpty);
    return parts.isEmpty ? null : parts.join(' ');
  }

  String _normalizedImageExtension(String? value) {
    final extension = (value ?? 'jpg').toLowerCase().replaceAll('.', '');
    switch (extension) {
      case 'png':
      case 'webp':
      case 'heic':
      case 'heif':
        return extension;
      case 'jpeg':
      case 'jpg':
      default:
        return 'jpg';
    }
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'image/jpeg';
    }
  }

  String _googleMessage(GoogleSignInException error) {
    switch (error.code) {
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google sign-in needs the Firebase OAuth client setup.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Google sign-in UI is not available right now.';
      default:
        return error.description ?? 'Google sign-in failed.';
    }
  }

  String _authMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with a different sign-in method.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'missing-google-id-token':
        return 'Google sign-in did not return a valid token.';
      case 'missing-apple-id-token':
        return 'Apple sign-in did not return a valid token.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'weak-password':
        return 'Use a stronger password.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'operation-not-allowed':
        return 'This sign-in provider is not enabled in Firebase yet.';
      default:
        return error.message ?? 'Authentication failed.';
    }
  }

  String _profileSyncMessage(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Signed in, but Firestore rules need to allow profile sync.';
      case 'not-found':
      case 'unavailable':
        return 'Signed in, but Firestore is not ready yet.';
      default:
        return 'Signed in, but profile sync is not ready yet.';
    }
  }

  String _storageMessage(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Storage rules need to allow profile photo uploads.';
      case 'object-not-found':
      case 'bucket-not-found':
        return 'Firebase Storage is not ready yet.';
      case 'unauthenticated':
        return 'Sign in again before uploading a profile photo.';
      default:
        return error.message ?? 'Profile update failed.';
    }
  }

  @override
  Future<void> close() async {
    await _authSubscription?.cancel();
    return super.close();
  }
}
