import 'package:flutter/material.dart';
import '../../core/router/app_router.dart';
import '../models/app_role.dart';
import 'nav_item.dart';

/// Generates the menu for the active role. This only *reads* the existing
/// `AppRoutes` constants — it never adds, renames, or removes a route in
/// `core/router/app_router.dart`, so today's Doctor navigation is completely
/// unaffected until a future prompt wires this menu into a shell.
///
/// Admin's menu is a placeholder until its own feature module exists;
/// returning an empty list for it here is intentional and keeps this layer
/// honest about what's actually built. Lab (`features/lab/`), Pharmacy
/// (`features/pharmacy/`), Ambulance (`features/ambulance/`), and Caregiver
/// (`features/caregiver/`) are all real, Firestore-backed modules.
List<NavItem> buildMenuForRole(AppRole role) {
  switch (role) {
    case AppRole.doctor:
      return const [
        NavItem(
          label: 'Home',
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          route: AppRoutes.dashboard,
        ),
        NavItem(
          label: 'Patients',
          icon: Icons.people_outline_rounded,
          activeIcon: Icons.people_rounded,
          route: AppRoutes.patients,
        ),
        NavItem(
          label: 'Schedule',
          icon: Icons.calendar_today_outlined,
          activeIcon: Icons.calendar_today_rounded,
          route: AppRoutes.schedule,
        ),
        NavItem(
          label: 'Earnings',
          icon: Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          route: AppRoutes.earnings,
        ),
        NavItem(
          label: 'Settings',
          icon: Icons.settings_outlined,
          activeIcon: Icons.settings_rounded,
          route: AppRoutes.settings,
        ),
      ];
    case AppRole.lab:
      return const [
        NavItem(
          label: 'Dashboard',
          icon: Icons.space_dashboard_outlined,
          activeIcon: Icons.space_dashboard_rounded,
          route: AppRoutes.labDashboard,
        ),
        NavItem(
          label: 'Bookings',
          icon: Icons.event_note_outlined,
          activeIcon: Icons.event_note_rounded,
          route: AppRoutes.labBookings,
        ),
        NavItem(
          label: 'Collection',
          icon: Icons.local_shipping_outlined,
          activeIcon: Icons.local_shipping_rounded,
          route: AppRoutes.labSampleCollection,
        ),
        NavItem(
          label: 'Tests',
          icon: Icons.biotech_outlined,
          activeIcon: Icons.biotech_rounded,
          route: AppRoutes.labTestInventory,
        ),
        NavItem(
          label: 'Reports',
          icon: Icons.description_outlined,
          activeIcon: Icons.description_rounded,
          route: AppRoutes.labReports,
        ),
        NavItem(
          label: 'Earnings',
          icon: Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          route: AppRoutes.labEarnings,
        ),
        NavItem(
          label: 'Profile',
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          route: AppRoutes.labProfile,
        ),
      ];
    case AppRole.pharmacy:
      return const [
        NavItem(
          label: 'Dashboard',
          icon: Icons.space_dashboard_outlined,
          activeIcon: Icons.space_dashboard_rounded,
          route: AppRoutes.pharmacyDashboard,
        ),
        NavItem(
          label: 'Orders',
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long_rounded,
          route: AppRoutes.pharmacyOrders,
        ),
        NavItem(
          label: 'Prescriptions',
          icon: Icons.medical_information_outlined,
          activeIcon: Icons.medical_information_rounded,
          route: AppRoutes.pharmacyPrescriptionVerification,
        ),
        NavItem(
          label: 'Inventory',
          icon: Icons.inventory_2_outlined,
          activeIcon: Icons.inventory_2_rounded,
          route: AppRoutes.pharmacyInventory,
        ),
        NavItem(
          label: 'Earnings',
          icon: Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          route: AppRoutes.pharmacyEarnings,
        ),
        NavItem(
          label: 'Profile',
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          route: AppRoutes.pharmacyProfile,
        ),
      ];
    case AppRole.ambulance:
      return const [
        NavItem(
          label: 'Dashboard',
          icon: Icons.space_dashboard_outlined,
          activeIcon: Icons.space_dashboard_rounded,
          route: AppRoutes.ambulanceDashboard,
        ),
        NavItem(
          label: 'Requests',
          icon: Icons.notifications_none_rounded,
          activeIcon: Icons.notifications_active_rounded,
          route: AppRoutes.ambulanceIncomingRequests,
        ),
        NavItem(
          label: 'Tracking',
          icon: Icons.map_outlined,
          activeIcon: Icons.map_rounded,
          route: AppRoutes.ambulanceLiveTracking,
        ),
        NavItem(
          label: 'History',
          icon: Icons.history_rounded,
          activeIcon: Icons.history_rounded,
          route: AppRoutes.ambulanceTripHistory,
        ),
        NavItem(
          label: 'Earnings',
          icon: Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          route: AppRoutes.ambulanceEarnings,
        ),
        NavItem(
          label: 'Vehicle',
          icon: Icons.local_shipping_outlined,
          activeIcon: Icons.local_shipping_rounded,
          route: AppRoutes.ambulanceVehicleProfile,
        ),
      ];
    case AppRole.caregiver:
      return const [
        NavItem(
          label: 'Dashboard',
          icon: Icons.space_dashboard_outlined,
          activeIcon: Icons.space_dashboard_rounded,
          route: AppRoutes.caregiverDashboard,
        ),
        NavItem(
          label: 'Visits',
          icon: Icons.event_note_outlined,
          activeIcon: Icons.event_note_rounded,
          route: AppRoutes.caregiverAssignedVisits,
        ),
        NavItem(
          label: 'Earnings',
          icon: Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          route: AppRoutes.caregiverEarnings,
        ),
        NavItem(
          label: 'Profile',
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          route: AppRoutes.caregiverProfile,
        ),
      ];
    case AppRole.physiotherapist:
      return const [
        NavItem(
          label: 'Dashboard',
          icon: Icons.space_dashboard_outlined,
          activeIcon: Icons.space_dashboard_rounded,
          route: AppRoutes.physioDashboard,
        ),
        NavItem(
          label: 'Sessions',
          icon: Icons.event_note_outlined,
          activeIcon: Icons.event_note_rounded,
          route: AppRoutes.physioSessions,
        ),
        NavItem(
          label: 'Earnings',
          icon: Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          route: AppRoutes.physioEarnings,
        ),
        NavItem(
          label: 'Profile',
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          route: AppRoutes.physioProfile,
        ),
      ];
    case AppRole.counsellor:
      return const [
        NavItem(
          label: 'Dashboard',
          icon: Icons.space_dashboard_outlined,
          activeIcon: Icons.space_dashboard_rounded,
          route: AppRoutes.counsellingDashboard,
        ),
        NavItem(
          label: 'Sessions',
          icon: Icons.event_note_outlined,
          activeIcon: Icons.event_note_rounded,
          route: AppRoutes.counsellingSessions,
        ),
        NavItem(
          label: 'Earnings',
          icon: Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          route: AppRoutes.counsellingEarnings,
        ),
        NavItem(
          label: 'Profile',
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          route: AppRoutes.counsellingProfile,
        ),
      ];
    case AppRole.nutritionist:
      return const [
        NavItem(
          label: 'Dashboard',
          icon: Icons.space_dashboard_outlined,
          activeIcon: Icons.space_dashboard_rounded,
          route: AppRoutes.nutritionDashboard,
        ),
        NavItem(
          label: 'Appointments',
          icon: Icons.event_note_outlined,
          activeIcon: Icons.event_note_rounded,
          route: AppRoutes.nutritionAppointments,
        ),
        NavItem(
          label: 'Earnings',
          icon: Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          route: AppRoutes.nutritionEarnings,
        ),
        NavItem(
          label: 'Profile',
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          route: AppRoutes.nutritionProfile,
        ),
      ];
    case AppRole.admin:
      // No feature module exists yet for this role — the app shell should
      // hide role-switching to it (or show a "coming soon" state) rather
      // than render an empty menu. Left empty deliberately.
      return const [];
  }
}
