import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../auth/data/auth_repository.dart';

/// Destinatarios del correo que dispara cada ingreso de material nuevo
/// (`mail/{id}`, consumido por la extensión de Firebase
/// `firestore-send-email`). Doc singleton admin-only, mismo patrón que
/// `WorkScheduleRepository`.
class MaterialNotificationSettingsRepository {
  MaterialNotificationSettingsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _ref => _firestore
      .collection(FirestorePaths.settings)
      .doc(FirestorePaths.materialNotificationSettings);

  Stream<List<String>> watch() {
    return _ref.snapshots().map((snap) {
      final raw = snap.data()?['recipientEmails'] as List?;
      return (raw ?? const []).cast<String>();
    });
  }

  Future<void> save(List<String> emails) async {
    await _ref.set({'recipientEmails': emails}, SetOptions(merge: true));
  }
}

final materialNotificationSettingsRepositoryProvider =
    Provider<MaterialNotificationSettingsRepository>((ref) {
  return MaterialNotificationSettingsRepository(FirebaseFirestore.instance);
});

final materialNotificationEmailsProvider =
    StreamProvider.autoDispose<List<String>>((ref) {
  ref.watch(authStateProvider);
  return ref
      .watch(materialNotificationSettingsRepositoryProvider)
      .watch();
});
