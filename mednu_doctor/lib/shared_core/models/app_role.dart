import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Every professional role the MedNu Partner app can host.
///
/// This is additive infrastructure: today's `doctors/{uid}` documents have
/// no `roles` field, so every reader in this layer treats a missing/absent
/// value as `[AppRole.doctor]` rather than throwing. No existing document
/// needs to be migrated for the app to keep working exactly as before.
enum AppRole { doctor, ambulance, pharmacy, lab, equipment, caregiver, careAssistant, physiotherapist, counsellor, nutritionist, hospital, admin }

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
      case AppRole.equipment:
        return 'equipment';
      case AppRole.caregiver:
        return 'caregiver';
      case AppRole.careAssistant:
        return 'care_assistant';
      case AppRole.physiotherapist:
        return 'physiotherapist';
      case AppRole.counsellor:
        return 'counsellor';
      case AppRole.nutritionist:
        return 'nutritionist';
      case AppRole.hospital:
        return 'hospital';
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
      case AppRole.equipment:
        return 'Medical Equipment';
      case AppRole.caregiver:
        return 'Nurse';
      case AppRole.careAssistant:
        return 'Care Assistant';
      case AppRole.physiotherapist:
        return 'Physiotherapist';
      case AppRole.counsellor:
        return 'Counsellor';
      case AppRole.nutritionist:
        return 'Dietician';
      case AppRole.hospital:
        return 'Hospital';
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
      case AppRole.equipment:
        return 'Rent & sell medical equipment';
      case AppRole.caregiver:
        return 'Home Care & Assistance';
      case AppRole.careAssistant:
        return 'Hospital escort & errands';
      case AppRole.physiotherapist:
        return 'Rehab & physiotherapy sessions';
      case AppRole.counsellor:
        return 'Mental health & counselling';
      case AppRole.nutritionist:
        return 'Dietician consultations';
      case AppRole.hospital:
        return 'Confirm patient bill payments';
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
      case AppRole.equipment:
        return Icons.health_and_safety_rounded;
      case AppRole.caregiver:
        return Icons.volunteer_activism_rounded;
      case AppRole.careAssistant:
        return Icons.support_agent_rounded;
      case AppRole.physiotherapist:
        return Icons.accessibility_new_rounded;
      case AppRole.counsellor:
        return Icons.psychology_rounded;
      case AppRole.nutritionist:
        return Icons.restaurant_menu_rounded;
      case AppRole.hospital:
        return Icons.receipt_long_rounded;
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
      case AppRole.equipment:
        return const Color(0xFFEF6C00);
      case AppRole.caregiver:
        return const Color(0xFF6A1B9A);
      case AppRole.careAssistant:
        return const Color(0xFF00897B);
      case AppRole.physiotherapist:
        return const Color(0xFF00838F);
      case AppRole.counsellor:
        return const Color(0xFF5E35B1);
      case AppRole.nutritionist:
        return const Color(0xFF2E7D32);
      case AppRole.hospital:
        return const Color(0xFF00695C);
      case AppRole.admin:
        return const Color(0xFF37474F);
    }
  }

  /// Firestore collection holding this role's partner profile. A Care
  /// Assistant is its own role in the app but shares the `caregiver_profiles`
  /// collection (distinguished by `serviceType: 'care_assistant'`), so the
  /// visit pipeline, approval flow, wallet ledger and Cloud Functions that
  /// already serve caregivers apply to it unchanged.
  String get profileCollection =>
      this == AppRole.careAssistant ? 'caregiver_profiles' : '${firestoreValue}_profiles';

  /// Token for `PartnerDocumentType.forRole` / Storage prefixes, which are
  /// keyed by profile collection name rather than role.
  String get documentRoleKey => this == AppRole.careAssistant ? 'caregiver' : firestoreValue;

  /// Key into `PartnerDocumentType.forRole` — differs from [documentRoleKey]
  /// for a Care Assistant, which stores files like a caregiver but has its
  /// own (ID-only) checklist.
  String get documentTypeKey => firestoreValue;

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
      case 'equipment':
        return AppRole.equipment;
      case 'caregiver':
        return AppRole.caregiver;
      case 'care_assistant':
        return AppRole.careAssistant;
      case 'physiotherapist':
        return AppRole.physiotherapist;
      case 'counsellor':
        return AppRole.counsellor;
      case 'nutritionist':
        return AppRole.nutritionist;
      case 'hospital':
        return AppRole.hospital;
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
