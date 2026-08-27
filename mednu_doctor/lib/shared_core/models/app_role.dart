import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Every professional role the MedNu Partner app can host.
///
/// This is additive infrastructure: today's `doctors/{uid}` documents have
/// no `roles` field, so every reader in this layer treats a missing/absent
/// value as `[AppRole.doctor]` rather than throwing. No existing document
/// needs to be migrated for the app to keep working exactly as before.
enum AppRole { doctor, ambulance, pharmacy, lab, caregiver, physiotherapist, counsellor, nutritionist, admin }

extension AppRoleX on AppRole {
  /// Value stored in Firestore (`roles` / `activeRole` fields). Kept
  /// deliberately distinct from the legacy `type` field on `doctors/{uid}`,
  /// which is never read or written by this layer.
  String get firestoreValue {
    switch (this) {
      case AppRole.doctor:
        return 'doctor';
      case AppRole.ambulance:
        return 'ambulance';
      case AppRole.pharmacy:
        return 'pharmacy';
      case AppRole.lab:
        return 'lab';
      case AppRole.caregiver:
        return 'caregiver';
      case AppRole.physiotherapist:
        return 'physiotherapist';
      case AppRole.counsellor:
        return 'counsellor';
      case AppRole.nutritionist:
        return 'nutritionist';
      case AppRole.admin:
        return 'admin';
    }
  }

  String get label {
    switch (this) {
      case AppRole.doctor:
        return 'Doctor';
      case AppRole.ambulance:
        return 'Ambulance';
      case AppRole.pharmacy:
        return 'Pharmacy';
      case AppRole.lab:
        return 'Lab & Diagnostics';
      case AppRole.caregiver:
        return 'Caregiver';
      case AppRole.physiotherapist:
        return 'Physiotherapist';
      case AppRole.counsellor:
        return 'Counsellor';
      case AppRole.nutritionist:
        return 'Nutritionist';
      case AppRole.admin:
        return 'Admin';
    }
  }

  /// One-line description of the role, shown under [label] on the
  /// registration role-picker so each option carries enough information
  /// density to feel considered rather than a bare icon + word.
  String get subtitle {
    switch (this) {
      case AppRole.doctor:
        return 'Consult & treat patients';
      case AppRole.ambulance:
        return 'Emergency transport & dispatch';
      case AppRole.pharmacy:
        return 'Fulfil prescriptions';
      case AppRole.lab:
        return 'Run tests & share reports';
      case AppRole.caregiver:
        return 'Home care & assistance';
      case AppRole.physiotherapist:
        return 'Rehab & physiotherapy sessions';
      case AppRole.counsellor:
        return 'Mental health & counselling';
      case AppRole.nutritionist:
        return 'Diet & nutrition consultations';
      case AppRole.admin:
        return 'Manage platform operations';
    }
  }

  IconData get icon {
    switch (this) {
      case AppRole.doctor:
        return Icons.medical_services_rounded;
      case AppRole.ambulance:
        return Icons.local_hospital_rounded;
      case AppRole.pharmacy:
        return Icons.local_pharmacy_rounded;
      case AppRole.lab:
        return Icons.biotech_rounded;
      case AppRole.caregiver:
        return Icons.volunteer_activism_rounded;
      case AppRole.physiotherapist:
        return Icons.accessibility_new_rounded;
      case AppRole.counsellor:
        return Icons.psychology_rounded;
      case AppRole.nutritionist:
        return Icons.restaurant_menu_rounded;
      case AppRole.admin:
        return Icons.admin_panel_settings_rounded;
    }
  }

  Color get accentColor {
    switch (this) {
      case AppRole.doctor:
        return AppColors.primary;
      case AppRole.ambulance:
        return const Color(0xFFC62828);
      case AppRole.pharmacy:
        return const Color(0xFF00897B);
      case AppRole.lab:
        return const Color(0xFF1565C0);
      case AppRole.caregiver:
        return const Color(0xFF6A1B9A);
      case AppRole.physiotherapist:
        return const Color(0xFF00838F);
      case AppRole.counsellor:
        return const Color(0xFF5E35B1);
      case AppRole.nutritionist:
        return const Color(0xFF2E7D32);
      case AppRole.admin:
        return const Color(0xFF37474F);
    }
  }

  static AppRole fromFirestoreValue(String? raw) {
    switch (raw) {
      case 'doctor':
        return AppRole.doctor;
      case 'ambulance':
        return AppRole.ambulance;
      case 'pharmacy':
        return AppRole.pharmacy;
      case 'lab':
        return AppRole.lab;
      case 'caregiver':
        return AppRole.caregiver;
      case 'physiotherapist':
        return AppRole.physiotherapist;
      case 'counsellor':
        return AppRole.counsellor;
      case 'nutritionist':
        return AppRole.nutritionist;
      case 'admin':
        return AppRole.admin;
      default:
        return AppRole.doctor;
    }
  }

  /// Parses a Firestore `roles` field of unknown shape (missing, empty,
  /// malformed) into a safe, non-empty role list. Falls back to
  /// `[AppRole.doctor]`, matching every account in production today.
  static List<AppRole> listFrom(dynamic rawRoles) {
    if (rawRoles is List) {
      final parsed = rawRoles
          .whereType<String>()
          .map(fromFirestoreValue)
          .toSet() // de-dupe
          .toList();
      if (parsed.isNotEmpty) return parsed;
    }
    return const [AppRole.doctor];
  }
}
