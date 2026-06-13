import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/services/consultation/consultation_screen.dart';
import '../../features/services/consultation/video_call_screen.dart';
import '../../features/services/consultation/outgoing_call_screen.dart';
import '../../features/services/consultation/incoming_call_screen.dart';
import '../../features/services/emergency/emergency_screen.dart';
import '../../features/services/emergency/sos_screen.dart';
import '../../features/services/emergency/manage_contacts_screen.dart';
import '../../features/services/medicine_delivery/medicine_screen.dart';
import '../../features/services/ambulance/ambulance_screen.dart';
import '../../features/services/diagnostics/diagnostics_screen.dart';
import '../../features/services/caregivers/caregivers_screen.dart';
import '../../features/services/care_assistant/care_assistant_screen.dart';
import '../../features/services/nutrition/screens/nutrition_home_screen.dart';
import '../../features/services/nutrition/screens/nutritionist_list_screen.dart';
import '../../features/services/nutrition/screens/nutritionist_profile_screen.dart';
import '../../features/services/nutrition/screens/book_nutrition_appointment_screen.dart';
import '../../features/services/nutrition/screens/nutrition_dashboard_screen.dart';
import '../../features/services/nutrition/screens/meal_tracking_screen.dart';
import '../../features/services/nutrition/screens/bmi_calculator_screen.dart';
import '../../features/services/nutrition/screens/nutrition_goals_screen.dart';
import '../../features/services/physiotherapy/physio_screen.dart';
import '../../features/services/counselling/counselling_screen.dart';
import '../../features/services/equipment_hiring/equipment_screen.dart';
import '../../features/services/appointment/appointment_screen.dart';
import '../../features/doctors/screens/doctors_list_screen.dart';
import '../../features/doctors/screens/doctor_profile_screen.dart';
import '../../features/doctors/screens/favourite_doctors_screen.dart';
import '../../features/doctors/screens/specialities_screen.dart';
import '../../features/hospitals/screens/hospitals_screen.dart';
import '../../features/pharmacy/screens/pharmacy_screen.dart';
import '../../features/records/screens/records_screen.dart';
import '../../features/wallet/screens/wallet_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/family_management_screen.dart';
import '../../features/profile/screens/family_member_detail_screen.dart';
import '../../features/profile/screens/settings_screen.dart';
import '../../features/profile/screens/language_screen.dart';
import '../../features/education/screens/education_screen.dart';
import '../../features/premium/screens/premium_screen.dart';
import '../../features/health/screens/health_dashboard_screen.dart';
import '../../features/health/screens/period_tracker_screen.dart';
import '../../features/health/screens/water_reminder_screen.dart';
import '../../features/health/screens/post_consultation_screen.dart';
import '../../features/health/screens/prescription_viewer_screen.dart';
import '../../features/tracking/screens/order_tracking_screen.dart';
import '../../features/payment/screens/payment_screen.dart';
import '../../features/referral/screens/referral_screen.dart';
import '../../features/pregnancy/screens/pregnancy_dashboard_screen.dart';
import '../../features/pregnancy/screens/pregnancy_onboarding_screen.dart';
import '../../features/pregnancy/screens/pregnancy_journal_screen.dart';
import '../../features/pregnancy/screens/pregnancy_weekly_screen.dart';
import '../../features/pregnancy/screens/pregnancy_checkups_screen.dart';
import '../../features/pregnancy/screens/pregnancy_medicines_screen.dart';
import '../../features/pregnancy/screens/pregnancy_nutrition_screen.dart';
import '../../features/pregnancy/screens/pregnancy_emergency_screen.dart';
import '../../features/location/screens/address_book_screen.dart';
import '../../features/location/screens/add_edit_address_screen.dart';
import '../../features/location/screens/map_location_picker_screen.dart';
import '../../features/doctors/screens/submit_review_screen.dart';
import '../../features/legal/screens/privacy_policy_screen.dart';
import '../../features/legal/screens/terms_of_service_screen.dart';
import '../../features/support/screens/help_support_screen.dart';
import '../../features/support/screens/about_screen.dart';
import '../../features/my_services/screens/my_services_screen.dart';
import '../../features/my_services/screens/service_detail_screen.dart';
import '../../features/my_services/models/unified_booking.dart';

class AppRoutes {
  static const splash             = '/';
  static const onboarding         = '/onboarding';
  static const login              = '/login';
  static const otp                = '/otp';
  static const register           = '/register';
  static const home               = '/home';
  static const doctors            = '/doctors';
  static const doctorProfile      = '/doctors/:id';
  static const appointment        = '/appointment';
  static const consultation       = '/consultation';
  static const videoCall          = '/consultation/video/:id';
  static const emergency          = '/emergency';
  static const sos                = '/sos';
  static const sosContacts        = '/sos/contacts';
  static const medicine           = '/medicine';
  static const diagnostics        = '/diagnostics';
  static const ambulance          = '/ambulance';
  static const caregivers         = '/caregivers';
  static const careAssistant      = '/care-assistant';
  static const physio             = '/physio';
  static const nutrition                      = '/nutrition';
  static const nutritionNutritionists         = '/nutrition/nutritionists';
  static const nutritionNutritionistProfile   = '/nutrition/nutritionist/:id';
  static const nutritionBookAppointment       = '/nutrition/book';
  static const nutritionDashboard             = '/nutrition/dashboard';
  static const nutritionMeals                 = '/nutrition/meals';
  static const nutritionBmi                   = '/nutrition/bmi';
  static const nutritionGoals                 = '/nutrition/goals';
  static const counselling        = '/counselling';
  static const equipment          = '/equipment';
  static const hospitals          = '/hospitals';
  static const pharmacy           = '/pharmacy';
  static const records            = '/records';
  static const wallet             = '/wallet';
  static const notifications      = '/notifications';
  static const profile            = '/profile';
  static const family             = '/profile/family';
  static const familyMemberDetail = '/profile/family/member';
  static const favouriteDoctors   = '/profile/favourites';
  static const settings           = '/profile/settings';
  static const language           = '/profile/language';
  static const education          = '/education';
  static const premium            = '/premium';
  static const healthDashboard    = '/health';
  static const periodTracker      = '/health/period';
  static const waterReminder      = '/health/water';
  static const postConsultation   = '/post-consultation';
  static const prescriptionViewer = '/prescription';
  static const orderTracking      = '/order-tracking';
  static const payment            = '/payment';
  static const referral           = '/referral';
  static const specialities       = '/specialities';

  // Location
  static const addressBook        = '/address-book';
  static const addAddress         = '/address-book/add';
  static const mapPicker          = '/location/map-picker';

  // Pregnancy
  static const pregnancy          = '/pregnancy';
  static const pregnancyOnboarding = '/pregnancy/setup';
  static const pregnancyJournal   = '/pregnancy/journal';
  static const pregnancyWeekly    = '/pregnancy/weekly';
  static const pregnancyCheckups  = '/pregnancy/checkups';
  static const pregnancyMedicines = '/pregnancy/medicines';
  static const pregnancyNutrition = '/pregnancy/nutrition';
  static const pregnancyEmergency = '/pregnancy/emergency';

  // Reviews
  static const submitReview = '/review/submit';

  // Legal
  static const privacyPolicy = '/legal/privacy';
  static const termsOfService = '/legal/terms';

  // Support
  static const helpSupport = '/support/help';
  static const about = '/support/about';

  // My Services Tracker
  static const myServices   = '/my-services';
  static const serviceDetail = '/my-services/detail';

  // Realtime calling
  static const outgoingCall = '/call/outgoing';
  static const incomingCall = '/call/incoming';
}

/// Global navigator key — allows navigation from outside the widget tree
/// (e.g., notification tap handlers in main.dart).
final appNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    routes: [
      GoRoute(path: AppRoutes.splash,             builder: (c, s) => const SplashScreen()),
      GoRoute(path: AppRoutes.onboarding,         builder: (c, s) => const OnboardingScreen()),
      GoRoute(path: AppRoutes.login,              builder: (c, s) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.otp,
        builder: (c, s) {
          final extra = s.extra;
          if (extra is Map<String, dynamic>) {
            return OtpScreen(
              phone: extra['phone'] as String? ?? '',
              signupData: extra,
            );
          }
          return OtpScreen(phone: extra as String? ?? '');
        },
      ),
      GoRoute(path: AppRoutes.register,           builder: (c, s) => const RegisterScreen()),
      GoRoute(path: AppRoutes.home,               builder: (c, s) => const HomeScreen()),
      GoRoute(path: AppRoutes.consultation,       builder: (c, s) => const ConsultationScreen()),
      GoRoute(
        path: AppRoutes.videoCall,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return VideoCallScreen(
            callId: s.pathParameters['id'] ?? '',
            doctorName: extra?['name'] as String?,
            doctorSpecialty: extra?['specialty'] as String?,
          );
        },
      ),
      GoRoute(path: AppRoutes.emergency,          builder: (c, s) => const EmergencyScreen()),
      GoRoute(path: AppRoutes.sos,                builder: (c, s) => const SOSScreen()),
      GoRoute(path: AppRoutes.sosContacts,        builder: (c, s) => const ManageContactsScreen()),
      GoRoute(path: AppRoutes.medicine,           builder: (c, s) {
        final extra = s.extra;
        List<Map<String, dynamic>>? rxMeds;
        if (extra is List) {
          rxMeds = extra.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        return MedicineScreen(prescriptionMedicines: rxMeds);
      }),
      GoRoute(path: AppRoutes.ambulance,          builder: (c, s) => const AmbulanceScreen()),
      GoRoute(path: AppRoutes.diagnostics,        builder: (c, s) => const DiagnosticsScreen()),
      GoRoute(path: AppRoutes.caregivers,         builder: (c, s) => const CaregiversScreen()),
      GoRoute(path: AppRoutes.careAssistant,      builder: (c, s) => const CareAssistantScreen()),
      GoRoute(path: AppRoutes.nutrition,                    builder: (c, s) => const NutritionHomeScreen()),
      GoRoute(path: AppRoutes.nutritionNutritionists,       builder: (c, s) => const NutritionistListScreen()),
      GoRoute(path: AppRoutes.nutritionNutritionistProfile, builder: (c, s) => NutritionistProfileScreen(nutritionistId: s.pathParameters['id'] ?? '')),
      GoRoute(path: AppRoutes.nutritionBookAppointment,     builder: (c, s) => BookNutritionAppointmentScreen(extra: s.extra as Map<String, dynamic>? ?? {})),
      GoRoute(path: AppRoutes.nutritionDashboard,           builder: (c, s) => const NutritionDashboardScreen()),
      GoRoute(path: AppRoutes.nutritionMeals,               builder: (c, s) => const MealTrackingScreen()),
      GoRoute(path: AppRoutes.nutritionBmi,                 builder: (c, s) => const BmiCalculatorScreen()),
      GoRoute(path: AppRoutes.nutritionGoals,               builder: (c, s) => const NutritionGoalsScreen()),
      GoRoute(path: AppRoutes.physio,             builder: (c, s) => const PhysioScreen()),
      GoRoute(path: AppRoutes.counselling,        builder: (c, s) => const CounsellingScreen()),
      GoRoute(path: AppRoutes.equipment,          builder: (c, s) => const EquipmentScreen()),
      GoRoute(path: AppRoutes.appointment,        builder: (c, s) => const AppointmentScreen()),
      GoRoute(path: AppRoutes.doctors,            builder: (c, s) => DoctorsListScreen(initialSpecialty: s.uri.queryParameters['specialty'], initialMode: s.uri.queryParameters['mode'])),
      GoRoute(path: AppRoutes.specialities,       builder: (c, s) => const SpecialitiesScreen()),
      GoRoute(path: AppRoutes.doctorProfile,      builder: (c, s) => DoctorProfileScreen(doctorId: s.pathParameters['id'] ?? '')),
      GoRoute(path: AppRoutes.hospitals,          builder: (c, s) => const HospitalsScreen()),
      GoRoute(path: AppRoutes.pharmacy,           builder: (c, s) => const PharmacyScreen()),
      GoRoute(path: AppRoutes.records, builder: (c, s) {
        final extra = s.extra as Map<String, dynamic>?;
        return RecordsScreen(
          memberId:   extra?['memberId']   as String?,
          memberName: extra?['memberName'] as String?,
          initialTab: extra?['tab']        as int?,
        );
      }),
      GoRoute(path: AppRoutes.wallet,             builder: (c, s) => const WalletScreen()),
      GoRoute(path: AppRoutes.notifications,      builder: (c, s) => const NotificationsScreen()),
      GoRoute(path: AppRoutes.profile,            builder: (c, s) => const ProfileScreen()),
      GoRoute(path: AppRoutes.favouriteDoctors,   builder: (c, s) => const FavouriteDoctorsScreen()),
      GoRoute(path: AppRoutes.family,             builder: (c, s) => const FamilyManagementScreen()),
      GoRoute(path: AppRoutes.familyMemberDetail, builder: (c, s) => FamilyMemberDetailScreen(member: s.extra as Map<String, dynamic>? ?? {})),
      GoRoute(path: AppRoutes.settings,           builder: (c, s) => const SettingsScreen()),
      GoRoute(path: AppRoutes.language,           builder: (c, s) => const LanguageScreen()),
      GoRoute(path: AppRoutes.education,          builder: (c, s) => const EducationScreen()),
      GoRoute(path: AppRoutes.premium,            builder: (c, s) => const PremiumScreen()),
GoRoute(path: AppRoutes.healthDashboard,    builder: (c, s) => const HealthDashboardScreen()),
GoRoute(path: AppRoutes.periodTracker,      builder: (c, s) => const PeriodTrackerScreen()),
GoRoute(path: AppRoutes.waterReminder,      builder: (c, s) => const WaterReminderScreen()),
GoRoute(
  path: AppRoutes.postConsultation,
  builder: (c, s) {
    final extra = s.extra as Map<String, dynamic>?;
    return PostConsultationScreen(
      consultationId:  extra?['consultationId']  as String?,
      doctorId:        extra?['doctorId']         as String?,
      doctorName:      extra?['doctorName']       as String?,
      doctorSpecialty: extra?['doctorSpecialty']  as String?,
      type:            extra?['type']             as String? ?? 'followup',
    );
  },
),
GoRoute(path: AppRoutes.prescriptionViewer, builder: (c, s) => PrescriptionViewerScreen(data: s.extra as Map<String, dynamic>?)),
GoRoute(path: AppRoutes.orderTracking,      builder: (c, s) => OrderTrackingScreen(orderData: s.extra as Map<String, dynamic>?)),
GoRoute(path: AppRoutes.payment,            builder: (c, s) => PaymentScreen(amount: s.extra?.toString() ?? '520')),
GoRoute(path: AppRoutes.referral,           builder: (c, s) => const ReferralScreen()),
      // Location
      GoRoute(path: AppRoutes.addressBook,        builder: (c, s) => const AddressBookScreen()),
      GoRoute(path: AppRoutes.addAddress,         builder: (c, s) => const AddEditAddressScreen()),
      GoRoute(
        path: AppRoutes.mapPicker,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return MapLocationPickerScreen(
            initialLat: extra?['lat'] as double?,
            initialLng: extra?['lng'] as double?,
          );
        },
      ),
      GoRoute(path: AppRoutes.pregnancy,          builder: (c, s) => const PregnancyDashboardScreen()),
      GoRoute(path: AppRoutes.pregnancyOnboarding, builder: (c, s) => const PregnancyOnboardingScreen()),
      GoRoute(path: AppRoutes.pregnancyJournal,   builder: (c, s) => const PregnancyJournalScreen()),
      GoRoute(path: AppRoutes.pregnancyWeekly,    builder: (c, s) => const PregnancyWeeklyScreen()),
      GoRoute(path: AppRoutes.pregnancyCheckups,  builder: (c, s) => const PregnancyCheckupsScreen()),
      GoRoute(path: AppRoutes.pregnancyMedicines, builder: (c, s) => const PregnancyMedicinesScreen()),
      GoRoute(path: AppRoutes.pregnancyNutrition, builder: (c, s) => const PregnancyNutritionScreen()),
      GoRoute(path: AppRoutes.pregnancyEmergency, builder: (c, s) => const PregnancyEmergencyScreen()),
      GoRoute(path: AppRoutes.privacyPolicy,   builder: (c, s) => const PrivacyPolicyScreen()),
      GoRoute(path: AppRoutes.termsOfService,  builder: (c, s) => const TermsOfServiceScreen()),
      GoRoute(path: AppRoutes.helpSupport,     builder: (c, s) => const HelpSupportScreen()),
      GoRoute(path: AppRoutes.about,           builder: (c, s) => const AboutScreen()),

      // ── My Services Tracker ───────────────────────────────────────────────
      GoRoute(path: AppRoutes.myServices,      builder: (c, s) => const MyServicesScreen()),
      GoRoute(
        path: AppRoutes.serviceDetail,
        builder: (c, s) {
          final booking = s.extra as UnifiedBooking?;
          if (booking == null) return const MyServicesScreen();
          return ServiceDetailScreen(booking: booking);
        },
      ),

      // ── Realtime calling ──────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.outgoingCall,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>? ?? {};
          return OutgoingCallScreen(
            consultationId:  extra['consultationId']  as String? ?? '',
            doctorName:      extra['doctorName']      as String? ?? 'Doctor',
            doctorSpecialty: extra['doctorSpecialty'] as String? ?? '',
          );
        },
      ),
      GoRoute(
        path: AppRoutes.incomingCall,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>? ?? {};
          return IncomingCallScreen(
            consultationId:   extra['consultationId']   as String? ?? '',
            doctorName:       extra['doctorName']       as String? ?? 'Doctor',
            doctorSpecialty:  extra['doctorSpecialty']  as String? ?? '',
            consultationType: extra['consultationType'] as String? ?? 'Video',
          );
        },
      ),
      GoRoute(
        path: AppRoutes.submitReview,
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>? ?? {};
          return SubmitReviewScreen(
            appointmentId: extra['appointmentId'] as String? ?? '',
            doctorId: extra['doctorId'] as String? ?? '',
            doctorName: extra['doctorName'] as String? ?? 'Doctor',
            doctorSpecialty: extra['doctorSpecialty'] as String? ?? '',
            consultationType: extra['consultationType'] as String? ?? 'Video',
          );
        },
      ),
    ],
  );
});