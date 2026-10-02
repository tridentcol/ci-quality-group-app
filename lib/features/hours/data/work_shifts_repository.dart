import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/work_shift.dart';

/// Acceso a la colección `work_shifts`.
///
/// Soft delete, igual que `workers`: los registros de horas guardan el
/// `shiftId` con el que se calcularon, así que un turno solo se desactiva.
class WorkShiftsRepository {
  WorkShiftsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestorePaths.workShifts);

  /// Todos los turnos (activos primero, luego por nombre). Se ordena en
  /// cliente para no depender de un índice compuesto.
  Stream<List<WorkShift>> watchAll() {
    return _col.snapshots().map((snap) {
      final all = <WorkShift>[];
      for (final doc in snap.docs) {
        // Un doc malformado no debe tumbar la pantalla de horas completa.
        try {
          all.add(WorkShift.fromSnapshot(doc));
        } catch (_) {}
      }
      all.sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return all;
    });
  }

  /// Crea el turno si [shift] no tiene id, o lo actualiza si ya existe.
  /// Devuelve el id del documento.
  Future<String> save(
    WorkShift shift, {
    required String updatedBy,
    required String updatedByName,
  }) async {
    final isNew = shift.id.isEmpty;
    final ref = isNew ? _col.doc() : _col.doc(shift.id);
    final data = <String, dynamic>{
      ...shift.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
      'updatedByName': updatedByName,
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
    };
    // Sin `merge`: los rangos opcionales en `null` deben reemplazar a los
    // anteriores. `createdAt` se conserva porque el update no lo toca.
    if (isNew) {
      await ref.set(data);
    } else {
      await ref.update(data);
    }
    return ref.id;
  }

  Future<void> setActive(
    String id, {
    required bool active,
    required String updatedBy,
    required String updatedByName,
  }) async {
    await _col.doc(id).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
      'updatedByName': updatedByName,
    });
  }
}

final workShiftsRepositoryProvider = Provider<WorkShiftsRepository>((ref) {
  return WorkShiftsRepository(FirebaseFirestore.instance);
});

/// Todos los turnos, incluidos los inactivos (hacen falta para resolver
/// el turno de registros viejos).
final workShiftsProvider = StreamProvider<List<WorkShift>>((ref) {
  // Mismo motivo que `workScheduleProvider`: re-crear el listener al
  // cambiar la sesión evita quedar atascado en permission-denied.
  ref.watch(authStateProvider);
  return ref.watch(workShiftsRepositoryProvider).watchAll();
});
