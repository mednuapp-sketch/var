import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Shown on a partner's own Profile screen whenever their profile has
/// `hasPendingChanges == true` — a self-edit was submitted while `status ==
/// 'active'` and is sitting in `pendingChanges`, waiting on an admin to
/// approve it (see `PendingProfileEditService`). Patients keep seeing the
/// last-approved version the whole time; this banner is purely so the
/// partner isn't confused about why their edit doesn't seem to have "taken".
class PendingReviewBanner extends StatelessWidget {
  const PendingReviewBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE0A3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.hourglass_top_rounded, size: 18, color: AppColors.warning),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile changes pending review',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF7A5B00)),
                ),
                SizedBox(height: 3),
                Text(
                  "You've submitted an edit and it's waiting on admin approval. Patients still see your "
                  "previous approved details until it's approved — this can take a little while.",
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFF7A5B00), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
