import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/work_schedule.dart';

/// Persistencia y lectura de la jornada laboral. Si todavía no se ha
/// configurado en Firestore, devolvemos `WorkSchedule.defaultSchedule`.
class WorkScheduleRepository {
  WorkScheduleRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _ref => _firestore
      .collection(FirestorePaths.settings)
      .doc(FirestorePaths.workScheduleSettings);

  Stream<WorkSchedule> watch() {
    return _ref.snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return WorkSchedule.defaultSchedule;
      }
      try {
        return WorkSchedule.fromMap(snap.data()!);
      } catch (_) {
        return WorkSchedule.defaultSchedule;
      }
    });
  }

  Future<WorkSchedule> get() async {
    final snap = await _ref.get();
    if (!snap.exists || snap.data() == null) {
      return WorkSchedule.defaultSchedule;
    }
    try {
      return WorkSchedule.fromMap(snap.data()!);
    } catch (_) {
      return WorkSchedule.defaultSchedule;
    }
  }

  Future<void> save(WorkSchedule schedule) async {
    await _ref.set(schedule.toMap(), SetOptions(merge: true));
  }
}

final workScheduleRepositoryProvider = Provider<WorkScheduleRepository>((ref) {
  return WorkScheduleRepository(FirebaseFirestore.instance);
});

final workScheduleProvider = StreamProvider<WorkSchedule>((ref) {
  // Re-crea el listener cuando cambia la sesión (logout + login). Sin esto
  // el snapshot listener queda con el token de Auth viejo y Firestore
  // tira permission-denied tras volver a entrar.
  ref.watch(authStateProvider);
  return ref.watch(workScheduleRepositoryProvider).watch();
});
