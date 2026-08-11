import '../models/ambulance_request.dart';
import '../models/trip.dart';
import '../models/vehicle_profile.dart';

/// In-memory, session-local mock data — deliberately not a Firestore
/// repository yet (see module brief: UI completion first, no backend
/// wiring). Shaped so a real repository implementing the same read
/// signatures can be dropped in later without the screens/providers
/// changing, mirroring how `LabTransactionWalletRepository` /
/// `PharmacyTransactionWalletRepository` slot into the same
/// `WalletRepository` interface `DoctorAppointmentWalletRepository` uses.
class MockAmbulanceRepository {
  MockAmbulanceRepository._();
  static final instance = MockAmbulanceRepository._();

  final vehicle = const VehicleProfile(
    plateNumber: 'KA 05 AB 4321',
    vehicleType: 'Advanced Life Support',
    driverName: 'Ramesh Kumar',
    driverPhone: '+91 98765 43210',
    driverLicense: 'KA-0520230004521',
    equipment: ['Defibrillator', 'Oxygen Cylinder', 'Stretcher', 'First-Aid Kit', 'Ventilator'],
    documentsVerified: true,
    rating: 4.8,
    totalTrips: 342,
  );

  List<AmbulanceRequest> seedRequests() {
    final now = DateTime.now();
    return [
      AmbulanceRequest(
        id: 'REQ-1042',
        type: EmergencyType.cardiac,
        status: AmbulanceRequestStatus.pending,
        patientName: 'Suresh Iyer',
        patientPhone: '+91 90000 11122',
        pickupAddress: '14th Cross, Indiranagar, Bengaluru',
        dropAddress: 'Manipal Hospital, Old Airport Road',
        distanceKm: 3.2,
        etaMinutes: 6,
        fare: 850,
        requestedAt: now.subtract(const Duration(minutes: 1)),
      ),
      AmbulanceRequest(
        id: 'REQ-1041',
        type: EmergencyType.accident,
        status: AmbulanceRequestStatus.pending,
        patientName: 'Farhan Sheikh',
        patientPhone: '+91 90000 33344',
        pickupAddress: 'Silk Board Junction, HSR Layout',
        dropAddress: 'Fortis Hospital, Bannerghatta Road',
        distanceKm: 5.8,
        etaMinutes: 11,
        fare: 1200,
        requestedAt: now.subtract(const Duration(minutes: 3)),
      ),
      AmbulanceRequest(
        id: 'REQ-1039',
        type: EmergencyType.maternity,
        status: AmbulanceRequestStatus.pending,
        patientName: 'Ananya Rao',
        patientPhone: '+91 90000 55566',
        pickupAddress: 'Koramangala 5th Block',
        dropAddress: 'Cloudnine Hospital, Old Airport Road',
        distanceKm: 4.1,
        etaMinutes: 8,
        fare: 950,
        requestedAt: now.subtract(const Duration(minutes: 5)),
      ),
    ];
  }

  List<Trip> seedTrips() {
    final now = DateTime.now();
    return [
      Trip(
        id: 'TRIP-2231',
        type: EmergencyType.general,
        patientName: 'Meena Pillai',
        pickupAddress: 'Jayanagar 4th Block',
        dropAddress: 'Apollo Hospital, Bannerghatta Road',
        distanceKm: 6.4,
        durationMinutes: 19,
        fare: 1100,
        rating: 5.0,
        completedAt: now.subtract(const Duration(hours: 3)),
      ),
      Trip(
        id: 'TRIP-2230',
        type: EmergencyType.accident,
        patientName: 'Vikram Shetty',
        pickupAddress: 'Marathahalli Bridge',
        dropAddress: 'Manipal Hospital, Whitefield',
        distanceKm: 8.9,
        durationMinutes: 24,
        fare: 1600,
        rating: 4.5,
        completedAt: now.subtract(const Duration(hours: 7)),
      ),
      Trip(
        id: 'TRIP-2226',
        type: EmergencyType.cardiac,
        patientName: 'Lakshmi Narayan',
        pickupAddress: 'RT Nagar',
        dropAddress: 'Columbia Asia, Hebbal',
        distanceKm: 3.5,
        durationMinutes: 13,
        fare: 800,
        rating: 5.0,
        completedAt: now.subtract(const Duration(days: 1, hours: 2)),
      ),
      Trip(
        id: 'TRIP-2219',
        type: EmergencyType.general,
        patientName: 'Divya Krishnan',
        pickupAddress: 'BTM Layout 2nd Stage',
        dropAddress: 'St. John\'s Medical College',
        distanceKm: 5.0,
        durationMinutes: 17,
        fare: 950,
        rating: 4.0,
        completedAt: now.subtract(const Duration(days: 2, hours: 5)),
      ),
    ];
  }

  /// Weekly earnings for the chart on the Earnings screen — Mon..Sun.
  List<double> weeklyEarnings() => const [1200, 2100, 1800, 2600, 3100, 2400, 1700];
}
