import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_role.dart';

/// Local-only persistence for "which role did this device last use."
///
/// Deliberately never touches Firestore: the Prompt 2 role switcher is a
/// client-side preference over roles the account already holds, not a
/// mechanism for granting/writing roles. Uses the same [SharedPreferences]
/// dependency already used elsewhere in the app (e.g. settings toggles).
class RolePrefs {
  RolePrefs._();

  static const _key = 'mednu_active_role';

  static Future<AppRole?> getActiveRole() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return AppRoleX.fromFirestoreValue(raw);
  }

  static Future<void> setActiveRole(AppRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, role.firestoreValue);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Resolves which role should be treated as "active" for a multi-role
  /// account, using the same precedence `roleEngineProvider` (shared_core/
  /// providers/role_providers.dart) already applies for every other screen
  /// in the app: persisted device preference > the account doc's own
  /// `activeRole` field > whichever role the account was granted first.
  ///
  /// Every call site that used to resolve this as a bare `roles.first`
  /// (post-login navigation in doctor_login_screen.dart /
  /// doctor_otp_screen.dart, and the router's own `_AuthChangeNotifier`)
  /// permanently stuck any account that was ever a Doctor before adding a
  /// second role on the Doctor dashboard on every fresh login/app-restart —
  /// `arrayUnion` appends new roles to the end of `roles` and never
  /// reorders it, so `.first` always meant "whichever role came first
  /// historically," not "whichever role this device is actually using."
  static Future<AppRole> resolveActive(
    List<AppRole> roles, {
    AppRole? serverPreferred,
  }) async {
    if (roles.isEmpty) return AppRole.doctor;
    final persisted = await getActiveRole();
    if (persisted != null && roles.contains(persisted)) return persisted;
    if (serverPreferred != null && roles.contains(serverPreferred)) {
      return serverPreferred;
    }
    return roles.first;
  }
}
