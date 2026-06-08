import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';

class BmiCalculatorScreen extends StatefulWidget {
  const BmiCalculatorScreen({super.key});

  @override
  State<BmiCalculatorScreen> createState() => _BmiCalculatorScreenState();
}

class _BmiCalculatorScreenState extends State<BmiCalculatorScreen> {
  double _height = 165; // cm
  double _weight = 65; // kg
  String _gender = 'male';
  int _age = 25;
  double? _bmi;
  String? _category;
  Color? _categoryColor;

  void _calculate() {
    final heightM = _height / 100;
    final bmi = _weight / (heightM * heightM);
    setState(() {
      _bmi = bmi;
      if (bmi < 18.5) { _category = 'Underweight'; _categoryColor = const Color(0xFF1565C0); }
      else if (bmi < 25) { _category = 'Normal Weight'; _categoryColor = const Color(0xFF2E7D32); }
      else if (bmi < 30) { _category = 'Overweight'; _categoryColor = const Color(0xFFF9A825); }
      else { _category = 'Obese'; _categoryColor = const Color(0xFFB71C1C); }
    });
  }

  double get _idealWeightMin => 18.5 * (_height / 100) * (_height / 100);
  double get _idealWeightMax => 24.9 * (_height / 100) * (_height / 100);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
        title: const Text('BMI Calculator', style: AppTextStyles.h3),
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
            _GenderSelector(selected: _gender, onSelect: (g) => setState(() => _gender = g)),
            const SizedBox(height: 16),
            _SliderCard(
              label: 'Height',
              value: _height,
              min: 100,
              max: 220,
              unit: 'cm',
              color: const Color(0xFF1565C0),
              onChanged: (v) => setState(() => _height = v),
            ),
            const SizedBox(height: 12),
            _SliderCard(
              label: 'Weight',
              value: _weight,
              min: 30,
              max: 200,
              unit: 'kg',
              color: const Color(0xFF2E7D32),
              onChanged: (v) => setState(() => _weight = v),
            ),
            const SizedBox(height: 12),
            _AgeCard(age: _age, onMinus: () => setState(() { if (_age > 10) _age--; }), onPlus: () => setState(() { if (_age < 100) _age++; })),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _calculate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Calculate BMI', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
              ),
            ),
            if (_bmi != null) ...[
              const SizedBox(height: 24),
              _ResultCard(
                bmi: _bmi!,
                category: _category!,
                categoryColor: _categoryColor!,
                idealMin: _idealWeightMin,
                idealMax: _idealWeightMax,
              ),
              const SizedBox(height: 16),
              _BmiScaleChart(bmi: _bmi!),
              const SizedBox(height: 16),
              _HealthTipsCard(category: _category!),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _GenderSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _GenderSelector({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _GenderCard(
          icon: Icons.male_rounded,
          label: 'Male',
          isSelected: selected == 'male',
          color: const Color(0xFF1565C0),
          onTap: () => onSelect('male'),
        )),
        const SizedBox(width: 12),
        Expanded(child: _GenderCard(
          icon: Icons.female_rounded,
          label: 'Female',
          isSelected: selected == 'female',
          color: const Color(0xFFC2185B),
          onTap: () => onSelect('female'),
        )),
      ],
    );
  }
}

class _GenderCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;
  const _GenderCard({required this.icon, required this.label, required this.isSelected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? color : AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : color, size: 32),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : color)),
          ],
        ),
      ),
    );
  }
}

class _SliderCard extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final Color color;
  final ValueChanged<double> onChanged;
  const _SliderCard({required this.label, required this.value, required this.min, required this.max, required this.unit, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: AppTextStyles.labelLarge),
              RichText(
                text: TextSpan(
                  text: value.toStringAsFixed(label == 'Weight' ? 1 : 0),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 24, fontWeight: FontWeight.w800, color: color),
                  children: [TextSpan(text: ' $unit', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: color.withOpacity(0.7)))],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              thumbColor: color,
              inactiveTrackColor: color.withOpacity(0.15),
              overlayColor: color.withOpacity(0.12),
              trackHeight: 6,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: ((max - min) * 2).toInt(),
              onChanged: onChanged,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${min.toInt()} $unit', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
              Text('${max.toInt()} $unit', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgeCard extends StatelessWidget {
  final int age;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _AgeCard({required this.age, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Age', style: AppTextStyles.labelLarge),
          Row(
            children: [
              _RoundBtn(icon: Icons.remove_rounded, onTap: onMinus, color: const Color(0xFFE65100)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: RichText(
                  text: TextSpan(
                    text: '$age',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFFE65100)),
                    children: const [TextSpan(text: ' yrs', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Color(0xFFE65100)))],
                  ),
                ),
              ),
              _RoundBtn(icon: Icons.add_rounded, onTap: onPlus, color: const Color(0xFFE65100)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _RoundBtn({required this.icon, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle, border: Border.all(color: color.withOpacity(0.3))),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final double bmi;
  final String category;
  final Color categoryColor;
  final double idealMin;
  final double idealMax;
  const _ResultCard({required this.bmi, required this.category, required this.categoryColor, required this.idealMin, required this.idealMax});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: categoryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: categoryColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text('Your BMI', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(bmi.toStringAsFixed(1), style: TextStyle(fontFamily: 'Poppins', fontSize: 56, fontWeight: FontWeight.w900, color: categoryColor, height: 1)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(color: categoryColor, borderRadius: BorderRadius.circular(20)),
            child: Text(category, style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text('Ideal weight: ${idealMin.toStringAsFixed(1)} – ${idealMax.toStringAsFixed(1)} kg', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BmiScaleChart extends StatelessWidget {
  final double bmi;
  const _BmiScaleChart({required this.bmi});

  @override
  Widget build(BuildContext context) {
    const ranges = [
      ('< 18.5', 'Underweight', Color(0xFF1565C0)),
      ('18.5–24.9', 'Normal', Color(0xFF2E7D32)),
      ('25–29.9', 'Overweight', Color(0xFFF9A825)),
      ('≥ 30', 'Obese', Color(0xFFB71C1C)),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BMI Scale', style: AppTextStyles.h4),
          const SizedBox(height: 12),
          ...ranges.map((r) {
            final isActive = _isInRange(bmi, r.$1);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isActive ? r.$3.withOpacity(0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isActive ? Border.all(color: r.$3, width: 1.5) : null,
              ),
              child: Row(
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: r.$3, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Text(r.$1, style: AppTextStyles.labelSmall.copyWith(color: r.$3)),
                  const SizedBox(width: 8),
                  Text(r.$2, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                  if (isActive) ...[
                    const Spacer(),
                    const Icon(Icons.arrow_left_rounded, color: AppColors.textSecondary, size: 20),
                    Text('You', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  bool _isInRange(double bmi, String range) {
    if (range.contains('<')) return bmi < 18.5;
    if (range.contains('≥')) return bmi >= 30;
    if (range.contains('18.5')) return bmi >= 18.5 && bmi < 25;
    if (range.contains('25')) return bmi >= 25 && bmi < 30;
    return false;
  }
}

class _HealthTipsCard extends StatelessWidget {
  final String category;
  const _HealthTipsCard({required this.category});

  static const _tips = {
    'Underweight': [
      'Eat more nutrient-dense foods',
      'Increase protein & healthy fat intake',
      'Consider consulting a nutritionist',
      'Avoid skipping meals',
    ],
    'Normal Weight': [
      'Maintain your balanced diet',
      'Stay physically active',
      'Focus on whole grains, fruits & veggies',
      'Stay well hydrated',
    ],
    'Overweight': [
      'Reduce processed foods and sugar',
      'Increase physical activity to 30 min/day',
      'Eat more fiber-rich foods',
      'Consult a dietitian for a plan',
    ],
    'Obese': [
      'Consult a doctor or dietitian urgently',
      'Set small, realistic weight-loss goals',
      'Reduce calorie-dense junk foods',
      'Track your meals daily',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final tips = _tips[category] ?? [];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Health Tips', style: AppTextStyles.h4),
          const SizedBox(height: 10),
          ...tips.map((tip) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF2E7D32), size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(tip, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, height: 1.4))),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
