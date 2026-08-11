import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// Mon..Sun bar chart for the Earnings screen — reuses `fl_chart`, already
/// a dependency. Kept local to this module (same reasoning as
/// `DutyPulse`) rather than importing the Ambulance module's chart widget.
class WeeklyEarningsChart extends StatelessWidget {
  final List<double> values;
  const WeeklyEarningsChart({super.key, required this.values});

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final maxVal = values.isEmpty ? 100.0 : (values.reduce((a, b) => a > b ? a : b) * 1.25);
    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxVal,
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= _days.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_days[i], style: AppTextStyles.caption),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: AppColors.primaryDark,
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                '₹${rod.toY.toInt()}',
                const TextStyle(color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ),
          barGroups: [
            for (int i = 0; i < values.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i],
                    width: 18,
                    borderRadius: BorderRadius.circular(6),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00695C), Color(0xFF00897B)],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
