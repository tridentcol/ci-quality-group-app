import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/utils/clock.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/expense.dart';

/// Acceso a la colección `expenses` (gastos de bodega). Misma mecánica
/// de fotos que `MaterialEntriesRepository`: el id se reserva con
/// [newExpenseRef], la foto sube a Storage y el doc nace con la URL ya
/// resuelta.
class ExpensesRepository {
  ExpensesRepository(this._firestore, this._storage);

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestorePaths.expenses);

  /// Reserva el id del próximo gasto ANTES de crearlo, para poder subir
  /// la foto a `expenses/{id}/receipt.jpg` y escribir el doc con la URL.
  DocumentReference<Map<String, dynamic>> newExpenseRef() => _col.doc();

  /// Sube el soporte y devuelve su download URL junto con el path, que
  /// hay que persistir para poder borrar el archivo después.
  Future<({String url, String storagePath})> uploadPhoto({
    required String expenseId,
    required Uint8List bytes,
  }) async {
    final path = 'expenses/$expenseId/receipt.jpg';
    final ref = _storage.ref().child(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return (url: await ref.getDownloadURL(), storagePath: path);
  }

  /// Crea el gasto. `expenseRef` debe venir de [newExpenseRef].
  Future<Expense> createExpense({
    required DocumentReference<Map<String, dynamic>> expenseRef,
    required DateTime date,
    required String description,
    required num amount,
    String? category,
    required String paidBy,
    String? photoUrl,
    String? photoStoragePath,
    String? notes,
    required String createdBy,
    required String createdByName,
  }) async {
    final now = AppClock.now();
    final expense = Expense(
      id: expenseRef.id,
      date: date,
      description: description,
      amount: amount,
      category: category,
      paidBy: paidBy,
      photoUrl: photoUrl,
      photoStoragePath: photoStoragePath,
      notes: notes,
      createdBy: createdBy,
      createdByName: createdByName,
      createdAt: now,
      editableUntil: now.add(const Duration(hours: 24)),
    );
    await expenseRef.set(expense.toMap());
    return expense;
  }

  /// Actualiza los campos indicados. `category` y `notes` usan el
  /// sentinela [_unset] para distinguir "no tocar" de "dejar vacío".
  ///
  /// - `clearPhoto: true` quita la foto del doc y borra el archivo en
  ///   Storage (best-effort).
  /// - `photoUrl` + `photoStoragePath` reemplazan la foto; como el path
  ///   es fijo, el archivo viejo se sobrescribe.
  Future<void> updateExpense(
    String id, {
    DateTime? date,
    String? description,
    num? amount,
    Object? category = _unset,
    String? paidBy,
    Object? notes = _unset,
    String? photoUrl,
    String? photoStoragePath,
    bool clearPhoto = false,
  }) async {
    final patch = <String, dynamic>{
      if (date != null) 'date': Timestamp.fromDate(AppClock.toInstant(date)),
      if (description != null) 'description': description,
      if (amount != null) 'amount': amount,
      if (!identical(category, _unset)) 'category': category,
      if (paidBy != null) 'paidBy': paidBy,
      if (!identical(notes, _unset)) 'notes': notes,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (photoStoragePath != null) 'photoStoragePath': photoStoragePath,
      if (clearPhoto) 'photoUrl': null,
      if (clearPhoto) 'photoStoragePath': null,
      'updatedAt': Timestamp.fromDate(AppClock.toInstant(AppClock.now())),
    };

    String? pathToDelete;
    if (clearPhoto) {
      final snap = await _col.doc(id).get();
      pathToDelete = snap.data()?['photoStoragePath'] as String?;
    }

    await _col.doc(id).update(patch);

    if (pathToDelete != null) await _deleteFileBestEffort(pathToDelete);
  }

  /// Borra el doc y su foto. El archivo es best-effort: si ya no está o
  /// el borrado falla, un huérfano en Storage no afecta a la app.
  Future<void> deleteExpense(String id) async {
    final snap = await _col.doc(id).get();
    final path = snap.data()?['photoStoragePath'] as String?;
    await _col.doc(id).delete();
    if (path != null) await _deleteFileBestEffort(path);
  }

  Future<void> _deleteFileBestEffort(String path) async {
    try {
      await _storage.ref().child(path).delete();
    } catch (_) {
      // Ver docstring de deleteExpense.
    }
  }

  Stream<List<Expense>> watchByDateRange(DateTime start, DateTime end) {
    return _col
        .where(
          'date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(AppClock.toInstant(start)),
        )
        .where(
          'date',
          isLessThanOrEqualTo: Timestamp.fromDate(AppClock.toInstant(end)),
        )
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Expense.fromSnapshot).toList());
  }

  Stream<List<Expense>> watchRecent({int limit = 50}) {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Expense.fromSnapshot).toList());
  }

  Stream<Expense?> watchById(String id) {
    return _col
        .doc(id)
        .snapshots()
        .map((snap) => snap.exists ? Expense.fromSnapshot(snap) : null);
  }
}

const Object _unset = Object();

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  return ExpensesRepository(
    FirebaseFirestore.instance,
    FirebaseStorage.instance,
  );
});

class ExpensesDateRange {
  const ExpensesDateRange({required this.start, required this.end});
  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is ExpensesDateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

final expensesByRangeProvider = StreamProvider.family
    .autoDispose<List<Expense>, ExpensesDateRange>((ref, range) {
  ref.watch(authStateProvider);
  return ref
      .watch(expensesRepositoryProvider)
      .watchByDateRange(range.start, range.end);
});

final recentExpensesProvider =
    StreamProvider.autoDispose<List<Expense>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(expensesRepositoryProvider).watchRecent();
});

final expenseByIdProvider =
    StreamProvider.family.autoDispose<Expense?, String>((ref, id) {
  ref.watch(authStateProvider);
  return ref.watch(expensesRepositoryProvider).watchById(id);
});
