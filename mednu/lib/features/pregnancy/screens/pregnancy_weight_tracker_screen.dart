import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/pregnancy_models.dart';
import '../providers/pregnancy_provider.dart';

class PregnancyWeightTrackerScreen extends ConsumerStatefulWidget {
  const PregnancyWeightTrackerScreen({super.key});

  @override
  ConsumerState<PregnancyWeightTrackerScreen> createState() =>
      _PregnancyWeightTrackerScreenState();
}

class _PregnancyWeightTrackerScreenState
    extends ConsumerState<PregnancyWeightTrackerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pregnancyProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pregnancyProvider);

    if (state.isLoading) return _buildSkeleton();
    if (!state.hasProfile) return _buildNoProfile();

    return Scaffold(
      backgroundColor: const Color(0xFFFFF0F5),
      body: FadeTransition(
        opacity: _fadeCtrl,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(state.profile!),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _buildSummaryRow(state),
                  _buildRecommendedCard(state.profile!),
                  _buildTriSetsCard(state),
                  _buildChartCard(state),
                  _buildLogList(state),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddWeightSheet(context, state.profile!),
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Log Weight',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // -- App Bar ---------------------------------------------------------------

  SliverAppBar _buildAppBar(PregnancyProfile profile) => SliverAppBar(
        expandedHeight: R.h(context, 160),
        pinned: true,
        backgroundColor: const Color(0xFF7B1FA2),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => context.pop(),
        ),
        flexibleSpace: FlexibleSpaceBar(
          background: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF7B1FA2), Color(0xFFC2185B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 56), R.p(context, 20), R.p(context, 16)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Weight Tracker',
                              style: TextStyle(fontFamily: 'Poppins',
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'Week ${profile.currentWeek} � ${profile.trimesterLabel}',
                                  style: TextStyle(fontFamily: 'Poppins',
                                      color: Colors.white70, fontSize: 13),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${profile.daysUntilDue} days left',
                                    style: TextStyle(fontFamily: 'Poppins',
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

  // -- Summary Row -----------------------------------------------------------

  Widget _buildSummaryRow(PregnancyState state) {
    final profile = state.profile!;
    final gain = state.weightGainKg;
    final (minGain, maxGain) = profile.recommendedWeightGain;
    final isOverGain = gain > maxGain;
    final gainColor = isOverGain
        ? const Color(0xFFEF5350)
        : gain > 0
            ? const Color(0xFF66BB6A)
            : const Color(0xFF7B1FA2);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _summaryTile(
            label: 'Starting',
            value: '${profile.weightKg.toStringAsFixed(1)} kg',
            icon: Icons.flag_rounded,
            color: const Color(0xFF7B1FA2),
          ),
          const SizedBox(width: 10),
          _summaryTile(
            label: 'Current',
            value: state.weightLogs.isEmpty
                ? '${profile.weightKg.toStringAsFixed(1)} kg'
                : '${state.currentWeightKg.toStringAsFixed(1)} kg',
            icon: Icons.monitor_weight_rounded,
            color: const Color(0xFFC2185B),
          ),
          const SizedBox(width: 10),
          _summaryTile(
            label: isOverGain ? 'Over Gain' : 'Gained',
            value: gain > 0 ? '+${gain.toStringAsFixed(1)} kg' : '0.0 kg',
            icon: isOverGain
                ? Icons.trending_up_rounded
                : Icons.show_chart_rounded,
            color: gainColor,
          ),
        ],
      ),
    );
  }

  Widget _summaryTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(fontFamily: 'Poppins', 
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontFamily: 'Poppins', 
                  fontSize: 10,
                  color: context.appTextHint,
                ),
              ),
            ],
          ),
        ),
      );

  // -- Recommended Gain Card -------------------------------------------------

  Widget _buildRecommendedCard(PregnancyProfile profile) {
    final (minGain, maxGain) = profile.recommendedWeightGain;
    final bmi = profile.bmi;
    final bmiLabel = bmi == null
        ? 'Add height for BMI'
        : bmi < 18.5
            ? 'Underweight'
            : bmi < 25
                ? 'Normal weight'
                : bmi < 30
                    ? 'Overweight'
                    : 'Obese';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF7B1FA2).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF7B1FA2).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.recommend_rounded,
                color: Color(0xFF7B1FA2), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recommended Gain: ${minGain.toStringAsFixed(1)}�${maxGain.toStringAsFixed(1)} kg',
                  style: TextStyle(fontFamily: 'Poppins', 
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: const Color(0xFF4A148C),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  bmi != null
                      ? 'Pre-pregnancy BMI ${bmi.toStringAsFixed(1)} ($bmiLabel) � IOM 2009'
                      : 'IOM 2009 guidelines � $bmiLabel for accurate range',
                  style: TextStyle(fontFamily: 'Poppins', 
                    fontSize: 11,
                    color: const Color(0xFF7B1FA2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -- Trimester Weight Targets ----------------------------------------------

  Widget _buildTriSetsCard(PregnancyState state) {
    final profile = state.profile!;
    final (minGain, maxGain) = profile.recommendedWeightGain;
    final currentWeek = profile.currentWeek;
    final currentGain = state.weightGainKg;

    final trimesters = [
      _TriData(
        label: '1st Trimester',
        weeks: 'Wk 1�13',
        minKg: minGain * 0.1,
        maxKg: maxGain * 0.1,
        isCurrent: currentWeek <= 13,
      ),
      _TriData(
        label: '2nd Trimester',
        weeks: 'Wk 14�26',
        minKg: minGain * 0.35,
        maxKg: maxGain * 0.35,
        isCurrent: currentWeek > 13 && currentWeek <= 26,
      ),
      _TriData(
        label: '3rd Trimester',
        weeks: 'Wk 27�40',
        minKg: minGain * 0.55,
        maxKg: maxGain * 0.55,
        isCurrent: currentWeek > 26,
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_rounded,
                  color: Color(0xFF7B1FA2), size: 18),
              const SizedBox(width: 8),
              Text(
                'Trimester Weight Targets',
                style: TextStyle(fontFamily: 'Poppins', 
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: context.appTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: trimesters
                .map((t) => Expanded(child: _buildTriCard(t, currentGain)))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTriCard(_TriData tri, double currentGain) {
    final color = tri.isCurrent
        ? const Color(0xFFC2185B)
        : const Color(0xFF7B1FA2);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tri.isCurrent
            ? const Color(0xFFFCE4EC)
            : const Color(0xFFF3E5F5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: tri.isCurrent ? 0.35 : 0.15),
          width: tri.isCurrent ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tri.isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(bottom: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Current',
                style: TextStyle(fontFamily: 'Poppins', 
                  fontSize: 8,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Text(
            tri.label,
            style: TextStyle(fontFamily: 'Poppins', 
              fontWeight: FontWeight.w700,
              fontSize: 10,
              color: color,
            ),
          ),
          Text(
            tri.weeks,
            style: TextStyle(fontFamily: 'Poppins', 
              fontSize: 9,
              color: context.appTextHint,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${tri.minKg.toStringAsFixed(1)}�${tri.maxKg.toStringAsFixed(1)} kg',
            style: TextStyle(fontFamily: 'Poppins', 
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // -- Chart -----------------------------------------------------------------

  Widget _buildChartCard(PregnancyState state) {
    final logs = state.weightLogs.reversed.toList(); // oldest first
    final profile = state.profile!;
    final startWeight = profile.weightKg;

    final List<FlSpot> spots = [];
    if (logs.isEmpty) {
      spots.add(FlSpot(
          profile.currentWeek.toDouble().clamp(1.0, 40.0), startWeight));
    } else {
      final firstWeek = logs.first.pregnancyWeek.toDouble();
      if (firstWeek > 1) {
        spots.add(FlSpot(1, startWeight));
      }
      for (final log in logs) {
        spots.add(
            FlSpot(log.pregnancyWeek.toDouble().clamp(1.0, 40.0), log.weightKg));
      }
    }

    final (minGain, maxGain) = profile.recommendedWeightGain;

    final allWeights = spots.map((s) => s.y).toList()
      ..add(startWeight)
      ..add(startWeight + maxGain);
    final minY =
        (allWeights.reduce((a, b) => a < b ? a : b) - 2).floorToDouble();
    final maxY =
        (allWeights.reduce((a, b) => a > b ? a : b) + 2).ceilToDouble();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph_rounded,
                  color: Color(0xFF7B1FA2), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Weight Progress',
                  style: TextStyle(fontFamily: 'Poppins', 
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              _chartLegend(const Color(0xFFC2185B), 'Actual'),
              const SizedBox(width: 10),
              _chartLegend(
                  const Color(0xFF7B1FA2).withValues(alpha: 0.3), 'Range'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: logs.isEmpty
                ? _buildEmptyChart(startWeight, minGain, maxGain)
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 2,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: context.appBorder.withValues(alpha: 0.5),
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            interval: 2,
                            getTitlesWidget: (v, _) => Text(
                              v.toStringAsFixed(0),
                              style: TextStyle(
                                  fontSize: 9, color: context.appTextHint),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 5,
                            getTitlesWidget: (v, _) => Text(
                              'W${v.toInt()}',
                              style: TextStyle(
                                  fontSize: 9, color: context.appTextHint),
                            ),
                          ),
                        ),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      minX: 1,
                      maxX: 40,
                      minY: minY,
                      maxY: maxY,
                      lineBarsData: [
                        // Recommended upper band
                        LineChartBarData(
                          spots: [
                            FlSpot(1, startWeight),
                            FlSpot(40, startWeight + maxGain),
                          ],
                          isCurved: true,
                          color: const Color(0xFF7B1FA2)
                              .withValues(alpha: 0.25),
                          barWidth: 1.5,
                          dotData: const FlDotData(show: false),
                          dashArray: [4, 4],
                          belowBarData: BarAreaData(
                            show: true,
                            color: const Color(0xFF7B1FA2)
                                .withValues(alpha: 0.06),
                            spotsLine: BarAreaSpotsLine(show: false),
                          ),
                        ),
                        // Recommended lower band
                        LineChartBarData(
                          spots: [
                            FlSpot(1, startWeight),
                            FlSpot(40, startWeight + minGain),
                          ],
                          isCurved: true,
                          color: const Color(0xFF7B1FA2)
                              .withValues(alpha: 0.25),
                          barWidth: 1.5,
                          dotData: const FlDotData(show: false),
                          dashArray: [4, 4],
                        ),
                        // Actual weight line
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          curveSmoothness: 0.35,
                          color: const Color(0xFFC2185B),
                          barWidth: 2.5,
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, _, __, ___) =>
                                FlDotCirclePainter(
                              radius: 4,
                              color: const Color(0xFFC2185B),
                              strokeWidth: 2,
                              strokeColor: Colors.white,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFC2185B)
                                    .withValues(alpha: 0.15),
                                const Color(0xFFC2185B)
                                    .withValues(alpha: 0.0),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touchedSpots) =>
                              touchedSpots.map((s) {
                            if (s.barIndex != 2) return null;
                            return LineTooltipItem(
                              'W${s.x.toInt()}\n${s.y.toStringAsFixed(1)} kg',
                              TextStyle(fontFamily: 'Poppins', 
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Wk ${profile.currentWeek} / 40  �  Shaded band = recommended range',
              style: TextStyle(fontFamily: 'Poppins', 
                  fontSize: 10, color: context.appTextHint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChart(double startWeight, double minGain, double maxGain) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.show_chart_rounded,
            size: 40,
            color: const Color(0xFF7B1FA2).withValues(alpha: 0.3),
          ),
          const SizedBox(height: 10),
          Text(
            'Log your first weight entry',
            style: TextStyle(fontFamily: 'Poppins', 
              fontWeight: FontWeight.w600,
              color: context.appTextSecondary,
              fontSize: 13,
            ),
          ),
          Text(
            'Your weight chart will appear here',
            style: TextStyle(fontFamily: 'Poppins', 
              color: context.appTextHint,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartLegend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: context.appTextHint)),
        ],
      );

  // -- Log List --------------------------------------------------------------

  Widget _buildLogList(PregnancyState state) {
    final logs = state.weightLogs;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded,
                  color: Color(0xFF7B1FA2), size: 18),
              const SizedBox(width: 8),
              Text(
                'Weight Log',
                style: TextStyle(fontFamily: 'Poppins', 
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: context.appTextPrimary,
                ),
              ),
              const Spacer(),
              if (logs.isNotEmpty)
                Text(
                  '${logs.length} ${logs.length == 1 ? 'entry' : 'entries'}',
                  style: TextStyle(fontFamily: 'Poppins', 
                      fontSize: 11, color: context.appTextHint),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (logs.isEmpty)
            _emptyLogState()
          else
            Column(
              children: logs
                  .take(20)
                  .map((log) => _buildLogTile(log, state.profile!))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _emptyLogState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF7B1FA2).withValues(alpha: 0.12),
                    const Color(0xFFC2185B).withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.monitor_weight_outlined,
                  color: Color(0xFF7B1FA2), size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              'No weight logs yet',
              style: TextStyle(fontFamily: 'Poppins', 
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap "Log Weight" below to record\nyour first pregnancy weight entry.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', 
                fontSize: 12,
                color: context.appTextHint,
                height: 1.6,
              ),
            ),
          ],
        ),
      );

  Widget _buildLogTile(PregnancyWeightLog log, PregnancyProfile profile) {
    final diff = log.weightKg - profile.weightKg;
    final diffLabel =
        diff > 0 ? '+${diff.toStringAsFixed(1)} kg' : '${diff.toStringAsFixed(1)} kg';
    final diffColor =
        diff > 0 ? const Color(0xFF66BB6A) : const Color(0xFF7B1FA2);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF7B1FA2).withValues(alpha: 0.15),
                  const Color(0xFFC2185B).withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'W${log.pregnancyWeek}',
                  style: TextStyle(fontFamily: 'Poppins', 
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF7B1FA2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${log.weightKg.toStringAsFixed(1)} kg',
                  style: TextStyle(fontFamily: 'Poppins', 
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                Text(
                  DateFormat('dd MMM yyyy').format(log.loggedAt),
                  style: TextStyle(fontFamily: 'Poppins', 
                      fontSize: 11, color: context.appTextHint),
                ),
                if (log.notes.isNotEmpty)
                  Text(
                    log.notes,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Poppins', 
                        fontSize: 11,
                        color: context.appTextSecondary,
                        fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                diffLabel,
                style: TextStyle(fontFamily: 'Poppins', 
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: diffColor,
                ),
              ),
              Text(
                'from start',
                style: TextStyle(fontFamily: 'Poppins', 
                    fontSize: 9, color: context.appTextHint),
              ),
            ],
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _confirmDelete(log.id),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.delete_outline_rounded,
                  size: 18, color: context.appTextHint),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(String logId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Entry'),
        content: const Text('Remove this weight log entry?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(pregnancyProvider.notifier).deleteWeightLog(logId);
    }
  }

  // -- Add Weight Bottom Sheet -----------------------------------------------

  void _showAddWeightSheet(BuildContext context, PregnancyProfile profile) {
    final weightCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: context.appSurface,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: context.appBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7B1FA2)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.monitor_weight_rounded,
                              color: Color(0xFF7B1FA2), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Log Weight',
                              style: TextStyle(fontFamily: 'Poppins', 
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: context.appTextPrimary,
                              ),
                            ),
                            Text(
                              'Week ${profile.currentWeek} � ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
                              style: TextStyle(fontFamily: 'Poppins', 
                                fontSize: 11,
                                color: context.appTextHint,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Weight field
                    TextFormField(
                      controller: weightCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                      style: TextStyle(fontFamily: 'Poppins', 
                          fontSize: 24, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        labelText: 'Weight (kg)',
                        labelStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13),
                        suffixText: 'kg',
                        suffixStyle: TextStyle(fontFamily: 'Poppins', 
                          fontSize: 16,
                          color: context.appTextHint,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF7F4F8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.appBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.appBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF7B1FA2), width: 2),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.red),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Colors.red, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Please enter your weight';
                        }
                        final w = double.tryParse(v);
                        if (w == null || w < 20 || w > 200) {
                          return 'Enter a valid weight (20�200 kg)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    // Notes field
                    TextFormField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Notes (optional)',
                        hintText: 'e.g. After morning meal, fasting',
                        labelStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13),
                        hintStyle: TextStyle(fontFamily: 'Poppins', 
                            fontSize: 12, color: context.appTextHint),
                        filled: true,
                        fillColor: const Color(0xFFF7F4F8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.appBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.appBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF7B1FA2), width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Save button
                    Consumer(builder: (bCtx, bRef, _) {
                      final loading =
                          bRef.watch(pregnancyProvider).isLoading;
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: loading
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) {
                                    return;
                                  }
                                  final ok = await bRef
                                      .read(pregnancyProvider.notifier)
                                      .addWeightLog(
                                        weightKg: double.parse(
                                            weightCtrl.text),
                                        notes: notesCtrl.text.trim(),
                                      );
                                  if (!bCtx.mounted) return;
                                  Navigator.pop(bCtx);
                                  if (!ok && mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Failed to save. Please try again.')),
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7B1FA2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            textStyle: TextStyle(fontFamily: 'Poppins', 
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          child: loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : const Text('Save Weight Entry'),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // -- Skeleton --------------------------------------------------------------

  Widget _buildSkeleton() => Scaffold(
        backgroundColor: const Color(0xFFFFF0F5),
        body: AppShimmer(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const SizedBox(height: 160),
                Row(
                  children: List.generate(
                    3,
                    (_) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: SkeletonBox(
                            width: double.infinity, height: 80, radius: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const SkeletonBox(
                    width: double.infinity, height: 60, radius: 14),
                const SizedBox(height: 12),
                const SkeletonBox(
                    width: double.infinity, height: 80, radius: 14),
                const SizedBox(height: 12),
                const SkeletonBox(
                    width: double.infinity, height: 240, radius: 16),
                const SizedBox(height: 12),
                ...List.generate(
                  4,
                  (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: SkeletonBox(
                        width: double.infinity, height: 64, radius: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  // -- No Profile ------------------------------------------------------------

  Widget _buildNoProfile() => Scaffold(
        backgroundColor: const Color(0xFFFFF0F5),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Color(0xFF880E4F), size: 20),
            onPressed: () => context.pop(),
          ),
          title: Text(
            'Weight Tracker',
            style: TextStyle(fontFamily: 'Poppins', 
              color: context.appTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B1FA2).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.monitor_weight_rounded,
                      color: Color(0xFF7B1FA2), size: 40),
                ),
                const SizedBox(height: 20),
                Text(
                  'No Pregnancy Profile',
                  style: TextStyle(fontFamily: 'Poppins', 
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Set up your pregnancy profile first to start tracking your weight journey.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', 
                    color: context.appTextHint,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle:
                        TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
}

// --- Trimester data model -----------------------------------------------------

class _TriData {
  final String label;
  final String weeks;
  final double minKg;
  final double maxKg;
  final bool isCurrent;

  const _TriData({
    required this.label,
    required this.weeks,
    required this.minKg,
    required this.maxKg,
    required this.isCurrent,
  });
}
