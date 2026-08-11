import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/services/doctor_auth_service.dart';
import '../models/user_profile.dart';

/// Single source of truth for "who is signed in right now," realtime.
///
/// Wraps [DoctorAuthService.profileStream] rather than bypassing it — every
/// existing call site that uses `DoctorAuthService.currentUid` /
/// `.profileStream` directly keeps working untouched. This provider is new
/// infrastructure additive on top, not a replacement.
final currentUserProvider = StreamProvider.autoDispose<UserProfile?>((ref) {
  final uid = DoctorAuthService.currentUid;
  if (uid == null) return Stream.value(null);
  return DoctorAuthService.profileStream(uid).map(
    (snap) => snap.exists ? UserProfile.fromSnapshot(snap) : null,
  );
});
