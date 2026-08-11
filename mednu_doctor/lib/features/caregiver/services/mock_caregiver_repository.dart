import '../models/care_note.dart';
import '../models/care_task.dart';
import '../models/caregiver_profile.dart';
import '../models/visit.dart';

/// In-memory, session-local mock data — deliberately not a Firestore
/// repository yet (UI-first module). Shaped so a real repository can be
/// dropped in later without the screens/providers changing, mirroring the
/// Ambulance module's `MockAmbulanceRepository`.
class MockCaregiverRepository {
  MockCaregiverRepository._();
  static final instance = MockCaregiverRepository._();

  final profile = const CaregiverProfile(
    name: 'Anita Fernandes',
    photoUrl: '',
    certifications: ['Certified Nursing Assistant', 'Basic Life Support', 'Geriatric Care Specialist'],
    specialties: ['Elderly Care', 'Post-Surgery Recovery', 'Medication Management'],
    hourlyRate: 350,
    rating: 4.9,
    totalVisits: 512,
    experienceYears: 6,
    documentsVerified: true,
  );

  List<Visit> seedVisits() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      Visit(
        id: 'VISIT-501',
        type: CareType.elderlyCare,
        status: VisitStatus.scheduled,
        patientName: 'Padma Venkatesh',
        patientAge: 78,
        address: '2nd Cross, Malleshwaram, Bengaluru',
        scheduledAt: today.add(const Duration(hours: 10)),
        durationMinutes: 90,
        fare: 700,
        tasks: const [
          CareTask(id: 't1', title: 'Check blood pressure', isDone: false),
          CareTask(id: 't2', title: 'Assist with morning medication', isDone: false),
          CareTask(id: 't3', title: 'Light mobility exercises', isDone: false),
          CareTask(id: 't4', title: 'Prepare and serve breakfast', isDone: false),
        ],
        notes: const [],
        photoPaths: const [],
      ),
      Visit(
        id: 'VISIT-498',
        type: CareType.postSurgery,
        status: VisitStatus.scheduled,
        patientName: 'Rohit Bhat',
        patientAge: 54,
        address: 'HSR Layout Sector 2, Bengaluru',
        scheduledAt: today.add(const Duration(hours: 14, minutes: 30)),
        durationMinutes: 60,
        fare: 550,
        tasks: const [
          CareTask(id: 't1', title: 'Change surgical dressing', isDone: false),
          CareTask(id: 't2', title: 'Check for signs of infection', isDone: false),
          CareTask(id: 't3', title: 'Pain level assessment', isDone: false),
        ],
        notes: const [],
        photoPaths: const [],
      ),
      Visit(
        id: 'VISIT-495',
        type: CareType.physiotherapy,
        status: VisitStatus.checkedIn,
        patientName: 'Geeta Kulkarni',
        patientAge: 66,
        address: 'Jayanagar 9th Block, Bengaluru',
        scheduledAt: today.subtract(const Duration(minutes: 20)),
        durationMinutes: 45,
        fare: 600,
        tasks: const [
          CareTask(id: 't1', title: 'Knee mobility exercises', isDone: true),
          CareTask(id: 't2', title: 'Gait training walk', isDone: false),
          CareTask(id: 't3', title: 'Ice pack application', isDone: false),
        ],
        notes: [
          CareNote(id: 'n1', text: 'Patient reports reduced knee stiffness since last visit.', createdAt: now.subtract(const Duration(minutes: 15))),
        ],
        photoPaths: const [],
      ),
      Visit(
        id: 'VISIT-489',
        type: CareType.medicationManagement,
        status: VisitStatus.completed,
        patientName: 'Suryakant Rao',
        patientAge: 82,
        address: 'RT Nagar, Bengaluru',
        scheduledAt: now.subtract(const Duration(days: 1, hours: 3)),
        durationMinutes: 40,
        fare: 450,
        tasks: const [
          CareTask(id: 't1', title: 'Organize weekly pill box', isDone: true),
          CareTask(id: 't2', title: 'Review medication side effects', isDone: true),
        ],
        notes: [
          CareNote(id: 'n1', text: 'Family requested a reminder call before evening dose.', createdAt: now.subtract(const Duration(days: 1, hours: 3))),
        ],
        photoPaths: const [],
      ),
      Visit(
        id: 'VISIT-481',
        type: CareType.generalNursing,
        status: VisitStatus.completed,
        patientName: 'Meera Joshi',
        patientAge: 71,
        address: 'Basavanagudi, Bengaluru',
        scheduledAt: now.subtract(const Duration(days: 2, hours: 5)),
        durationMinutes: 60,
        fare: 500,
        tasks: const [
          CareTask(id: 't1', title: 'Wound dressing change', isDone: true),
          CareTask(id: 't2', title: 'Vitals check', isDone: true),
        ],
        notes: const [],
        photoPaths: const [],
      ),
      Visit(
        id: 'VISIT-475',
        type: CareType.elderlyCare,
        status: VisitStatus.missed,
        patientName: 'Krishnan Iyer',
        patientAge: 85,
        address: 'Vijayanagar, Bengaluru',
        scheduledAt: now.subtract(const Duration(days: 3, hours: 2)),
        durationMinutes: 90,
        fare: 700,
        tasks: const [],
        notes: const [],
        photoPaths: const [],
      ),
    ];
  }

  List<double> weeklyEarnings() => const [900, 1400, 1100, 1700, 2000, 1500, 1200];
}
