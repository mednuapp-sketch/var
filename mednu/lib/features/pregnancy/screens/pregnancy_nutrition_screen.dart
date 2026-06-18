import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../data/pregnancy_week_data.dart';
import '../providers/pregnancy_provider.dart';

class PregnancyNutritionScreen extends ConsumerWidget {
  const PregnancyNutritionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(pregnancyProvider).profile;
    final week = profile?.currentWeek ?? 1;
    final data = getWeekData(week);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nutrition Guide',
                style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w700, fontSize: 16)),
            Text('Week $week personalized',
                style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heroCard(week, data),
            const SizedBox(height: 16),
            _dailyGoalsCard(week),
            const SizedBox(height: 16),
            _foodsSection(data),
            const SizedBox(height: 16),
            _nutrientsSection(data),
            const SizedBox(height: 16),
            _tipsSection(data),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _heroCard(int week, WeeklyPregnancyData data) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('🥗', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Week Nutrition Plan',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text('Week $week', style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha:0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(data.nutritionTip,
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5)),
        ),
      ],
    ),
  );

  Widget _dailyGoalsCard(int week) {
    final trimester = week <= 13 ? 1 : week <= 26 ? 2 : 3;
    final extraCals = trimester == 1 ? 0 : trimester == 2 ? 300 : 450;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.track_changes_rounded, color: Color(0xFF66BB6A), size: 18),
              SizedBox(width: 8),
              Text('Daily Nutrition Goals',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _goalItem('💧', 'Water', '8-10 glasses'),
              _goalItem('🥩', 'Protein', '71g/day'),
              _goalItem('🦴', 'Calcium', '1000mg/day'),
              _goalItem('🔥', 'Extra Cal', '+${extraCals > 0 ? extraCals : 0}kcal'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _goalItem('💊', 'Iron', '27mg/day'),
              _goalItem('🫀', 'Folate', '600mcg/day'),
              _goalItem('☀️', 'Vit D', '600IU/day'),
              _goalItem('🐟', 'Omega-3', '200mg DHA'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _goalItem(String emoji, String label, String value) => Expanded(
    child: Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textHint)),
      ],
    ),
  );

  Widget _foodsSection(WeeklyPregnancyData data) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeader(Icons.check_circle_rounded, 'Recommended Foods', const Color(0xFF66BB6A)),
      const SizedBox(height: 10),
      _foodGrid(data.foodsToEat, const Color(0xFF66BB6A), const Color(0xFFF1F8E9)),
      const SizedBox(height: 16),
      _sectionHeader(Icons.cancel_rounded, 'Foods to Avoid', const Color(0xFFEF5350)),
      const SizedBox(height: 10),
      _foodGrid(data.foodsToAvoid, const Color(0xFFEF5350), const Color(0xFFFFEBEE)),
    ],
  );

  Widget _foodGrid(List<String> foods, Color color, Color bg) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: foods.map((f) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha:0.3)),
      ),
      child: Text(f, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
    )).toList(),
  );

  Widget _nutrientsSection(WeeklyPregnancyData data) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 8)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(Icons.science_rounded, 'Key Nutrients This Week', const Color(0xFF7B1FA2)),
        const SizedBox(height: 12),
        ...data.keyNutrients.map((n) => _nutrientTile(n)),
      ],
    ),
  );

  Widget _nutrientTile(String nutrient) {
    const nutrients = {
      'Folic Acid': ('🧬', 'Prevents neural tube defects', const Color(0xFF7B1FA2)),
      'Iron': ('💪', 'Supports increased blood volume', const Color(0xFFEF5350)),
      'Calcium': ('🦴', 'Builds strong bones and teeth', const Color(0xFF42A5F5)),
      'Vitamin D': ('☀️', 'Helps absorb calcium', const Color(0xFFFFA726)),
      'Omega-3': ('🐟', 'Supports brain development', const Color(0xFF26C6DA)),
      'Protein': ('🥩', 'Builds baby\'s muscles and organs', const Color(0xFF66BB6A)),
      'Vitamin B6': ('🌿', 'Reduces morning sickness', const Color(0xFF66BB6A)),
      'Magnesium': ('⚡', 'Reduces leg cramps', const Color(0xFF26C6DA)),
      'Fiber': ('🥦', 'Prevents constipation', const Color(0xFF8BC34A)),
      'Vitamin C': ('🍊', 'Immune support and iron absorption', const Color(0xFFFFA726)),
      'Vitamin K': ('🥬', 'Blood clotting for delivery', const Color(0xFF66BB6A)),
      'Hydration': ('💧', 'Essential for all body functions', const Color(0xFF42A5F5)),
      'Electrolytes': ('⚡', 'Energy and hydration balance', const Color(0xFFFFA726)),
      'Ginger': ('🫚', 'Natural nausea relief', const Color(0xFF8D6E63)),
    };
    final info = nutrients[nutrient] ?? ('💊', 'Important for your pregnancy', const Color(0xFF7B1FA2));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: info.$3.withValues(alpha:0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(info.$1, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nutrient, style: TextStyle(fontWeight: FontWeight.w600, color: info.$3, fontSize: 13)),
                Text(info.$2, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipsSection(WeeklyPregnancyData data) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFFCE4EC), Color(0xFFF3E5F5)],
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text('💡', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('This Week\'s Tip',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF880E4F))),
          ],
        ),
        const SizedBox(height: 10),
        Text(data.weeklyTip, style: const TextStyle(fontSize: 13, height: 1.6, color: Color(0xFF4A148C))),
      ],
    ),
  );

  Widget _sectionHeader(IconData icon, String title, Color color) => Row(
    children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: color)),
    ],
  );
}
