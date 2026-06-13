import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Pregnancy Profile ───────────────────────────────────────────────────────

class PregnancyProfile {
  final String id;
  final String patientId;
  final DateTime pregnancyStartDate;
  final DateTime lmpDate;
  final DateTime dueDate;
  final String bloodGroup;
  final double weightKg;
  final double? heightCm;
  final int ageYears;
  final List<String> medicalConditions;
  final int previousPregnancies;
  final int previousLiveBirths;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String? assignedDoctorId;
  final String? assignedDoctorName;
  final bool isHighRisk;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PregnancyProfile({
    required this.id,
    required this.patientId,
    required this.pregnancyStartDate,
    required this.lmpDate,
    required this.dueDate,
    required this.bloodGroup,
    required this.weightKg,
    this.heightCm,
    required this.ageYears,
    required this.medicalConditions,
    required this.previousPregnancies,
    required this.previousLiveBirths,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    this.assignedDoctorId,
    this.assignedDoctorName,
    this.isHighRisk = false,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  // Bug fix: clamp to 40, not 42
  int get currentWeek {
    final days = DateTime.now().difference(lmpDate).inDays;
    return (days / 7).floor().clamp(1, 40);
  }

  int get currentTrimester {
    final w = currentWeek;
    if (w <= 13) return 1;
    if (w <= 26) return 2;
    return 3;
  }

  int get daysUntilDue => dueDate.difference(DateTime.now()).inDays.clamp(0, 280);

  String get trimesterLabel {
    switch (currentTrimester) {
      case 1: return '1st Trimester';
      case 2: return '2nd Trimester';
      default: return '3rd Trimester';
    }
  }

  Map<String, dynamic> toMap() => {
    'patientId': patientId,
    'pregnancyStartDate': Timestamp.fromDate(pregnancyStartDate),
    'lmpDate': Timestamp.fromDate(lmpDate),
    'dueDate': Timestamp.fromDate(dueDate),
    'bloodGroup': bloodGroup,
    'weightKg': weightKg,
    'heightCm': heightCm,
    'ageYears': ageYears,
    'medicalConditions': medicalConditions,
    'previousPregnancies': previousPregnancies,
    'previousLiveBirths': previousLiveBirths,
    'emergencyContactName': emergencyContactName,
    'emergencyContactPhone': emergencyContactPhone,
    'assignedDoctorId': assignedDoctorId,
    'assignedDoctorName': assignedDoctorName,
    'isHighRisk': isHighRisk,
    'isActive': isActive,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  factory PregnancyProfile.fromMap(String id, Map<String, dynamic> d) =>
      PregnancyProfile(
        id: id,
        patientId: d['patientId'] as String? ?? '',
        pregnancyStartDate: (d['pregnancyStartDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        lmpDate: (d['lmpDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        dueDate: (d['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(days: 280)),
        bloodGroup: d['bloodGroup'] as String? ?? '',
        weightKg: (d['weightKg'] as num?)?.toDouble() ?? 0,
        heightCm: (d['heightCm'] as num?)?.toDouble(),
        ageYears: d['ageYears'] as int? ?? 0,
        medicalConditions: List<String>.from(d['medicalConditions'] as List? ?? []),
        previousPregnancies: d['previousPregnancies'] as int? ?? 0,
        previousLiveBirths: d['previousLiveBirths'] as int? ?? 0,
        emergencyContactName: d['emergencyContactName'] as String? ?? '',
        emergencyContactPhone: d['emergencyContactPhone'] as String? ?? '',
        assignedDoctorId: d['assignedDoctorId'] as String?,
        assignedDoctorName: d['assignedDoctorName'] as String?,
        isHighRisk: d['isHighRisk'] as bool? ?? false,
        isActive: d['isActive'] as bool? ?? true,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  PregnancyProfile copyWith({
    String? id,
    String? patientId,
    DateTime? pregnancyStartDate,
    DateTime? lmpDate,
    DateTime? dueDate,
    String? bloodGroup,
    double? weightKg,
    double? heightCm,
    int? ageYears,
    List<String>? medicalConditions,
    int? previousPregnancies,
    int? previousLiveBirths,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? assignedDoctorId,
    String? assignedDoctorName,
    bool? isHighRisk,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => PregnancyProfile(
    id: id ?? this.id,
    patientId: patientId ?? this.patientId,
    pregnancyStartDate: pregnancyStartDate ?? this.pregnancyStartDate,
    lmpDate: lmpDate ?? this.lmpDate,
    dueDate: dueDate ?? this.dueDate,
    bloodGroup: bloodGroup ?? this.bloodGroup,
    weightKg: weightKg ?? this.weightKg,
    heightCm: heightCm ?? this.heightCm,
    ageYears: ageYears ?? this.ageYears,
    medicalConditions: medicalConditions ?? this.medicalConditions,
    previousPregnancies: previousPregnancies ?? this.previousPregnancies,
    previousLiveBirths: previousLiveBirths ?? this.previousLiveBirths,
    emergencyContactName: emergencyContactName ?? this.emergencyContactName,
    emergencyContactPhone: emergencyContactPhone ?? this.emergencyContactPhone,
    assignedDoctorId: assignedDoctorId ?? this.assignedDoctorId,
    assignedDoctorName: assignedDoctorName ?? this.assignedDoctorName,
    isHighRisk: isHighRisk ?? this.isHighRisk,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );
}

// ─── Weekly Log ──────────────────────────────────────────────────────────────

class PregnancyWeeklyLog {
  final String id;
  final String patientId;
  final String date; // yyyy-MM-dd
  final int pregnancyWeek;
  final List<String> symptoms;
  final double? weightKg;
  final String? bpSystolic;
  final String? bpDiastolic;
  final double? sugarLevel;
  final int? babyMovements;
  final String mood;
  final double? sleepHours;
  final int? waterGlasses;
  final String notes;
  final DateTime loggedAt;

  const PregnancyWeeklyLog({
    required this.id,
    required this.patientId,
    required this.date,
    required this.pregnancyWeek,
    required this.symptoms,
    this.weightKg,
    this.bpSystolic,
    this.bpDiastolic,
    this.sugarLevel,
    this.babyMovements,
    required this.mood,
    this.sleepHours,
    this.waterGlasses,
    required this.notes,
    required this.loggedAt,
  });

  Map<String, dynamic> toMap() => {
    'patientId': patientId,
    'date': date,
    'pregnancyWeek': pregnancyWeek,
    'symptoms': symptoms,
    'weightKg': weightKg,
    'bpSystolic': bpSystolic,
    'bpDiastolic': bpDiastolic,
    'sugarLevel': sugarLevel,
    'babyMovements': babyMovements,
    'mood': mood,
    'sleepHours': sleepHours,
    'waterGlasses': waterGlasses,
    'notes': notes,
    'loggedAt': Timestamp.fromDate(loggedAt),
  };

  factory PregnancyWeeklyLog.fromMap(String id, Map<String, dynamic> d) =>
      PregnancyWeeklyLog(
        id: id,
        patientId: d['patientId'] as String? ?? '',
        date: d['date'] as String? ?? '',
        pregnancyWeek: d['pregnancyWeek'] as int? ?? 1,
        symptoms: List<String>.from(d['symptoms'] as List? ?? []),
        weightKg: (d['weightKg'] as num?)?.toDouble(),
        bpSystolic: d['bpSystolic'] as String?,
        bpDiastolic: d['bpDiastolic'] as String?,
        sugarLevel: (d['sugarLevel'] as num?)?.toDouble(),
        babyMovements: d['babyMovements'] as int?,
        mood: d['mood'] as String? ?? 'Calm',
        sleepHours: (d['sleepHours'] as num?)?.toDouble(),
        waterGlasses: d['waterGlasses'] as int?,
        notes: d['notes'] as String? ?? '',
        loggedAt: (d['loggedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  PregnancyWeeklyLog copyWith({
    String? id,
    String? patientId,
    String? date,
    int? pregnancyWeek,
    List<String>? symptoms,
    double? weightKg,
    String? bpSystolic,
    String? bpDiastolic,
    double? sugarLevel,
    int? babyMovements,
    String? mood,
    double? sleepHours,
    int? waterGlasses,
    String? notes,
    DateTime? loggedAt,
  }) => PregnancyWeeklyLog(
    id: id ?? this.id,
    patientId: patientId ?? this.patientId,
    date: date ?? this.date,
    pregnancyWeek: pregnancyWeek ?? this.pregnancyWeek,
    symptoms: symptoms ?? this.symptoms,
    weightKg: weightKg ?? this.weightKg,
    bpSystolic: bpSystolic ?? this.bpSystolic,
    bpDiastolic: bpDiastolic ?? this.bpDiastolic,
    sugarLevel: sugarLevel ?? this.sugarLevel,
    babyMovements: babyMovements ?? this.babyMovements,
    mood: mood ?? this.mood,
    sleepHours: sleepHours ?? this.sleepHours,
    waterGlasses: waterGlasses ?? this.waterGlasses,
    notes: notes ?? this.notes,
    loggedAt: loggedAt ?? this.loggedAt,
  );
}

// ─── Pregnancy Checkup ───────────────────────────────────────────────────────

class PregnancyCheckup {
  final String id;
  final String patientId;
  final String type; // 'routine', 'ultrasound', 'blood_test', 'scan', 'vaccination'
  final String title;
  final DateTime scheduledDate;
  final String status; // 'upcoming', 'completed', 'missed', 'cancelled'
  final String? notes;
  final String? doctorId;
  final int pregnancyWeek;
  final DateTime createdAt;

  const PregnancyCheckup({
    required this.id,
    required this.patientId,
    required this.type,
    required this.title,
    required this.scheduledDate,
    required this.status,
    this.notes,
    this.doctorId,
    required this.pregnancyWeek,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'patientId': patientId,
    'type': type,
    'title': title,
    'scheduledDate': Timestamp.fromDate(scheduledDate),
    'status': status,
    'notes': notes,
    'doctorId': doctorId,
    'pregnancyWeek': pregnancyWeek,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory PregnancyCheckup.fromMap(String id, Map<String, dynamic> d) =>
      PregnancyCheckup(
        id: id,
        patientId: d['patientId'] as String? ?? '',
        type: d['type'] as String? ?? 'routine',
        title: d['title'] as String? ?? 'Checkup',
        scheduledDate: (d['scheduledDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        status: d['status'] as String? ?? 'upcoming',
        notes: d['notes'] as String?,
        doctorId: d['doctorId'] as String?,
        pregnancyWeek: d['pregnancyWeek'] as int? ?? 1,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  PregnancyCheckup copyWith({
    String? id,
    String? patientId,
    String? type,
    String? title,
    DateTime? scheduledDate,
    String? status,
    String? notes,
    String? doctorId,
    int? pregnancyWeek,
    DateTime? createdAt,
  }) => PregnancyCheckup(
    id: id ?? this.id,
    patientId: patientId ?? this.patientId,
    type: type ?? this.type,
    title: title ?? this.title,
    scheduledDate: scheduledDate ?? this.scheduledDate,
    status: status ?? this.status,
    notes: notes ?? this.notes,
    doctorId: doctorId ?? this.doctorId,
    pregnancyWeek: pregnancyWeek ?? this.pregnancyWeek,
    createdAt: createdAt ?? this.createdAt,
  );
}

// ─── Pregnancy Medicine ──────────────────────────────────────────────────────

class PregnancyMedicine {
  final String id;
  final String patientId;
  final String name;
  final String dosage;
  final String frequency;
  final String type; // 'medicine', 'vitamin', 'supplement', 'injection'
  final DateTime startDate;
  final DateTime? endDate;
  final String? reminderTime;
  final String? instructions;
  final String? prescribedBy;
  final bool isActive;
  final DateTime createdAt;

  const PregnancyMedicine({
    required this.id,
    required this.patientId,
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.type,
    required this.startDate,
    this.endDate,
    this.reminderTime,
    this.instructions,
    this.prescribedBy,
    required this.isActive,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'patientId': patientId,
    'name': name,
    'dosage': dosage,
    'frequency': frequency,
    'type': type,
    'startDate': Timestamp.fromDate(startDate),
    'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
    'reminderTime': reminderTime,
    'instructions': instructions,
    'prescribedBy': prescribedBy,
    'isActive': isActive,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory PregnancyMedicine.fromMap(String id, Map<String, dynamic> d) =>
      PregnancyMedicine(
        id: id,
        patientId: d['patientId'] as String? ?? '',
        name: d['name'] as String? ?? '',
        dosage: d['dosage'] as String? ?? '',
        frequency: d['frequency'] as String? ?? '',
        type: d['type'] as String? ?? 'medicine',
        startDate: (d['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        endDate: (d['endDate'] as Timestamp?)?.toDate(),
        reminderTime: d['reminderTime'] as String?,
        instructions: d['instructions'] as String?,
        prescribedBy: d['prescribedBy'] as String?,
        isActive: d['isActive'] as bool? ?? true,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  PregnancyMedicine copyWith({
    String? id,
    String? patientId,
    String? name,
    String? dosage,
    String? frequency,
    String? type,
    DateTime? startDate,
    DateTime? endDate,
    String? reminderTime,
    String? instructions,
    String? prescribedBy,
    bool? isActive,
    DateTime? createdAt,
  }) => PregnancyMedicine(
    id: id ?? this.id,
    patientId: patientId ?? this.patientId,
    name: name ?? this.name,
    dosage: dosage ?? this.dosage,
    frequency: frequency ?? this.frequency,
    type: type ?? this.type,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    reminderTime: reminderTime ?? this.reminderTime,
    instructions: instructions ?? this.instructions,
    prescribedBy: prescribedBy ?? this.prescribedBy,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
  );
}

// ─── Pregnancy Alert ─────────────────────────────────────────────────────────

class PregnancyAlert {
  final String id;
  final String patientId;
  final String patientName;
  final String type; // 'emergency', 'high_bp', 'pain', 'bleeding', 'other'
  final String severity; // 'critical', 'high', 'medium', 'low'
  final String message;
  final bool isResolved;
  final String? resolvedBy;
  final DateTime reportedAt;
  final DateTime? resolvedAt;

  const PregnancyAlert({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.type,
    required this.severity,
    required this.message,
    required this.isResolved,
    this.resolvedBy,
    required this.reportedAt,
    this.resolvedAt,
  });

  Map<String, dynamic> toMap() => {
    'patientId': patientId,
    'patientName': patientName,
    'type': type,
    'severity': severity,
    'message': message,
    'isResolved': isResolved,
    'resolvedBy': resolvedBy,
    'reportedAt': Timestamp.fromDate(reportedAt),
    'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
  };

  factory PregnancyAlert.fromMap(String id, Map<String, dynamic> d) =>
      PregnancyAlert(
        id: id,
        patientId: d['patientId'] as String? ?? '',
        patientName: d['patientName'] as String? ?? '',
        type: d['type'] as String? ?? 'other',
        severity: d['severity'] as String? ?? 'medium',
        message: d['message'] as String? ?? '',
        isResolved: d['isResolved'] as bool? ?? false,
        resolvedBy: d['resolvedBy'] as String?,
        reportedAt: (d['reportedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        resolvedAt: (d['resolvedAt'] as Timestamp?)?.toDate(),
      );

  PregnancyAlert copyWith({
    String? id,
    String? patientId,
    String? patientName,
    String? type,
    String? severity,
    String? message,
    bool? isResolved,
    String? resolvedBy,
    DateTime? reportedAt,
    DateTime? resolvedAt,
  }) => PregnancyAlert(
    id: id ?? this.id,
    patientId: patientId ?? this.patientId,
    patientName: patientName ?? this.patientName,
    type: type ?? this.type,
    severity: severity ?? this.severity,
    message: message ?? this.message,
    isResolved: isResolved ?? this.isResolved,
    resolvedBy: resolvedBy ?? this.resolvedBy,
    reportedAt: reportedAt ?? this.reportedAt,
    resolvedAt: resolvedAt ?? this.resolvedAt,
  );
}

// ─── Doctor Note ─────────────────────────────────────────────────────────────

class PregnancyDoctorNote {
  final String id;
  final String patientId;
  final String doctorId;
  final String doctorName;
  final String content;
  final String? recommendation;
  final int pregnancyWeek;
  final DateTime createdAt;

  const PregnancyDoctorNote({
    required this.id,
    required this.patientId,
    required this.doctorId,
    required this.doctorName,
    required this.content,
    this.recommendation,
    required this.pregnancyWeek,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'patientId': patientId,
    'doctorId': doctorId,
    'doctorName': doctorName,
    'content': content,
    'recommendation': recommendation,
    'pregnancyWeek': pregnancyWeek,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory PregnancyDoctorNote.fromMap(String id, Map<String, dynamic> d) =>
      PregnancyDoctorNote(
        id: id,
        patientId: d['patientId'] as String? ?? '',
        doctorId: d['doctorId'] as String? ?? '',
        doctorName: d['doctorName'] as String? ?? '',
        content: d['content'] as String? ?? '',
        recommendation: d['recommendation'] as String?,
        pregnancyWeek: d['pregnancyWeek'] as int? ?? 1,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  PregnancyDoctorNote copyWith({
    String? id,
    String? patientId,
    String? doctorId,
    String? doctorName,
    String? content,
    String? recommendation,
    int? pregnancyWeek,
    DateTime? createdAt,
  }) => PregnancyDoctorNote(
    id: id ?? this.id,
    patientId: patientId ?? this.patientId,
    doctorId: doctorId ?? this.doctorId,
    doctorName: doctorName ?? this.doctorName,
    content: content ?? this.content,
    recommendation: recommendation ?? this.recommendation,
    pregnancyWeek: pregnancyWeek ?? this.pregnancyWeek,
    createdAt: createdAt ?? this.createdAt,
  );
}
