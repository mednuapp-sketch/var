import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_role.dart';

/// Read-only view over `doctors/{uid}` shaped for the Shared Core layer.
///
/// This is intentionally **not** a rename or reshape of the existing
/// document — every field is read with a safe default, and no field this
/// class reads is required to exist for [fromSnapshot] to succeed. New
/// fields introduced here (`roles`, `activeRole`) are optional and never
/// written by this layer, so no Firestore migration is required to adopt it.
class UserProfile {
  final String uid;
  final String name;
  final String phone;
  final String email;
  final String photoUrl;
  final bool isVerified;
  final bool isOnline;
  final String status; // 'pending' | 'active' | ... (existing approval gate)
  final List<AppRole> roles;
  final AppRole? preferredActiveRole; // optional `activeRole` field, if set
  final Map<String, dynamic> raw;

  const UserProfile({
    required this.uid,
    required this.name,
    required this.phone,
    required this.email,
    required this.photoUrl,
    required this.isVerified,
    required this.isOnline,
    required this.status,
    required this.roles,
    required this.preferredActiveRole,
    required this.raw,
  });

  factory UserProfile.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? const <String, dynamic>{};
    final activeRoleRaw = d['activeRole'] as String?;
    return UserProfile(
      uid: snap.id,
      name: (d['name'] as String?) ?? '',
      phone: (d['phone'] as String?) ?? '',
      email: (d['email'] as String?) ?? '',
      photoUrl: (d['photoUrl'] as String?) ?? '',
      isVerified: (d['isVerified'] as bool?) ?? false,
      isOnline: (d['isOnline'] as bool?) ?? false,
      status: (d['status'] as String?) ?? 'pending',
      roles: AppRoleX.listFrom(d['roles']),
      preferredActiveRole:
          activeRoleRaw != null ? AppRoleX.fromFirestoreValue(activeRoleRaw) : null,
      raw: d,
    );
  }

  String get initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
