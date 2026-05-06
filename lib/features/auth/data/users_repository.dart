import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/roles.dart';
import '../domain/app_user.dart';
import 'auth_repository.dart';

/// Acceso a la colección `users` y creación de cuentas de Firebase Auth.
///
/// `createUser` se ejecuta a través de una app de Firebase **secundaria**
/// para que el admin que está logueado no quede expulsado de su sesión
/// cuando se crea la cuenta nueva. Al final esa app secundaria se elimina,
/// dejando solo la sesión del admin original.
///
/// Las operaciones de cambiar contraseña o eliminar otra cuenta de Auth
/// no son posibles desde el SDK de cliente — se delegan a la consola de
/// Firebase. Aquí solo se gestiona el doc en `users`.
class UsersRepository {
  UsersRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestorePaths.users);

  Stream<List<AppUser>> watchAll() {
    return _col.snapshots().map((snap) {
      final list = snap.docs.map(AppUser.fromSnapshot).toList()
        ..sort((a, b) {
          if (a.active != b.active) return a.active ? -1 : 1;
          return a.username.toLowerCase().compareTo(b.username.toLowerCase());
        });
      return list;
    });
  }

  Future<AppUser?> getUser(String uid) async {
    final snap = await _col.doc(uid).get();
    if (!snap.exists) return null;
    return AppUser.fromSnapshot(snap);
  }

  Stream<AppUser?> watchUser(String uid) {
    return _col
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists ? AppUser.fromSnapshot(snap) : null);
  }

  Future<AppUser> createUser({
    required String username,
    required String password,
    required String fullName,
    required AppRole role,
    AuditFilter? auditFilter,
  }) async {
    final email = AppUser.emailFor(username);
    // App secundaria temporal para no perder la sesión del admin actual.
    final secondary = await Firebase.initializeApp(
      name: 'cqg_secondary_${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    try {
      final auth = FirebaseAuth.instanceFor(app: secondary);
      final cred = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = cred.user!.uid;
      final user = AppUser(
        uid: uid,
        username: username,
        fullName: fullName,
        role: role,
        auditFilter: role == AppRole.auditor ? auditFilter : null,
      );
      await _col.doc(uid).set(user.toMap());
      // Cierra la sesión secundaria antes de borrar la app.
      await auth.signOut();
      return user;
    } finally {
      await secondary.delete();
    }
  }

  Future<void> updateProfile(
    String uid, {
    String? fullName,
    AppRole? role,
    bool? active,
    AuditFilter? auditFilter,
    bool clearAuditFilter = false,
  }) async {
    final patch = <String, dynamic>{
      if (fullName != null) 'fullName': fullName.trim(),
      if (role != null) 'role': role.id,
      if (active != null) 'active': active,
      if (clearAuditFilter)
        'auditFilter': FieldValue.delete()
      else if (auditFilter != null)
        'auditFilter': auditFilter.toMap(),
    };
    if (patch.isEmpty) return;
    await _col.doc(uid).update(patch);
  }
}

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(FirebaseFirestore.instance);
});

final allUsersProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(usersRepositoryProvider).watchAll();
});

/// Stream a un usuario por uid. Antes era FutureProvider y se cacheaba el
/// resultado, dejando la pantalla de edición con datos viejos al reabrirla
/// después de modificar.
final userByIdProvider =
    StreamProvider.family.autoDispose<AppUser?, String>((ref, uid) {
  ref.watch(authStateProvider);
  return ref.watch(usersRepositoryProvider).watchUser(uid);
});
