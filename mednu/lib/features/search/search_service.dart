import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/router/app_router.dart';

enum SearchCategory { doctor, service, speciality, labTest, hospital, medicine }

class SearchResult {
  final String id;
  final String title;
  final String subtitle;
  final String route;
  final IconData icon;
  final Color color;
  final SearchCategory category;
  final List<String> keywords;
  final Map<String, dynamic>? extra;
  final String? badge;

  const SearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.icon,
    required this.color,
    required this.category,
    required this.keywords,
    this.extra,
    this.badge,
  });
}

class SearchService {
  // ── Services ──────────────────────────────────────────────────────────────
  static const _services = <SearchResult>[
    SearchResult(
      id: 'video_consult',
      title: 'Consultation',
      subtitle: 'Online doctor consultation from home',
      route: AppRoutes.consultation,
      icon: Icons.video_call_rounded,
      color: Color(0xFF633058),
      category: SearchCategory.service,
      keywords: ['video', 'online', 'consultation', 'video consultation', 'teleconsult', 'virtual', 'call doctor', 'video call'],
      badge: 'Online',
    ),
    SearchResult(
      id: 'ambulance',
      title: 'Ambulance',
      subtitle: 'Book emergency ambulance instantly',
      route: AppRoutes.ambulance,
      icon: Icons.emergency_share_rounded,
      color: Color(0xFFB71C1C),
      category: SearchCategory.service,
      keywords: ['ambulance', 'ambulance service', 'emergency transport', 'urgent transport', 'ems'],
      badge: '24/7',
    ),
    SearchResult(
      id: 'diagnostics',
      title: 'Diagnostics',
      subtitle: 'X-Ray, MRI, CT, ECG and imaging scans',
      route: AppRoutes.diagnostics,
      icon: Icons.science_rounded,
      color: Color(0xFF0097A7),
      category: SearchCategory.service,
      keywords: ['diagnostic', 'xray', 'mri', 'ct scan', 'scan', 'imaging', 'ecg', 'ultrasound', 'echo'],
    ),
    SearchResult(
      id: 'lab_tests',
      title: 'Lab Tests',
      subtitle: 'Blood tests & sample collection at home',
      route: AppRoutes.diagnostics,
      icon: Icons.bloodtype_rounded,
      color: Color(0xFF3949AB),
      category: SearchCategory.service,
      keywords: ['lab', 'lab test', 'blood test', 'pathology', 'sample', 'sample collection'],
    ),
    SearchResult(
      id: 'physio',
      title: 'Physiotherapy',
      subtitle: 'Expert physiotherapy at home or clinic',
      route: AppRoutes.physio,
      icon: Icons.sports_gymnastics_rounded,
      color: Color(0xFF1565C0),
      category: SearchCategory.service,
      keywords: ['physio', 'physiotherapy', 'physical therapy', 'therapy', 'therapist', 'rehab', 'rehabilitation', 'back pain', 'joint pain', 'mobility'],
    ),
    SearchResult(
      id: 'caregivers',
      title: 'Caregivers',
      subtitle: 'Trained caregivers for elderly & patients',
      route: AppRoutes.caregivers,
      icon: Icons.elderly_rounded,
      color: Color(0xFFEC407A),
      category: SearchCategory.service,
      keywords: ['caregiver', 'nurse', 'attendant', 'elderly care', 'home nurse', 'patient care'],
    ),
    SearchResult(
      id: 'care_assistant',
      title: 'Care Assist',
      subtitle: 'Personal healthcare assistant service',
      route: AppRoutes.careAssistant,
      icon: Icons.support_agent_rounded,
      color: Color(0xFFE65100),
      category: SearchCategory.service,
      keywords: ['care assist', 'care assistant', 'personal care', 'home help', 'assistant', 'home care'],
    ),
    SearchResult(
      id: 'equipment',
      title: 'Equipment',
      subtitle: 'Rent or buy medical devices & aids',
      route: AppRoutes.equipment,
      icon: Icons.medical_information_rounded,
      color: Color(0xFF546E7A),
      category: SearchCategory.service,
      keywords: ['equipment', 'medical equipment', 'wheelchair', 'walker', 'oxygen', 'nebulizer', 'hospital bed', 'crutches', 'bp machine', 'rent'],
    ),
    SearchResult(
      id: 'medicines',
      title: 'Pharmacy',
      subtitle: 'Order medicines online, delivered fast',
      route: AppRoutes.medicine,
      icon: Icons.medication_rounded,
      color: Color(0xFF2E7D32),
      category: SearchCategory.medicine,
      keywords: ['medicine', 'drug', 'tablet', 'capsule', 'order medicine', 'pharmacy delivery', 'prescription delivery', 'pharmacy'],
    ),
    SearchResult(
      id: 'pharmacy',
      title: 'Online Pharmacy',
      subtitle: 'Upload prescription & get medicines',
      route: AppRoutes.pharmacy,
      icon: Icons.local_pharmacy_rounded,
      color: Color(0xFF388E3C),
      category: SearchCategory.medicine,
      keywords: ['pharmacy', 'chemist', 'drugstore', 'upload prescription', 'medicine shop'],
    ),
    SearchResult(
      id: 'emergency',
      title: 'Emergency',
      subtitle: 'Immediate emergency medical help',
      route: AppRoutes.emergency,
      icon: Icons.emergency_rounded,
      color: Color(0xFFB71C1C),
      category: SearchCategory.service,
      keywords: ['emergency', 'emergency services', 'urgent', 'sos', 'critical', 'accident', 'heart attack', 'first aid'],
      badge: '24/7',
    ),
    SearchResult(
      id: 'pregnancy',
      title: 'Pregnancy',
      subtitle: 'Complete pregnancy tracking & support',
      route: AppRoutes.pregnancy,
      icon: Icons.pregnant_woman_rounded,
      color: Color(0xFF522546),
      category: SearchCategory.service,
      keywords: ['pregnancy', 'pregnancy care', 'pregnant', 'maternity', 'antenatal', 'prenatal', 'baby', 'trimester', 'gynecologist'],
    ),
    SearchResult(
      id: 'hospitals',
      title: 'Nearby Hospitals',
      subtitle: 'Hospitals & clinics near you',
      route: AppRoutes.hospitals,
      icon: Icons.local_hospital_rounded,
      color: Color(0xFF1565C0),
      category: SearchCategory.hospital,
      keywords: ['hospital', 'clinic', 'medical center', 'nursing home', 'admission', 'inpatient', 'icu'],
    ),
    SearchResult(
      id: 'appointment',
      title: 'OP Appointment Booking',
      subtitle: 'Book outpatient clinic appointments',
      route: AppRoutes.appointment,
      icon: Icons.calendar_today_rounded,
      color: Color(0xFF1565C0),
      category: SearchCategory.service,
      keywords: ['appointment', 'op', 'outpatient', 'book', 'schedule', 'clinic visit', 'op booking'],
    ),
    SearchResult(
      id: 'specialities',
      title: 'Medical Specialities',
      subtitle: 'Browse all medical specialities',
      route: AppRoutes.specialities,
      icon: Icons.category_rounded,
      color: Color(0xFF633058),
      category: SearchCategory.speciality,
      keywords: ['speciality', 'specialist', 'browse speciality', 'all doctors'],
    ),
    SearchResult(
      id: 'nutrition',
      title: 'Nutrition and Diet',
      subtitle: 'Diet plans and nutrition guidance',
      route: AppRoutes.nutrition,
      icon: Icons.restaurant_menu_rounded,
      color: Color(0xFF558B2F),
      category: SearchCategory.service,
      keywords: ['nutrition', 'nutrition & diet', 'diet', 'food', 'dietitian', 'weight loss', 'meal plan', 'nutritionist'],
    ),
    SearchResult(
      id: 'counselling',
      title: 'Therapy and Counselling',
      subtitle: 'Mental health & wellness support',
      route: AppRoutes.counselling,
      icon: Icons.psychology_rounded,
      color: Color(0xFF6A1B9A),
      category: SearchCategory.service,
      keywords: ['counselling', 'mental health', 'counseling', 'therapy', 'therapist', 'psychotherapy', 'psychologist', 'anxiety', 'depression', 'stress', 'wellness', 'counsellor', 'counselor'],
    ),
    SearchResult(
      id: 'health_dashboard',
      title: 'Health Dashboard',
      subtitle: 'Track vitals and health metrics',
      route: AppRoutes.healthDashboard,
      icon: Icons.dashboard_rounded,
      color: Color(0xFFF9943B),
      category: SearchCategory.service,
      keywords: ['health dashboard', 'vitals', 'bmi', 'health tracking', 'steps', 'heart rate', 'monitor'],
    ),
    SearchResult(
      id: 'bmi_calculator',
      title: 'BMI Calculator',
      subtitle: 'Check your Body Mass Index',
      route: AppRoutes.nutritionBmi,
      icon: Icons.monitor_weight_rounded,
      color: Color(0xFFF9943B),
      category: SearchCategory.service,
      keywords: ['bmi', 'body mass index', 'weight', 'height', 'calculator', 'obesity'],
    ),
    SearchResult(
      id: 'period_tracker',
      title: 'Period Tracker',
      subtitle: 'Track menstrual cycle and ovulation',
      route: AppRoutes.periodTracker,
      icon: Icons.favorite_rounded,
      color: Color(0xFFA36BAC),
      category: SearchCategory.service,
      keywords: ['period', 'menstrual', 'cycle', 'ovulation', 'fertility', 'pms', 'womens health'],
    ),
    SearchResult(
      id: 'water_reminder',
      title: 'Water Reminder',
      subtitle: 'Stay hydrated with daily water tracking',
      route: AppRoutes.waterReminder,
      icon: Icons.water_drop_rounded,
      color: Color(0xFF0288D1),
      category: SearchCategory.service,
      keywords: ['water', 'hydration', 'drink water', 'daily water', 'water tracker'],
    ),
    SearchResult(
      id: 'education',
      title: 'Health Education',
      subtitle: 'AI-powered health tips and articles',
      route: AppRoutes.education,
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFF633058),
      category: SearchCategory.service,
      keywords: ['education', 'health tips', 'article', 'ai health', 'wellness', 'blog', 'guide'],
    ),
    SearchResult(
      id: 'records',
      title: 'Health Records & Reports',
      subtitle: 'Prescriptions, lab reports & medical history',
      route: AppRoutes.records,
      icon: Icons.folder_special_rounded,
      color: Color(0xFF1565C0),
      category: SearchCategory.service,
      keywords: ['records', 'report', 'reports', 'health records', 'prescription', 'medical history', 'documents', 'lab report', 'test results', 'discharge summary', 'medical report', 'my reports'],
    ),
    SearchResult(
      id: 'my_services',
      title: 'My Bookings',
      subtitle: 'Track all appointments, orders & services',
      route: AppRoutes.myServices,
      icon: Icons.bookmark_added_rounded,
      color: Color(0xFF0288D1),
      category: SearchCategory.service,
      keywords: ['bookings', 'my services', 'appointments', 'my appointments', 'orders', 'track', 'history', 'upcoming', 'my bookings'],
    ),
    SearchResult(
      id: 'wallet',
      title: 'MedNU Wallet',
      subtitle: 'Manage credits, payments & refunds',
      route: AppRoutes.wallet,
      icon: Icons.account_balance_wallet_rounded,
      color: Color(0xFF2E7D32),
      category: SearchCategory.service,
      keywords: ['wallet', 'credits', 'balance', 'payment', 'refund', 'cashback', 'money', 'mednu wallet'],
    ),
    SearchResult(
      id: 'referral',
      title: 'Refer & Earn',
      subtitle: 'Invite friends and earn rewards',
      route: AppRoutes.referral,
      icon: Icons.card_giftcard_rounded,
      color: Color(0xFFE91E63),
      category: SearchCategory.service,
      keywords: ['referral', 'refer', 'invite', 'earn', 'rewards', 'share', 'referral code', 'refer earn'],
    ),
    SearchResult(
      id: 'profile',
      title: 'My Profile',
      subtitle: 'View and edit your personal details',
      route: AppRoutes.profile,
      icon: Icons.person_rounded,
      color: Color(0xFF546E7A),
      category: SearchCategory.service,
      keywords: ['profile', 'account', 'my account', 'personal', 'details', 'edit profile', 'my profile'],
    ),
    SearchResult(
      id: 'family',
      title: 'Family Members',
      subtitle: 'Manage health records for family',
      route: AppRoutes.family,
      icon: Icons.family_restroom_rounded,
      color: Color(0xFF633058),
      category: SearchCategory.service,
      keywords: ['family', 'family members', 'dependent', 'spouse', 'children', 'parents', 'family health'],
    ),
    SearchResult(
      id: 'favourite_doctors',
      title: 'Favourite Doctors',
      subtitle: 'Your saved and preferred doctors',
      route: AppRoutes.favouriteDoctors,
      icon: Icons.favorite_rounded,
      color: Color(0xFFE91E63),
      category: SearchCategory.service,
      keywords: ['favourite', 'favorite', 'saved doctors', 'my doctors', 'preferred doctor', 'bookmarked'],
    ),
    SearchResult(
      id: 'address_book',
      title: 'Saved Addresses',
      subtitle: 'Manage delivery and home visit addresses',
      route: AppRoutes.addressBook,
      icon: Icons.location_on_rounded,
      color: Color(0xFFF9943B),
      category: SearchCategory.service,
      keywords: ['address', 'location', 'home address', 'saved address', 'delivery address', 'my address'],
    ),
    SearchResult(
      id: 'help_support',
      title: 'Help & Support',
      subtitle: 'FAQs, contact us and support tickets',
      route: AppRoutes.helpSupport,
      icon: Icons.support_agent_rounded,
      color: Color(0xFF1565C0),
      category: SearchCategory.service,
      keywords: ['help', 'support', 'faq', 'contact us', 'customer care', 'complaint', 'assistance', 'query'],
    ),
    SearchResult(
      id: 'notifications',
      title: 'Notifications',
      subtitle: 'Updates, reminders and alerts',
      route: AppRoutes.notifications,
      icon: Icons.notifications_rounded,
      color: Color(0xFFF9943B),
      category: SearchCategory.service,
      keywords: ['notifications', 'alerts', 'reminders', 'updates', 'inbox'],
    ),
    SearchResult(
      id: 'settings',
      title: 'Settings',
      subtitle: 'App preferences and account settings',
      route: AppRoutes.settings,
      icon: Icons.settings_rounded,
      color: Color(0xFF546E7A),
      category: SearchCategory.service,
      keywords: ['settings', 'preferences', 'account settings', 'app settings', 'privacy', 'security'],
    ),
    SearchResult(
      id: 'cart',
      title: 'Cart',
      subtitle: 'Review items before checkout',
      route: AppRoutes.cart,
      icon: Icons.shopping_cart_rounded,
      color: Color(0xFF2E7D32),
      category: SearchCategory.service,
      keywords: ['cart', 'checkout', 'basket', 'my cart'],
    ),
    SearchResult(
      id: 'sos_contacts',
      title: 'SOS Emergency Contacts',
      subtitle: 'Manage your emergency contact list',
      route: AppRoutes.sosContacts,
      icon: Icons.contact_phone_rounded,
      color: Color(0xFFB71C1C),
      category: SearchCategory.service,
      keywords: ['sos', 'emergency contacts', 'sos contacts', 'trusted contacts', 'safety contacts'],
    ),
    SearchResult(
      id: 'nutritionists',
      title: 'Find Nutritionists',
      subtitle: 'Book a certified dietitian',
      route: AppRoutes.nutritionNutritionists,
      icon: Icons.restaurant_rounded,
      color: Color(0xFF558B2F),
      category: SearchCategory.service,
      keywords: ['nutritionist', 'dietitian', 'diet expert', 'book nutritionist', 'find dietitian'],
    ),
  ];

  // ── Specialities ──────────────────────────────────────────────────────────
  static const _specialities = <SearchResult>[
    SearchResult(
      id: 'spec_general',
      title: 'General Physician',
      subtitle: 'Common illnesses & checkups',
      route: AppRoutes.doctors,
      icon: Icons.local_hospital_rounded,
      color: Color(0xFF2E7D32),
      category: SearchCategory.speciality,
      keywords: ['general physician', 'gp', 'fever', 'cold', 'cough', 'flu', 'general doctor', 'family doctor'],
      // Must match the canonical category string doctors_list_screen.dart's
      // Firestore query filters on exactly (where('specialty', isEqualTo:)) —
      // 'General Medicine' matched no doctor and silently returned an empty
      // list.
      extra: <String, dynamic>{'specialty': 'General', 'mode': 'filter'},
    ),
    SearchResult(
      id: 'spec_cardiology',
      title: 'Cardiologist',
      subtitle: 'Heart & cardiac care',
      route: AppRoutes.doctors,
      icon: Icons.favorite_rounded,
      color: Color(0xFFEF5350),
      category: SearchCategory.speciality,
      keywords: ['cardiologist', 'cardiac', 'heart', 'cardiology', 'heart attack', 'bp', 'blood pressure', 'chest pain'],
      extra: <String, dynamic>{'specialty': 'Cardiology', 'mode': 'filter'},
    ),
    SearchResult(
      id: 'spec_gynecology',
      title: 'Gynaecologist',
      subtitle: "Women's health",
      route: AppRoutes.doctors,
      icon: Icons.pregnant_woman_rounded,
      color: Color(0xFF522546),
      category: SearchCategory.speciality,
      keywords: ['gynaecologist', 'gynecologist', 'gynecology', 'women', 'pcos', 'fertility', 'ovarian', 'uterus'],
      extra: <String, dynamic>{'specialty': 'Gynaecology', 'mode': 'filter'},
    ),
    SearchResult(
      id: 'spec_pediatrics',
      title: 'Pediatrician',
      subtitle: 'Child health specialists',
      route: AppRoutes.doctors,
      icon: Icons.child_care_rounded,
      color: Color(0xFF1565C0),
      category: SearchCategory.speciality,
      keywords: ['pediatrician', 'pediatrics', 'child', 'baby', 'infant', 'kid', 'vaccination', 'growth', 'children'],
      extra: <String, dynamic>{'specialty': 'Paediatrics', 'mode': 'filter'},
    ),
    SearchResult(
      id: 'spec_dermatology',
      title: 'Dermatologist',
      subtitle: 'Skin, hair & nails',
      route: AppRoutes.doctors,
      icon: Icons.face_rounded,
      color: Color(0xFFFF6F00),
      category: SearchCategory.speciality,
      keywords: ['dermatologist', 'skin', 'dermatology', 'acne', 'rash', 'hair loss', 'eczema', 'psoriasis'],
      extra: <String, dynamic>{'specialty': 'Dermatology', 'mode': 'filter'},
    ),
    SearchResult(
      id: 'spec_orthopedics',
      title: 'Orthopedic',
      subtitle: 'Bone, joint & spine',
      route: AppRoutes.doctors,
      icon: Icons.accessibility_new_rounded,
      color: Color(0xFF546E7A),
      category: SearchCategory.speciality,
      keywords: ['orthopedic', 'ortho', 'bone', 'joint', 'spine', 'fracture', 'knee', 'back pain', 'sports injury'],
      // Canonical spelling used everywhere else is British ('Orthopaedics') —
      // the American spelling here matched no doctor.
      extra: <String, dynamic>{'specialty': 'Orthopaedics', 'mode': 'filter'},
    ),
    SearchResult(
      id: 'spec_neurology',
      title: 'Neurologist',
      subtitle: 'Brain & nervous system',
      route: AppRoutes.doctors,
      icon: Icons.psychology_rounded,
      color: Color(0xFF6A1B9A),
      category: SearchCategory.speciality,
      keywords: ['neurologist', 'neurology', 'brain', 'nerve', 'headache', 'migraine', 'epilepsy', 'paralysis'],
      extra: <String, dynamic>{'specialty': 'Neurology', 'mode': 'filter'},
    ),
    SearchResult(
      id: 'spec_psychiatry',
      title: 'Psychiatrist',
      subtitle: 'Mental health',
      route: AppRoutes.doctors,
      icon: Icons.self_improvement_rounded,
      color: Color(0xFF4527A0),
      category: SearchCategory.speciality,
      keywords: ['psychiatrist', 'psychiatry', 'mental health', 'depression', 'anxiety', 'ocd', 'bipolar'],
      extra: <String, dynamic>{'specialty': 'Psychiatry', 'mode': 'filter'},
    ),
    SearchResult(
      id: 'spec_ophthalmology',
      title: 'Ophthalmologist',
      subtitle: 'Eye care',
      route: AppRoutes.doctors,
      icon: Icons.remove_red_eye_rounded,
      color: Color(0xFF00838F),
      category: SearchCategory.speciality,
      keywords: ['ophthalmologist', 'eye', 'vision', 'glasses', 'cataract', 'glaucoma', 'retina', 'lasik'],
      extra: <String, dynamic>{'specialty': 'Ophthalmology', 'mode': 'filter'},
    ),
    SearchResult(
      id: 'spec_ent',
      title: 'ENT Specialist',
      subtitle: 'Ear, Nose & Throat',
      route: AppRoutes.doctors,
      icon: Icons.hearing_rounded,
      color: Color(0xFF00695C),
      category: SearchCategory.speciality,
      keywords: ['ent', 'ear', 'nose', 'throat', 'sinus', 'tonsil', 'hearing', 'vertigo'],
      extra: <String, dynamic>{'specialty': 'ENT', 'mode': 'filter'},
    ),
    SearchResult(
      id: 'spec_diabetes',
      title: 'Diabetologist',
      subtitle: 'Diabetes & endocrinology',
      route: AppRoutes.doctors,
      icon: Icons.bloodtype_rounded,
      color: Color(0xFFE65100),
      category: SearchCategory.speciality,
      keywords: ['diabetologist', 'diabetes', 'sugar', 'endocrinology', 'insulin', 'thyroid', 'hormone'],
      // 'Diabetology' isn't a category anywhere else in the app — no doctor
      // record uses it. 'Endocrinology' is the real category diabetes
      // specialists are filed under (see specialities_screen.dart).
      extra: <String, dynamic>{'specialty': 'Endocrinology', 'mode': 'filter'},
    ),
    SearchResult(
      id: 'spec_oncology',
      title: 'Oncologist',
      subtitle: 'Cancer care',
      route: AppRoutes.doctors,
      icon: Icons.biotech_rounded,
      color: Color(0xFF33172C),
      category: SearchCategory.speciality,
      keywords: ['oncologist', 'cancer', 'oncology', 'tumor', 'chemo', 'radiation'],
      extra: <String, dynamic>{'specialty': 'Oncology', 'mode': 'filter'},
    ),
  ];

  // ── Lab Tests ─────────────────────────────────────────────────────────────
  static const _labTests = <SearchResult>[
    SearchResult(
      id: 'lab_cbc',
      title: 'CBC – Complete Blood Count',
      subtitle: 'Blood test · Results in 24 hrs',
      route: AppRoutes.diagnostics,
      icon: Icons.water_drop_rounded,
      color: Color(0xFF0097A7),
      category: SearchCategory.labTest,
      keywords: ['cbc', 'complete blood count', 'blood test', 'hemoglobin', 'wbc', 'rbc', 'platelet'],
    ),
    SearchResult(
      id: 'lab_hba1c',
      title: 'HbA1c (Diabetes Test)',
      subtitle: 'Blood sugar level · Results in 24 hrs',
      route: AppRoutes.diagnostics,
      icon: Icons.bloodtype_rounded,
      color: Color(0xFFE65100),
      category: SearchCategory.labTest,
      keywords: ['hba1c', 'diabetes test', 'blood sugar', 'glycated hemoglobin', 'sugar test'],
    ),
    SearchResult(
      id: 'lab_lipid',
      title: 'Lipid Profile',
      subtitle: 'Cholesterol test · Results in 24 hrs',
      route: AppRoutes.diagnostics,
      icon: Icons.monitor_heart_rounded,
      color: Color(0xFFEF5350),
      category: SearchCategory.labTest,
      keywords: ['lipid profile', 'cholesterol', 'triglyceride', 'hdl', 'ldl', 'heart test'],
    ),
    SearchResult(
      id: 'lab_thyroid',
      title: 'Thyroid Function Test',
      subtitle: 'TSH, T3, T4 · Results in 24 hrs',
      route: AppRoutes.diagnostics,
      icon: Icons.biotech_rounded,
      color: Color(0xFF6A1B9A),
      category: SearchCategory.labTest,
      keywords: ['thyroid', 'tsh', 't3', 't4', 'hypothyroid', 'hyperthyroid', 'thyroid function'],
    ),
    SearchResult(
      id: 'lab_xray',
      title: 'X-Ray',
      subtitle: 'Chest, bone & joint imaging',
      route: AppRoutes.diagnostics,
      icon: Icons.image_rounded,
      color: Color(0xFF1565C0),
      category: SearchCategory.labTest,
      keywords: ['xray', 'x-ray', 'chest xray', 'bone xray', 'imaging', 'radiology', 'x ray'],
    ),
    SearchResult(
      id: 'lab_mri',
      title: 'MRI Scan',
      subtitle: 'Brain, spine, joint MRI',
      route: AppRoutes.diagnostics,
      icon: Icons.blur_circular_rounded,
      color: Color(0xFF546E7A),
      category: SearchCategory.labTest,
      keywords: ['mri', 'mri scan', 'brain mri', 'spine mri', 'magnetic resonance'],
    ),
    SearchResult(
      id: 'lab_ecg',
      title: 'ECG / EKG',
      subtitle: 'Heart electrical activity test',
      route: AppRoutes.diagnostics,
      icon: Icons.monitor_heart_rounded,
      color: Color(0xFFB71C1C),
      category: SearchCategory.labTest,
      keywords: ['ecg', 'ekg', 'electrocardiogram', 'heart test', 'cardiac test'],
    ),
    SearchResult(
      id: 'lab_urine',
      title: 'Urine Routine & Microscopy',
      subtitle: 'Kidney & bladder health · 24 hrs',
      route: AppRoutes.diagnostics,
      icon: Icons.science_rounded,
      color: Color(0xFFFFB300),
      category: SearchCategory.labTest,
      keywords: ['urine', 'urine test', 'urine routine', 'kidney test', 'uti', 'bladder'],
    ),
    SearchResult(
      id: 'lab_covid',
      title: 'COVID-19 Test (RT-PCR)',
      subtitle: 'Rapid / RT-PCR test available',
      route: AppRoutes.diagnostics,
      icon: Icons.coronavirus_rounded,
      color: Color(0xFFFF6F00),
      category: SearchCategory.labTest,
      keywords: ['covid', 'corona', 'rt-pcr', 'rapid test', 'antigen', 'covid test'],
    ),
  ];

  // ── Public API ────────────────────────────────────────────────────────────

  static List<SearchResult> get allStatic => [..._services, ..._specialities, ..._labTests];

  static const popularSearches = [
    'Cardiologist',
    'Blood Test',
    'Fever',
    'Pediatrician',
    'Video Consult',
    'Ambulance',
    'Physiotherapy',
    'Pregnancy',
  ];

  /// Scored partial-match search across entire static index.
  static List<SearchResult> searchStatic(String query) {
    if (query.length < 2) return [];
    final q = query.toLowerCase().trim();
    final scored = <MapEntry<double, SearchResult>>[];

    for (final item in allStatic) {
      double score = 0;
      final titleLower = item.title.toLowerCase();
      final subtitleLower = item.subtitle.toLowerCase();

      if (titleLower == q) {
        score += 20;
      } else if (titleLower.startsWith(q)) {
        score += 12;
      } else if (titleLower.contains(q)) {
        score += 8;
      }

      if (subtitleLower.contains(q)) score += 3;

      for (final kw in item.keywords) {
        if (kw == q) {
          score += 10;
          break;
        } else if (kw.startsWith(q)) {
          score += 6;
          break;
        } else if (kw.contains(q)) {
          score += 2;
          break;
        }
      }

      // Typo-tolerant fallback — only runs when nothing above already
      // matched, so it never outranks a real substring/keyword hit.
      if (score == 0) {
        for (final word in titleLower.split(' ')) {
          if (_isCloseMatch(word, q)) {
            score += 5;
            break;
          }
        }
        if (score == 0) {
          for (final kw in item.keywords) {
            if (_isCloseMatch(kw, q)) {
              score += 4;
              break;
            }
          }
        }
      }

      if (score > 0) scored.add(MapEntry(score, item));
    }

    scored.sort((a, b) => b.key.compareTo(a.key));
    return scored.map((e) => e.value).toList();
  }

  /// True if [word] and [q] are close enough to be the same typed word
  /// (substring either way, or a small edit distance for likely typos).
  static bool _isCloseMatch(String word, String q) {
    if (word.isEmpty || q.isEmpty) return false;
    if (word.contains(q) || q.contains(word)) return true;
    if ((word.length - q.length).abs() > 3) return false;
    final threshold = q.length <= 4 ? 1 : (q.length <= 8 ? 2 : 3);
    return _levenshtein(word, q) <= threshold;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var curr = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      curr[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        final del = prev[j + 1] + 1;
        final ins = curr[j] + 1;
        final sub = prev[j] + cost;
        curr[j + 1] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[b.length];
  }

  /// Queries the live Firestore `doctors` collection.
  static Future<List<Map<String, dynamic>>> searchFirestoreDoctors(
      String query) async {
    if (query.length < 2) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('doctors')
          .where('status', isEqualTo: 'active')
          .limit(30)
          .get();
      final q = query.toLowerCase();
      return snap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .where((d) {
        final name = (d['name'] as String? ?? '').toLowerCase();
        final spec = (d['specialty'] as String? ??
                d['speciality'] as String? ??
                '')
            .toLowerCase();
        return name.contains(q) || spec.contains(q);
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
