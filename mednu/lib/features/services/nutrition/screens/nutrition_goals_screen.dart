import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mednu/core/constants/app_colors.dart';
import 'package:mednu/core/constants/app_text_styles.dart';
import 'package:mednu/core/widgets/ux_widgets.dart';
import '../models/nutrition_goal_model.dart';
import '../providers/nutrition_provider.dart';
import '../services/nutrition_service.dart';

// ─── Local state model ────────────────────────────────────────────────────────

class _GoalFormState {
  final String goalType;
  final int calorie;
  final int carbPct;
  final int proteinPct;
  final int fatPct;
  final int waterCups;
  final String activityLevel;
  final String weightGoal;
  final double currentWeight;
  final double targetWeight;
  final String notes;

  const _GoalFormState({
    this.goalType = 'weight_loss',
    this.calorie = 1800,
    this.carbPct = 50,
    this.proteinPct = 25,
    this.fatPct = 25,
    this.waterCups = 8,
    this.activityLevel = 'moderate',
    this.weightGoal = 'lose',
    this.currentWeight = 0,
    this.targetWeight = 0,
    this.notes = '',
  });

  _GoalFormState copyWith({
    String? goalType, int? calorie, int? carbPct, int? proteinPct,
    int? fatPct, int? waterCups, String? activityLevel, String? weightGoal,
    double? currentWeight, double? targetWeight, String? notes,
  }) => _GoalFormState(
    goalType: goalType ?? this.goalType,
    calorie: calorie ?? this.calorie,
    carbPct: carbPct ?? this.carbPct,
    proteinPct: proteinPct ?? this.proteinPct,
    fatPct: fatPct ?? this.fatPct,
    waterCups: waterCups ?? this.waterCups,
    activityLevel: activityLevel ?? this.activityLevel,
    weightGoal: weightGoal ?? this.weightGoal,
    currentWeight: currentWeight ?? this.currentWeight,
    targetWeight: targetWeight ?? this.targetWeight,
    notes: notes ?? this.notes,
  );

  _GoalFormState adjustMacros({int? carb, int? protein, int? fat}) {
    if (carb != null) {
      final remainder = 100 - carb;
      final total = proteinPct + fatPct;
      if (total == 0) return copyWith(carbPct: carb, proteinPct: remainder ~/ 2, fatPct: remainder - remainder ~/ 2);
      final newP = (remainder * proteinPct / total).round();
      return copyWith(carbPct: carb, proteinPct: newP, fatPct: remainder - newP);
    }
    if (protein != null) {
      final remainder = 100 - protein;
      final total = carbPct + fatPct;
      if (total == 0) return copyWith(proteinPct: protein, carbPct: remainder ~/ 2, fatPct: remainder - remainder ~/ 2);
      final newC = (remainder * carbPct / total).round();
      return copyWith(proteinPct: protein, carbPct: newC, fatPct: remainder - newC);
    }
    if (fat != null) {
      final remainder = 100 - fat;
      final total = carbPct + proteinPct;
      if (total == 0) return copyWith(fatPct: fat, carbPct: remainder ~/ 2, proteinPct: remainder - remainder ~/ 2);
      final newC = (remainder * carbPct / total).round();
      return copyWith(fatPct: fat, carbPct: newC, proteinPct: remainder - newC);
    }
    return this;
  }

  int get carbsGrams   => (calorie * carbPct / 100 / 4).round();
  int get proteinGrams => (calorie * proteinPct / 100 / 4).round();
  int get fatGrams     => (calorie * fatPct / 100 / 9).round();
  double get waterLiters => waterCups * 0.237;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const _kGoalTypes = [
  ('weight_loss',  'Weight Loss',         Icons.monitor_weight_rounded,    AppColors.success),
  ('weight_gain',  'Weight Gain',          Icons.fitness_center_rounded,    AppColors.info),
  ('diabetes',     'Diabetes Diet',        Icons.bloodtype_rounded,          Color(0xFFB71C1C)),
  ('pregnancy',    'Pregnancy Nutrition',  Icons.pregnant_woman_rounded,     AppColors.secondary),
  ('fitness',      'Sports & Fitness',     Icons.sports_gymnastics_rounded,  AppColors.accent),
  ('pcos',         'PCOS Diet',            Icons.spa_rounded,                AppColors.accent),
  ('heart_health', 'Healthy Heart',        Icons.favorite_rounded,           AppColors.primary),
];

const _kCaloriePresets = [1500, 1800, 2000, 2500];

const _kActivityLevels = [
  ('sedentary', 'Sedentary', '🛋️', 'Little or no exercise'),
  ('light',     'Light',     '🚶', '1–3 days/week'),
  ('moderate',  'Moderate',  '🏃', '3–5 days/week'),
  ('active',    'Active',    '⚡', '6–7 days/week'),
];

const _kWeightGoals = [
  ('lose',     'Lose',     Icons.trending_down_rounded, AppColors.success),
  ('maintain', 'Maintain', Icons.trending_flat_rounded, AppColors.accent),
  ('gain',     'Gain',     Icons.trending_up_rounded,   AppColors.info),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class NutritionGoalsScreen extends ConsumerStatefulWidget {
  const NutritionGoalsScreen({super.key});

  @override
  ConsumerState<NutritionGoalsScreen> createState() => _NutritionGoalsScreenState();
}

class _NutritionGoalsScreenState extends ConsumerState<NutritionGoalsScreen>
    with SingleTickerProviderStateMixin {
  var _form = const _GoalFormState();
  final _currentWeightCtrl = TextEditingController();
  final _targetWeightCtrl  = TextEditingController();
  final _notesCtrl         = TextEditingController();
  bool _isSaving = false;
  late AnimationController _saveAnim;
  late Animation<double> _saveScale;

  @override
  void initState() {
    super.initState();
    _saveAnim  = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _saveScale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _saveAnim, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _currentWeightCtrl.dispose();
    _targetWeightCtrl.dispose();
    _notesCtrl.dispose();
    _saveAnim.dispose();
    super.dispose();
  }

  Color get _primaryColor {
    for (final t in _kGoalTypes) {
      if (t.$1 == _form.goalType) return t.$4;
    }
    return AppColors.primary;
  }

  Future<void> _save() async {
    HapticFeedback.mediumImpact();
    await _saveAnim.forward();
    await _saveAnim.reverse();
    setState(() => _isSaving = true);
    try {
      final goal = NutritionGoalModel(
        id: '',
        userId: '',
        goalType: _form.goalType,
        currentWeight: double.tryParse(_currentWeightCtrl.text) ?? 0,
        targetWeight: double.tryParse(_targetWeightCtrl.text) ?? 0,
        targetCalories: _form.calorie.toDouble(),
        targetProtein: _form.proteinGrams.toDouble(),
        targetCarbs: _form.carbsGrams.toDouble(),
        targetFat: _form.fatGrams.toDouble(),
        targetWaterLiters: _form.waterLiters,
        notes: _notesCtrl.text.trim(),
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await NutritionService.saveGoal(goal);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text('Goals saved!', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          ]),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e', style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingGoal = ref.watch(activeNutritionGoalProvider);
    final size         = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Nutrition Goals', style: AppTextStyles.h3),
        centerTitle: true,
        backgroundColor: context.appSurface,
        foregroundColor: context.appTextPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, math.max(MediaQuery.of(context).padding.bottom + 16, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            existingGoal.when(
              loading: () => AppShimmer(child: SkeletonBox(width: size.width, height: 76, radius: 16)),
              error:   (_, __) => const SizedBox.shrink(),
              data:    (g) => g != null ? _ActiveGoalBanner(goal: g) : const SizedBox.shrink(),
            ),

            _SectionHeader(icon: Icons.flag_rounded, title: 'What is your goal?', color: _primaryColor),
            const SizedBox(height: 12),
            _GoalTypeSelector(
              selected: _form.goalType,
              onSelect: (t) => setState(() => _form = _form.copyWith(goalType: t)),
            ),
            const SizedBox(height: 24),

            const _SectionHeader(icon: Icons.local_fire_department_rounded, title: 'Daily Calorie Goal', color: Color(0xFFE65100)),
            const SizedBox(height: 12),
            _CalorieSection(
              calorie: _form.calorie,
              onCalorieChanged: (v) => setState(() => _form = _form.copyWith(calorie: v)),
            ),
            const SizedBox(height: 24),

            const _SectionHeader(icon: Icons.pie_chart_rounded, title: 'Macro Ratios', color: AppColors.info),
            const SizedBox(height: 4),
            Text(
              'Percentages must total 100% — adjusting one will auto-balance others.',
              style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
            ),
            const SizedBox(height: 12),
            _MacroSlidersCard(
              carbPct: _form.carbPct,
              proteinPct: _form.proteinPct,
              fatPct: _form.fatPct,
              carbsGrams: _form.carbsGrams,
              proteinGrams: _form.proteinGrams,
              fatGrams: _form.fatGrams,
              calorie: _form.calorie,
              onCarbChanged:    (v) => setState(() => _form = _form.adjustMacros(carb: v)),
              onProteinChanged: (v) => setState(() => _form = _form.adjustMacros(protein: v)),
              onFatChanged:     (v) => setState(() => _form = _form.adjustMacros(fat: v)),
            ),
            const SizedBox(height: 24),

            const _SectionHeader(icon: Icons.water_drop_rounded, title: 'Water Intake Goal', color: AppColors.info),
            const SizedBox(height: 12),
            _WaterStepperCard(
              cups: _form.waterCups,
              onDecrement: () => setState(() {
                if (_form.waterCups > 1) _form = _form.copyWith(waterCups: _form.waterCups - 1);
              }),
              onIncrement: () => setState(() {
                if (_form.waterCups < 20) _form = _form.copyWith(waterCups: _form.waterCups + 1);
              }),
            ),
            const SizedBox(height: 24),

            const _SectionHeader(icon: Icons.directions_run_rounded, title: 'Activity Level', color: AppColors.accent),
            const SizedBox(height: 12),
            _ActivityChips(
              selected: _form.activityLevel,
              onSelect: (v) => setState(() => _form = _form.copyWith(activityLevel: v)),
            ),
            const SizedBox(height: 24),

            _SectionHeader(icon: Icons.monitor_weight_rounded, title: 'Weight Goal', color: _primaryColor),
            const SizedBox(height: 12),
            _WeightGoalSelector(
              selected: _form.weightGoal,
              onSelect: (v) => setState(() => _form = _form.copyWith(weightGoal: v)),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _WeightField(ctrl: _currentWeightCtrl, label: 'Current Weight', hint: '70 kg')),
              const SizedBox(width: 12),
              Expanded(child: _WeightField(ctrl: _targetWeightCtrl, label: 'Target Weight', hint: '60 kg')),
            ]),
            const SizedBox(height: 24),

            _SectionHeader(icon: Icons.edit_note_rounded, title: 'Notes (optional)', color: context.appTextSecondary),
            const SizedBox(height: 12),
            _NotesField(ctrl: _notesCtrl, accentColor: _primaryColor),
            const SizedBox(height: 28),

            ScaleTransition(
              scale: _saveScale,
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    disabledBackgroundColor: _primaryColor.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Save Goals', style: AppTextStyles.button),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  const _SectionHeader({required this.icon, required this.title, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 16),
      ),
      const SizedBox(width: 10),
      Text(title, style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
    ],
  );
}

// ─── Active Goal Banner ───────────────────────────────────────────────────────

class _ActiveGoalBanner extends StatelessWidget {
  final NutritionGoalModel goal;
  const _ActiveGoalBanner({required this.goal});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: AppColors.primaryGradient,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
          child: const Icon(Icons.flag_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Active Goal', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
              Text(
                NutritionGoalModel.goalLabel(goal.goalType),
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              Text(
                '${goal.targetCalories.toInt()} kcal/day · ${goal.targetWaterLiters.toStringAsFixed(1)} L water',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
          child: const Text('Update', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

// ─── Goal Type Selector ───────────────────────────────────────────────────────

class _GoalTypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _GoalTypeSelector({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Column(
    children: _kGoalTypes.map((t) {
      final isSelected = selected == t.$1;
      return GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); onSelect(t.$1); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: isSelected ? t.$4.withValues(alpha: 0.06) : context.appSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isSelected ? t.$4 : context.appBorder, width: isSelected ? 1.5 : 1),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: isSelected ? t.$4 : t.$4.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(t.$3, color: isSelected ? Colors.white : t.$4, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(t.$2, style: AppTextStyles.labelLarge.copyWith(color: isSelected ? t.$4 : context.appTextPrimary)),
            ),
            if (isSelected)
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(color: t.$4, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
              )
            else
              Icon(Icons.chevron_right_rounded, color: context.appTextHint, size: 20),
          ]),
        ),
      );
    }).toList(),
  );
}

// ─── Calorie Section ──────────────────────────────────────────────────────────

class _CalorieSection extends StatelessWidget {
  final int calorie;
  final ValueChanged<int> onCalorieChanged;
  const _CalorieSection({required this.calorie, required this.onCalorieChanged});

  static const _kOrange = Color(0xFFE65100);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.appBorder)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: _kCaloriePresets.map((c) {
            final isSelected = calorie == c;
            return GestureDetector(
              onTap: () { HapticFeedback.selectionClick(); onCalorieChanged(c); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? _kOrange : _kOrange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$c',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : _kOrange,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Center(
          child: RichText(
            text: TextSpan(
              text: '$calorie',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 48, fontWeight: FontWeight.w900, color: _kOrange, height: 1.1),
              children: [
                TextSpan(text: ' kcal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: context.appTextSecondary)),
              ],
            ),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _kOrange, thumbColor: _kOrange,
            inactiveTrackColor: _kOrange.withValues(alpha: 0.15),
            overlayColor: _kOrange.withValues(alpha: 0.1),
            trackHeight: 5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(value: calorie.toDouble(), min: 1000, max: 4000, divisions: 60, onChanged: (v) => onCalorieChanged(v.round())),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('1,000 kcal', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
            Text('4,000 kcal', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
          ],
        ),
      ],
    ),
  );
}

// ─── Macro Sliders Card ───────────────────────────────────────────────────────

class _MacroSlidersCard extends StatelessWidget {
  final int carbPct, proteinPct, fatPct;
  final int carbsGrams, proteinGrams, fatGrams;
  final int calorie;
  final ValueChanged<int> onCarbChanged, onProteinChanged, onFatChanged;

  const _MacroSlidersCard({
    required this.carbPct, required this.proteinPct, required this.fatPct,
    required this.carbsGrams, required this.proteinGrams, required this.fatGrams,
    required this.calorie,
    required this.onCarbChanged, required this.onProteinChanged, required this.onFatChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.appBorder)),
    child: Column(
      children: [
        _MacroBar(carbPct: carbPct, proteinPct: proteinPct, fatPct: fatPct),
        const SizedBox(height: 20),
        _MacroSlider(label: 'Carbs', pct: carbPct, grams: carbsGrams, color: AppColors.success, onChanged: onCarbChanged),
        const SizedBox(height: 14),
        _MacroSlider(label: 'Protein', pct: proteinPct, grams: proteinGrams, color: AppColors.info, onChanged: onProteinChanged),
        const SizedBox(height: 14),
        _MacroSlider(label: 'Fat', pct: fatPct, grams: fatGrams, color: AppColors.secondary, onChanged: onFatChanged),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: context.appBackground, borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MacroStat('Carbs', '${carbsGrams}g', AppColors.success),
              Container(width: 1, height: 28, color: context.appBorder),
              _MacroStat('Protein', '${proteinGrams}g', AppColors.info),
              Container(width: 1, height: 28, color: context.appBorder),
              _MacroStat('Fat', '${fatGrams}g', AppColors.secondary),
              Container(width: 1, height: 28, color: context.appBorder),
              _MacroStat('Total', '${carbPct + proteinPct + fatPct}%',
                (carbPct + proteinPct + fatPct) == 100 ? AppColors.success : AppColors.error),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MacroBar extends StatelessWidget {
  final int carbPct, proteinPct, fatPct;
  const _MacroBar({required this.carbPct, required this.proteinPct, required this.fatPct});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Expanded(flex: carbPct,    child: Container(height: 10, color: AppColors.success)),
            Expanded(flex: proteinPct, child: Container(height: 10, color: AppColors.info)),
            Expanded(flex: fatPct,     child: Container(height: 10, color: AppColors.secondary)),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _LegendDot(color: AppColors.success,   label: 'Carbs $carbPct%'),
          _LegendDot(color: AppColors.info,      label: 'Protein $proteinPct%'),
          _LegendDot(color: AppColors.secondary, label: 'Fat $fatPct%'),
        ],
      ),
    ],
  );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
    ],
  );
}

class _MacroSlider extends StatelessWidget {
  final String label;
  final int pct;
  final int grams;
  final Color color;
  final ValueChanged<int> onChanged;
  const _MacroSlider({required this.label, required this.pct, required this.grams, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.labelMedium.copyWith(color: color)),
          Text('$pct%  ·  ${grams}g', style: AppTextStyles.labelSmall.copyWith(color: context.appTextSecondary)),
        ],
      ),
      const SizedBox(height: 4),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: color, thumbColor: color,
          inactiveTrackColor: color.withValues(alpha: 0.12),
          overlayColor: color.withValues(alpha: 0.1),
          trackHeight: 5,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        ),
        child: Slider(
          value: pct.toDouble().clamp(5, 80), min: 5, max: 80, divisions: 75,
          onChanged: (v) => onChanged(v.round()),
        ),
      ),
    ],
  );
}

class _MacroStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MacroStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
    ],
  );
}

// ─── Water Stepper Card ───────────────────────────────────────────────────────

class _WaterStepperCard extends StatelessWidget {
  final int cups;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  const _WaterStepperCard({required this.cups, required this.onDecrement, required this.onIncrement});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.appBorder)),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('💧', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(
                  '$cups cups / day',
                  style: AppTextStyles.h3.copyWith(color: AppColors.info),
                ),
              ]),
              Text(
                '≈ ${(cups * 0.237).toStringAsFixed(2)} litres',
                style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
              ),
            ],
          ),
        ),
        Row(children: [
          _StepBtn(icon: Icons.remove_rounded, onTap: onDecrement, color: AppColors.info),
          const SizedBox(width: 6),
          _StepBtn(icon: Icons.add_rounded,    onTap: onIncrement, color: AppColors.info),
        ]),
      ],
    ),
  );
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _StepBtn({required this.icon, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); onTap(); },
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Icon(icon, color: color, size: 20),
    ),
  );
}

// ─── Activity Chips ───────────────────────────────────────────────────────────

class _ActivityChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _ActivityChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => staticGrid(
    crossAxisCount: 2,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
    aspectRatio: 2.5,
    children: _kActivityLevels.map((a) {
      final isSel = selected == a.$1;
      return GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); onSelect(a.$1); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSel ? AppColors.accent : context.appSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSel ? AppColors.accent : context.appBorder, width: isSel ? 1.5 : 1),
          ),
          child: Row(children: [
            Text(a.$3, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.$2, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: isSel ? Colors.white : context.appTextPrimary)),
                  Text(a.$4, style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: isSel ? Colors.white70 : context.appTextHint), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ]),
        ),
      );
    }).toList(),
  );
}

// ─── Weight Goal Selector ─────────────────────────────────────────────────────

class _WeightGoalSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _WeightGoalSelector({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Row(
    children: _kWeightGoals.map((g) {
      final isSel = selected == g.$1;
      return Expanded(
        child: GestureDetector(
          onTap: () { HapticFeedback.selectionClick(); onSelect(g.$1); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: EdgeInsets.only(right: g.$1 == 'gain' ? 0 : 10),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isSel ? g.$4 : context.appSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isSel ? g.$4 : context.appBorder, width: isSel ? 1.5 : 1),
            ),
            child: Column(
              children: [
                Icon(g.$3, color: isSel ? Colors.white : g.$4, size: 22),
                const SizedBox(height: 6),
                Text(g.$2, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: isSel ? Colors.white : g.$4)),
              ],
            ),
          ),
        ),
      );
    }).toList(),
  );
}

// ─── Weight Field ─────────────────────────────────────────────────────────────

class _WeightField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String hint;
  const _WeightField({required this.ctrl, required this.label, required this.hint});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTextStyles.labelSmall.copyWith(color: context.appTextSecondary)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
          suffixText: 'kg',
          suffixStyle: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
          filled: true,
          fillColor: context.appSurface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.appBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.appBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.secondary, width: 1.5)),
        ),
      ),
    ],
  );
}

// ─── Notes Field ──────────────────────────────────────────────────────────────

class _NotesField extends StatelessWidget {
  final TextEditingController ctrl;
  final Color accentColor;
  const _NotesField({required this.ctrl, required this.accentColor});

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    maxLines: 3,
    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
    decoration: InputDecoration(
      hintText: 'Dietary restrictions, allergies, health conditions...',
      hintStyle: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
      filled: true,
      fillColor: context.appSurface,
      contentPadding: const EdgeInsets.all(14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: context.appBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: context.appBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accentColor, width: 1.5)),
    ),
  );
}
