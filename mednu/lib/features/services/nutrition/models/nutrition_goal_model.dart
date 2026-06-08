import 'package:cloud_firestore/cloud_firestore.dart';

class NutritionGoalModel {
  final String id;
  final String userId;
  final String goalType; // weight_loss | weight_gain | diabetes | pregnancy | fitness | pcos | heart_health
  final double targetWeight;
  final double currentWeight;
  final double targetCalories;
  final double targetProtein;
  final double targetCarbs;
  final double targetFat;
  final double targetWaterLiters;
  final String notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NutritionGoalModel({
    required this.id,
    required this.userId,
    required this.goalType,
    required this.targetWeight,
    required this.currentWeight,
    required this.targetCalories,
    required this.targetProtein,
    required this.targetCarbs,
    required this.targetFat,
    required this.targetWaterLiters,
    required this.notes,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NutritionGoalModel.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return NutritionGoalModel(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      goalType: d['goalType'] as String? ?? 'weight_loss',
      targetWeight: (d['targetWeight'] as num?)?.toDouble() ?? 0.0,
      currentWeight: (d['currentWeight'] as num?)?.toDouble() ?? 0.0,
      targetCalories: (d['targetCalories'] as num?)?.toDouble() ?? 2000.0,
      targetProtein: (d['targetProtein'] as num?)?.toDouble() ?? 50.0,
      targetCarbs: (d['targetCarbs'] as num?)?.toDouble() ?? 250.0,
      targetFat: (d['targetFat'] as num?)?.toDouble() ?? 65.0,
      targetWaterLiters: (d['targetWaterLiters'] as num?)?.toDouble() ?? 2.5,
      notes: d['notes'] as String? ?? '',
      isActive: d['isActive'] as bool? ?? true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'goalType': goalType,
        'targetWeight': targetWeight,
        'currentWeight': currentWeight,
        'targetCalories': targetCalories,
        'targetProtein': targetProtein,
        'targetCarbs': targetCarbs,
        'targetFat': targetFat,
        'targetWaterLiters': targetWaterLiters,
        'notes': notes,
        'isActive': isActive,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static String goalLabel(String type) {
    switch (type) {
      case 'weight_loss': return 'Weight Loss';
      case 'weight_gain': return 'Weight Gain';
      case 'diabetes': return 'Diabetes Diet';
      case 'pregnancy': return 'Pregnancy Nutrition';
      case 'fitness': return 'Sports & Fitness';
      case 'pcos': return 'PCOS Diet';
      case 'heart_health': return 'Heart Healthy';
      default: return 'General Wellness';
    }
  }

  double get progressPercent {
    if (currentWeight == 0 || targetWeight == 0) return 0.0;
    if (goalType == 'weight_loss') {
      if (currentWeight <= targetWeight) return 1.0;
      // Progress = how close current is to target (1.0 = reached goal)
      // This requires knowing starting weight — approximate via calories consumed
      return 0.0;
    }
    if (goalType == 'weight_gain') {
      if (currentWeight >= targetWeight) return 1.0;
      return 0.0;
    }
    return 0.0;
  }
}
