import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DietPlanModel {
  final String id;
  final String title;
  final String description;
  final String iconKey;
  final String colorKey;
  final String price;
  final int order;
  final bool isActive;

  const DietPlanModel({
    required this.id,
    required this.title,
    required this.description,
    required this.iconKey,
    required this.colorKey,
    required this.price,
    required this.order,
    required this.isActive,
  });

  factory DietPlanModel.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return DietPlanModel(
      id: doc.id,
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      iconKey: d['iconKey'] as String? ?? 'restaurant',
      colorKey: d['colorKey'] as String? ?? 'green',
      price: d['price'] as String? ?? '',
      order: (d['order'] as num?)?.toInt() ?? 99,
      isActive: d['isActive'] as bool? ?? true,
    );
  }

  static IconData iconFromKey(String key) {
    const map = {
      'monitor_weight': Icons.monitor_weight_rounded,
      'bloodtype': Icons.bloodtype_rounded,
      'favorite': Icons.favorite_rounded,
      'pregnant_woman': Icons.pregnant_woman_rounded,
      'fitness_center': Icons.fitness_center_rounded,
      'spa': Icons.spa_rounded,
      'restaurant': Icons.restaurant_rounded,
      'eco': Icons.eco_rounded,
      'local_hospital': Icons.local_hospital_rounded,
    };
    return map[key] ?? Icons.restaurant_rounded;
  }

  static Color colorFromKey(String key) {
    const map = {
      'green': Color(0xFF2E7D32),
      'red': Color(0xFFB71C1C),
      'pink': Color(0xFF522546),
      'purple': Color(0xFF633058),
      'blue': Color(0xFF1565C0),
      'teal': Color(0xFFF9943B),
      'orange': Color(0xFFE65100),
      'brown': Color(0xFF4E342E),
    };
    return map[key] ?? const Color(0xFF2E7D32);
  }
}
