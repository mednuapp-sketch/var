import 'package:cloud_firestore/cloud_firestore.dart';

class BmiLogModel {
  final String id;
  final String userId;
  final double heightCm;
  final double weightKg;
  final int age;
  final String gender;
  final double bmi;
  final String category;
  final String dateKey; // YYYY-MM-DD
  final DateTime loggedAt;

  const BmiLogModel({
    required this.id,
    required this.userId,
    required this.heightCm,
    required this.weightKg,
    required this.age,
    required this.gender,
    required this.bmi,
    required this.category,
    required this.dateKey,
    required this.loggedAt,
  });

  factory BmiLogModel.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return BmiLogModel(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      heightCm: (d['heightCm'] as num?)?.toDouble() ?? 0.0,
      weightKg: (d['weightKg'] as num?)?.toDouble() ?? 0.0,
      age: (d['age'] as num?)?.toInt() ?? 0,
      gender: d['gender'] as String? ?? 'female',
      bmi: (d['bmi'] as num?)?.toDouble() ?? 0.0,
      category: d['category'] as String? ?? '',
      dateKey: d['dateKey'] as String? ?? '',
      loggedAt: (d['loggedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'age': age,
        'gender': gender,
        'bmi': bmi,
        'category': category,
        'dateKey': dateKey,
        'loggedAt': FieldValue.serverTimestamp(),
      };
}
