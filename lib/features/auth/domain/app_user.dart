import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/roles.dart';
import '../../../core/utils/clock.dart';

/// Filtro asociado a un usuario `auditor`. Define qué subset de ventas
/// puede ver en su dashboard:
///   field: 'materialVariant' / 'material' / 'providerName' / etc.
///   value: el valor exacto (ej. 'PEDRO').
///
/// Se guarda como un mapa anidado en `users/{uid}.auditFilter`. Si el
/// rol no es auditor, este campo viene null.
class AuditFilter {
  const AuditFilter({required this.field, required this.value});
  final String field;
  final String value;

  /// Etiqueta legible del campo para mostrar en UI ("Tipo de material",
  /// "Cliente", etc.). Se mantiene en español y mapeada explícitamente
  /// para que admin entienda qué está configurando.
  String get fieldLabel => switch (field) {
        'materialVariant' => 'Tipo de material',
        'material' => 'Material',
        'providerName' => 'Cliente',
        'payerName' => 'Quién recibe',
        'paymentMethod' => 'Método de pago',
        'transferDestination' => 'Destino transferencia',
        _ => field,
      };

  Map<String, dynamic> toMap() => {'field': field, 'value': value};

  static AuditFilter? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final f = data['field'] as String?;
    final v = data['value'] as String?;
    if (f == null || v == null || f.isEmpty || v.isEmpty) return null;
    return AuditFilter(field: f, value: v);
  }
}

/// Usuario de la app (admin / control de ventas / control de horas /
/// auditor).
///
/// `username` es lo que el usuario digita en el login. Internamente se
/// mapea a un correo sintético (`<username>@cqg.app`) que es lo que Firebase
/// Auth necesita.
class AppUser {
  const AppUser({
    required this.uid,
    required this.username,
    required this.fullName,
    required this.role,
    this.active = true,
    this.createdAt,
    this.auditFilter,
  });

  final String uid;
  final String username;
  final String fullName;
  final AppRole role;
  final bool active;
  final DateTime? createdAt;

  /// Solo se setea cuando role == auditor. Define qué ventas ve.
  final AuditFilter? auditFilter;

  static String emailFor(String username) =>
      '${username.trim().toLowerCase()}@cqg.app';

  Map<String, dynamic> toMap() => {
        'username': username,
        'fullName': fullName,
        'role': role.id,
        'active': active,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(AppClock.toInstant(createdAt!)),
        if (auditFilter != null) 'auditFilter': auditFilter!.toMap(),
      };

  factory AppUser.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data()!;
    return AppUser(
      uid: snap.id,
      username: data['username'] as String,
      fullName: data['fullName'] as String,
      role: AppRole.fromId(data['role'] as String),
      active: (data['active'] as bool?) ?? true,
      createdAt: data['createdAt'] == null
          ? null
          : AppClock.fromInstant((data['createdAt'] as Timestamp).toDate()),
      auditFilter:
          AuditFilter.fromMap(data['auditFilter'] as Map<String, dynamic>?),
    );
  }
}
