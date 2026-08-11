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
}
