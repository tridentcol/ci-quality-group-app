import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/clock.dart';

/// Trabajador operativo. No es usuario de la app — solo se le registran horas.
class Worker {
  const Worker({
    required this.id,
    required this.fullName,
    required this.idNumber,
    required this.role,
    this.address,
    this.email,
    this.phone,
    this.bank,
    this.active = true,
    this.createdAt,
    this.deactivatedAt,
  });

  final String id;
  final String fullName;
  final String idNumber;
  final String role;
  final String? address;
  final String? email;
  final String? phone;
  final String? bank;
  final bool active;
  final DateTime? createdAt;
  final DateTime? deactivatedAt;

  Worker copyWith({
    String? fullName,
    String? idNumber,
    String? role,
    String? address,
    String? email,
    String? phone,
    String? bank,
    bool? active,
    DateTime? deactivatedAt,
  }) {
    return Worker(
      id: id,
      fullName: fullName ?? this.fullName,
      idNumber: idNumber ?? this.idNumber,
      role: role ?? this.role,
      address: address ?? this.address,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      bank: bank ?? this.bank,
      active: active ?? this.active,
      createdAt: createdAt,
      deactivatedAt: deactivatedAt ?? this.deactivatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'fullName': fullName,
        'idNumber': idNumber,
        'role': role,
        'address': address,
        'email': email,
        'phone': phone,
        'bank': bank,
        'active': active,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(AppClock.toInstant(createdAt!)),
        'deactivatedAt': deactivatedAt == null
            ? null
            : Timestamp.fromDate(AppClock.toInstant(deactivatedAt!)),
      };

  factory Worker.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data()!;
    return Worker(
      id: snap.id,
      fullName: data['fullName'] as String,
      idNumber: data['idNumber'] as String,
      role: data['role'] as String,
      address: data['address'] as String?,
      email: data['email'] as String?,
      phone: data['phone'] as String?,
      bank: data['bank'] as String?,
      active: (data['active'] as bool?) ?? true,
      createdAt: data['createdAt'] == null
          ? null
          : AppClock.fromInstant((data['createdAt'] as Timestamp).toDate()),
      deactivatedAt: data['deactivatedAt'] == null
          ? null
          : AppClock.fromInstant((data['deactivatedAt'] as Timestamp).toDate()),
    );
  }
}
