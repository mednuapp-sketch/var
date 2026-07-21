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
    ],
  );
});
