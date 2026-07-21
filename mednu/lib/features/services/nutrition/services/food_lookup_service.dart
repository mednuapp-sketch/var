import 'package:dio/dio.dart';

class FoodNutrition {
  final String name;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;

  const FoodNutrition({
    required this.name,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
  });

  ({double calories, double protein, double carbs, double fat}) forGrams(double grams) {
    final f = grams / 100.0;
    return (
      calories: caloriesPer100g * f,
      protein: proteinPer100g * f,
      carbs: carbsPer100g * f,
      fat: fatPer100g * f,
    );
  }
}

class FoodLookupService {
  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  // Approximate grams per unit
  static const unitGrams = <String, double>{
    'g': 1.0,
    'ml': 1.0,
    'cup': 240.0,
    'tbsp': 15.0,
    'tsp': 5.0,
    'piece': 100.0,
    'bowl': 300.0,
    'plate': 400.0,
  };

  static Future<List<FoodNutrition>> search(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final resp = await _dio.get(
        'https://world.openfoodfacts.org/cgi/search.pl',
        queryParameters: {
          'search_terms': query,
          'json': 1,
          'page_size': 10,
          'fields': 'product_name,nutriments',
          'sort_by': 'unique_scans_n',
        },
      );
      final products = (resp.data['products'] as List?) ?? [];
      return products
          .map((p) {
            final name = (p['product_name'] as String?)?.trim() ?? '';
            if (name.isEmpty) return null;
            final n = p['nutriments'] as Map? ?? {};
            final cals = (n['energy-kcal_100g'] as num?)?.toDouble() ?? 0;
            if (cals <= 0) return null;
            return FoodNutrition(
              name: name,
              caloriesPer100g: cals,
              proteinPer100g: (n['proteins_100g'] as num?)?.toDouble() ?? 0,
              carbsPer100g: (n['carbohydrates_100g'] as num?)?.toDouble() ?? 0,
              fatPer100g: (n['fat_100g'] as num?)?.toDouble() ?? 0,
            );
          })
          .whereType<FoodNutrition>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
