import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';

// ─── BMI data ─────────────────────────────────────────────────────────────────

class _BmiRecord {
  final DateTime date;
  final double bmi;
  const _BmiRecord(this.date, this.bmi);
}

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

// ─── Screen ───────────────────────────────────────────────────────────────────

class BmiCalculatorScreen extends StatefulWidget {
  const BmiCalculatorScreen({super.key});

  @override
  State<BmiCalculatorScreen> createState() => _BmiCalculatorScreenState();
}

class _BmiCalculatorScreenState extends State<BmiCalculatorScreen>
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

  // History (in-session mock data for chart)
  final List<_BmiRecord> _history = [
    _BmiRecord(DateTime.now().subtract(const Duration(days: 120)), 27.4),
    _BmiRecord(DateTime.now().subtract(const Duration(days: 90)),  26.8),
    _BmiRecord(DateTime.now().subtract(const Duration(days: 60)),  26.1),
    _BmiRecord(DateTime.now().subtract(const Duration(days: 30)),  25.3),
  ];

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
  }

  @override
  void dispose() {
    _resultAnim.dispose();
    super.dispose();
  }

  double get _heightForCalc => _useImperial ? _heightCm : _heightCm; // always stored in cm
  double get _weightForCalc => _weightKg; // always stored in kg

  void _calculate() {
    HapticFeedback.mediumImpact();
    final hm = _heightForCalc / 100;
    final bmi = _weightForCalc / (hm * hm);
    String cat = 'Normal';
    for (final r in _kRanges) {
      if (bmi >= r.min && bmi < r.max) { cat = r.label; break; }
    }
    setState(() {
      _bmi = bmi;
      _category = cat;
      _calculated = true;
    });
    _resultAnim.forward(from: 0);
    // Add to history
    _history.add(_BmiRecord(DateTime.now(), bmi));
  }

  Color get _categoryColor {
    for (final r in _kRanges) {
      if (r.label == _category) return r.color;
    }
    return AppColors.primary;
  }

  double get _idealWeightMin => 18.5 * (_heightCm / 100) * (_heightCm / 100);
  double get _idealWeightMax => 24.9 * (_heightCm / 100) * (_heightCm / 100);

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
                  _useImperial ? 'ft/lbs' : 'cm/kg',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
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
            // Gender Selector
            _GenderSelector(selected: _gender, onSelect: (g) => setState(() => _gender = g)),
            const SizedBox(height: 16),

            // Height
            _SliderCard(
              label: 'Height',
              displayValue: _useImperial
                  ? '${(_heightCm / 30.48).floor()}\' ${((_heightCm / 2.54) % 12).round()}"'
                  : '${_heightCm.toStringAsFixed(0)} cm',
              value: _heightCm,
              min: 100,
              max: 220,
              color: const Color(0xFF1565C0),
              minLabel: _useImperial ? '3\'3"' : '100 cm',
              maxLabel: _useImperial ? '7\'2"' : '220 cm',
              onChanged: (v) => setState(() => _heightCm = v),
            ),
            const SizedBox(height: 12),

            // Weight
            _SliderCard(
              label: 'Weight',
              displayValue: _useImperial
                  ? '${(_weightKg * 2.205).toStringAsFixed(1)} lbs'
                  : '${_weightKg.toStringAsFixed(1)} kg',
              value: _weightKg,
              min: 30,
              max: 200,
              color: const Color(0xFF2E7D32),
              minLabel: _useImperial ? '66 lbs' : '30 kg',
              maxLabel: _useImperial ? '441 lbs' : '200 kg',
              onChanged: (v) => setState(() => _weightKg = v),
            ),
            const SizedBox(height: 12),

            // Age
            _AgeStepperCard(
              age: _age,
              onMinus: () => setState(() { if (_age > 10) _age--; }),
              onPlus: () => setState(() { if (_age < 100) _age++; }),
            ),
            const SizedBox(height: 20),

            // Calculate Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.calculate_rounded, color: Colors.white),
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
                      // Big BMI result card with gauge
                      _BmiResultCard(
                        bmi: _bmi!,
                        category: _category,
                        categoryColor: _categoryColor,
                        idealMin: _idealWeightMin,
                        idealMax: _idealWeightMax,
                      ),
                      const SizedBox(height: 16),

                      // Scale bar
                      _BmiScaleBar(bmi: _bmi!),
                      const SizedBox(height: 16),

                      // History chart
                      if (_history.length >= 2) ...[
                        _BmiHistoryChart(history: _history),
                        const SizedBox(height: 16),
                      ],

                      // Health tips
                      _HealthTipsCard(category: _category, color: _categoryColor),
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
  Widget build(BuildContext context) => GestureDetector(
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
  );
}

// ─── Slider Card ──────────────────────────────────────────────────────────────

class _SliderCard extends StatelessWidget {
  final String label;
  final String displayValue;
  final double value;
  final double min;
  final double max;
  final Color color;
  final String minLabel;
  final String maxLabel;
  final ValueChanged<double> onChanged;
  const _SliderCard({
    required this.label,
    required this.displayValue,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.minLabel,
    required this.maxLabel,
    required this.onChanged,
  });

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
          children: [
            Text(label, style: AppTextStyles.labelLarge.copyWith(color: context.appTextSecondary)),
            Text(
              displayValue,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: color.withValues(alpha: 0.14),
            overlayColor: color.withValues(alpha: 0.1),
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
          ),
          child: Slider(value: value, min: min, max: max, divisions: ((max - min) * 2).toInt(), onChanged: onChanged),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(minLabel, style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
              Text(maxLabel, style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
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
  const _AgeStepperCard({required this.age, required this.onMinus, required this.onPlus});

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
        _AgeBtn(icon: Icons.remove_rounded, onTap: onMinus, color: const Color(0xFFE65100)),
        const SizedBox(width: 20),
        RichText(
          text: TextSpan(
            text: '$age',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFFE65100)),
            children: [
              TextSpan(text: ' yrs', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.appTextSecondary)),
            ],
          ),
        ),
        const SizedBox(width: 20),
        _AgeBtn(icon: Icons.add_rounded, onTap: onPlus, color: const Color(0xFFE65100)),
      ],
    ),
  );
}

class _AgeBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _AgeBtn({required this.icon, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); onTap(); },
    child: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Icon(icon, color: color, size: 20),
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
  const _BmiResultCard({required this.bmi, required this.category, required this.categoryColor, required this.idealMin, required this.idealMax});

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
        LayoutBuilder(
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: context.appBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
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
        ),
      ],
    ),
  );
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

// ─── BMI History Chart ────────────────────────────────────────────────────────

class _BmiHistoryChart extends StatelessWidget {
  final List<_BmiRecord> history;
  const _BmiHistoryChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final spots = history.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.bmi)).toList();
    final minY = (history.map((r) => r.bmi).reduce(math.min) - 2).floorToDouble().clamp(10.0, 40.0);
    final maxY = (history.map((r) => r.bmi).reduce(math.max) + 2).ceilToDouble().clamp(14.0, 50.0);

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
          const Row(children: [
            Icon(Icons.show_chart_rounded, color: AppColors.primary, size: 18),
            SizedBox(width: 8),
            Text('BMI History', style: AppTextStyles.h4),
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
                        if (idx >= 0 && idx < history.length) {
                          final d = history[idx].date;
                          return Text('${d.day}/${d.month}', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
