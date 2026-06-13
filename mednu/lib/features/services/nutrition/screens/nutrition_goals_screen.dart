import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../providers/nutrition_provider.dart';
import '../models/nutrition_goal_model.dart';
import '../services/nutrition_service.dart';

class NutritionGoalsScreen extends ConsumerStatefulWidget {
  const NutritionGoalsScreen({super.key});

  @override
  ConsumerState<NutritionGoalsScreen> createState() => _NutritionGoalsScreenState();
}

class _NutritionGoalsScreenState extends ConsumerState<NutritionGoalsScreen> {
  String _selectedGoal = 'weight_loss';
  final _currentWeightCtrl = TextEditingController();
  final _targetWeightCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isLoading = false;

  static const _goalTypes = [
    'weight_loss', 'weight_gain', 'diabetes', 'pregnancy', 'fitness', 'pcos', 'heart_health',
  ];

  static const _presets = <String, Map<String, double>>{
    'weight_loss':   {'calories': 1500, 'protein': 80, 'carbs': 150, 'fat': 45, 'water': 2.5},
    'weight_gain':   {'calories': 2800, 'protein': 130, 'carbs': 350, 'fat': 80, 'water': 3.0},
    'diabetes':      {'calories': 1800, 'protein': 80, 'carbs': 180, 'fat': 60, 'water': 2.5},
    'pregnancy':     {'calories': 2200, 'protein': 100, 'carbs': 280, 'fat': 70, 'water': 3.0},
    'fitness':       {'calories': 2500, 'protein': 150, 'carbs': 280, 'fat': 70, 'water': 3.5},
    'pcos':          {'calories': 1700, 'protein': 85, 'carbs': 170, 'fat': 55, 'water': 2.5},
    'heart_health':  {'calories': 1900, 'protein': 75, 'carbs': 230, 'fat': 50, 'water': 2.5},
  };

  static const _icons = <String, IconData>{
    'weight_loss': Icons.monitor_weight_rounded,
    'weight_gain': Icons.fitness_center_rounded,
    'diabetes': Icons.bloodtype_rounded,
    'pregnancy': Icons.pregnant_woman_rounded,
    'fitness': Icons.sports_gymnastics_rounded,
    'pcos': Icons.spa_rounded,
    'heart_health': Icons.favorite_rounded,
  };

  static const _colors = <String, Color>{
    'weight_loss': Color(0xFF2E7D32),
    'weight_gain': Color(0xFF1565C0),
    'diabetes': Color(0xFFB71C1C),
    'pregnancy': Color(0xFF7B1FA2),
    'fitness': Color(0xFF0097A7),
    'pcos': Color(0xFF00897B),
    'heart_health': Color(0xFFC2185B),
  };

  Future<void> _saveGoal() async {
    final currentWeight = double.tryParse(_currentWeightCtrl.text) ?? 0;
    final targetWeight = double.tryParse(_targetWeightCtrl.text) ?? 0;
    final preset = _presets[_selectedGoal]!;

    setState(() => _isLoading = true);
    try {
      final goal = NutritionGoalModel(
        id: '',
        userId: '',
        goalType: _selectedGoal,
        currentWeight: currentWeight,
        targetWeight: targetWeight,
        targetCalories: preset['calories']!,
        targetProtein: preset['protein']!,
        targetCarbs: preset['carbs']!,
        targetFat: preset['fat']!,
        targetWaterLiters: preset['water']!,
        notes: _notesCtrl.text.trim(),
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await NutritionService.saveGoal(goal);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Goal saved successfully!'), backgroundColor: Color(0xFF2E7D32)),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save goal: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _currentWeightCtrl.dispose();
    _targetWeightCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existingGoal = ref.watch(activeNutritionGoalProvider);
    final preset = _presets[_selectedGoal]!;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
        title: const Text('Health Goals', style: AppTextStyles.h3),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            existingGoal.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (g) => g != null ? _ActiveGoalBanner(goal: g) : const SizedBox.shrink(),
            ),
            Text('Select Your Goal', style: AppTextStyles.h4),
            const SizedBox(height: 12),
            ..._goalTypes.map((type) => _GoalOptionTile(
              type: type,
              label: NutritionGoalModel.goalLabel(type),
              icon: _icons[type]!,
              color: _colors[type]!,
              isSelected: _selectedGoal == type,
              onTap: () => setState(() => _selectedGoal = type),
            )),
            const SizedBox(height: 20),
            Text('Current & Target Weight', style: AppTextStyles.h4),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _WeightField(ctrl: _currentWeightCtrl, label: 'Current Weight (kg)', hint: '70')),
                const SizedBox(width: 12),
                Expanded(child: _WeightField(ctrl: _targetWeightCtrl, label: 'Target Weight (kg)', hint: '60')),
              ],
            ),
            const SizedBox(height: 20),
            _MacroPreviewCard(preset: preset, goalLabel: NutritionGoalModel.goalLabel(_selectedGoal), color: _colors[_selectedGoal]!),
            const SizedBox(height: 16),
            _NotesField(ctrl: _notesCtrl),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveGoal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _colors[_selectedGoal],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Set This Goal', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _ActiveGoalBanner extends StatelessWidget {
  final NutritionGoalModel goal;
  const _ActiveGoalBanner({required this.goal});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Active Goal', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
                Text(NutritionGoalModel.goalLabel(goal.goalType), style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              ],
            ),
          ),
          const Text('Update Below', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: Colors.white70)),
        ],
      ),
    );
  }
}

class _GoalOptionTile extends StatelessWidget {
  final String type;
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _GoalOptionTile({required this.type, required this.label, required this.icon, required this.color, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha:0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? color : AppColors.border, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? color : color.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: isSelected ? Colors.white : color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: AppTextStyles.labelLarge.copyWith(color: isSelected ? color : AppColors.textPrimary)),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeightField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String hint;
  const _WeightField({required this.ctrl, required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2E7D32))),
          ),
        ),
      ],
    );
  }
}

class _MacroPreviewCard extends StatelessWidget {
  final Map<String, double> preset;
  final String goalLabel;
  final Color color;
  const _MacroPreviewCard({required this.preset, required this.goalLabel, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha:0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: color, size: 18),
              const SizedBox(width: 8),
              Text('Recommended for $goalLabel', style: AppTextStyles.labelMedium.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _PreviewStat(label: 'Calories', value: '${preset['calories']!.toInt()}', unit: 'kcal', color: const Color(0xFFE65100)),
              _PreviewStat(label: 'Protein', value: '${preset['protein']!.toInt()}', unit: 'g', color: const Color(0xFF1565C0)),
              _PreviewStat(label: 'Carbs', value: '${preset['carbs']!.toInt()}', unit: 'g', color: const Color(0xFF2E7D32)),
              _PreviewStat(label: 'Fat', value: '${preset['fat']!.toInt()}', unit: 'g', color: const Color(0xFF7B1FA2)),
              _PreviewStat(label: 'Water', value: '${preset['water']!.toStringAsFixed(1)}', unit: 'L', color: const Color(0xFF1565C0)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _PreviewStat({required this.label, required this.value, required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RichText(
          text: TextSpan(
            text: value,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w800, color: color),
            children: [TextSpan(text: unit, style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: color))],
          ),
        ),
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
      ],
    );
  }
}

class _NotesField extends StatelessWidget {
  final TextEditingController ctrl;
  const _NotesField({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Additional Notes (optional)', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: 3,
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Any specific dietary needs, allergies, health conditions...',
            hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF2E7D32))),
          ),
        ),
      ],
    );
  }
}
