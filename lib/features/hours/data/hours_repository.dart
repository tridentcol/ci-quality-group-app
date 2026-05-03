import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/utils/clock.dart';
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

    final now = AppClock.now();
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
      'checkIn': Timestamp.fromDate(AppClock.toInstant(newCheckIn)),
      if (newCheckOut != null)
        'checkOut': Timestamp.fromDate(AppClock.toInstant(newCheckOut)),
      if (note != null) 'note': note,
      'updatedAt': Timestamp.fromDate(AppClock.toInstant(AppClock.now())),
    };

    if (closedAt != null) {
      patch['closedAt'] = Timestamp.fromDate(AppClock.toInstant(closedAt));
      // La ventana de 24 h se inicia SOLO en el primer cierre del registro.
      // Reaperturas y re-cierres no la reinician — la idea es que sea una
      // ventana fija a partir del primer envío.
      if (entry.editableUntil == null) {
        patch['editableUntil'] = Timestamp.fromDate(
          AppClock.toInstant(closedAt.add(const Duration(hours: 24))),
        );
      }
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
      closedAt: AppClock.now(),
      schedule: schedule,
    );
  }

  /// Reabre un día cerrado. Solo el admin debería invocarlo.
  ///
  /// `editableUntil` se conserva intencionalmente: la ventana original de
  /// 24 h del primer cierre sigue vigente. Si ya expiró, el encargado no
  /// puede editar aunque el día vuelva a estar abierto — solo el admin.
  Future<void> reopenDay(String id) async {
    await _col.doc(id).update({
      'closedAt': null,
      'breakdown': HoursBreakdown().toMinutesMap(),
      'updatedAt': Timestamp.fromDate(AppClock.toInstant(AppClock.now())),
    });
  }

  Future<void> deleteEntry(String id) => _col.doc(id).delete();

  Future<HoursEntry?> getEntry(String id) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return HoursEntry.fromSnapshot(snap);
  }

  /// Stream del registro de un trabajador en una fecha específica.
  /// Útil cuando el encargado/admin quiere ver o editar un día distinto a
  /// hoy. Aprovecha el id determinístico para resolver con un solo doc.
  Stream<HoursEntry?> watchEntryForDate(String workerId, DateTime date) {
    final dayStart = startOfDay(date);
    final id = entryIdFor(workerId, dayStart);
    return _col.doc(id).snapshots().map(
          (snap) => snap.exists ? HoursEntry.fromSnapshot(snap) : null,
        );
  }

  /// Crea o actualiza una entrada cerrada de manera manual desde el admin.
  ///
  /// A diferencia del flujo diario (open → mark salida → close), aquí se
  /// persiste todo de una vez: entrada, salida y cierre con desglose
  /// calculado. Pensado para entradas retroactivas o correcciones.
  ///
  /// Si ya existe una entrada para `workerId` en `date`, se actualizan
  /// los campos sin tocar la metadata original (`createdBy`, `createdAt`).
  Future<HoursEntry> upsertManualEntry({
    required String workerId,
    required String workerName,
    required DateTime date,
    required DateTime checkIn,
    required DateTime checkOut,
    required String createdBy,
    required String createdByName,
    required WorkSchedule schedule,
  }) async {
    if (!checkOut.isAfter(checkIn)) {
      throw ArgumentError('La salida debe ser posterior a la entrada.');
    }

    final dayStart = startOfDay(date);
    final id = entryIdFor(workerId, dayStart);
    final ref = _col.doc(id);
    final existing = await ref.get();

    final calc = HoursCalculator(schedule: schedule);
    final breakdown = calc.calculate(checkIn, checkOut);
    final now = AppClock.now();

    if (existing.exists) {
      final data = existing.data()!;
      final patch = <String, dynamic>{
        'workerName': workerName,
        'workDate': Timestamp.fromDate(AppClock.toInstant(dayStart)),
        'checkIn': Timestamp.fromDate(AppClock.toInstant(checkIn)),
        'checkOut': Timestamp.fromDate(AppClock.toInstant(checkOut)),
        'breakdown': breakdown.toMinutesMap(),
        'updatedAt': Timestamp.fromDate(AppClock.toInstant(now)),
      };
      // Si todavía estaba abierta, la cerramos.
      if (data['closedAt'] == null) {
        patch['closedAt'] = Timestamp.fromDate(AppClock.toInstant(now));
      }
      // editableUntil: solo se inicia en el primer cierre. Si ya tiene
      // valor, no se toca (la ventana original sigue corriendo).
      if (data['editableUntil'] == null) {
        patch['editableUntil'] = Timestamp.fromDate(
          AppClock.toInstant(now.add(const Duration(hours: 24))),
        );
      }
      await ref.update(patch);
    } else {
      final entry = HoursEntry(
        id: id,
        workerId: workerId,
        workerName: workerName,
        workDate: dayStart,
        checkIn: checkIn,
        checkOut: checkOut,
        closedAt: now,
        breakdown: breakdown,
        createdBy: createdBy,
        createdByName: createdByName,
        createdAt: now,
        editableUntil: now.add(const Duration(hours: 24)),
      );
      await ref.set(entry.toMap());
    }

    final snap = await ref.get();
    return HoursEntry.fromSnapshot(snap);
  }

  /// Stream de todas las entradas de hoy, indexadas por workerId. Sirve para
  /// pintar el estado del día en la pantalla del encargado.
  Stream<Map<String, HoursEntry>> watchTodayByWorker() {
    final today = startOfDay(AppClock.now());
    final tomorrow = today.add(const Duration(days: 1));
    return _col
        .where('workDate',
            isGreaterThanOrEqualTo:
                Timestamp.fromDate(AppClock.toInstant(today)))
        .where('workDate',
            isLessThan: Timestamp.fromDate(AppClock.toInstant(tomorrow)))
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
        .where('workDate',
            isGreaterThanOrEqualTo:
                Timestamp.fromDate(AppClock.toInstant(start)))
        .where('workDate',
            isLessThanOrEqualTo: Timestamp.fromDate(AppClock.toInstant(end)))
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
          isGreaterThanOrEqualTo:
              Timestamp.fromDate(AppClock.toInstant(start)));
    }
    if (end != null) {
      q = q.where('workDate',
          isLessThanOrEqualTo: Timestamp.fromDate(AppClock.toInstant(end)));
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

class WorkerDayQuery {
  const WorkerDayQuery({required this.workerId, required this.date});
  final String workerId;
  final DateTime date;

  @override
  bool operator ==(Object other) =>
      other is WorkerDayQuery &&
      other.workerId == workerId &&
      other.date.year == date.year &&
      other.date.month == date.month &&
      other.date.day == date.day;

  @override
  int get hashCode =>
      Object.hash(workerId, date.year, date.month, date.day);
}

/// Registro de horas de un trabajador en un día específico (cualquier fecha,
/// no solo hoy). Sirve para que `WorkerDayScreen` se abra sobre el día
/// seleccionado por el usuario.
final workerDayEntryProvider =
    StreamProvider.family.autoDispose<HoursEntry?, WorkerDayQuery>((ref, q) {
  ref.watch(authStateProvider);
  return ref
      .watch(hoursRepositoryProvider)
      .watchEntryForDate(q.workerId, q.date);
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
