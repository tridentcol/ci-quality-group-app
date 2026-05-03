import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/clock.dart';
import 'hours_categories.dart';

/// Registro de horas de un trabajador en un día específico.
///
/// La idea es que el encargado abre el día con la entrada, puede ajustar
/// durante la jornada, y al final hace el cierre. La salida queda confirmada
/// solo cuando `closedAt != null`.
class HoursEntry {
  const HoursEntry({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.workDate,
    required this.checkIn,
    this.checkOut,
    this.closedAt,
    this.note,
    required this.breakdown,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    this.updatedAt,
    this.editableUntil,
    this.customFields = const {},
  });

  final String id;
  final String workerId;
  final String workerName;

  /// Día calendario al que pertenece el registro (00:00 local).
  final DateTime workDate;

  final DateTime checkIn;
  final DateTime? checkOut;

  /// Cuando se hace el "cierre del día". Mientras sea `null`, el día está
  /// abierto y el encargado puede modificar `checkOut`.
  final DateTime? closedAt;

  final String? note;

  /// Distribución por categoría calculada al cerrar el día. Se guarda para
  /// no recalcular al consultar reportes.
  final HoursBreakdown breakdown;

  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Ventana de 24 h durante la cual el encargado puede editar luego de cerrar.
  final DateTime? editableUntil;

  final Map<String, dynamic> customFields;

  bool get isOpen => closedAt == null;

  Map<String, dynamic> toMap() => {
        'workerId': workerId,
        'workerName': workerName,
        'workDate': Timestamp.fromDate(AppClock.toInstant(workDate)),
        'checkIn': Timestamp.fromDate(AppClock.toInstant(checkIn)),
        'checkOut': checkOut == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(checkOut!)),
        'closedAt': closedAt == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(closedAt!)),
        'note': note,
        'breakdown': breakdown.toMinutesMap(),
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': Timestamp.fromDate(AppClock.toInstant(createdAt)),
        'updatedAt': updatedAt == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(updatedAt!)),
        'editableUntil': editableUntil == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(editableUntil!)),
        'customFields': customFields,
      };

  factory HoursEntry.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data()!;
    return HoursEntry(
      id: snap.id,
      workerId: data['workerId'] as String,
      workerName: data['workerName'] as String,
      workDate: AppClock.fromInstant((data['workDate'] as Timestamp).toDate()),
      checkIn: AppClock.fromInstant((data['checkIn'] as Timestamp).toDate()),
      checkOut: data['checkOut'] == null
          ? null
          : AppClock.fromInstant((data['checkOut'] as Timestamp).toDate()),
      closedAt: data['closedAt'] == null
          ? null
          : AppClock.fromInstant((data['closedAt'] as Timestamp).toDate()),
      note: data['note'] as String?,
      breakdown: HoursBreakdown.fromMinutesMap(
        Map<String, dynamic>.from(data['breakdown'] as Map? ?? const {}),
      ),
      createdBy: data['createdBy'] as String,
      createdByName: data['createdByName'] as String,
      createdAt:
          AppClock.fromInstant((data['createdAt'] as Timestamp).toDate()),
      updatedAt: data['updatedAt'] == null
          ? null
          : AppClock.fromInstant((data['updatedAt'] as Timestamp).toDate()),
      editableUntil: data['editableUntil'] == null
          ? null
          : AppClock.fromInstant((data['editableUntil'] as Timestamp).toDate()),
      customFields:
          Map<String, dynamic>.from(data['customFields'] as Map? ?? const {}),
    );
  }
}
