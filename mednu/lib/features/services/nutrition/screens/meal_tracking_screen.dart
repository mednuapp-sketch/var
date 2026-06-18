import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../providers/nutrition_provider.dart';
import '../models/meal_log_model.dart';
import '../../../../core/widgets/ux_widgets.dart';

class MealTrackingScreen extends ConsumerStatefulWidget {
  const MealTrackingScreen({super.key});

  @override
  ConsumerState<MealTrackingScreen> createState() => _MealTrackingScreenState();
}

class _MealTrackingScreenState extends ConsumerState<MealTrackingScreen> {
  String _selectedType = 'breakfast';

  void _openAddMeal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _AddMealSheet(selectedType: _selectedType, onAdd: (type, name, cals, protein, carbs, fat, notes) async {
        final ok = await ref.read(mealLoggingProvider.notifier).logMeal(
          mealType: type,
          foodName: name,
          calories: cals,
          protein: protein,
          carbs: carbs,
          fat: fat,
          notes: notes,
        );
        if (!ctx.mounted) return;
        Navigator.pop(ctx);
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to log meal'), backgroundColor: Colors.red),
          );
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meals = ref.watch(mealLogsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
        title: const Text('Meal Tracker', style: AppTextStyles.h3),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _openAddMeal,
            icon: const Icon(Icons.add_rounded, color: Color(0xFFE65100), size: 18),
            label: const Text('Add', style: TextStyle(fontFamily: 'Poppins', color: Color(0xFFE65100), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Column(
        children: [
          _DailySummary(meals: meals),
          _MealTypeFilter(
            selected: _selectedType,
            onSelect: (t) => setState(() => _selectedType = t),
            meals: meals,
          ),
          Expanded(
            child: meals.when(
              loading: () => Column(children: List.generate(4, (_) => const SkeletonListTile())),
              error: (e, _) => const AppErrorState(),
              data: (list) {
                final filtered = list.where((m) => m.mealType == _selectedType).toList();
                if (filtered.isEmpty) {
                  return _EmptyMealState(type: _selectedType, onAdd: _openAddMeal);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) => _MealTile(
                    log: filtered[i],
                    onDelete: () async {
                      await ref.read(mealLoggingProvider.notifier).deleteLog(filtered[i].id);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddMeal,
        backgroundColor: const Color(0xFFE65100),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Log Meal', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}

class _DailySummary extends StatelessWidget {
  final AsyncValue<List<MealLogModel>> meals;
  const _DailySummary({required this.meals});

  @override
  Widget build(BuildContext context) {
    final list = meals.valueOrNull ?? [];
    final cals = list.fold<double>(0, (s, m) => s + m.calories);
    final protein = list.fold<double>(0, (s, m) => s + m.protein);
    final carbs = list.fold<double>(0, (s, m) => s + m.carbs);
    final fat = list.fold<double>(0, (s, m) => s + m.fat);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SumItem(label: 'Calories', value: '${cals.toInt()}', unit: 'kcal', color: const Color(0xFFE65100)),
          _SumItem(label: 'Protein', value: '${protein.toInt()}', unit: 'g', color: const Color(0xFF1565C0)),
          _SumItem(label: 'Carbs', value: '${carbs.toInt()}', unit: 'g', color: const Color(0xFF2E7D32)),
          _SumItem(label: 'Fat', value: '${fat.toInt()}', unit: 'g', color: const Color(0xFF7B1FA2)),
        ],
      ),
    );
  }
}

class _SumItem extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _SumItem({required this.label, required this.value, required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RichText(
          text: TextSpan(
            text: value,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w800, color: color),
            children: [TextSpan(text: unit, style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: color.withValues(alpha:0.7)))],
          ),
        ),
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _MealTypeFilter extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  final AsyncValue<List<MealLogModel>> meals;

  const _MealTypeFilter({required this.selected, required this.onSelect, required this.meals});

  static const _icons = {
    'breakfast': Icons.wb_sunny_rounded,
    'lunch': Icons.wb_cloudy_rounded,
    'dinner': Icons.nightlight_rounded,
    'snack': Icons.cookie_rounded,
  };
  static const _colors = {
    'breakfast': Color(0xFFF9A825),
    'lunch': Color(0xFF2E7D32),
    'dinner': Color(0xFF1565C0),
    'snack': Color(0xFF7B1FA2),
  };

  @override
  Widget build(BuildContext context) {
    final list = meals.valueOrNull ?? [];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: ['breakfast', 'lunch', 'dinner', 'snack'].map((type) {
          final isSelected = selected == type;
          final color = _colors[type]!;
          final count = list.where((m) => m.mealType == type).length;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(type),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? color : color.withValues(alpha:0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSelected ? color : color.withValues(alpha:0.2)),
                ),
                child: Column(
                  children: [
                    Icon(_icons[type], color: isSelected ? Colors.white : color, size: 20),
                    const SizedBox(height: 3),
                    Text(MealLogModel.mealTypeLabel(type), style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : color)),
                    if (count > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: isSelected ? Colors.white.withValues(alpha:0.3) : color.withValues(alpha:0.15), borderRadius: BorderRadius.circular(6)),
                        child: Text('$count', style: TextStyle(fontFamily: 'Poppins', fontSize: 8, fontWeight: FontWeight.w700, color: isSelected ? Colors.white : color)),
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MealTile extends StatelessWidget {
  final MealLogModel log;
  final VoidCallback onDelete;
  const _MealTile({required this.log, required this.onDelete});

  static const _colors = {
    'breakfast': Color(0xFFF9A825),
    'lunch': Color(0xFF2E7D32),
    'dinner': Color(0xFF1565C0),
    'snack': Color(0xFF7B1FA2),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[log.mealType] ?? AppColors.textSecondary;
    return Dismissible(
      key: Key(log.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: Colors.red.withValues(alpha:0.1), borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.delete_rounded, color: Colors.red),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.restaurant_rounded, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(log.foodName, style: AppTextStyles.labelLarge),
                  if (log.notes.isNotEmpty) Text(log.notes, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (log.protein > 0) _MacroTag(label: 'P: ${log.protein.toInt()}g', color: const Color(0xFF1565C0)),
                      if (log.carbs > 0) _MacroTag(label: 'C: ${log.carbs.toInt()}g', color: const Color(0xFF2E7D32)),
                      if (log.fat > 0) _MacroTag(label: 'F: ${log.fat.toInt()}g', color: const Color(0xFF7B1FA2)),
                    ],
                  ),
                ],
              ),
            ),
            Text('${log.calories.toInt()}\nkcal', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: color, height: 1.2)),
          ],
        ),
      ),
    );
  }
}

class _MacroTag extends StatelessWidget {
  final String label;
  final Color color;
  const _MacroTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha:0.08), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmptyMealState extends StatelessWidget {
  final String type;
  final VoidCallback onAdd;
  const _EmptyMealState({required this.type, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant_menu_rounded, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No ${MealLogModel.mealTypeLabel(type)} logged', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text('Tap the button below to log what you ate', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text('Log ${MealLogModel.mealTypeLabel(type)}', style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add Meal Sheet ─────────────────────────────────────

typedef _AddMealCallback = Future<void> Function(
  String type, String name, double cals, double protein, double carbs, double fat, String notes,
);

class _AddMealSheet extends StatefulWidget {
  final String selectedType;
  final _AddMealCallback onAdd;
  const _AddMealSheet({required this.selectedType, required this.onAdd});

  @override
  State<_AddMealSheet> createState() => _AddMealSheetState();
}

class _AddMealSheetState extends State<_AddMealSheet> {
  late String _type;
  final _nameCtrl = TextEditingController();
  final _calsCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _type = widget.selectedType;
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _calsCtrl.dispose(); _proteinCtrl.dispose();
    _carbsCtrl.dispose(); _fatCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final cals = double.tryParse(_calsCtrl.text) ?? 0;
    if (name.isEmpty || cals <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter food name and calories')),
      );
      return;
    }
    setState(() => _isLoading = true);
    await widget.onAdd(
      _type, name, cals,
      double.tryParse(_proteinCtrl.text) ?? 0,
      double.tryParse(_carbsCtrl.text) ?? 0,
      double.tryParse(_fatCtrl.text) ?? 0,
      _notesCtrl.text.trim(),
    );
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Log Meal', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            _MealTypeRow(selected: _type, onSelect: (t) => setState(() => _type = t)),
            const SizedBox(height: 14),
            _Field(controller: _nameCtrl, label: 'Food Name', hint: 'e.g. Oats with milk', required: true),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _Field(controller: _calsCtrl, label: 'Calories (kcal)', hint: '350', keyboardType: TextInputType.number, required: true)),
                const SizedBox(width: 10),
                Expanded(child: _Field(controller: _proteinCtrl, label: 'Protein (g)', hint: '12', keyboardType: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _Field(controller: _carbsCtrl, label: 'Carbs (g)', hint: '60', keyboardType: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _Field(controller: _fatCtrl, label: 'Fat (g)', hint: '8', keyboardType: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 12),
            _Field(controller: _notesCtrl, label: 'Notes (optional)', hint: 'Homemade, restaurant name...'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Meal', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealTypeRow extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _MealTypeRow({required this.selected, required this.onSelect});

  static const _types = ['breakfast', 'lunch', 'dinner', 'snack'];
  static const _colors = {
    'breakfast': Color(0xFFF9A825),
    'lunch': Color(0xFF2E7D32),
    'dinner': Color(0xFF1565C0),
    'snack': Color(0xFF7B1FA2),
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _types.map((t) {
        final color = _colors[t]!;
        final isSelected = t == selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelect(t),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? color : color.withValues(alpha:0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isSelected ? color : color.withValues(alpha:0.2)),
              ),
              child: Text(
                MealLogModel.mealTypeLabel(t),
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: isSelected ? Colors.white : color),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboardType;
  final bool required;
  const _Field({required this.controller, required this.label, required this.hint, this.keyboardType = TextInputType.text, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
            children: required ? [const TextSpan(text: ' *', style: TextStyle(color: Colors.red))] : [],
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
            filled: true,
            fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE65100))),
          ),
        ),
      ],
    );
  }
}
