import 'package:flutter/material.dart';
import '../../../core/constants/app_text_styles.dart';

/// A circular ETA/countdown indicator — used on incoming request cards so
/// urgency reads visually (a shrinking ring) rather than just as text.
class CountdownRing extends StatelessWidget {
  final int minutes;
  final double progress; // 0..1, remaining fraction
  final Color color;
  final double size;

  const CountdownRing({
    super.key,
    required this.minutes,
    required this.progress,
    required this.color,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress.clamp(0, 1),
              strokeWidth: 4,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$minutes', style: AppTextStyles.labelLarge.copyWith(color: color, height: 1)),
              Text('min', style: AppTextStyles.caption.copyWith(color: color)),
            ],
          ),
        ],
      ),
    );
  }
}
