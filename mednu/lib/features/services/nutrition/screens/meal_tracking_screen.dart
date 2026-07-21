import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../providers/nutrition_provider.dart';
import '../models/meal_log_model.dart';
import '../../../../core/widgets/ux_widgets.dart';
import '../services/food_lookup_service.dart';

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
          if (!mounted) return;
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
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
        title: const Text('Meal Tracker', style: AppTextStyles.h3),
        centerTitle: true,
        backgroundColor: context.appSurface,
        foregroundColor: context.appTextPrimary,
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
              loading: () => Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(children: List.generate(4, (_) => const _MealTileSkeleton())),
              ),
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
      color: context.appSurface,
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
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
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
      color: context.appSurface,
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
    final color = _colors[log.mealType] ?? context.appTextSecondary;
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
          color: context.appSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.appBorder),
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
                  if (log.notes.isNotEmpty) Text(log.notes, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
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
            Text('No ${MealLogModel.mealTypeLabel(type)} logged', style: AppTextStyles.labelLarge.copyWith(color: context.appTextSecondary)),
            const SizedBox(height: 8),
            Text('Tap the button below to log what you ate', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint), textAlign: TextAlign.center),
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
  final _qtyCtrl = TextEditingController(text: '100');
  final _calsCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _unit = 'g';
  bool _isLoading = false;
  bool _isSearching = false;
  List<FoodNutrition> _searchResults = [];
  FoodNutrition? _selectedFood;
  bool _autoFilled = false;

  static const _units = ['g', 'ml', 'cup', 'tbsp', 'tsp', 'piece', 'bowl', 'plate'];

  @override
  void initState() {
    super.initState();
    _type = widget.selectedType;
    _qtyCtrl.addListener(_recalculate);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _calsCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _recalculate() {
    final food = _selectedFood;
    if (food == null) return;
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) return;
    final grams = qty * (FoodLookupService.unitGrams[_unit] ?? 1.0);
    final r = food.forGrams(grams);
    _calsCtrl.text = r.calories.toStringAsFixed(0);
    _proteinCtrl.text = r.protein.toStringAsFixed(1);
    _carbsCtrl.text = r.carbs.toStringAsFixed(1);
    _fatCtrl.text = r.fat.toStringAsFixed(1);
    if (mounted) setState(() => _autoFilled = true);
  }

  void _selectUnit(String unit) {
    setState(() => _unit = unit);
    _recalculate();
  }

  Future<void> _search() async {
    final query = _nameCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() { _isSearching = true; _searchResults = []; });
    final results = await FoodLookupService.search(query);
    if (mounted) setState(() { _isSearching = false; _searchResults = results; });
  }

  void _selectFood(FoodNutrition food) {
    setState(() {
      _selectedFood = food;
      _nameCtrl.text = food.name;
      _searchResults = [];
    });
    _recalculate();
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
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: context.appDivider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Log Meal', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            _MealTypeRow(selected: _type, onSelect: (t) => setState(() => _type = t)),
            const SizedBox(height: 16),

            // ── Food name + search ──
            _FieldLabel(label: 'Food Name', required: true),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    style: AppTextStyles.bodyMedium,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: 'e.g. Chicken breast, Rice, Dal',
                      hintStyle: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
                      filled: true,
                      fillColor: context.appBackground,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE65100))),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isSearching ? null : _search,
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE65100),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _isSearching
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),

            // ── Search results ──
            if (_isSearching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: Text('Searching food database...', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Color(0xFF9E9E9E)))),
              ),
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.appBorder),
                  boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    children: _searchResults.take(6).toList().asMap().entries.map((e) {
                      final idx = e.key;
                      final food = e.value;
                      return InkWell(
                        onTap: () => _selectFood(food),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            border: idx != 0 ? Border(top: BorderSide(color: context.appBorder)) : null,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.restaurant_rounded, size: 14, color: Color(0xFFE65100)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  food.name,
                                  style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${food.caloriesPer100g.toStringAsFixed(0)} kcal/100g',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: const Color(0xFFE65100), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
            if (!_isSearching && _searchResults.isEmpty && _selectedFood == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Type food name and tap 🔍 to auto-fill nutrition info',
                  style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
                ),
              ),

            const SizedBox(height: 14),

            // ── Quantity + unit ──
            _FieldLabel(label: 'Quantity & Unit'),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: AppTextStyles.bodyMedium,
                    decoration: InputDecoration(
                      hintText: '100',
                      hintStyle: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
                      filled: true,
                      fillColor: context.appBackground,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE65100))),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _units.map((u) {
                        final sel = u == _unit;
                        return GestureDetector(
                          onTap: () => _selectUnit(u),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: sel ? const Color(0xFFE65100) : context.appBackground,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: sel ? const Color(0xFFE65100) : context.appBorder),
                            ),
                            child: Text(
                              u,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: sel ? Colors.white : context.appTextSecondary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Nutrition fields ──
            Row(
              children: [
                _FieldLabel(label: 'Nutrition'),
                if (_autoFilled) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(6)),
                    child: const Text('Auto-filled', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.appBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _autoFilled ? const Color(0xFFE65100).withValues(alpha: 0.25) : context.appBorder),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _NutriField(controller: _calsCtrl, label: 'Calories', unit: 'kcal', color: const Color(0xFFE65100))),
                      const SizedBox(width: 10),
                      Expanded(child: _NutriField(controller: _proteinCtrl, label: 'Protein', unit: 'g', color: const Color(0xFF1565C0))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _NutriField(controller: _carbsCtrl, label: 'Carbs', unit: 'g', color: const Color(0xFF2E7D32))),
                      const SizedBox(width: 10),
                      Expanded(child: _NutriField(controller: _fatCtrl, label: 'Fat', unit: 'g', color: const Color(0xFF7B1FA2))),
                    ],
                  ),
                ],
              ),
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

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool required;
  const _FieldLabel({required this.label, this.required = false});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        text: label,
        style: AppTextStyles.labelSmall.copyWith(color: context.appTextSecondary),
        children: required ? [const TextSpan(text: ' *', style: TextStyle(color: Colors.red))] : [],
      ),
    );
  }
}

class _NutriField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String unit;
  final Color color;
  const _NutriField({required this.controller, required this.label, required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text('$label ($unit)', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
            filled: true,
            fillColor: context.appSurface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color.withValues(alpha: 0.2))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color.withValues(alpha: 0.2))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color)),
          ),
        ),
      ],
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
  const _Field({required this.controller, required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelSmall.copyWith(color: context.appTextSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
            filled: true,
            fillColor: context.appBackground,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE65100))),
          ),
        ),
      ],
    );
  }
}

class _MealTileSkeleton extends StatelessWidget {
  const _MealTileSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 6)],
      ),
      child: const AppShimmer(
        child: Row(children: [
          SkeletonBox(width: 44, height: 44, radius: 12),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: double.infinity, height: 13, radius: 4),
            SizedBox(height: 6),
            SkeletonBox(width: 120, height: 11, radius: 4),
          ])),
          SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            SkeletonBox(width: 50, height: 13, radius: 4),
            SizedBox(height: 5),
            SkeletonBox(width: 40, height: 11, radius: 4),
          ]),
        ]),
      ),
    );
  }
}
