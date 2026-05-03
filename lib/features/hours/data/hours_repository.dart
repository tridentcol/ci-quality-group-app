import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/utils/dates.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/hours_calculator.dart';
import '../domain/hours_categories.dart';
import '../domain/hours_entry.dart';
import '../domain/work_schedule.dart';

/// Acceso a la colección `hours_entries`.
///
/// Reglas de negocio relevantes:
///  - Un trabajador puede tener máximo un registro abierto por día. Si ya hay
///    un registro abierto, [openDay] no crea uno nuevo: lo retorna.
///  - El cierre del día calcula y persiste el desglose por categoría usando
///    [HoursCalculator].
///  - Los registros mantienen una ventana de edición de 24 h para el
///    encargado; el admin puede editar siempre.
class HoursRepository {
  HoursRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestorePaths.hoursEntries);

  /// Construye el id determinístico de un registro: `<workerId>_<YYYYMMDD>`.
  /// Garantiza una sola entrada por trabajador-día sin necesidad de índices.
  static String entryIdFor(String workerId, DateTime date) {
    final ymd =
        '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    return '${workerId}_$ymd';
  }

  /// Crea o retorna el registro de [workerId] para [checkIn].
  ///
  /// Si ya existe un registro para ese día (abierto o cerrado), simplemente
  /// se retorna. Esto evita duplicados si el encargado vuelve a tocar
  /// "abrir día" sin querer.
  Future<HoursEntry> openDay({
    required String workerId,
    required String workerName,
    required DateTime checkIn,
    required String createdBy,
    required String createdByName,
  }) async {
    final dayStart = startOfDay(checkIn);
    final id = entryIdFor(workerId, dayStart);
    final ref = _col.doc(id);
    final existing = await ref.get();
    if (existing.exists) {
      return HoursEntry.fromSnapshot(existing);
    }

    final now = DateTime.now();
    final entry = HoursEntry(
      id: id,
      workerId: workerId,
      workerName: workerName,
      workDate: dayStart,
      checkIn: checkIn,
      breakdown: HoursBreakdown(),
      createdBy: createdBy,
      createdByName: createdByName,
      createdAt: now,
    );
    await ref.set(entry.toMap());
    return entry;
  }

  /// Actualiza la entrada o salida de un registro. Si [closedAt] está
  /// presente, recalcula el desglose y arranca la ventana de 24 h.
  Future<void> updateEntry(
    String id, {
    DateTime? checkIn,
    DateTime? checkOut,
    DateTime? closedAt,
    String? note,
    required WorkSchedule schedule,
  }) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) throw StateError('Registro no encontrado.');
    final entry = HoursEntry.fromSnapshot(snap);

    final newCheckIn = checkIn ?? entry.checkIn;
    final newCheckOut = checkOut ?? entry.checkOut;

    final patch = <String, dynamic>{
      'checkIn': Timestamp.fromDate(newCheckIn),
      if (newCheckOut != null) 'checkOut': Timestamp.fromDate(newCheckOut),
      if (note != null) 'note': note,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };

    if (closedAt != null) {
      patch['closedAt'] = Timestamp.fromDate(closedAt);
      patch['editableUntil'] =
          Timestamp.fromDate(closedAt.add(const Duration(hours: 24)));
    }

    if (newCheckOut != null) {
      final calc = HoursCalculator(schedule: schedule);
      final breakdown = calc.calculate(newCheckIn, newCheckOut);
      patch['breakdown'] = breakdown.toMinutesMap();
    }

    await _col.doc(id).update(patch);
  }

  /// Cierra el día con la salida indicada, calcula el desglose y arranca la
  /// ventana de 24 h. Atajo de [updateEntry].
  Future<void> closeDay(
    String id, {
    required DateTime checkOut,
    required WorkSchedule schedule,
  }) async {
    await updateEntry(
      id,
      checkOut: checkOut,
      closedAt: DateTime.now(),
      schedule: schedule,
    );
  }

  /// Reabre un día cerrado. Solo el admin debería invocarlo.
  Future<void> reopenDay(String id) async {
    await _col.doc(id).update({
      'closedAt': null,
      'editableUntil': null,
      'breakdown': HoursBreakdown().toMinutesMap(),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> deleteEntry(String id) => _col.doc(id).delete();

  Future<HoursEntry?> getEntry(String id) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return HoursEntry.fromSnapshot(snap);
  }

  /// Stream de todas las entradas de hoy, indexadas por workerId. Sirve para
  /// pintar el estado del día en la pantalla del encargado.
  Stream<Map<String, HoursEntry>> watchTodayByWorker() {
    final today = startOfDay(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    return _col
        .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .where('workDate', isLessThan: Timestamp.fromDate(tomorrow))
        .snapshots()
        .map((snap) {
      final map = <String, HoursEntry>{};
      for (final doc in snap.docs) {
        final entry = HoursEntry.fromSnapshot(doc);
        map[entry.workerId] = entry;
      }
      return map;
    });
  }

  Stream<List<HoursEntry>> watchByRange(DateTime start, DateTime end) {
    return _col
        .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('workDate', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(HoursEntry.fromSnapshot).toList()
        ..sort((a, b) => b.workDate.compareTo(a.workDate));
      return list;
    });
  }

  Stream<List<HoursEntry>> watchByWorker(
    String workerId, {
    DateTime? start,
    DateTime? end,
  }) {
    Query<Map<String, dynamic>> q =
        _col.where('workerId', isEqualTo: workerId);
    if (start != null) {
      q = q.where('workDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start));
    }
    if (end != null) {
      q = q.where('workDate', isLessThanOrEqualTo: Timestamp.fromDate(end));
    }
    return q.snapshots().map((snap) {
      final list = snap.docs.map(HoursEntry.fromSnapshot).toList()
        ..sort((a, b) => b.workDate.compareTo(a.workDate));
      return list;
    });
  }
}

final hoursRepositoryProvider = Provider<HoursRepository>((ref) {
  return HoursRepository(FirebaseFirestore.instance);
});

final todayHoursByWorkerProvider =
    StreamProvider<Map<String, HoursEntry>>((ref) {
  // Re-crea el listener al cambiar la sesión para que arranque siempre con
  // el token correcto y no quede atascado en permission-denied.
  ref.watch(authStateProvider);
  return ref.watch(hoursRepositoryProvider).watchTodayByWorker();
});

class HoursDateRange {
  const HoursDateRange({required this.start, required this.end});
  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is HoursDateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

final hoursByRangeProvider = StreamProvider.family
    .autoDispose<List<HoursEntry>, HoursDateRange>((ref, range) {
  ref.watch(authStateProvider);
  return ref.watch(hoursRepositoryProvider).watchByRange(range.start, range.end);
});

final hoursEntryByIdProvider =
    FutureProvider.family.autoDispose<HoursEntry?, String>((ref, id) {
  return ref.watch(hoursRepositoryProvider).getEntry(id);
});
