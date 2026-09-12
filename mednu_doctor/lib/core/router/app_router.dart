import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../features/auth/services/doctor_auth_service.dart';
import '../../shared_core/navigation/role_menu.dart';
import '../../features/auth/screens/doctor_login_screen.dart';
import '../../features/auth/screens/doctor_register_screen.dart';
import '../../features/auth/screens/doctor_otp_screen.dart';
import '../../features/auth/screens/verification_pending_screen.dart';
import '../../features/auth/screens/partner_role_select_screen.dart';
import '../../features/auth/screens/partner_role_register_screen.dart';
import '../../shared_core/models/app_role.dart';
import '../../shared_core/services/role_prefs.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/consultations/screens/incoming_request_screen.dart';
import '../../features/emergency/screens/emergency_requests_screen.dart';
import '../../features/consultations/screens/doctor_video_call_screen.dart';
import '../../features/prescription/screens/write_prescription_screen.dart';
import '../../features/patients/screens/patient_detail_screen.dart';
import '../../features/patients/screens/pre_consultation_summary_screen.dart';
import '../../features/patients/screens/patients_list_screen.dart';
import '../../features/schedule/screens/availability_screen.dart';
import '../../features/schedule/screens/block_slots_screen.dart';
import '../../features/profile/screens/doctor_profile_screen.dart';
import '../../features/notifications/screens/doctor_notifications_screen.dart';
import '../../features/earnings/screens/doctor_earnings_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/help/screens/help_support_screen.dart';
import '../../features/pregnancy/screens/pregnancy_patients_screen.dart';
import '../../features/pregnancy/screens/pregnancy_patient_detail_screen.dart';
import '../../features/pregnancy/screens/maternity_prescription_screen.dart';
import '../../features/profile/screens/specialization_change_request_screen.dart';
import '../../features/help/screens/live_chat_screen.dart';
import '../../features/help/screens/report_problem_screen.dart';
import '../../features/consultations/screens/doctor_outgoing_call_screen.dart';
import '../../features/consultations/screens/provider_outgoing_call_screen.dart';
import '../../features/consultations/screens/provider_video_call_screen.dart';
import '../../features/lab/screens/lab_onboarding_screen.dart';
import '../../features/lab/screens/lab_dashboard_screen.dart';
import '../../features/lab/screens/lab_bookings_screen.dart';
import '../../features/lab/screens/lab_test_inventory_screen.dart';
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
import '../../features/physiotherapy/screens/physio_dashboard_screen.dart';
import '../../features/physiotherapy/screens/physio_sessions_screen.dart';
import '../../features/physiotherapy/screens/physio_session_detail_screen.dart';
import '../../features/physiotherapy/screens/physio_earnings_screen.dart';
import '../../features/physiotherapy/screens/physio_profile_screen.dart';
import '../../features/counselling/screens/counselling_dashboard_screen.dart';
import '../../features/counselling/screens/counselling_sessions_screen.dart';
import '../../features/counselling/screens/counselling_session_detail_screen.dart';
import '../../features/counselling/screens/counselling_earnings_screen.dart';
import '../../features/counselling/screens/counselling_profile_screen.dart';
import '../../features/nutrition/screens/nutrition_dashboard_screen.dart';
import '../../features/nutrition/screens/nutrition_appointments_screen.dart';
import '../../features/nutrition/screens/nutrition_appointment_detail_screen.dart';
import '../../features/nutrition/screens/nutrition_earnings_screen.dart';
import '../../features/nutrition/screens/nutrition_profile_screen.dart';
import '../../features/hospital_billing/screens/hospital_payments_screen.dart';

/// Bridges Firebase's auth stream into a [Listenable] so GoRouter's
/// [refreshListenable] re-evaluates the redirect on every auth state change.
///
/// Also owns the account's cached, synchronously-readable gate state (role /
/// profile existence / approval status), kept warm by a pair of realtime
/// Firestore listeners for the whole signed-in session. `redirect` below
/// reads these fields directly instead of running its own Firestore `.get()`
/// on every navigation — that earlier approach worked but added a network
/// round-trip to every route change, including every bottom-nav tap, which
/// is what made in-app navigation feel like a full page reload each time.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }
  late final StreamSubscription<User?> _authSub;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _doctorSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roleProfileSub;
  String? _roleProfileUid;
  String? _roleProfileCollection;
  Completer<void> _readyCompleter = Completer<void>();

  bool ready = false;
  bool profileExists = false;
  AppRole role = AppRole.doctor;
  bool roleProfileExists = false;
  String? status;

  /// Resolves once the first read of this signed-in session lands. Every
  /// `redirect` call after that is fully synchronous — only the very first
  /// navigation of a session (or the one right after sign-in) ever actually
  /// waits on this.
  Future<void> get onReady => ready ? Future.value() : _readyCompleter.future;

  void _markReady() {
    ready = true;
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  void _onAuthChanged(User? user) {
    _doctorSub?.cancel();
    _roleProfileSub?.cancel();
    _doctorSub = null;
    _roleProfileSub = null;
    _roleProfileUid = null;
    _roleProfileCollection = null;
    if (_readyCompleter.isCompleted) _readyCompleter = Completer<void>();
    ready = false;
    profileExists = false;
    role = AppRole.doctor;
    roleProfileExists = false;
    status = null;

    if (user == null) {
      _markReady();
      notifyListeners();
      return;
    }

    _doctorSub = FirebaseFirestore.instance
        .collection('doctors')
        .doc(user.uid)
        .snapshots()
        .listen((snap) async {
      // This document also receives frequent writes unrelated to routing —
      // PresenceService's online heartbeat (isOnline/acceptingConsultations/
      // lastHeartbeat, every 60s while online) and location pushes. Since
      // this notifier drives GoRouter's refreshListenable, notifying on
      // every one of those snapshots re-runs the full redirect and rebuilds
      // the route tree — which was resetting DashboardScreen's local
      // _isOnline toggle state and flashing the screen on every heartbeat.
      // Only notify when a value the redirect logic actually reads changes.
      final wasReady = ready;
      final prevProfileExists = profileExists;
      final prevRole = role;
      final prevRoleProfileExists = roleProfileExists;
      final prevStatus = status;

      profileExists = snap.exists;

      // Same precedence `roleEngineProvider` (shared_core/providers/
      // role_providers.dart) already applies for every other screen in the
      // app: persisted device preference > the account doc's own
      // `activeRole` field > whichever role the account was granted first.
      // This used to just take `roles.first` unconditionally — meaning any
      // account that was ever a Doctor before adding a second role (Lab,
      // Pharmacy, ...) would land back on the Doctor dashboard on every
      // fresh login/app-restart no matter which role the role switcher was
      // last set to, since `arrayUnion` appends new roles to the end of the
      // array and never reorders it.
      final roles = AppRoleX.listFrom(snap.data()?['roles']);
      final serverActiveRoleRaw = snap.data()?['activeRole'] as String?;
      final serverPreferred = serverActiveRoleRaw != null
          ? AppRoleX.fromFirestoreValue(serverActiveRoleRaw)
          : null;
      role = await RolePrefs.resolveActive(roles, serverPreferred: serverPreferred);
      // The signed-in account may have changed while that (fast, usually
      // cached) read was in flight — never let a stale resolution from a
      // previous user clobber the notifier's current state.
      if (DoctorAuthService.currentUid != user.uid) return;

      if (role == AppRole.doctor) {
        status = snap.data()?['status'] as String?;
        roleProfileExists = profileExists;
        _roleProfileSub?.cancel();
        _roleProfileSub = null;
        _roleProfileUid = null;
        _markReady();
        if (!wasReady ||
            profileExists != prevProfileExists ||
            role != prevRole ||
            roleProfileExists != prevRoleProfileExists ||
            status != prevStatus) {
          notifyListeners();
        }
        return;
      }

      if (!profileExists) {
        status = null;
        roleProfileExists = false;
        _roleProfileSub?.cancel();
        _roleProfileSub = null;
        _roleProfileUid = null;
        _markReady();
        if (!wasReady ||
            profileExists != prevProfileExists ||
            role != prevRole ||
            roleProfileExists != prevRoleProfileExists ||
            status != prevStatus) {
          notifyListeners();
        }
        return;
      }

      final collection = '${role.firestoreValue}_profiles';
      if (_roleProfileUid != user.uid || _roleProfileCollection != collection) {
        _roleProfileUid = user.uid;
        _roleProfileCollection = collection;
        _roleProfileSub?.cancel();
        _roleProfileSub = FirebaseFirestore.instance
            .collection(collection)
            .doc(user.uid)
            .snapshots()
            .listen((roleSnap) {
          roleProfileExists = roleSnap.exists;
          status = roleSnap.data()?['status'] as String?;
          _markReady();
          notifyListeners();
        });
      } else {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    _doctorSub?.cancel();
    _roleProfileSub?.cancel();
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
  static const emergencyRequests   = '/emergency-requests';
  static const videoCall           = '/video-call';
  static const prescription        = '/prescription';
  static const patientDetail       = '/patient-detail';
  static const preConsultationSummary = '/pre-consultation-summary';
  static const patients            = '/patients';
  static const schedule            = '/schedule';
  static const blockSlots          = '/block-slots';
  static const editProfile         = '/edit-profile';
  static const earnings            = '/earnings';
  static const notifications       = '/notifications';
  static const settings            = '/settings';
  static const helpSupport              = '/help-support';
  static const liveChat                 = '/live-chat';
  static const reportProblem            = '/report-problem';
  static const pregnancyPatients        = '/pregnancy-patients';
  static const pregnancyPatientDetail   = '/pregnancy-patient-detail';
  static const maternityPrescription    = '/maternity-prescription';
  static const specChangeRequest        = '/spec-change-request';
  static const outgoingCall             = '/outgoing-call';
  static const providerOutgoingCall     = '/provider-outgoing-call';
  static const providerVideoCall        = '/provider-video-call';

  // ── Lab & Diagnostics partner module ─────────────────────────────────────
  static const labOnboarding       = '/lab/onboarding';
  static const labDashboard        = '/lab/dashboard';
  static const labBookings         = '/lab/bookings';
  static const labTestInventory    = '/lab/tests';
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

  // ── Ambulance partner module (Firestore-backed) ──────────────────────────
  static const ambulanceDashboard         = '/ambulance/dashboard';
  static const ambulanceIncomingRequests  = '/ambulance/incoming-requests';
  static const ambulanceRequestDetail     = '/ambulance/request-detail';
  static const ambulanceLiveTracking      = '/ambulance/live-tracking';
  static const ambulanceNavigation        = '/ambulance/navigation';
  static const ambulanceTripHistory       = '/ambulance/trip-history';
  static const ambulanceEarnings          = '/ambulance/earnings';
  static const ambulanceVehicleProfile    = '/ambulance/vehicle-profile';
  static const ambulanceSettings          = '/ambulance/settings';

  // ── Caregiver / Care Assistant partner module (Firestore-backed) ─────────
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

  // ── Physiotherapy partner module (Firestore-backed) ──────────────────────
  static const physioDashboard       = '/physio/dashboard';
  static const physioSessions        = '/physio/sessions';
  static const physioSessionDetail   = '/physio/session-detail';
  static const physioEarnings        = '/physio/earnings';
  static const physioProfile         = '/physio/profile';

  // ── Counselling partner module (Firestore-backed) ────────────────────────
  static const counsellingDashboard     = '/counselling/dashboard';
  static const counsellingSessions      = '/counselling/sessions';
  static const counsellingSessionDetail = '/counselling/session-detail';
  static const counsellingEarnings      = '/counselling/earnings';
  static const counsellingProfile       = '/counselling/profile';

  // ── Nutrition partner module (admin-provisioned, no onboarding step) ─────
  static const nutritionDashboard           = '/nutrition/dashboard';
  static const nutritionAppointments        = '/nutrition/appointments';
  static const nutritionAppointmentDetail   = '/nutrition/appointment-detail';
  static const nutritionEarnings            = '/nutrition/earnings';
  static const nutritionProfile             = '/nutrition/profile';

  // ── Hospital billing-desk partner module ──────────────────────────────────
  static const hospitalPayments = '/hospital/payments';
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
    redirect: (context, state) async {
      final isLoggedIn = DoctorAuthService.currentUid != null;
      final loc = state.matchedLocation;

      if (!isLoggedIn) {
        return _publicRoutes.contains(loc) ? null : AppRoutes.login;
      }

      // Only the very first navigation of a session (or the one right after
      // sign-in) ever actually waits here — every subsequent call reads
      // already-warm cached fields below with no Firestore round-trip.
      if (!_authChangeNotifier.ready) await _authChangeNotifier.onReady;

      if (!_authChangeNotifier.profileExists) {
        // Brand-new authenticated session with no base identity doc yet.
        // partnerRoleRegister now carries its role as a URL segment
        // (.../lab, .../pharmacy, ...), so this checks the prefix rather
        // than an exact match — see that route's own builder for why.
        // AppRoutes.register is Doctor's own destination from this same
        // screen (see PartnerRoleSelectScreen._onRoleTap) and must stay
        // reachable here too.
        return loc == AppRoutes.partnerRoleSelect ||
                loc == AppRoutes.register ||
                loc.startsWith(AppRoutes.partnerRoleRegister)
            ? null
            : AppRoutes.partnerRoleSelect;
      }

      final role = _authChangeNotifier.role;

      // Lab/Pharmacy have a dedicated recovery screen for the rare case
      // where `doctors/{uid}` was written but `{role}_profiles/{uid}`
      // wasn't (e.g. a registration that failed partway through) — send
      // them there to finish the one missing step, same as their
      // dashboard screens' own `_checkOnboarded` already does.
      if (!_authChangeNotifier.roleProfileExists) {
        // `PartnerRoleRegisterScreen` writes `doctors/{uid}` and then
        // `{role}_profiles/{uid}` as two sequential awaited steps — the
        // live listeners above can observe the account between those two
        // writes and re-run this redirect while that screen is still mid
        // -submit. Treating it as reachable here (same as the pending-
        // review screen already is below) stops that in-flight submission
        // from being yanked over to the onboarding recovery screen.
        if (loc.startsWith(AppRoutes.partnerRoleRegister)) return null;
        if (role == AppRole.lab) {
          return loc == AppRoutes.labOnboarding ? null : AppRoutes.labOnboarding;
        }
        if (role == AppRole.pharmacy) {
          return loc == AppRoutes.pharmacyOnboarding ? null : AppRoutes.pharmacyOnboarding;
        }
        // Physiotherapist/Counsellor have no dedicated onboarding-recovery
        // screen — same as Ambulance/Caregiver, whose profile is written in
        // one shot by PartnerRoleRegisterScreen's initial submit. A rare
        // partial failure there (doctors/{uid} written, profile doc not)
        // falls through to the pending-review screen below, same as those
        // two roles already do.
        return loc == AppRoutes.verificationPending ? null : AppRoutes.verificationPending;
      }

      // Verification documents are only ever submitted once, up front,
      // during registration — an account that hasn't been approved yet
      // must only ever reach the pending-review screen (or the
      // registration flow itself, for an account adding a second role)
      // until admin flips status to 'active'. No other route in the app is
      // reachable until then.
      if (_authChangeNotifier.status != 'active') {
        if (loc.startsWith(AppRoutes.partnerRoleRegister)) return null;
        const alwaysReachableWhilePending = {
          AppRoutes.verificationPending,
          AppRoutes.partnerRoleSelect,
          AppRoutes.labOnboarding,
          AppRoutes.pharmacyOnboarding,
        };
        return alwaysReachableWhilePending.contains(loc) ? null : AppRoutes.verificationPending;
      }

      // Active — AppRoutes.dashboard is Doctor's own screen, so a non-Doctor
      // role must land on its own role home instead (mirrors the same
      // roles-lookup used post-OTP in doctor_login_screen.dart /
      // doctor_otp_screen.dart).
      if (loc == AppRoutes.login || loc == AppRoutes.dashboard) {
        if (role != AppRole.doctor) {
          final destination = buildMenuForRole(role);
          if (destination.isNotEmpty) return destination.first.route;
        }
        if (loc == AppRoutes.login) return AppRoutes.dashboard;
      }
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
            verificationId: extra?['verificationId'] as String? ?? '',
            isLogin: extra?['isLogin'] as bool? ?? true,
          );
        },
      ),
      GoRoute(path: AppRoutes.partnerRoleSelect,   builder: (c, s) => const PartnerRoleSelectScreen()),
      GoRoute(
        path: '${AppRoutes.partnerRoleRegister}/:role',
        builder: (c, s) {
          // The role travels as a URL path segment, not `extra` — `extra`
          // lives only in memory, and this form's own document-upload step
          // hands off to an external app (camera/gallery/file picker),
          // which can get the Activity reclaimed by Android under memory
          // pressure. GoRouter then restores this route from the URL alone
          // on resume; a bare `s.extra as AppRole?` came back null in that
          // case and silently fell through to Doctor registration with no
          // error — a real bug this fixes. `fromFirestoreValue` already
          // defaults an unrecognised/missing value to AppRole.doctor, which
          // correctly hits the same Doctor-registration fallback below.
          final role = AppRoleX.fromFirestoreValue(s.pathParameters['role']);
          if (role == AppRole.doctor || role == AppRole.admin) {
            return const DoctorRegisterScreen();
          }
          return PartnerRoleRegisterScreen(role: role);
        },
      ),
      GoRoute(path: AppRoutes.verificationPending, builder: (c, s) => const VerificationPendingScreen()),
      GoRoute(path: AppRoutes.dashboard,           builder: (c, s) => const DashboardScreen()),
      GoRoute(path: AppRoutes.incomingRequest,     builder: (c, s) => const IncomingRequestScreen()),
      GoRoute(path: AppRoutes.emergencyRequests,   builder: (c, s) => const EmergencyRequestsScreen()),
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
      GoRoute(
        path: AppRoutes.preConsultationSummary,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return PreConsultationSummaryScreen(
            appointmentId: extra?['appointmentId'] as String? ?? '',
            patientName: extra?['patientName'] as String? ?? 'Patient',
          );
        },
      ),
      GoRoute(path: AppRoutes.patients,        builder: (c, s) => const PatientsListScreen()),
      GoRoute(path: AppRoutes.schedule,        builder: (c, s) => const AvailabilityScreen()),
      GoRoute(path: AppRoutes.blockSlots,      builder: (c, s) => const BlockSlotsScreen()),
      GoRoute(path: AppRoutes.editProfile,     builder: (c, s) => const DoctorProfileEditScreen()),
      GoRoute(path: AppRoutes.notifications,   builder: (c, s) => const DoctorNotificationsScreen()),
      GoRoute(path: AppRoutes.earnings,        builder: (c, s) => const DoctorEarningsScreen()),
      GoRoute(path: AppRoutes.settings,        builder: (c, s) => const SettingsScreen()),
      GoRoute(path: AppRoutes.helpSupport,       builder: (c, s) => const HelpSupportScreen()),
      GoRoute(path: AppRoutes.liveChat,          builder: (c, s) => const LiveChatScreen()),
      GoRoute(path: AppRoutes.reportProblem,     builder: (c, s) => const ReportProblemScreen()),
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
      GoRoute(
        path: AppRoutes.providerOutgoingCall,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>? ?? {};
          return ProviderOutgoingCallScreen(
            providerRole:    extra['providerRole']    as String? ?? 'physiotherapist',
            patientId:       extra['patientId']       as String? ?? '',
            patientName:     extra['patientName']     as String? ?? 'Patient',
            patientPhotoUrl: extra['patientPhotoUrl'] as String? ?? '',
            sessionId:       extra['sessionId']       as String?,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.providerVideoCall,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>? ?? {};
          return ProviderVideoCallScreen(
            consultationId: extra['consultationId'] as String? ?? '',
            providerRole:   extra['providerRole']   as String? ?? 'physiotherapist',
            patientName:    extra['patientName']    as String? ?? 'Patient',
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
      // Bottom-nav-driven routes use pageBuilder + NoTransitionPage instead
      // of builder — SharedAppShell's bottom nav switches between these via
      // plain context.go(), and the default MaterialPage slide transition
      // made every tab tap look like navigating to a brand-new screen
      // rather than an instant tab switch (Doctor's own dashboard never had
      // this problem since its tabs are an in-place IndexedStack, not
      // separate routes).
      GoRoute(path: AppRoutes.labDashboard,        pageBuilder: (c, s) => const NoTransitionPage(child: LabDashboardScreen())),
      GoRoute(path: AppRoutes.labBookings,         pageBuilder: (c, s) => const NoTransitionPage(child: LabBookingsScreen())),
      GoRoute(path: AppRoutes.labTestInventory,    pageBuilder: (c, s) => const NoTransitionPage(child: LabTestInventoryScreen())),
      GoRoute(
        path: AppRoutes.labBookingDetail,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return LabBookingDetailScreen(bookingId: extra?['bookingId'] as String? ?? '');
        },
      ),
      GoRoute(path: AppRoutes.labSampleCollection, pageBuilder: (c, s) => const NoTransitionPage(child: LabSampleCollectionScreen())),
      GoRoute(path: AppRoutes.labReports,          pageBuilder: (c, s) => const NoTransitionPage(child: LabReportsScreen())),
      GoRoute(path: AppRoutes.labEarnings,         pageBuilder: (c, s) => const NoTransitionPage(child: LabEarningsScreen())),
      GoRoute(path: AppRoutes.labProfile,          pageBuilder: (c, s) => const NoTransitionPage(child: LabProfileScreen())),

      // ── Pharmacy & Medical Equipment partner module ──────────────────────
      GoRoute(path: AppRoutes.pharmacyOnboarding, builder: (c, s) => const PharmacyOnboardingScreen()),
      GoRoute(path: AppRoutes.pharmacyDashboard,  pageBuilder: (c, s) => const NoTransitionPage(child: PharmacyDashboardScreen())),
      GoRoute(path: AppRoutes.pharmacyOrders,     pageBuilder: (c, s) => const NoTransitionPage(child: PharmacyOrdersScreen())),
      GoRoute(
        path: AppRoutes.pharmacyOrderDetail,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return PharmacyOrderDetailScreen(orderId: extra?['orderId'] as String? ?? '');
        },
      ),
      GoRoute(
        path: AppRoutes.pharmacyPrescriptionVerification,
        pageBuilder: (c, s) => const NoTransitionPage(child: PharmacyPrescriptionVerificationScreen()),
      ),
      GoRoute(path: AppRoutes.pharmacyInventory,        pageBuilder: (c, s) => const NoTransitionPage(child: PharmacyInventoryScreen())),
      GoRoute(path: AppRoutes.pharmacyDeliveryTracking, builder: (c, s) => const PharmacyDeliveryTrackingScreen()),
      GoRoute(path: AppRoutes.pharmacyEarnings,         pageBuilder: (c, s) => const NoTransitionPage(child: PharmacyEarningsScreen())),
      GoRoute(path: AppRoutes.pharmacyProfile,          pageBuilder: (c, s) => const NoTransitionPage(child: PharmacyProfileScreen())),
      GoRoute(path: AppRoutes.pharmacySettings,         builder: (c, s) => const PharmacySettingsScreen()),

      // ── Ambulance partner module (Firestore-backed) ──────────────────────
      GoRoute(path: AppRoutes.ambulanceDashboard,        pageBuilder: (c, s) => const NoTransitionPage(child: AmbulanceDashboardScreen())),
      GoRoute(path: AppRoutes.ambulanceIncomingRequests, pageBuilder: (c, s) => const NoTransitionPage(child: AmbulanceIncomingRequestsScreen())),
      GoRoute(
        path: AppRoutes.ambulanceRequestDetail,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return AmbulanceRequestDetailScreen(requestId: extra?['requestId'] as String? ?? '');
        },
      ),
      GoRoute(path: AppRoutes.ambulanceLiveTracking, pageBuilder: (c, s) => const NoTransitionPage(child: AmbulanceLiveTrackingScreen())),
      GoRoute(
        path: AppRoutes.ambulanceNavigation,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return AmbulanceNavigationScreen(requestId: extra?['requestId'] as String? ?? '');
        },
      ),
      GoRoute(path: AppRoutes.ambulanceTripHistory,    pageBuilder: (c, s) => const NoTransitionPage(child: AmbulanceTripHistoryScreen())),
      GoRoute(path: AppRoutes.ambulanceEarnings,       pageBuilder: (c, s) => const NoTransitionPage(child: AmbulanceEarningsScreen())),
      GoRoute(path: AppRoutes.ambulanceVehicleProfile, pageBuilder: (c, s) => const NoTransitionPage(child: AmbulanceVehicleProfileScreen())),
      GoRoute(path: AppRoutes.ambulanceSettings,       builder: (c, s) => const AmbulanceSettingsScreen()),

      // ── Caregiver / Care Assistant partner module (Firestore-backed) ─────
      GoRoute(path: AppRoutes.caregiverDashboard,      pageBuilder: (c, s) => const NoTransitionPage(child: CaregiverDashboardScreen())),
      GoRoute(path: AppRoutes.caregiverAssignedVisits, pageBuilder: (c, s) => const NoTransitionPage(child: CaregiverAssignedVisitsScreen())),
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
      GoRoute(path: AppRoutes.caregiverEarnings, pageBuilder: (c, s) => const NoTransitionPage(child: CaregiverEarningsScreen())),
      GoRoute(path: AppRoutes.caregiverProfile,  pageBuilder: (c, s) => const NoTransitionPage(child: CaregiverProfileScreen())),
      GoRoute(path: AppRoutes.caregiverSettings, builder: (c, s) => const CaregiverSettingsScreen()),

      // ── Physiotherapy partner module ──────────────────────────────────────
      GoRoute(path: AppRoutes.physioDashboard, pageBuilder: (c, s) => const NoTransitionPage(child: PhysioDashboardScreen())),
      GoRoute(path: AppRoutes.physioSessions,  pageBuilder: (c, s) => const NoTransitionPage(child: PhysioSessionsScreen())),
      GoRoute(
        path: AppRoutes.physioSessionDetail,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return PhysioSessionDetailScreen(sessionId: extra?['sessionId'] as String? ?? '');
        },
      ),
      GoRoute(path: AppRoutes.physioEarnings, pageBuilder: (c, s) => const NoTransitionPage(child: PhysioEarningsScreen())),
      GoRoute(path: AppRoutes.physioProfile,  pageBuilder: (c, s) => const NoTransitionPage(child: PhysioProfileScreen())),

      // ── Counselling partner module ────────────────────────────────────────
      GoRoute(path: AppRoutes.counsellingDashboard, pageBuilder: (c, s) => const NoTransitionPage(child: CounsellingDashboardScreen())),
      GoRoute(path: AppRoutes.counsellingSessions,  pageBuilder: (c, s) => const NoTransitionPage(child: CounsellingSessionsScreen())),
      GoRoute(
        path: AppRoutes.counsellingSessionDetail,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return CounsellingSessionDetailScreen(sessionId: extra?['sessionId'] as String? ?? '');
        },
      ),
      GoRoute(path: AppRoutes.counsellingEarnings, pageBuilder: (c, s) => const NoTransitionPage(child: CounsellingEarningsScreen())),
      GoRoute(path: AppRoutes.counsellingProfile,  pageBuilder: (c, s) => const NoTransitionPage(child: CounsellingProfileScreen())),

      // ── Nutrition partner module ──────────────────────────────────────────
      GoRoute(path: AppRoutes.nutritionDashboard,    pageBuilder: (c, s) => const NoTransitionPage(child: NutritionDashboardScreen())),
      GoRoute(path: AppRoutes.nutritionAppointments, pageBuilder: (c, s) => const NoTransitionPage(child: NutritionAppointmentsScreen())),
      GoRoute(
        path: AppRoutes.nutritionAppointmentDetail,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return NutritionAppointmentDetailScreen(appointmentId: extra?['appointmentId'] as String? ?? '');
        },
      ),
      GoRoute(path: AppRoutes.nutritionEarnings, pageBuilder: (c, s) => const NoTransitionPage(child: NutritionEarningsScreen())),
      GoRoute(path: AppRoutes.nutritionProfile,  pageBuilder: (c, s) => const NoTransitionPage(child: NutritionProfileScreen())),

      // ── Hospital billing-desk partner module ──────────────────────────────
      GoRoute(path: AppRoutes.hospitalPayments, pageBuilder: (c, s) => const NoTransitionPage(child: HospitalPaymentsScreen())),
    ],
  );
});

/// Safe back navigation for an app-bar back button.
///
/// A screen's own back button calling `context.pop()` assumes something is
/// actually on the stack to pop back to — but several entry points in this
/// app (notably `SharedAppShell`'s notification bell and profile-edit
/// actions) reach their target screen via `context.go(...)`, which replaces
/// the stack rather than pushing onto it. `context.pop()` on a screen
/// reached that way has nothing to pop and silently does nothing, making
/// the back arrow look broken. This checks first and falls back to a
/// sensible default route instead of failing silently.
extension SafeBackNavigation on BuildContext {
  void safeBack({String fallbackRoute = AppRoutes.dashboard}) {
    if (canPop()) {
      pop();
    } else {
      go(fallbackRoute);
    }
  }
}
