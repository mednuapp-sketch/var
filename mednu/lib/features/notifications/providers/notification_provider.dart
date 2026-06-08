import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';

final patientNotificationsProvider =
    StreamProvider.autoDispose<List<NotificationModel>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  return PatientNotificationService.streamForPatient(uid);
});

final patientUnreadCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(patientNotificationsProvider).when(
        data: (list) => list.where((n) => !n.isRead).length,
        loading: () => 0,
        error: (_, __) => 0,
      );
});
