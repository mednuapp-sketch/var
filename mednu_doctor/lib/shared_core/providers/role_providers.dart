import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_role.dart';
import '../services/role_prefs.dart';
import 'current_user_provider.dart';

/// Computed, read-only snapshot of the role engine — this is what UI code
/// should branch on instead of hardcoding role checks against raw Firestore
/// fields.
class RoleEngineState {
  final List<AppRole> roles;
  final AppRole activeRole;
  final bool isLoading;

  const RoleEngineState({
    required this.roles,
    required this.activeRole,
    required this.isLoading,
  });

  bool get isDoctor => activeRole == AppRole.doctor;
  bool get isAmbulance => activeRole == AppRole.ambulance;
  bool get isPharmacy => activeRole == AppRole.pharmacy;
  bool get isLab => activeRole == AppRole.lab;
  bool get isCaregiver => activeRole == AppRole.caregiver;
  bool get isPhysiotherapist => activeRole == AppRole.physiotherapist;
  bool get isCounsellor => activeRole == AppRole.counsellor;
  bool get isNutritionist => activeRole == AppRole.nutritionist;
  bool get isHospital => activeRole == AppRole.hospital;
  bool get isAdmin => activeRole == AppRole.admin;

  bool get canSwitchRoles => roles.length > 1;

  /// First role granted to the account — used as the default landing role
  /// and as the fallback when a persisted `activeRole` is no longer valid
  /// (e.g. a role was revoked server-side).
  AppRole get primaryRole => roles.isNotEmpty ? roles.first : AppRole.doctor;
}

/// Persisted "last selected role" for this device. Reconciled against the
/// account's actual `roles` list by [roleEngineProvider] below — a stale
/// pref pointing at a role the account no longer holds never leaks into the
/// UI.
class ActiveRoleNotifier extends StateNotifier<AppRole?> {
  ActiveRoleNotifier() : super(null) {
    _restore();
  }

  Future<void> _restore() async {
    state = await RolePrefs.getActiveRole();
  }

  Future<void> switchTo(AppRole role) async {
    state = role;
    await RolePrefs.setActiveRole(role);
  }
}

final activeRoleProvider =
    StateNotifierProvider<ActiveRoleNotifier, AppRole?>(
        (ref) => ActiveRoleNotifier());

/// True while a role switch is in flight — the role switcher sheet shows a
/// loading state and blocks re-entry while this is true.
final roleSwitchInProgressProvider = StateProvider<bool>((ref) => false);

/// Extension point for feature modules (e.g. an active Agora call screen)
/// to block role switching mid-operation. Defaults to `false` and is not
/// wired into any existing screen by this layer — the Doctor module's call
/// screens are untouched per the Shared-Core-only scope of this change.
/// A future module sets this to `true` on entering a critical operation and
/// back to `false` on leaving it.
final criticalOperationInProgressProvider = StateProvider<bool>((ref) => false);

/// The role engine: single derived source of truth combining the account's
/// realtime `roles` (via [currentUserProvider]) with the device's persisted
/// `activeRole` (via [activeRoleProvider]), with safe defaults at every
/// stage so a brand-new/loading/error state never crashes the UI.
final roleEngineProvider = Provider<RoleEngineState>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  final persistedActive = ref.watch(activeRoleProvider);

  return userAsync.when(
    data: (user) {
      final roles = (user?.roles.isNotEmpty ?? false)
          ? user!.roles
          : const [AppRole.doctor];
      final resolved = (persistedActive != null && roles.contains(persistedActive))
          ? persistedActive
          : (user?.preferredActiveRole != null &&
                  roles.contains(user!.preferredActiveRole))
              ? user.preferredActiveRole!
              : roles.first;
      return RoleEngineState(roles: roles, activeRole: resolved, isLoading: false);
    },
    loading: () => const RoleEngineState(
      roles: [AppRole.doctor],
      activeRole: AppRole.doctor,
      isLoading: true,
    ),
    error: (_, __) => const RoleEngineState(
      roles: [AppRole.doctor],
      activeRole: AppRole.doctor,
      isLoading: false,
    ),
  );
});
