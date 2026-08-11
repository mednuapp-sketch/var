import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// A vertical pickup → drop route strip: two pins connected by a dashed
/// line, each with its own address line. Stands in for a real map
/// waypoint list without pulling in a maps SDK — this module is UI-first.
class RouteLine extends StatelessWidget {
  final String pickupAddress;
  final String dropAddress;

  const RouteLine({super.key, required this.pickupAddress, required this.dropAddress});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.success,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: AppColors.success.withValues(alpha: 0.4), blurRadius: 6)],
                  ),
                ),
                const Expanded(
                  child: CustomPaint(
                    painter: _DashedLinePainter(color: AppColors.border),
                    child: SizedBox(width: 2),
                  ),
                ),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: AppColors.error.withValues(alpha: 0.4), blurRadius: 6)],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PICKUP', style: AppTextStyles.caption.copyWith(letterSpacing: 0.6, color: AppColors.success)),
                      const SizedBox(height: 2),
                      Text(pickupAddress, style: AppTextStyles.labelLarge),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DROP-OFF', style: AppTextStyles.caption.copyWith(letterSpacing: 0.6, color: AppColors.error)),
                      const SizedBox(height: 2),
                      Text(dropAddress, style: AppTextStyles.labelLarge),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dashHeight = 4.0;
    const gap = 4.0;
    var y = 0.0;
    final x = size.width / 2;
    while (y < size.height) {
      canvas.drawLine(Offset(x, y), Offset(x, y + dashHeight), paint);
      y += dashHeight + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => oldDelegate.color != color;
}
