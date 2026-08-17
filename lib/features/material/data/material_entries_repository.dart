import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../shared/models/app_notification.dart';
import '../../../shared/services/notifications_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/material_entry.dart';

/// Acceso a la colección `material_entries` (control de ingreso de
/// material). Mismo patrón que `SalesRepository`: consecutivo `ING-XXX`
/// atómico vía `runTransaction`, notificación in-app emitida en la misma
/// transacción, y opcionalmente un doc en `mail/` para que la extensión
/// de Firebase `firestore-send-email` le avise a gerencia por correo.
class MaterialEntriesRepository {
  MaterialEntriesRepository(
    this._firestore,
    this._storage,
    this._notifications,
  );

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final NotificationsRepository _notifications;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(FirestorePaths.materialEntries);

  DocumentReference<Map<String, dynamic>> _counterRefFor(
    MaterialMovementType type,
  ) =>
      _firestore.collection(FirestorePaths.counters).doc(
            type == MaterialMovementType.ingreso
                ? FirestorePaths.materialEntriesCounter
                : FirestorePaths.materialExitsCounter,
          );

  /// Genera el id que va a tener el próximo ingreso ANTES de crearlo.
  /// El formulario lo usa para subir las fotos a Storage (path
  /// `material_entries/{id}/...`) antes de escribir el doc — así el doc
  /// nace con las URLs ya resueltas.
  DocumentReference<Map<String, dynamic>> newEntryRef() => _col.doc();

  /// Sube una foto (`kind`: `'material'` u `'origin'`) y devuelve su
  /// download URL. Estas URLs no requieren sesión de Firebase para
  /// visualizarse (el token va embebido en la URL) — es justamente lo
  /// que permite incrustarlas en el correo a gerencia.
  Future<String> uploadPhoto({
    required String entryId,
    required String kind,
    required Uint8List bytes,
  }) async {
    final ref =
        _storage.ref().child('material_entries/$entryId/$kind.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Crea un movimiento (ingreso o salida). `entryRef` debe venir de
  /// [newEntryRef] (mismo id usado para subir las fotos previamente).
  /// Exactamente uno de `providerName`/`clientName` debe venir según
  /// `type` — lo valida el formulario antes de llamar acá.
  Future<MaterialEntry> createEntry({
    required DocumentReference<Map<String, dynamic>> entryRef,
    required MaterialMovementType type,
    required DateTime date,
    required String material,
    String? materialVariant,
    required num quantity,
    required String unit,
    String? providerName,
    String? clientName,
    String? originDescription,
    String? vehicleRef,
    required String materialPhotoUrl,
    String? originPhotoUrl,
    String? notes,
    required String createdBy,
    required String createdByName,
  }) async {
    final now = AppClock.now();
    final counterRef = _counterRefFor(type);

    final entry = await _firestore.runTransaction<MaterialEntry>((txn) async {
      final counterSnap = await txn.get(counterRef);
      final current = (counterSnap.data()?['value'] as num?)?.toInt() ?? 0;
      final next = current + 1;
      final consecutive = _formatConsecutive(type, next);

      final entry = MaterialEntry(
        id: entryRef.id,
        consecutive: consecutive,
        type: type,
        date: date,
        material: material,
        materialVariant: materialVariant,
        quantity: quantity,
        unit: unit,
        providerName: providerName,
        clientName: clientName,
        originDescription: originDescription,
        vehicleRef: vehicleRef,
        materialPhotoUrl: materialPhotoUrl,
        originPhotoUrl: originPhotoUrl,
        notes: notes,
        createdBy: createdBy,
        createdByName: createdByName,
        createdAt: now,
        editableUntil: now.add(const Duration(hours: 24)),
      );

      txn.set(counterRef, {'value': next}, SetOptions(merge: true));
      txn.set(entryRef, entry.toMap());

      final isIngreso = type == MaterialMovementType.ingreso;
      _notifications.emitInTxn(
        txn,
        type: isIngreso
            ? NotificationType.materialEntryCreated
            : NotificationType.materialExitCreated,
        title: isIngreso ? 'Nuevo ingreso de material' : 'Nueva salida de material',
        body: '${entry.consecutive} — ${entry.counterpartyName}, '
            '${formatQuantity(quantity)} $unit de ${entry.displayLabel}',
        actorUid: createdBy,
        actorName: createdByName,
        targetRoles: const [AppRole.admin],
        data: {'materialEntryId': entryRef.id},
      );

      return entry;
    });

    // Correo: best-effort, DELIBERADAMENTE fuera de la transacción de
    // arriba. Es una notificación secundaria (gerencia también se
    // entera por la campanita in-app, que sí va en la transacción) —
    // si falla por lo que sea (regla de destinatarios, red, la
    // extensión sin configurar todavía), el ingreso/salida ya quedó
    // guardado igual. Nunca debe poder tumbar el registro del
    // movimiento físico.
    try {
      final recipientEmails = await _fetchRecipientEmails();
      if (recipientEmails.isNotEmpty) {
        final isIngreso = type == MaterialMovementType.ingreso;
        await _firestore.collection(FirestorePaths.mail).doc().set({
          'to': recipientEmails,
          'message': {
            'subject': '${isIngreso ? 'Nuevo ingreso' : 'Nueva salida'} de '
                'material — ${entry.consecutive} (${entry.counterpartyName})',
            'html': _buildMailHtml(entry),
          },
        });
      }
    } catch (_) {
      // Silencioso a propósito — ver comentario arriba.
    }

    return entry;
  }

  /// Edición simple de campos no financieros. Las fotos no se pueden
  /// reemplazar desde acá (si hace falta corregir una foto, se borra el
  /// ingreso y se registra de nuevo — bajo volumen, no amerita más).
  Future<void> updateEntry(
    String id, {
    DateTime? date,
    String? material,
    Object? materialVariant = _unset,
    num? quantity,
    String? unit,
    String? providerName,
    String? clientName,
    Object? originDescription = _unset,
    Object? vehicleRef = _unset,
    Object? notes = _unset,
  }) async {
    final patch = <String, dynamic>{
      if (date != null) 'date': Timestamp.fromDate(AppClock.toInstant(date)),
      if (material != null) 'material': material,
      if (!identical(materialVariant, _unset))
        'materialVariant': materialVariant,
      if (quantity != null) 'quantity': quantity,
      if (unit != null) 'unit': unit,
      if (providerName != null) 'providerName': providerName,
      if (clientName != null) 'clientName': clientName,
      if (!identical(originDescription, _unset))
        'originDescription': originDescription,
      if (!identical(vehicleRef, _unset)) 'vehicleRef': vehicleRef,
      if (!identical(notes, _unset)) 'notes': notes,
      'updatedAt': Timestamp.fromDate(AppClock.toInstant(AppClock.now())),
    };
    if (patch.isEmpty) return;
    await _col.doc(id).update(patch);
  }

  /// Borra el doc y sus fotos en Storage. Best-effort sobre las fotos:
  /// si por lo que sea ya no están (o el borrado falla), no bloqueamos
  /// el borrado del registro — quedaría un archivo huérfano en Storage,
  /// que no es grave (no aparece en ningún lado de la app).
  Future<void> deleteEntry(String id) async {
    try {
      final files = await _storage.ref().child('material_entries/$id').listAll();
      await Future.wait(files.items.map((f) => f.delete()));
    } catch (_) {
      // Ver comentario arriba.
    }
    await _col.doc(id).delete();
  }

  Stream<List<MaterialEntry>> watchByDateRange(DateTime start, DateTime end) {
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
        .map((snap) => snap.docs.map(MaterialEntry.fromSnapshot).toList());
  }

  Stream<List<MaterialEntry>> watchRecent({int limit = 50}) {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(MaterialEntry.fromSnapshot).toList());
  }

  Stream<MaterialEntry?> watchById(String id) {
    return _col
        .doc(id)
        .snapshots()
        .map((snap) => snap.exists ? MaterialEntry.fromSnapshot(snap) : null);
  }

  Future<List<String>> _fetchRecipientEmails() async {
    final snap = await _firestore
        .collection(FirestorePaths.settings)
        .doc(FirestorePaths.materialNotificationSettings)
        .get();
    final raw = snap.data()?['recipientEmails'] as List?;
    return (raw ?? const []).cast<String>();
  }

  /// El correo se arma con texto que viene de campos que el usuario
  /// escribe a mano (notas, origen/destino, etc.) — se escapan todos
  /// antes de insertarlos en el HTML para no romper el layout ni dejar
  /// pasar markup involuntario. Las URLs de fotos TAMBIÉN se escapan:
  /// en teoría son download URLs de Storage generadas por el sistema,
  /// pero eso no está garantizado del lado del servidor (alguien con
  /// acceso a la API cruda podría escribir cualquier string ahí), así
  /// que las tratamos igual que cualquier otro input. Además llevan un
  /// `&` en la query string (`?alt=media&token=...`) — escapado a
  /// `&amp;` es lo correcto dentro de un atributo HTML de todas formas.
  static const _esc = HtmlEscape();

  String _buildMailHtml(MaterialEntry entry) {
    final isIngreso = entry.type == MaterialMovementType.ingreso;
    final photos = StringBuffer()
      ..write(
        '<p><strong>Foto del material:</strong><br>'
        '<img src="${_esc.convert(entry.materialPhotoUrl)}" style="max-width:480px;"></p>',
      );
    if (entry.originPhotoUrl != null) {
      photos.write(
        '<p><strong>${isIngreso ? 'Foto de procedencia' : 'Foto de destino'}:</strong><br>'
        '<img src="${_esc.convert(entry.originPhotoUrl!)}" style="max-width:480px;"></p>',
      );
    }
    final originDescription = entry.originDescription;
    final vehicleRef = entry.vehicleRef;
    final notes = entry.notes;
    return '''
<h2>${isIngreso ? 'Nuevo ingreso' : 'Nueva salida'} de material — ${_esc.convert(entry.consecutive)}</h2>
<p><strong>Fecha:</strong> ${formatDateTime(entry.date)}</p>
<p><strong>${entry.type.counterpartyLabel}:</strong> ${_esc.convert(entry.counterpartyName)}</p>
<p><strong>Material:</strong> ${_esc.convert(entry.displayLabel)}</p>
<p><strong>Cantidad:</strong> ${formatQuantity(entry.quantity)} ${_esc.convert(entry.unit)}</p>
${originDescription != null ? '<p><strong>${isIngreso ? 'Origen' : 'Destino'}:</strong> ${_esc.convert(originDescription)}</p>' : ''}
${vehicleRef != null ? '<p><strong>Vehículo/vagón:</strong> ${_esc.convert(vehicleRef)}</p>' : ''}
${notes != null ? '<p><strong>Notas:</strong> ${_esc.convert(notes)}</p>' : ''}
<p><strong>Registrado por:</strong> ${_esc.convert(entry.createdByName)}</p>
$photos
''';
  }

  static String _formatConsecutive(MaterialMovementType type, int value) {
    final padded = value.toString().padLeft(3, '0');
    return type == MaterialMovementType.ingreso ? 'ING-$padded' : 'SAL-$padded';
  }
}

const Object _unset = Object();

final materialEntriesRepositoryProvider =
    Provider<MaterialEntriesRepository>((ref) {
  return MaterialEntriesRepository(
    FirebaseFirestore.instance,
    FirebaseStorage.instance,
    ref.watch(notificationsRepositoryProvider),
  );
});

class MaterialDateRange {
  const MaterialDateRange({required this.start, required this.end});
  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is MaterialDateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

final materialEntriesByRangeProvider = StreamProvider.family
    .autoDispose<List<MaterialEntry>, MaterialDateRange>((ref, range) {
  ref.watch(authStateProvider);
  return ref
      .watch(materialEntriesRepositoryProvider)
      .watchByDateRange(range.start, range.end);
});

final recentMaterialEntriesProvider =
    StreamProvider.autoDispose<List<MaterialEntry>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(materialEntriesRepositoryProvider).watchRecent();
});

final materialEntryByIdProvider =
    StreamProvider.family.autoDispose<MaterialEntry?, String>((ref, id) {
  ref.watch(authStateProvider);
  return ref.watch(materialEntriesRepositoryProvider).watchById(id);
});
