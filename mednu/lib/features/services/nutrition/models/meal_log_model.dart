import 'package:cloud_firestore/cloud_firestore.dart';

class MealLogModel {
  final String id;
  final String userId;
  final String mealType; // breakfast | lunch | dinner | snack
  final String foodName;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final String notes;
  final String dateKey; // YYYY-MM-DD
  final DateTime loggedAt;

  const MealLogModel({
    required this.id,
    required this.userId,
    required this.mealType,
    required this.foodName,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.notes,
    required this.dateKey,
    required this.loggedAt,
  });

  factory MealLogModel.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return MealLogModel(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      mealType: d['mealType'] as String? ?? 'snack',
      foodName: d['foodName'] as String? ?? '',
      calories: (d['calories'] as num?)?.toDouble() ?? 0.0,
      protein: (d['protein'] as num?)?.toDouble() ?? 0.0,
      carbs: (d['carbs'] as num?)?.toDouble() ?? 0.0,
      fat: (d['fat'] as num?)?.toDouble() ?? 0.0,
      notes: d['notes'] as String? ?? '',
      dateKey: d['dateKey'] as String? ?? '',
      loggedAt: (d['loggedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'mealType': mealType,
        'foodName': foodName,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'notes': notes,
        'dateKey': dateKey,
        'loggedAt': FieldValue.serverTimestamp(),
      };

  static String mealTypeLabel(String type) {
    switch (type) {
      case 'breakfast': return 'Breakfast';
      case 'lunch': return 'Lunch';
      case 'dinner': return 'Dinner';
      default: return 'Snack';
    }
  }
}
