import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/worker.dart';

/// Acceso a la colección `workers`.
///
/// Soft delete: nunca borra documentos para preservar el histórico de horas
/// que los referencian. Marcar `active=false` los oculta de la lista
/// operativa pero conserva el dato en reportes.
class WorkersRepository {
  WorkersRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestorePaths.workers);

  Stream<List<Worker>> watchActive() {
    return _col.snapshots().map((snap) {
      final all = snap.docs.map(Worker.fromSnapshot).toList();
      final active = all.where((w) => w.active).toList()
        ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
      return active;
    });
  }

  Stream<List<Worker>> watchAll() {
    return _col.snapshots().map((snap) {
      final all = snap.docs.map(Worker.fromSnapshot).toList()
        ..sort((a, b) {
          if (a.active != b.active) return a.active ? -1 : 1;
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        });
      return all;
    });
  }

  Future<Worker?> getWorker(String id) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return Worker.fromSnapshot(snap);
  }

  Future<Worker> create({
    required String fullName,
    required String idNumber,
    required String role,
    String? address,
    String? email,
    String? phone,
    String? bank,
  }) async {
    final ref = _col.doc();
    final worker = Worker(
      id: ref.id,
      fullName: fullName.trim(),
      idNumber: idNumber.trim(),
      role: role.trim(),
      address: address?.trim(),
      email: email?.trim(),
      phone: phone?.trim(),
      bank: bank?.trim(),
      active: true,
      createdAt: DateTime.now(),
    );
    await ref.set(worker.toMap());
    return worker;
  }

  Future<void> update(
    String id, {
    String? fullName,
    String? idNumber,
    String? role,
    String? address,
    String? email,
    String? phone,
    String? bank,
  }) async {
    final patch = <String, dynamic>{
      if (fullName != null) 'fullName': fullName.trim(),
      if (idNumber != null) 'idNumber': idNumber.trim(),
      if (role != null) 'role': role.trim(),
      if (address != null) 'address': address.trim(),
      if (email != null) 'email': email.trim(),
      if (phone != null) 'phone': phone.trim(),
      if (bank != null) 'bank': bank.trim(),
    };
    if (patch.isEmpty) return;
    await _col.doc(id).update(patch);
  }

  Future<void> deactivate(String id) async {
    await _col.doc(id).update({
      'active': false,
      'deactivatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> reactivate(String id) async {
    await _col.doc(id).update({
      'active': true,
      'deactivatedAt': null,
    });
  }

  /// Carga el seed de `assets/seed/workers_seed.json` la primera vez. Si la
  /// colección ya tiene trabajadores, no hace nada.
  ///
  /// Devuelve el número de trabajadores cargados.
  Future<int> seedFromAssetsIfEmpty() async {
    final existing = await _col.limit(1).get();
    if (existing.docs.isNotEmpty) return 0;

    final raw = await rootBundle.loadString('assets/seed/workers_seed.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['workers'] as List).cast<Map<String, dynamic>>();

    final batch = _firestore.batch();
    final now = DateTime.now();
    for (final entry in list) {
      final ref = _col.doc();
      batch.set(ref, {
        'fullName': entry['fullName'],
        'idNumber': entry['idNumber'].toString(),
        'role': entry['role'],
        'address': entry['address'],
        'email': entry['email'],
        'phone': entry['phone'],
        'bank': entry['bank'],
        'active': entry['active'] ?? true,
        'createdAt': Timestamp.fromDate(now),
        'deactivatedAt': null,
      });
    }
    await batch.commit();
    return list.length;
  }
}

final workersRepositoryProvider = Provider<WorkersRepository>((ref) {
  return WorkersRepository(FirebaseFirestore.instance);
});

final activeWorkersProvider = StreamProvider<List<Worker>>((ref) {
  // Re-crea el listener cuando cambia la sesión, para que arranque siempre
  // con el token correcto y evite errores residuales de permission-denied.
  ref.watch(authStateProvider);
  return ref.watch(workersRepositoryProvider).watchActive();
});

final allWorkersProvider = StreamProvider<List<Worker>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(workersRepositoryProvider).watchAll();
});

final workerByIdProvider =
    FutureProvider.family.autoDispose<Worker?, String>((ref, id) {
  return ref.watch(workersRepositoryProvider).getWorker(id);
});
