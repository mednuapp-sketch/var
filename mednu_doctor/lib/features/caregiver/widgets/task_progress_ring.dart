import 'package:flutter/material.dart';
import '../../../core/constants/app_text_styles.dart';

/// A circular completion indicator for the Task Checklist screen — reads
/// "3/4 done" as a filling ring rather than plain text, matching the
/// countdown-ring treatment the Ambulance module uses for urgency.
class TaskProgressRing extends StatelessWidget {
  final int completed;
  final int total;
  final Color color;
  final double size;

  const TaskProgressRing({
    super.key,
    required this.completed,
    required this.total,
    required this.color,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: 6,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$completed/$total', style: AppTextStyles.labelLarge.copyWith(color: color, height: 1)),
              Text('done', style: AppTextStyles.caption.copyWith(color: color)),
            ],
          ),
        ],
      ),
    );
  }
}
