import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/nutritionist_model.dart';
import '../models/nutrition_appointment_model.dart';
import '../models/meal_log_model.dart';
import '../models/nutrition_goal_model.dart';
import '../models/diet_plan_model.dart';
import '../models/bmi_log_model.dart';

class NutritionService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String? get _uid => _auth.currentUser?.uid;

  // ── Nutritionists ──────────────────────────────────────

  static Stream<List<NutritionistModel>> nutritionistsStream({String? specialty}) {
    // All where() clauses must come before orderBy() to avoid failed-precondition errors
    Query query = _db.collection('nutritionists').where('isAvailable', isEqualTo: true);
    if (specialty != null && specialty.isNotEmpty) {
      query = query.where('specialization', isEqualTo: specialty);
    }
    query = query.orderBy('rating', descending: true);
    return query.snapshots().map(
          (s) => s.docs.map((d) => NutritionistModel.fromFirestore(d)).toList(),
        );
  }

  static Stream<NutritionistModel?> nutritionistStream(String id) {
    return _db
        .collection('nutritionists')
        .doc(id)
        .snapshots()
        .map((d) => d.exists ? NutritionistModel.fromFirestore(d) : null);
  }

  // Returns booked slot strings for a nutritionist on a given date
  static Stream<List<String>> bookedSlotsStream(String nutritionistId, String date) {
    return _db
        .collection('nutrition_appointments')
        .where('nutritionistId', isEqualTo: nutritionistId)
        .where('date', isEqualTo: date)
        .where('status', whereIn: ['pending', 'confirmed'])
        .snapshots()
        .map((s) => s.docs
            .map((d) => (d.data()['timeSlot'] as String?) ?? '')
            .where((t) => t.isNotEmpty)
            .toList());
  }

  // ── Appointments ───────────────────────────────────────

  static Future<String> bookAppointment({
    required String nutritionistId,
    required String nutritionistName,
    required String nutritionistSpecialization,
    required String consultationType,
    required String date,
    required String timeSlot,
    required String notes,
    required double fee,
    required String healthGoal,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final ref = await _db.collection('nutrition_appointments').add({
      'userId': uid,
      'userName': user.displayName ?? 'Patient',
      'userPhone': user.phoneNumber ?? '',
      'nutritionistId': nutritionistId,
      'nutritionistName': nutritionistName,
      'nutritionistSpecialization': nutritionistSpecialization,
      'consultationType': consultationType,
      'date': date,
      'timeSlot': timeSlot,
      'status': 'pending',
      'notes': notes,
      'fee': fee,
      'healthGoal': healthGoal,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Stream<List<NutritionAppointmentModel>> userAppointmentsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('nutrition_appointments')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => NutritionAppointmentModel.fromFirestore(d)).toList());
  }

  static Future<void> cancelAppointment(String appointmentId) async {
    await _db.collection('nutrition_appointments').doc(appointmentId).update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Meal Tracking ──────────────────────────────────────

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static Stream<List<MealLogModel>> mealLogsStream({String? dateKey}) {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    final key = dateKey ?? _todayKey();
    return _db
        .collection('meal_tracking')
        .where('userId', isEqualTo: uid)
        .where('dateKey', isEqualTo: key)
        .orderBy('loggedAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map((d) => MealLogModel.fromFirestore(d)).toList());
  }

  static Future<void> logMeal({
    required String mealType,
    required String foodName,
    required double calories,
    double protein = 0,
    double carbs = 0,
    double fat = 0,
    String notes = '',
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    await _db.collection('meal_tracking').add({
      'userId': uid,
      'mealType': mealType,
      'foodName': foodName,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'notes': notes,
      'dateKey': _todayKey(),
      'loggedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteMealLog(String logId) async {
    await _db.collection('meal_tracking').doc(logId).delete();
  }

  // ── Nutrition Goals ────────────────────────────────────

  static Stream<NutritionGoalModel?> activeGoalStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(null);
    return _db
        .collection('nutrition_goals')
        .where('userId', isEqualTo: uid)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((s) =>
            s.docs.isEmpty ? null : NutritionGoalModel.fromFirestore(s.docs.first));
  }

  static Future<void> saveGoal(NutritionGoalModel goal) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    // Deactivate existing goals
    final existing = await _db
        .collection('nutrition_goals')
        .where('userId', isEqualTo: uid)
        .where('isActive', isEqualTo: true)
        .get();
    final batch = _db.batch();
    for (final doc in existing.docs) {
      batch.update(doc.reference, {'isActive': false});
    }
    final newRef = _db.collection('nutrition_goals').doc();
    // Always inject the authenticated user ID into the saved map
    final data = goal.toMap()..['userId'] = uid;
    batch.set(newRef, data);
    await batch.commit();
  }

  static Future<void> updateGoalWeight(double newWeight) async {
    final uid = _uid;
    if (uid == null) return;
    final existing = await _db
        .collection('nutrition_goals')
        .where('userId', isEqualTo: uid)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.update({
        'currentWeight': newWeight,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ── Water Tracking ─────────────────────────────────────

  static Stream<int> waterTrackingStream({String? dateKey}) {
    final uid = _uid;
    if (uid == null) return Stream.value(0);
    final key = dateKey ?? _todayKey();
    return _db
        .collection('water_tracking')
        .where('userId', isEqualTo: uid)
        .where('dateKey', isEqualTo: key)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isEmpty
            ? 0
            : (s.docs.first.data()['glasses'] as num?)?.toInt() ?? 0);
  }

  static Future<void> updateWaterGlasses(int glasses, {String? dateKey}) async {
    final uid = _uid;
    if (uid == null) return;
    final key = dateKey ?? _todayKey();
    final existing = await _db
        .collection('water_tracking')
        .where('userId', isEqualTo: uid)
        .where('dateKey', isEqualTo: key)
        .limit(1)
        .get();
    if (existing.docs.isEmpty) {
      await _db.collection('water_tracking').add({
        'userId': uid,
        'dateKey': key,
        'glasses': glasses,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await existing.docs.first.reference.update({
        'glasses': glasses,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ── BMI Tracking ────────────────────────────────────────

  static Stream<List<BmiLogModel>> bmiLogsStream({int limit = 60}) {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('bmi_logs')
        .where('userId', isEqualTo: uid)
        .orderBy('loggedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => BmiLogModel.fromFirestore(d)).toList());
  }

  static Future<void> saveBmiLog({
    required double heightCm,
    required double weightKg,
    required int age,
    required String gender,
    required double bmi,
    required String category,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final key = _todayKey();
    final data = {
      'userId': uid,
      'heightCm': heightCm,
      'weightKg': weightKg,
      'age': age,
      'gender': gender,
      'bmi': bmi,
      'category': category,
      'dateKey': key,
      'loggedAt': FieldValue.serverTimestamp(),
    };
    // Upsert by day — one BMI reading represents that day's measurement
    final existing = await _db
        .collection('bmi_logs')
        .where('userId', isEqualTo: uid)
        .where('dateKey', isEqualTo: key)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.set(data);
    } else {
      await _db.collection('bmi_logs').add(data);
    }
  }

  static Future<void> deleteBmiLog(String logId) async {
    await _db.collection('bmi_logs').doc(logId).delete();
  }

  // ── Diet Plans (admin-managed) ────────────────────────

  static Stream<List<DietPlanModel>> dietPlansStream() {
    return _db
        .collection('diet_plans')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((s) {
      final list = s.docs.map((d) => DietPlanModel.fromFirestore(d)).toList();
      list.sort((a, b) => a.order.compareTo(b.order));
      return list;
    });
  }

  // ── Nutrition Analytics (for admin sync) ───────────────

  static Future<Map<String, dynamic>> getDailyAnalytics({String? dateKey}) async {
    final uid = _uid;
    if (uid == null) return {};
    final key = dateKey ?? _todayKey();
    final meals = await _db
        .collection('meal_tracking')
        .where('userId', isEqualTo: uid)
        .where('dateKey', isEqualTo: key)
        .get();
    double calories = 0, protein = 0, carbs = 0, fat = 0;
    for (final doc in meals.docs) {
      final d = doc.data();
      calories += (d['calories'] as num?)?.toDouble() ?? 0;
      protein += (d['protein'] as num?)?.toDouble() ?? 0;
      carbs += (d['carbs'] as num?)?.toDouble() ?? 0;
      fat += (d['fat'] as num?)?.toDouble() ?? 0;
    }
    return {
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'mealCount': meals.docs.length,
      'dateKey': key,
    };
  }
}
