import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/roles.dart';

/// Usuario de la app (admin / control de ventas / control de horas).
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
  });

  final String uid;
  final String username;
  final String fullName;
  final AppRole role;
  final bool active;
  final DateTime? createdAt;

  static String emailFor(String username) =>
      '${username.trim().toLowerCase()}@cqg.app';

  Map<String, dynamic> toMap() => {
        'username': username,
        'fullName': fullName,
        'role': role.id,
        'active': active,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(createdAt!),
      };

  factory AppUser.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data()!;
    return AppUser(
      uid: snap.id,
      username: data['username'] as String,
      fullName: data['fullName'] as String,
      role: AppRole.fromId(data['role'] as String),
      active: (data['active'] as bool?) ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
