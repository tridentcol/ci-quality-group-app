import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/clock.dart';

/// Un gasto de bodega (arreglo de llantas, combustible, insumos, …) con
/// su soporte fotográfico opcional. Independiente de `sales` y de
/// `material_entries`; no tiene consecutivo.
class Expense {
  const Expense({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    this.category,
    required this.paidBy,
    this.photoUrl,
    this.photoStoragePath,
    this.notes,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    this.updatedAt,
    this.editableUntil,
  });

  final String id;
  final DateTime date;
  final String description;
  final num amount;

  /// De la lista maestra `expense_categories`. Opcional.
  final String? category;

  /// Quién puso la plata. De la lista maestra `expense_payers`.
  final String paidBy;

  final String? photoUrl;

  /// Path en Storage de la foto (`expenses/{id}/receipt.jpg`). Se guarda
  /// aparte de la URL para poder borrar el archivo al quitar la foto o
  /// borrar el gasto.
  final String? photoStoragePath;

  final String? notes;

  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Ventana fija de edición (`createdAt + 24h`), mismo patrón que
  /// `Sale.editableUntil` y `MaterialEntry.editableUntil`.
  final DateTime? editableUntil;

  bool get isEditable =>
      editableUntil == null || AppClock.now().isBefore(editableUntil!);

  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(AppClock.toInstant(date)),
        'description': description,
        'amount': amount,
        'category': category,
        'paidBy': paidBy,
        'photoUrl': photoUrl,
        'photoStoragePath': photoStoragePath,
        'notes': notes,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': Timestamp.fromDate(AppClock.toInstant(createdAt)),
        'updatedAt': updatedAt == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(updatedAt!)),
        'editableUntil': editableUntil == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(editableUntil!)),
      };

  factory Expense.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data()!;
    return Expense(
      id: snap.id,
      date: AppClock.fromInstant((data['date'] as Timestamp).toDate()),
      description: (data['description'] as String?) ?? '',
      amount: (data['amount'] as num?) ?? 0,
      category: data['category'] as String?,
      paidBy: (data['paidBy'] as String?) ?? '',
      photoUrl: data['photoUrl'] as String?,
      photoStoragePath: data['photoStoragePath'] as String?,
      notes: data['notes'] as String?,
      createdBy: (data['createdBy'] as String?) ?? '',
      createdByName: (data['createdByName'] as String?) ?? '',
      createdAt:
          AppClock.fromInstant((data['createdAt'] as Timestamp).toDate()),
      updatedAt: data['updatedAt'] == null
          ? null
          : AppClock.fromInstant((data['updatedAt'] as Timestamp).toDate()),
      editableUntil: data['editableUntil'] == null
          ? null
          : AppClock.fromInstant(
              (data['editableUntil'] as Timestamp).toDate(),
            ),
    );
  }
}
