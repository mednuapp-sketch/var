import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../features/auth/services/doctor_auth_service.dart';
import '../../features/auth/screens/doctor_login_screen.dart';
import '../../features/auth/screens/doctor_register_screen.dart';
import '../../features/auth/screens/doctor_otp_screen.dart';
import '../../features/auth/screens/verification_pending_screen.dart';
import '../../features/auth/screens/partner_role_select_screen.dart';
import '../../features/auth/screens/partner_role_register_screen.dart';
import '../../shared_core/models/app_role.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/consultations/screens/incoming_request_screen.dart';
import '../../features/consultations/screens/doctor_video_call_screen.dart';
import '../../features/prescription/screens/write_prescription_screen.dart';
import '../../features/patients/screens/patient_detail_screen.dart';
import '../../features/patients/screens/patients_list_screen.dart';
import '../../features/schedule/screens/availability_screen.dart';
import '../../features/profile/screens/doctor_profile_screen.dart';
import '../../features/notifications/screens/doctor_notifications_screen.dart';
import '../../features/earnings/screens/doctor_earnings_screen.dart';
import '../../features/sos/screens/sos_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/help/screens/help_support_screen.dart';
import '../../features/feedback/screens/patient_feedback_screen.dart';
import '../../features/pregnancy/screens/pregnancy_patients_screen.dart';
import '../../features/pregnancy/screens/pregnancy_patient_detail_screen.dart';
import '../../features/pregnancy/screens/maternity_prescription_screen.dart';
import '../../features/profile/screens/specialization_change_request_screen.dart';
import '../../features/reviews/screens/doctor_reviews_screen.dart';
import '../../features/help/screens/live_chat_screen.dart';
import '../../features/help/screens/report_problem_screen.dart';
import '../../features/consultations/screens/doctor_outgoing_call_screen.dart';
import '../../features/lab/screens/lab_onboarding_screen.dart';
import '../../features/lab/screens/lab_dashboard_screen.dart';
import '../../features/lab/screens/lab_bookings_screen.dart';
import '../../features/lab/screens/lab_booking_detail_screen.dart';
import '../../features/lab/screens/lab_sample_collection_screen.dart';
import '../../features/lab/screens/lab_reports_screen.dart';
import '../../features/lab/screens/lab_earnings_screen.dart';
import '../../features/lab/screens/lab_profile_screen.dart';
import '../../features/pharmacy/screens/pharmacy_onboarding_screen.dart';
import '../../features/pharmacy/screens/pharmacy_dashboard_screen.dart';
import '../../features/pharmacy/screens/pharmacy_orders_screen.dart';
import '../../features/pharmacy/screens/pharmacy_order_detail_screen.dart';
import '../../features/pharmacy/screens/pharmacy_prescription_verification_screen.dart';
import '../../features/pharmacy/screens/pharmacy_inventory_screen.dart';
import '../../features/pharmacy/screens/pharmacy_delivery_tracking_screen.dart';
import '../../features/pharmacy/screens/pharmacy_earnings_screen.dart';
import '../../features/pharmacy/screens/pharmacy_profile_screen.dart';
import '../../features/pharmacy/screens/pharmacy_settings_screen.dart';
import '../../features/ambulance/screens/ambulance_dashboard_screen.dart';
import '../../features/ambulance/screens/ambulance_incoming_requests_screen.dart';
import '../../features/ambulance/screens/ambulance_request_detail_screen.dart';
import '../../features/ambulance/screens/ambulance_live_tracking_screen.dart';
import '../../features/ambulance/screens/ambulance_navigation_screen.dart';
import '../../features/ambulance/screens/ambulance_trip_history_screen.dart';
import '../../features/ambulance/screens/ambulance_earnings_screen.dart';
import '../../features/ambulance/screens/ambulance_vehicle_profile_screen.dart';
import '../../features/ambulance/screens/ambulance_settings_screen.dart';
import '../../features/caregiver/screens/caregiver_dashboard_screen.dart';
import '../../features/caregiver/screens/caregiver_assigned_visits_screen.dart';
import '../../features/caregiver/screens/caregiver_visit_detail_screen.dart';
import '../../features/caregiver/screens/caregiver_task_checklist_screen.dart';
import '../../features/caregiver/screens/caregiver_notes_screen.dart';
import '../../features/caregiver/screens/caregiver_upload_photos_screen.dart';
import '../../features/caregiver/screens/caregiver_completion_summary_screen.dart';
import '../../features/caregiver/screens/caregiver_earnings_screen.dart';
import '../../features/caregiver/screens/caregiver_profile_screen.dart';
import '../../features/caregiver/screens/caregiver_settings_screen.dart';

/// Bridges Firebase's auth stream into a [Listenable] so GoRouter's
/// [refreshListenable] re-evaluates the redirect on every auth state change.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier() {
    _sub = FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
  }
  late final StreamSubscription<User?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _authChangeNotifier = _AuthChangeNotifier();

class AppRoutes {
  static const login               = '/';
  static const register            = '/register';
  static const otp                 = '/otp';
  /// First registration step for a brand-new account: pick which partner
  /// service this account is signing up as. Doctor continues to [register].
  static const partnerRoleSelect   = '/partner-role-select';
  /// Generic Lab/Pharmacy/Ambulance/Caregiver registration form, given the
  /// selected `AppRole` via `extra`.
  static const partnerRoleRegister = '/partner-role-register';
  static const verificationPending = '/verification-pending';
  static const dashboard           = '/dashboard';
  static const incomingRequest     = '/incoming-request';
  static const videoCall           = '/video-call';
  static const prescription        = '/prescription';
  static const patientDetail       = '/patient-detail';
  static const patients            = '/patients';
  static const schedule            = '/schedule';
  static const editProfile         = '/edit-profile';
  static const earnings            = '/earnings';
  static const notifications       = '/notifications';
  static const settings            = '/settings';
  static const sos                 = '/sos';
  static const helpSupport              = '/help-support';
  static const liveChat                 = '/live-chat';
  static const reportProblem            = '/report-problem';
  static const feedback                 = '/feedback';
  static const pregnancyPatients        = '/pregnancy-patients';
  static const pregnancyPatientDetail   = '/pregnancy-patient-detail';
  static const maternityPrescription    = '/maternity-prescription';
  static const specChangeRequest        = '/spec-change-request';
  static const reviews                  = '/reviews';
  static const outgoingCall             = '/outgoing-call';

  // ── Lab & Diagnostics partner module ─────────────────────────────────────
  static const labOnboarding       = '/lab/onboarding';
  static const labDashboard        = '/lab/dashboard';
  static const labBookings         = '/lab/bookings';
  static const labBookingDetail    = '/lab/booking-detail';
  static const labSampleCollection = '/lab/sample-collection';
  static const labReports          = '/lab/reports';
  static const labEarnings         = '/lab/earnings';
  static const labProfile          = '/lab/profile';

  // ── Pharmacy & Medical Equipment partner module ──────────────────────────
  static const pharmacyOnboarding               = '/pharmacy/onboarding';
  static const pharmacyDashboard                = '/pharmacy/dashboard';
  static const pharmacyOrders                   = '/pharmacy/orders';
  static const pharmacyOrderDetail               = '/pharmacy/order-detail';
  static const pharmacyPrescriptionVerification = '/pharmacy/prescription-verification';
  static const pharmacyInventory                = '/pharmacy/inventory';
  static const pharmacyDeliveryTracking         = '/pharmacy/delivery-tracking';
  static const pharmacyEarnings                 = '/pharmacy/earnings';
  static const pharmacyProfile                  = '/pharmacy/profile';
  static const pharmacySettings                 = '/pharmacy/settings';

  // ── Ambulance partner module (UI-only, mock data) ────────────────────────
  static const ambulanceDashboard         = '/ambulance/dashboard';
  static const ambulanceIncomingRequests  = '/ambulance/incoming-requests';
  static const ambulanceRequestDetail     = '/ambulance/request-detail';
  static const ambulanceLiveTracking      = '/ambulance/live-tracking';
  static const ambulanceNavigation        = '/ambulance/navigation';
  static const ambulanceTripHistory       = '/ambulance/trip-history';
  static const ambulanceEarnings          = '/ambulance/earnings';
  static const ambulanceVehicleProfile    = '/ambulance/vehicle-profile';
  static const ambulanceSettings          = '/ambulance/settings';

  // ── Caregiver / Care Assistant partner module (UI-only, mock data) ───────
  static const caregiverDashboard         = '/caregiver/dashboard';
  static const caregiverAssignedVisits    = '/caregiver/assigned-visits';
  static const caregiverVisitDetail       = '/caregiver/visit-detail';
  static const caregiverTaskChecklist     = '/caregiver/task-checklist';
  static const caregiverNotes             = '/caregiver/notes';
  static const caregiverUploadPhotos      = '/caregiver/upload-photos';
  static const caregiverCompletionSummary = '/caregiver/completion-summary';
  static const caregiverEarnings          = '/caregiver/earnings';
  static const caregiverProfile           = '/caregiver/profile';
  static const caregiverSettings          = '/caregiver/settings';
}

// Routes that unauthenticated users may visit.
const _publicRoutes = {
  AppRoutes.login,
  AppRoutes.register,
  AppRoutes.otp,
  AppRoutes.verificationPending,
};

final appRouterProvider = Provider<GoRouter>((ref) {
  final initialLocation = DoctorAuthService.currentUid != null
      ? AppRoutes.dashboard
      : AppRoutes.login;
  return GoRouter(
    initialLocation: initialLocation,
    debugLogDiagnostics: false,
    refreshListenable: _authChangeNotifier,
    redirect: (context, state) {
      final isLoggedIn = DoctorAuthService.currentUid != null;
      final isPublic = _publicRoutes.contains(state.matchedLocation);

      if (!isLoggedIn && !isPublic) return AppRoutes.login;
      if (isLoggedIn && state.matchedLocation == AppRoutes.login) return AppRoutes.dashboard;
      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.login,              builder: (c, s) => const DoctorLoginScreen()),
      GoRoute(path: AppRoutes.register,           builder: (c, s) => const DoctorRegisterScreen()),
      GoRoute(
        path: AppRoutes.otp,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return DoctorOtpScreen(
            phone: extra?['phone'] as String? ?? '',
            isLogin: extra?['isLogin'] as bool? ?? true,
          );
        },
      ),
      GoRoute(path: AppRoutes.partnerRoleSelect,   builder: (c, s) => const PartnerRoleSelectScreen()),
      GoRoute(
        path: AppRoutes.partnerRoleRegister,
        builder: (c, s) {
          // Falls back to Doctor registration if the role is missing —
          // this route is only ever reached with a non-Doctor role.
          final role = s.extra as AppRole?;
          if (role == null || role == AppRole.doctor || role == AppRole.admin) {
            return const DoctorRegisterScreen();
          }
          return PartnerRoleRegisterScreen(role: role);
        },
      ),
      GoRoute(path: AppRoutes.verificationPending, builder: (c, s) => const VerificationPendingScreen()),
      GoRoute(path: AppRoutes.dashboard,           builder: (c, s) => const DashboardScreen()),
      GoRoute(path: AppRoutes.incomingRequest,     builder: (c, s) => const IncomingRequestScreen()),
      GoRoute(
        path: AppRoutes.videoCall,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return DoctorVideoCallScreen(
            consultationId: extra?['consultationId'] as String? ?? '',
            patientName: extra?['patientName'] as String? ?? 'Patient',
          );
        },
      ),
      GoRoute(
        path: AppRoutes.prescription,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return WritePrescriptionScreen(
            patientId: extra?['patientId'] as String? ?? '',
            patientName: extra?['patientName'] as String? ?? 'Patient',
            appointmentId: extra?['appointmentId'] as String?,
            consultationId: extra?['consultationId'] as String?,
            sessionValidated: extra?['sessionValidated'] as bool? ?? false,
            allowOffline: extra?['allowOffline'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.patientDetail,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return PatientDetailScreen(
            patientId: extra?['patientId'] as String? ?? '',
            patientName: extra?['patientName'] as String? ?? 'Patient',
          );
        },
      ),
      GoRoute(path: AppRoutes.patients,        builder: (c, s) => const PatientsListScreen()),
      GoRoute(path: AppRoutes.schedule,        builder: (c, s) => const AvailabilityScreen()),
      GoRoute(path: AppRoutes.editProfile,     builder: (c, s) => const DoctorProfileEditScreen()),
      GoRoute(path: AppRoutes.notifications,   builder: (c, s) => const DoctorNotificationsScreen()),
      GoRoute(path: AppRoutes.earnings,        builder: (c, s) => const DoctorEarningsScreen()),
      GoRoute(path: AppRoutes.settings,        builder: (c, s) => const SettingsScreen()),
      GoRoute(path: AppRoutes.sos,             builder: (c, s) => const SosScreen()),
      GoRoute(path: AppRoutes.helpSupport,       builder: (c, s) => const HelpSupportScreen()),
      GoRoute(path: AppRoutes.liveChat,          builder: (c, s) => const LiveChatScreen()),
      GoRoute(path: AppRoutes.reportProblem,     builder: (c, s) => const ReportProblemScreen()),
      GoRoute(path: AppRoutes.feedback,          builder: (c, s) => const PatientFeedbackScreen()),
      GoRoute(path: AppRoutes.reviews,           builder: (c, s) => const DoctorReviewsScreen()),
      GoRoute(path: AppRoutes.specChangeRequest, builder: (c, s) => const SpecializationChangeRequestScreen()),
      GoRoute(
        path: AppRoutes.outgoingCall,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>? ?? {};
          return DoctorOutgoingCallScreen(
            patientId:      extra['patientId']      as String? ?? '',
            patientName:    extra['patientName']    as String? ?? 'Patient',
            patientPhotoUrl: extra['patientPhotoUrl'] as String? ?? '',
          );
        },
      ),
      GoRoute(path: AppRoutes.pregnancyPatients, builder: (c, s) => const PregnancyPatientsScreen()),
      GoRoute(
        path: AppRoutes.pregnancyPatientDetail,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return PregnancyPatientDetailScreen(
            profileId: extra?['profileId'] as String? ?? '',
            patientId: extra?['patientId'] as String? ?? '',
            patientName: extra?['patientName'] as String? ?? 'Patient',
          );
        },
      ),
      GoRoute(
        path: AppRoutes.maternityPrescription,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return MaternityPrescriptionScreen(
            patientId: extra?['patientId'] as String? ?? '',
            patientName: extra?['patientName'] as String? ?? 'Patient',
            pregnancyWeek: extra?['pregnancyWeek'] as int? ?? 1,
          );
        },
      ),

      // ── Lab & Diagnostics partner module ─────────────────────────────────
      GoRoute(path: AppRoutes.labOnboarding,       builder: (c, s) => const LabOnboardingScreen()),
      GoRoute(path: AppRoutes.labDashboard,        builder: (c, s) => const LabDashboardScreen()),
      GoRoute(path: AppRoutes.labBookings,         builder: (c, s) => const LabBookingsScreen()),
      GoRoute(
        path: AppRoutes.labBookingDetail,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return LabBookingDetailScreen(bookingId: extra?['bookingId'] as String? ?? '');
        },
      ),
      GoRoute(path: AppRoutes.labSampleCollection, builder: (c, s) => const LabSampleCollectionScreen()),
      GoRoute(path: AppRoutes.labReports,          builder: (c, s) => const LabReportsScreen()),
      GoRoute(path: AppRoutes.labEarnings,         builder: (c, s) => const LabEarningsScreen()),
      GoRoute(path: AppRoutes.labProfile,          builder: (c, s) => const LabProfileScreen()),

      // ── Pharmacy & Medical Equipment partner module ──────────────────────
      GoRoute(path: AppRoutes.pharmacyOnboarding, builder: (c, s) => const PharmacyOnboardingScreen()),
      GoRoute(path: AppRoutes.pharmacyDashboard,  builder: (c, s) => const PharmacyDashboardScreen()),
      GoRoute(path: AppRoutes.pharmacyOrders,     builder: (c, s) => const PharmacyOrdersScreen()),
      GoRoute(
        path: AppRoutes.pharmacyOrderDetail,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return PharmacyOrderDetailScreen(orderId: extra?['orderId'] as String? ?? '');
        },
      ),
      GoRoute(
        path: AppRoutes.pharmacyPrescriptionVerification,
        builder: (c, s) => const PharmacyPrescriptionVerificationScreen(),
      ),
      GoRoute(path: AppRoutes.pharmacyInventory,        builder: (c, s) => const PharmacyInventoryScreen()),
      GoRoute(path: AppRoutes.pharmacyDeliveryTracking, builder: (c, s) => const PharmacyDeliveryTrackingScreen()),
      GoRoute(path: AppRoutes.pharmacyEarnings,         builder: (c, s) => const PharmacyEarningsScreen()),
      GoRoute(path: AppRoutes.pharmacyProfile,          builder: (c, s) => const PharmacyProfileScreen()),
      GoRoute(path: AppRoutes.pharmacySettings,         builder: (c, s) => const PharmacySettingsScreen()),

      // ── Ambulance partner module (UI-only, mock data) ────────────────────
      GoRoute(path: AppRoutes.ambulanceDashboard,        builder: (c, s) => const AmbulanceDashboardScreen()),
      GoRoute(path: AppRoutes.ambulanceIncomingRequests, builder: (c, s) => const AmbulanceIncomingRequestsScreen()),
      GoRoute(
        path: AppRoutes.ambulanceRequestDetail,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return AmbulanceRequestDetailScreen(requestId: extra?['requestId'] as String? ?? '');
        },
      ),
      GoRoute(path: AppRoutes.ambulanceLiveTracking, builder: (c, s) => const AmbulanceLiveTrackingScreen()),
      GoRoute(
        path: AppRoutes.ambulanceNavigation,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return AmbulanceNavigationScreen(requestId: extra?['requestId'] as String? ?? '');
        },
      ),
      GoRoute(path: AppRoutes.ambulanceTripHistory,    builder: (c, s) => const AmbulanceTripHistoryScreen()),
      GoRoute(path: AppRoutes.ambulanceEarnings,       builder: (c, s) => const AmbulanceEarningsScreen()),
      GoRoute(path: AppRoutes.ambulanceVehicleProfile, builder: (c, s) => const AmbulanceVehicleProfileScreen()),
      GoRoute(path: AppRoutes.ambulanceSettings,       builder: (c, s) => const AmbulanceSettingsScreen()),

      // ── Caregiver / Care Assistant partner module (UI-only, mock data) ───
      GoRoute(path: AppRoutes.caregiverDashboard,      builder: (c, s) => const CaregiverDashboardScreen()),
      GoRoute(path: AppRoutes.caregiverAssignedVisits, builder: (c, s) => const CaregiverAssignedVisitsScreen()),
      GoRoute(
        path: AppRoutes.caregiverVisitDetail,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return CaregiverVisitDetailScreen(visitId: extra?['visitId'] as String? ?? '');
        },
      ),
      GoRoute(
        path: AppRoutes.caregiverTaskChecklist,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return CaregiverTaskChecklistScreen(visitId: extra?['visitId'] as String? ?? '');
        },
      ),
      GoRoute(
        path: AppRoutes.caregiverNotes,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return CaregiverNotesScreen(visitId: extra?['visitId'] as String? ?? '');
        },
      ),
      GoRoute(
        path: AppRoutes.caregiverUploadPhotos,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return CaregiverUploadPhotosScreen(visitId: extra?['visitId'] as String? ?? '');
        },
      ),
      GoRoute(
        path: AppRoutes.caregiverCompletionSummary,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return CaregiverCompletionSummaryScreen(visitId: extra?['visitId'] as String? ?? '');
        },
      ),
      GoRoute(path: AppRoutes.caregiverEarnings, builder: (c, s) => const CaregiverEarningsScreen()),
      GoRoute(path: AppRoutes.caregiverProfile,  builder: (c, s) => const CaregiverProfileScreen()),
      GoRoute(path: AppRoutes.caregiverSettings, builder: (c, s) => const CaregiverSettingsScreen()),
    ],
  );
});
