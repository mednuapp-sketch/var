import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../data/pregnancy_week_data.dart';
import '../providers/pregnancy_provider.dart';

class PregnancyNutritionScreen extends ConsumerStatefulWidget {
  const PregnancyNutritionScreen({super.key});

  @override
  ConsumerState<PregnancyNutritionScreen> createState() =>
      _PregnancyNutritionScreenState();
}

class _PregnancyNutritionScreenState
    extends ConsumerState<PregnancyNutritionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(pregnancyProvider).profile;
    final week = profile?.currentWeek ?? 12;
    final trimester = week <= 13 ? 1 : week <= 26 ? 2 : 3;
    final data = getWeekData(week);

    return Scaffold(
      backgroundColor: const Color(0xFFF5FBF0),
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.appTextPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nutrition Guide',
              style: TextStyle(
                  color: context.appTextPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
            Text(
              'Week $week · Trimester $trimester',
              style: TextStyle(
                  color: context.appTextHint, fontSize: 11),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                  bottom: BorderSide(color: context.appBorder, width: 1)),
            ),
            child: TabBar(
              controller: _tab,
              labelColor: const Color(0xFF2E7D32),
              unselectedLabelColor: context.appTextHint,
              indicatorColor: const Color(0xFF2E7D32),
              indicatorWeight: 2.5,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 12),
              unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 12),
              tabs: const [
                Tab(
                  child: Text('Overview',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Tab(
                  child: Text('Foods',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Tab(
                  child: Text('Nutrients',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildOverviewTab(week, trimester, data),
          _buildFoodsTab(data),
          _buildNutrientsTab(data),
        ],
      ),
    );
  }

  // ── Overview Tab ──────────────────────────────────────────────────────────

  Widget _buildOverviewTab(
      int week, int trimester, WeeklyPregnancyData data) {
    final extraCals =
        trimester == 1 ? 0 : trimester == 2 ? 300 : 450;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero banner
          _HeroBanner(week: week, trimester: trimester, tip: data.nutritionTip),
          const SizedBox(height: 16),

          // Macros chart card
          _MacroPieCard(trimester: trimester),
          const SizedBox(height: 16),

          // Daily targets grid
          _DailyTargetsCard(trimester: trimester, extraCals: extraCals),
          const SizedBox(height: 16),

          // Weekly tip
          _WeeklyTipCard(tip: data.weeklyTip),
          const SizedBox(height: 16),

          // Mother changes this week
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🤰', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Text('How You May Feel',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: context.appTextPrimary)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  data.motherChanges,
                  style: TextStyle(
                      fontSize: 13,
                      color: context.appTextSecondary,
                      height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Foods Tab ─────────────────────────────────────────────────────────────

  Widget _buildFoodsTab(WeeklyPregnancyData data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FoodSection(
            title: 'Eat More Of These',
            subtitle: 'Nourishing foods for you and baby',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF2E7D32),
            bgColor: const Color(0xFFF1F8E9),
            foods: data.foodsToEat,
            emoji: '✅',
          ),
          const SizedBox(height: 16),
          _FoodSection(
            title: 'Foods to Avoid',
            subtitle: 'Keep you and baby safe',
            icon: Icons.cancel_rounded,
            color: const Color(0xFFB71C1C),
            bgColor: const Color(0xFFFFEBEE),
            foods: data.foodsToAvoid,
            emoji: '❌',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFFFFA000).withValues(alpha: 0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('⚠️', style: TextStyle(fontSize: 18)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Always consult your doctor before making major dietary changes during pregnancy.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFE65100),
                        height: 1.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Nutrients Tab ─────────────────────────────────────────────────────────

  Widget _buildNutrientsTab(WeeklyPregnancyData data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF3E5F5), Color(0xFFFCE4EC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Text('🔬', style: TextStyle(fontSize: 22)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Key Nutrients This Week',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Color(0xFF4A148C))),
                      SizedBox(height: 2),
                      Text('Focus on these for optimal development',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF7B1FA2))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ...data.keyNutrients.map((n) => _NutrientCard(nutrient: n)),
        ],
      ),
    );
  }
}

// ─── Hero Banner ──────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  final int week;
  final int trimester;
  final String tip;
  const _HeroBanner(
      {required this.week, required this.trimester, required this.tip});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
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
              const Text('🥗', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trimester $trimester Nutrition',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      'Week $week Plan',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Personalized',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              tip,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Macro Pie Card ───────────────────────────────────────────────────────────

class _MacroPieCard extends StatefulWidget {
  final int trimester;
  const _MacroPieCard({required this.trimester});

  @override
  State<_MacroPieCard> createState() => _MacroPieCardState();
}

class _MacroPieCardState extends State<_MacroPieCard> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    // Macro distribution: carbs, protein, fat
    final macros = [
      _MacroData('Carbohydrates', 50, const Color(0xFF43A047)),
      _MacroData('Protein', 25, const Color(0xFFC2185B)),
      _MacroData('Healthy Fats', 25, const Color(0xFF7B1FA2)),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_rounded,
                  color: Color(0xFF2E7D32), size: 18),
              const SizedBox(width: 8),
              Text('Macro Distribution',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: context.appTextPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Recommended daily balance',
            style: TextStyle(fontSize: 11, color: context.appTextHint),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Pie chart
              SizedBox(
                height: 140,
                width: 140,
                child: PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(
                      touchCallback: (event, pieTouchResponse) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            _touchedIndex = -1;
                          } else {
                            _touchedIndex = pieTouchResponse
                                .touchedSection!.touchedSectionIndex;
                          }
                        });
                      },
                    ),
                    borderData: FlBorderData(show: false),
                    sectionsSpace: 2,
                    centerSpaceRadius: 32,
                    sections: macros.asMap().entries.map((e) {
                      final isTouched = e.key == _touchedIndex;
                      return PieChartSectionData(
                        value: e.value.percent.toDouble(),
                        color: e.value.color,
                        radius: isTouched ? 38 : 30,
                        title: '${e.value.percent}%',
                        titleStyle: TextStyle(
                          fontSize: isTouched ? 12 : 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Legend
              Expanded(
                child: Column(
                  children: macros
                      .map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: m.color,
                                    borderRadius:
                                        BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(m.name,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight:
                                                  FontWeight.w600)),
                                      Text('${m.percent}% of calories',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color:
                                                  context.appTextHint)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacroData {
  final String name;
  final int percent;
  final Color color;
  const _MacroData(this.name, this.percent, this.color);
}

// ─── Daily Targets Card ───────────────────────────────────────────────────────

class _DailyTargetsCard extends StatelessWidget {
  final int trimester;
  final int extraCals;
  const _DailyTargetsCard(
      {required this.trimester, required this.extraCals});

  @override
  Widget build(BuildContext context) {
    final targets = [
      _TargetItem('💧', 'Water', '8–10\nglasses', const Color(0xFF1976D2)),
      _TargetItem('🥩', 'Protein', '71g\n/day', const Color(0xFFC2185B)),
      _TargetItem('🦴', 'Calcium', '1000mg\n/day', const Color(0xFF0097A7)),
      _TargetItem('🔥', 'Extra Cal',
          extraCals > 0 ? '+${extraCals}kcal' : '—', const Color(0xFFE65100)),
      _TargetItem('💊', 'Iron', '27mg\n/day', const Color(0xFFB71C1C)),
      _TargetItem('🧬', 'Folate', '600mcg\n/day', const Color(0xFF7B1FA2)),
      _TargetItem('☀️', 'Vitamin D', '600IU\n/day', const Color(0xFFFFA000)),
      _TargetItem('🐟', 'Omega-3', '200mg\nDHA', const Color(0xFF00695C)),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.track_changes_rounded,
                  color: Color(0xFF2E7D32), size: 18),
              SizedBox(width: 8),
              Text('Daily Nutrition Targets',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 14),
          staticGrid(
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 8,
            aspectRatio: 0.85,
            children: targets.map((t) => _TargetCell(item: t)).toList(),
          ),
        ],
      ),
    );
  }
}

class _TargetItem {
  final String emoji, label, value;
  final Color color;
  const _TargetItem(this.emoji, this.label, this.value, this.color);
}

class _TargetCell extends StatelessWidget {
  final _TargetItem item;
  const _TargetCell({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: item.color.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(item.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            item.value,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: item.color,
                height: 1.3),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
                fontSize: 9, color: context.appTextHint),
          ),
        ],
      ),
    );
  }
}

// ─── Weekly Tip Card ──────────────────────────────────────────────────────────

class _WeeklyTipCard extends StatelessWidget {
  final String tip;
  const _WeeklyTipCard({required this.tip});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFCE4EC), Color(0xFFF3E5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('💡', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text("This Week's Nutrition Tip",
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF880E4F))),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            tip,
            style: const TextStyle(
                fontSize: 13,
                height: 1.65,
                color: Color(0xFF4A148C)),
          ),
        ],
      ),
    );
  }
}

// ─── Food Section ─────────────────────────────────────────────────────────────

class _FoodSection extends StatelessWidget {
  final String title, subtitle, emoji;
  final IconData icon;
  final Color color, bgColor;
  final List<String> foods;

  const _FoodSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.foods,
    required this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: color)),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 11,
                            color: context.appTextHint)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: foods
                .map((f) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: color.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(emoji,
                              style: const TextStyle(fontSize: 11)),
                          const SizedBox(width: 5),
                          Text(f,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: color,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Nutrient Card ────────────────────────────────────────────────────────────

class _NutrientCard extends StatelessWidget {
  final String nutrient;
  const _NutrientCard({required this.nutrient});

  static const _data = {
    'Folic Acid': (
      '🧬',
      'Prevents neural tube defects',
      '600 mcg/day',
      Color(0xFF7B1FA2)
    ),
    'Iron': (
      '💪',
      'Supports increased blood volume',
      '27 mg/day',
      Color(0xFFB71C1C)
    ),
    'Calcium': (
      '🦴',
      'Builds strong bones and teeth',
      '1000 mg/day',
      Color(0xFF1565C0)
    ),
    'Vitamin D': (
      '☀️',
      'Helps absorb calcium effectively',
      '600 IU/day',
      Color(0xFFF57F17)
    ),
    'Omega-3': (
      '🐟',
      'Supports brain & eye development',
      '200 mg DHA',
      Color(0xFF00695C)
    ),
    'Protein': (
      '🥩',
      "Builds baby's muscles and organs",
      '71 g/day',
      Color(0xFF2E7D32)
    ),
    'Vitamin B6': (
      '🌿',
      'Reduces morning sickness',
      '1.9 mg/day',
      Color(0xFF43A047)
    ),
    'Magnesium': (
      '⚡',
      'Reduces leg cramps, supports sleep',
      '350 mg/day',
      Color(0xFF0097A7)
    ),
    'Fiber': (
      '🥦',
      'Prevents constipation',
      '28 g/day',
      Color(0xFF558B2F)
    ),
    'Vitamin C': (
      '🍊',
      'Immune support & iron absorption',
      '85 mg/day',
      Color(0xFFE65100)
    ),
    'Vitamin K': (
      '🥬',
      'Blood clotting support for delivery',
      '90 mcg/day',
      Color(0xFF33691E)
    ),
    'Hydration': (
      '💧',
      'Essential for all body functions',
      '8–10 glasses',
      Color(0xFF1976D2)
    ),
    'Electrolytes': (
      '⚡',
      'Energy & hydration balance',
      'As needed',
      Color(0xFFFFA000)
    ),
    'Ginger': (
      '🫚',
      'Natural nausea & vomiting relief',
      '250 mg cap',
      Color(0xFF6D4C41)
    ),
  };

  @override
  Widget build(BuildContext context) {
    final info =
        _data[nutrient] ?? ('💊', 'Important for your pregnancy', 'Daily', const Color(0xFF7B1FA2));
    final color = info.$4;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child:
                Center(child: Text(info.$1, style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nutrient,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(info.$2,
                    style: TextStyle(
                        fontSize: 11,
                        color: context.appTextSecondary,
                        height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(info.$3,
                style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
