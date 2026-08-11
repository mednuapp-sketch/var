/// Documents the contract a future Admin-managed multi-role migration must
/// satisfy. This file contains **no client-side write logic** — the MedNu
/// Partner client never writes `roles` / `activeRole` to `doctors/{uid}`.
/// Those fields are set exclusively server-side (e.g. a Cloud Function
/// triggered from MedNu Admin once an account is approved for an
/// additional role such as Ambulance or Pharmacy).
///
/// Contract for whatever writes those fields later:
///  - `roles`: `List<String>`, each entry one of [AppRole.firestoreValue]
///    (`'doctor' | 'ambulance' | 'pharmacy' | 'lab' | 'caregiver' | 'admin'`).
///  - `activeRole`: optional `String`, one of `roles` — the role the app
///    should land on by default. Falls back to `roles.first` if absent or
///    if it no longer appears in `roles` (see `role_providers.dart`).
///
/// The moment such a write lands on a `doctors/{uid}` document, the
/// existing realtime pipeline (`currentUserProvider` → `roleEngineProvider`
/// in `providers/role_providers.dart`, both already listening on
/// `DoctorAuthService.profileStream`) picks it up automatically. No app
/// release is required to "activate" a newly multi-role account — the
/// role switcher simply starts showing more than one tile.
library role_migration_hook;

class RoleMigrationHook {
  RoleMigrationHook._();

  /// True once an account has been migrated to hold more than one role.
  /// Read-only convenience for callers that want to branch on "is this a
  /// migrated, multi-role account" — never a trigger for a write.
  static bool isMigrated(List<dynamic> roles) => roles.length > 1;
}
