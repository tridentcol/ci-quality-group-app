import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../domain/app_user.dart';

/// Manejo de autenticación con Firebase Auth.
///
/// La UI usa "usuario + contraseña". Internamente lo mapeamos a
/// `<usuario>@cqg.app` porque Firebase requiere correo. El admin nunca ve
/// los pseudo-correos: en la administración de usuarios trabaja siempre con
/// el username.
class AuthRepository {
  AuthRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signIn(
      {required String username, required String password}) async {
    await _auth.signInWithEmailAndPassword(
      email: AppUser.emailFor(username),
      password: password,
    );
  }

  Future<void> signOut() => _auth.signOut();

  /// Lee el perfil (rol, nombre completo) desde `users/{uid}`.
  Future<AppUser?> fetchProfile(String uid) async {
    final snap = await _firestore
        .collection(FirestorePaths.users)
        .doc(uid)
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (s, _) => s.data() ?? {},
          toFirestore: (data, _) => data,
        )
        .get();
    if (!snap.exists) return null;
    return AppUser.fromSnapshot(snap);
  }

  Stream<AppUser?> watchProfile(String uid) {
    return _firestore
        .collection(FirestorePaths.users)
        .doc(uid)
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (s, _) => s.data() ?? {},
          toFirestore: (data, _) => data,
        )
        .snapshots()
        .map((snap) => snap.exists ? AppUser.fromSnapshot(snap) : null);
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(FirebaseAuth.instance, FirebaseFirestore.instance);
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final currentProfileProvider = StreamProvider<AppUser?>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  return ref.watch(authRepositoryProvider).watchProfile(user.uid);
});
