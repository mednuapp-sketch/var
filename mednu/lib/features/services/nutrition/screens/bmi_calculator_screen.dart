import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../models/bmi_log_model.dart';
import '../providers/nutrition_provider.dart';

// ─── BMI data ─────────────────────────────────────────────────────────────────

const _kTips = {
  'Underweight': [
    'Add calorie-dense, nutrient-rich foods like nuts and avocados.',
    'Increase protein intake to build healthy muscle mass.',
    'Eat 5–6 small meals per day rather than 3 large ones.',
    'Consult a nutritionist for a personalised weight-gain plan.',
  ],
  'Normal': [
    'Maintain your balanced, varied diet — you are doing great!',
    'Stay physically active with at least 150 min of exercise/week.',
    'Focus on whole grains, lean protein, fruits and vegetables.',
    'Keep up with regular health check-ups.',
  ],
  'Overweight': [
    'Reduce processed foods, sugary drinks and refined carbs.',
    'Aim for at least 30 minutes of moderate activity each day.',
    'Eat more fibre-rich foods to feel full longer.',
    'Track meals and set small, achievable goals.',
  ],
  'Obese': [
    'Consult your doctor or a dietitian for personalised guidance.',
    'Set realistic, gradual weight-loss goals (0.5–1 kg/week).',
    'Reduce highly processed and calorie-dense foods significantly.',
    'Daily tracking — even 10 min walks — builds great habits.',
  ],
};

class _BmiRange {
  final String label;
  final Color color;
  final double min;
  final double max;
  const _BmiRange(this.label, this.color, this.min, this.max);
}

const _kRanges = [
  _BmiRange('Underweight', Color(0xFF1565C0), 0, 18.5),
  _BmiRange('Normal',      Color(0xFF2E7D32), 18.5, 25),
  _BmiRange('Overweight',  Color(0xFFF9A825), 25, 30),
  _BmiRange('Obese',       Color(0xFFB71C1C), 30, 50),
];

const _kPediatricCategory = 'Ask your doctor';

// ─── Screen ───────────────────────────────────────────────────────────────────

class BmiCalculatorScreen extends ConsumerStatefulWidget {
  const BmiCalculatorScreen({super.key});

  @override
  ConsumerState<BmiCalculatorScreen> createState() => _BmiCalculatorScreenState();
}

class _BmiCalculatorScreenState extends ConsumerState<BmiCalculatorScreen>
    with SingleTickerProviderStateMixin {
  // Inputs
  double _heightCm = 165;
  double _weightKg = 65;
  int _age = 25;
  String _gender = 'female';
  bool _useImperial = false;

  // Result
  double? _bmi;
  String _category = '';
  bool _calculated = false;
  bool _saving = false;

  late AnimationController _resultAnim;
  late Animation<double> _resultFade;
  late Animation<Offset> _resultSlide;

  @override
  void initState() {
    super.initState();
    _resultAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _resultFade = CurvedAnimation(parent: _resultAnim, curve: Curves.easeOut);
    _resultSlide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _resultAnim, curve: Curves.easeOut));
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillFromLastLog());
  }

  @override
  void dispose() {
    _resultAnim.dispose();
    super.dispose();
  }

  // Load the most recent saved reading (if any) so returning users see their
  // last measurement and trend immediately instead of a blank default state.
  Future<void> _prefillFromLastLog() async {
    try {
      final logs = await ref.read(bmiLogsProvider.future);
      if (!mounted || logs.isEmpty) return;
      final last = logs.first;
      setState(() {
        _heightCm = last.heightCm.clamp(100, 220);
        _weightKg = last.weightKg.clamp(30, 200);
        _age = last.age.clamp(10, 100);
        _gender = last.gender;
        _bmi = last.bmi;
        _category = last.category;
        _calculated = true;
      });
      _resultAnim.forward(from: 0);
    } catch (_) {
      // Offline or not signed in yet — keep the default starting values.
    }
  }

  bool get _isPediatric => _age < 18;
  bool get _isSenior => _age >= 65;

  double get _heightForCalc => _heightCm; // always stored in cm
  double get _weightForCalc => _weightKg; // always stored in kg

  void _calculate() {
    HapticFeedback.mediumImpact();
    final hm = _heightForCalc / 100;
    final bmi = _weightForCalc / (hm * hm);

    String cat;
    if (_isPediatric) {
      // Fixed adult cut-offs (18.5 / 25 / 30) are not valid for growing
      // bodies — paediatric BMI is read against age- and sex-specific
      // percentile charts, so we deliberately don't classify it here.
      cat = _kPediatricCategory;
    } else {
      cat = 'Normal';
      for (final r in _kRanges) {
        if (bmi >= r.min && bmi < r.max) { cat = r.label; break; }
      }
    }

    setState(() {
      _bmi = bmi;
      _category = cat;
      _calculated = true;
    });
    _resultAnim.forward(from: 0);
    _persist(bmi, cat);
  }

  Future<void> _persist(double bmi, String cat) async {
    setState(() => _saving = true);
    final ok = await ref.read(bmiSaveProvider.notifier).save(
          heightCm: _heightCm,
          weightKg: _weightKg,
          age: _age,
          gender: _gender,
          bmi: bmi,
          category: cat,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Result shown, but could not sync to your history. Check your connection.')),
      );
    }
  }

  Color get _categoryColor {
    if (_isPediatric) return const Color(0xFF00838F);
    for (final r in _kRanges) {
      if (r.label == _category) return r.color;
    }
    return AppColors.primary;
  }

  double get _idealWeightMin => 18.5 * (_heightCm / 100) * (_heightCm / 100);
  double get _idealWeightMax => 24.9 * (_heightCm / 100) * (_heightCm / 100);

  // Devine formula — the standard clinical estimate of ideal body weight,
  // the one place gender actually changes the numbers shown.
  double get _idealBodyWeightDevine {
    final totalInches = _heightCm / 2.54;
    final over60 = math.max(0, totalInches - 60);
    final base = _gender == 'male' ? 50.0 : 45.5;
    return base + 2.3 * over60;
  }

  // Precise numeric entry — sliders alone make it hard to land on an exact
  // value, so tapping the number opens a keyboard-driven alternative.
  Future<void> _editNumber({
    required String title,
    required double initial,
    required double min,
    required double max,
    required String suffix,
    required ValueChanged<double> onSaved,
    bool isInt = false,
  }) async {
    final ctrl = TextEditingController(
      text: isInt ? initial.round().toString() : initial.toStringAsFixed(1),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Enter $title', style: AppTextStyles.h4),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: !isInt),
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            suffixText: suffix,
            helperText: 'Range: ${min.toStringAsFixed(0)}–${max.toStringAsFixed(0)} $suffix',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v == null) return;
              Navigator.pop(ctx, v.clamp(min, max));
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (result != null) onSaved(result);
  }

  void _editAge() => _editNumber(
        title: 'Age',
        initial: _age.toDouble(),
        min: 10,
        max: 100,
        suffix: 'yrs',
        isInt: true,
        onSaved: (v) => setState(() => _age = v.round()),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('BMI Calculator', style: AppTextStyles.h3),
        centerTitle: true,
        backgroundColor: context.appSurface,
        foregroundColor: context.appTextPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          // Imperial / Metric toggle
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Semantics(
              button: true,
              label: _useImperial ? 'Switch to metric units' : 'Switch to imperial units',
              child: GestureDetector(
                onTap: () => setState(() => _useImperial = !_useImperial),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _useImperial ? 'Imperial' : 'Metric',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16,
            math.max(MediaQuery.of(context).padding.bottom + 16, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // What BMI is / isn't — sets expectations up front
            const _BmiLimitationsNote(),
            const SizedBox(height: 16),

            // Gender Selector
            _GenderSelector(selected: _gender, onSelect: (g) => setState(() => _gender = g)),
            const SizedBox(height: 16),

            // Height — slider for coarse adjustment, input box for an exact value
            _SliderCard(
              label: 'Height',
              value: _heightCm,
              min: 100,
              max: 220,
              color: const Color(0xFF1565C0),
              minLabel: _useImperial ? '3\'3"' : '100 cm',
              maxLabel: _useImperial ? '7\'2"' : '220 cm',
              onChanged: (v) => setState(() => _heightCm = v),
              editValue: _useImperial ? _heightCm / 2.54 : _heightCm,
              editMin: _useImperial ? 100 / 2.54 : 100,
              editMax: _useImperial ? 220 / 2.54 : 220,
              editSuffix: _useImperial ? 'in' : 'cm',
              onEditCommitted: (v) => setState(
                () => _heightCm = (_useImperial ? v * 2.54 : v).clamp(100, 220),
              ),
            ),
            const SizedBox(height: 12),

            // Weight — slider for coarse adjustment, input box for an exact value
            _SliderCard(
              label: 'Weight',
              value: _weightKg,
              min: 30,
              max: 200,
              color: const Color(0xFF2E7D32),
              minLabel: _useImperial ? '66 lbs' : '30 kg',
              maxLabel: _useImperial ? '441 lbs' : '200 kg',
              onChanged: (v) => setState(() => _weightKg = v),
              editValue: _useImperial ? _weightKg * 2.205 : _weightKg,
              editMin: _useImperial ? 30 * 2.205 : 30,
              editMax: _useImperial ? 200 * 2.205 : 200,
              editSuffix: _useImperial ? 'lbs' : 'kg',
              onEditCommitted: (v) => setState(
                () => _weightKg = (_useImperial ? v / 2.205 : v).clamp(30, 200),
              ),
            ),
            const SizedBox(height: 12),

            // Age
            _AgeStepperCard(
              age: _age,
              onMinus: () => setState(() { if (_age > 10) _age--; }),
              onPlus: () => setState(() { if (_age < 100) _age++; }),
              onTapNumber: _editAge,
            ),
            const SizedBox(height: 20),

            // Calculate Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _calculate,
                icon: _saving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.calculate_rounded, color: Colors.white),
                label: const Text(
                  'Calculate BMI',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              ),
            ),

            // ── Results ──────────────────────────────────────────
            if (_calculated && _bmi != null) ...[
              const SizedBox(height: 28),
              FadeTransition(
                opacity: _resultFade,
                child: SlideTransition(
                  position: _resultSlide,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isPediatric)
                        _PediatricResultCard(bmi: _bmi!, age: _age)
                      else ...[
                        // Big BMI result card with gauge
                        _BmiResultCard(
                          bmi: _bmi!,
                          category: _category,
                          categoryColor: _categoryColor,
                          idealMin: _idealWeightMin,
                          idealMax: _idealWeightMax,
                          idealBodyWeightDevine: _idealBodyWeightDevine,
                          showSeniorNote: _isSenior,
                        ),
                        const SizedBox(height: 16),

                        // Scale bar
                        _BmiScaleBar(bmi: _bmi!),
                        const SizedBox(height: 16),

                        // Health tips
                        _HealthTipsCard(category: _category, color: _categoryColor),
                      ],
                      const SizedBox(height: 16),

                      // History chart — real, persisted readings
                      _BmiHistorySection(currentAge: _age),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─── BMI Limitations Note ─────────────────────────────────────────────────────

class _BmiLimitationsNote extends StatelessWidget {
  const _BmiLimitationsNote();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'About BMI: BMI is a general screening indicator. It does not account for '
        'muscle mass, bone density or body composition. Use it as a starting point, not a diagnosis.',
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'BMI is a general screening indicator — it doesn\'t account for muscle mass, '
              'bone density or body composition. Use it as a starting point, not a diagnosis.',
              style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Gender Selector ──────────────────────────────────────────────────────────

class _GenderSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _GenderSelector({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: _GenderCard(
        icon: Icons.male_rounded,
        label: 'Male',
        isSelected: selected == 'male',
        color: const Color(0xFF1565C0),
        onTap: () { HapticFeedback.selectionClick(); onSelect('male'); },
      )),
      const SizedBox(width: 12),
      Expanded(child: _GenderCard(
        icon: Icons.female_rounded,
        label: 'Female',
        isSelected: selected == 'female',
        color: const Color(0xFF522546),
        onTap: () { HapticFeedback.selectionClick(); onSelect('female'); },
      )),
    ],
  );
}

class _GenderCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;
  const _GenderCard({required this.icon, required this.label, required this.isSelected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: isSelected,
    label: '$label, ${isSelected ? 'selected' : 'not selected'}',
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isSelected ? color : context.appSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? color : context.appBorder, width: isSelected ? 2 : 1),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))]
              : [],
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : color, size: 32),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: isSelected ? Colors.white : color)),
          ],
        ),
      ),
    ),
  );
}

// ─── Slider Card ──────────────────────────────────────────────────────────────

class _SliderCard extends StatefulWidget {
  final String label;
  final double value; // canonical unit (cm / kg) — drives the slider
  final double min;   // canonical unit
  final double max;   // canonical unit
  final Color color;
  final String minLabel;
  final String maxLabel;
  final ValueChanged<double> onChanged; // canonical unit, fired on drag

  // The manual-entry box operates in whatever unit is currently displayed
  // (metric or imperial), independent of the slider's canonical cm/kg range.
  final double editValue;
  final double editMin;
  final double editMax;
  final String editSuffix;
  final ValueChanged<double> onEditCommitted;

  const _SliderCard({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.minLabel,
    required this.maxLabel,
    required this.onChanged,
    required this.editValue,
    required this.editMin,
    required this.editMax,
    required this.editSuffix,
    required this.onEditCommitted,
  });

  @override
  State<_SliderCard> createState() => _SliderCardState();
}

class _SliderCardState extends State<_SliderCard> {
  late final TextEditingController _ctrl;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _format(widget.editValue));
    _focusNode.addListener(_onFocusChange);
  }

  String _format(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final parsed = double.tryParse(_ctrl.text);
    if (parsed == null) {
      _ctrl.text = _format(widget.editValue);
      return;
    }
    final clamped = parsed.clamp(widget.editMin, widget.editMax);
    _ctrl.text = _format(clamped);
    if (clamped != widget.editValue) widget.onEditCommitted(clamped);
  }

  @override
  void didUpdateWidget(covariant _SliderCard old) {
    super.didUpdateWidget(old);
    // Keep the box in sync with slider drags and unit-toggle conversions,
    // but never fight the user while they're actively typing in it.
    if (!_focusNode.hasFocus && widget.editValue != old.editValue) {
      _ctrl.text = _format(widget.editValue);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
    decoration: BoxDecoration(
      color: context.appSurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.appBorder),
    ),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(widget.label, style: AppTextStyles.labelLarge.copyWith(color: context.appTextSecondary)),
            Semantics(
              textField: true,
              label: '${widget.label} in ${widget.editSuffix}',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 56,
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focusNode,
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _focusNode.unfocus(),
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: widget.color),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(widget.editSuffix, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: widget.color.withValues(alpha: 0.7))),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Icon(Icons.edit_rounded, size: 13, color: widget.color.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: widget.color,
            thumbColor: widget.color,
            inactiveTrackColor: widget.color.withValues(alpha: 0.14),
            overlayColor: widget.color.withValues(alpha: 0.1),
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
          ),
          child: Slider(
            value: widget.value.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: ((widget.max - widget.min) * 2).toInt(),
            onChanged: widget.onChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.minLabel, style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
              Text(widget.maxLabel, style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
            ],
          ),
        ),
      ],
    ),
  );
}

// ─── Age Stepper ──────────────────────────────────────────────────────────────

class _AgeStepperCard extends StatelessWidget {
  final int age;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback? onTapNumber;
  const _AgeStepperCard({required this.age, required this.onMinus, required this.onPlus, this.onTapNumber});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: context.appSurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.appBorder),
    ),
    child: Row(
      children: [
        Text('Age', style: AppTextStyles.labelLarge.copyWith(color: context.appTextSecondary)),
        const Spacer(),
        _AgeBtn(icon: Icons.remove_rounded, onTap: onMinus, color: const Color(0xFFE65100), semanticLabel: 'Decrease age'),
        const SizedBox(width: 16),
        Semantics(
          button: onTapNumber != null,
          label: 'Age, $age years. ${onTapNumber != null ? 'Double tap to enter an exact age.' : ''}',
          child: GestureDetector(
            onTap: onTapNumber,
            child: RichText(
              text: TextSpan(
                text: '$age',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFFE65100)),
                children: [
                  TextSpan(text: ' yrs', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.appTextSecondary)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        _AgeBtn(icon: Icons.add_rounded, onTap: onPlus, color: const Color(0xFFE65100), semanticLabel: 'Increase age'),
      ],
    ),
  );
}

class _AgeBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final String semanticLabel;
  const _AgeBtn({required this.icon, required this.onTap, required this.color, required this.semanticLabel});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    ),
  );
}

// ─── BMI Result Card with Gauge ───────────────────────────────────────────────

class _BmiResultCard extends StatelessWidget {
  final double bmi;
  final String category;
  final Color categoryColor;
  final double idealMin;
  final double idealMax;
  final double idealBodyWeightDevine;
  final bool showSeniorNote;
  const _BmiResultCard({
    required this.bmi,
    required this.category,
    required this.categoryColor,
    required this.idealMin,
    required this.idealMax,
    required this.idealBodyWeightDevine,
    required this.showSeniorNote,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: context.appSurface,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: categoryColor.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 6))],
      border: Border.all(color: categoryColor.withValues(alpha: 0.25), width: 1.5),
    ),
    child: Column(
      children: [
        Text('Your BMI', style: AppTextStyles.labelMedium.copyWith(color: context.appTextSecondary)),
        const SizedBox(height: 16),

        // Gauge — sized so the arc spans the full card width. The BMI figure
        // sits inside the dome's open interior (empty space above the
        // baseline, since the marker lives on the arc rather than at the
        // center), so it reads as one instrument instead of an arc plus a
        // separate number stacked underneath.
        Semantics(
          label: 'Your BMI is ${bmi.toStringAsFixed(1)} kilograms per square metre, category $category',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gaugeWidth = constraints.maxWidth;
              final gaugeHeight = gaugeWidth / 2 + 16;
              return SizedBox(
                height: gaugeHeight,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(size: Size(gaugeWidth, gaugeHeight), painter: _GaugePainter(bmi: bmi)),
                    Positioned(
                      top: gaugeHeight * 0.4,
                      left: 0,
                      right: 0,
                      child: Column(
                        children: [
                          Text(
                            bmi.toStringAsFixed(1),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 40, fontWeight: FontWeight.w900, color: categoryColor, height: 1),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'kg/m²',
                            style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // Category Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(color: categoryColor, borderRadius: BorderRadius.circular(20)),
          child: Text(
            category,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
        const SizedBox(height: 16),

        // Ideal weight info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: context.appBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: context.appTextSecondary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Ideal weight for your height: ${idealMin.toStringAsFixed(1)} – ${idealMax.toStringAsFixed(1)} kg',
                      style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Ideal body weight (Devine formula): ${idealBodyWeightDevine.toStringAsFixed(1)} kg',
                style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
                textAlign: TextAlign.center,
              ),
              if (showSeniorNote) ...[
                const SizedBox(height: 6),
                Text(
                  'For adults 65+, a slightly higher BMI is sometimes considered healthy — ask your doctor for a target suited to you.',
                  style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint, height: 1.3),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

// ─── Pediatric Result Card ─────────────────────────────────────────────────────

class _PediatricResultCard extends StatelessWidget {
  final double bmi;
  final int age;
  const _PediatricResultCard({required this.bmi, required this.age});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF00838F);
    return Semantics(
      label: 'Your BMI is ${bmi.toStringAsFixed(1)} kilograms per square metre. '
          'Standard adult BMI categories do not apply under age 18 — talk to a pediatrician.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 6))],
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
        ),
        child: Column(
          children: [
            Text('Your BMI', style: AppTextStyles.labelMedium.copyWith(color: context.appTextSecondary)),
            const SizedBox(height: 12),
            Text(
              bmi.toStringAsFixed(1),
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 40, fontWeight: FontWeight.w900, color: color, height: 1),
            ),
            Text('kg/m²', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
              child: const Text(
                'Ask your doctor',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: context.appBackground, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.child_care_rounded, size: 16, color: context.appTextSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'At age $age, BMI is read against age- and sex-specific growth-chart '
                      'percentiles rather than the fixed adult ranges (18.5 / 25 / 30) used above. '
                      'This number is accurate, but only a pediatrician can tell you what it means.',
                      style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Gauge Painter ────────────────────────────────────────────────────────────

class _GaugePainter extends CustomPainter {
  final double bmi;
  const _GaugePainter({required this.bmi});

  @override
  void paint(Canvas canvas, Size size) {
    const colors = [Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFFF9A825), Color(0xFFB71C1C)];
    final cx = size.width / 2;
    // Radius is driven by the available width so the dome always spans the
    // full card, with the baseline placed just far enough below it for the
    // stroke + marker dot to stay inside the box.
    final radius = cx - 8;
    final cy = radius + 8;
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    const segmentSweep = sweepAngle / 4;
    for (int i = 0; i < 4; i++) {
      trackPaint.color = colors[i].withValues(alpha: 0.18);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        startAngle + i * segmentSweep + 0.02,
        segmentSweep - 0.04,
        false,
        trackPaint,
      );
    }

    // Colored arc up to BMI position
    final bmiClamped = bmi.clamp(10.0, 40.0);
    final fraction = (bmiClamped - 10) / 30;
    final filledSweep = sweepAngle * fraction;

    // Compute current color
    Color gaugeColor = colors[0];
    if (bmi >= 30) {
      gaugeColor = colors[3];
    } else if (bmi >= 25) {
      gaugeColor = colors[2];
    } else if (bmi >= 18.5) {
      gaugeColor = colors[1];
    }

    trackPaint.color = gaugeColor;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      startAngle,
      filledSweep,
      false,
      trackPaint,
    );

    // Marker dot at current position on the arc (no line back to center,
    // so it never crosses over the BMI number rendered below the gauge)
    final markerAngle = startAngle + sweepAngle * fraction;
    final markerPos = Offset(
      cx + radius * math.cos(markerAngle),
      cy + radius * math.sin(markerAngle),
    );
    canvas.drawCircle(markerPos, 9, Paint()..color = gaugeColor);
    canvas.drawCircle(markerPos, 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.bmi != bmi;
}

// ─── BMI Scale Bar ────────────────────────────────────────────────────────────

class _BmiScaleBar extends StatelessWidget {
  final double bmi;
  const _BmiScaleBar({required this.bmi});

  @override
  Widget build(BuildContext context) {
    final ranges = [
      ('< 18.5', 'Underweight', const Color(0xFF1565C0)),
      ('18.5–24.9', 'Normal', const Color(0xFF2E7D32)),
      ('25–29.9', 'Overweight', const Color(0xFFF9A825)),
      ('≥ 30', 'Obese', const Color(0xFFB71C1C)),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('BMI Scale Reference', style: AppTextStyles.h4),
          const SizedBox(height: 12),
          // Colored bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: const Row(
              children: [
                Expanded(child: SizedBox(height: 8, child: ColoredBox(color: Color(0xFF1565C0)))),
                Expanded(child: SizedBox(height: 8, child: ColoredBox(color: Color(0xFF2E7D32)))),
                Expanded(child: SizedBox(height: 8, child: ColoredBox(color: Color(0xFFF9A825)))),
                Expanded(child: SizedBox(height: 8, child: ColoredBox(color: Color(0xFFB71C1C)))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ...ranges.map((r) {
            final isActive = _inRange(bmi, r.$1);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isActive ? r.$3.withValues(alpha: 0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isActive ? Border.all(color: r.$3, width: 1.5) : null,
              ),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: r.$3, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Text(r.$1, style: AppTextStyles.labelSmall.copyWith(color: r.$3)),
                const SizedBox(width: 8),
                Text(r.$2, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
                if (isActive) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: r.$3, borderRadius: BorderRadius.circular(10)),
                    child: const Text('You', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ],
              ]),
            );
          }),
        ],
      ),
    );
  }

  bool _inRange(double b, String range) {
    if (range.contains('<')) return b < 18.5;
    if (range.contains('≥')) return b >= 30;
    if (range.contains('18.5')) return b >= 18.5 && b < 25;
    if (range.contains('25')) return b >= 25 && b < 30;
    return false;
  }
}

// ─── BMI History Section (Firestore-backed) ───────────────────────────────────

class _BmiHistorySection extends ConsumerWidget {
  final int currentAge;
  const _BmiHistorySection({required this.currentAge});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(bmiLogsProvider);
    return historyAsync.when(
      loading: () => Container(
        height: 140,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.appBorder),
        ),
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (logs) {
        if (logs.length < 2) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.appBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.show_chart_rounded, color: context.appTextHint, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    logs.isEmpty
                        ? 'Your BMI trend will appear here after you calculate on a couple of different days.'
                        : 'One reading saved so far — calculate again on another day to start your trend line.',
                    style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary, height: 1.4),
                  ),
                ),
              ],
            ),
          );
        }
        return _BmiHistoryChart(history: logs);
      },
    );
  }
}

class _BmiHistoryChart extends StatelessWidget {
  final List<BmiLogModel> history;
  const _BmiHistoryChart({required this.history});

  @override
  Widget build(BuildContext context) {
    // Provider returns newest-first; the chart reads oldest-to-newest left to right.
    final ordered = history.reversed.toList();
    final spots = ordered.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.bmi)).toList();
    final minY = (ordered.map((r) => r.bmi).reduce(math.min) - 2).floorToDouble().clamp(10.0, 40.0);
    final maxY = (ordered.map((r) => r.bmi).reduce(math.max) + 2).ceilToDouble().clamp(14.0, 50.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.show_chart_rounded, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            const Text('BMI History', style: AppTextStyles.h4),
            const Spacer(),
            Text('${ordered.length} ${ordered.length == 1 ? 'entry' : 'entries'}',
                style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (spots.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(color: context.appBorder, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx >= 0 && idx < ordered.length) {
                          final d = ordered[idx].loggedAt;
                          return Text('${d.day}/${d.month}', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                      final idx = s.x.toInt();
                      if (idx < 0 || idx >= ordered.length) return null;
                      final d = ordered[idx].loggedAt;
                      return LineTooltipItem(
                        '${d.day}/${d.month}\n${s.y.toStringAsFixed(1)} kg/m²',
                        const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    dotData: FlDotData(
                      getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                        radius: 4,
                        color: AppColors.primary,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [AppColors.primary.withValues(alpha: 0.2), AppColors.primary.withValues(alpha: 0)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Health Tips Card ─────────────────────────────────────────────────────────

class _HealthTipsCard extends StatelessWidget {
  final String category;
  final Color color;
  const _HealthTipsCard({required this.category, required this.color});

  @override
  Widget build(BuildContext context) {
    final tips = _kTips[category] ?? [];
    if (tips.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.lightbulb_rounded, color: color, size: 18),
            const SizedBox(width: 8),
            Text('Health Tips for $category', style: AppTextStyles.h4),
          ]),
          const SizedBox(height: 12),
          ...tips.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      '${e.key + 1}',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800, color: color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(e.value, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary, height: 1.5)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
