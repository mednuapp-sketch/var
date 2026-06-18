import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/doctor_review.dart';
import '../services/review_service.dart';

class SubmitReviewScreen extends StatefulWidget {
  final String appointmentId;
  final String doctorId;
  final String doctorName;
  final String doctorSpecialty;
  final String consultationType;

  const SubmitReviewScreen({
    super.key,
    required this.appointmentId,
    required this.doctorId,
    required this.doctorName,
    required this.doctorSpecialty,
    required this.consultationType,
  });

  @override
  State<SubmitReviewScreen> createState() => _SubmitReviewScreenState();
}

class _SubmitReviewScreenState extends State<SubmitReviewScreen>
    with SingleTickerProviderStateMixin {
  double _overallRating = 0;
  double _communication = 0;
  double _treatment = 0;
  double _waitTime = 0;
  double _professionalism = 0;
  double _helpfulness = 0;

  final _textController = TextEditingController();
  bool _submitting = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _scaleAnim =
        CurvedAnimation(parent: _animController, curve: Curves.elasticOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _textController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_overallRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a star rating before submitting'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _submitting = true);

    try {
      await ReviewService.submitReview(
        appointmentId: widget.appointmentId,
        doctorId: widget.doctorId,
        rating: _overallRating,
        reviewText: _textController.text.trim(),
        categories: ReviewCategories(
          communication: _communication,
          treatment: _treatment,
          waitTime: _waitTime,
          professionalism: _professionalism,
          helpfulness: _helpfulness,
        ),
        consultationType: widget.consultationType,
      );

      if (mounted) _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        final msg = e.toString();
        final isAlreadyReviewed = msg.contains('already_reviewed');
        final isPermission = msg.contains('PERMISSION_DENIED') || msg.contains('permission-denied');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isAlreadyReviewed
              ? 'You have already reviewed this appointment.'
              : isPermission
                  ? 'Permission error. Please log out and log in again.'
                  : 'Error: $msg'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
        ));
      }
    }
  }

  void _showSuccessDialog() {
    _animController.reset();
    _animController.forward();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ScaleTransition(
              scale: _scaleAnim,
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                    color: Color(0xFFE8F5E9), shape: BoxShape.circle),
                child: const Icon(Icons.star_rounded,
                    color: Color(0xFF2E7D32), size: 40),
              ),
            ),
            const SizedBox(height: 20),
            Text('Review Submitted!',
                style: AppTextStyles.h3
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Thank you for sharing your experience with ${widget.doctorName}. Your feedback helps other patients.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context, true);
                },
                child: const Text('Done'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Rate Your Experience'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Doctor card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.person_rounded,
                    size: 28, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(widget.doctorName,
                      style: AppTextStyles.labelLarge),
                  Text(widget.doctorSpecialty,
                      style: AppTextStyles.bodySmall),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.verified_rounded,
                          size: 12, color: AppColors.accent),
                      const SizedBox(width: 4),
                      Text('Verified Consultation',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.accent)),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // Overall star rating
          Text('Overall Rating', style: AppTextStyles.h4),
          const SizedBox(height: 4),
          Text('How would you rate your overall experience?',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Center(
            child: _StarRatingRow(
              rating: _overallRating,
              size: 44,
              onChanged: (v) => setState(() => _overallRating = v),
            ),
          ),
          if (_overallRating > 0) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(_ratingLabel(_overallRating),
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _ratingColor(_overallRating))),
            ),
          ],
          const SizedBox(height: 28),

          // Category ratings
          Text('Rate by Category', style: AppTextStyles.h4),
          const SizedBox(height: 4),
          Text('Optional — helps doctors improve specific areas',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(children: [
              _CategoryRating(
                label: 'Communication',
                icon: Icons.chat_bubble_outline_rounded,
                rating: _communication,
                onChanged: (v) => setState(() => _communication = v),
              ),
              const Divider(height: 20),
              _CategoryRating(
                label: 'Treatment Quality',
                icon: Icons.medical_services_outlined,
                rating: _treatment,
                onChanged: (v) => setState(() => _treatment = v),
              ),
              const Divider(height: 20),
              _CategoryRating(
                label: 'Wait Time',
                icon: Icons.schedule_outlined,
                rating: _waitTime,
                onChanged: (v) => setState(() => _waitTime = v),
              ),
              const Divider(height: 20),
              _CategoryRating(
                label: 'Professionalism',
                icon: Icons.workspace_premium_outlined,
                rating: _professionalism,
                onChanged: (v) => setState(() => _professionalism = v),
              ),
              const Divider(height: 20),
              _CategoryRating(
                label: 'Helpfulness',
                icon: Icons.volunteer_activism_outlined,
                rating: _helpfulness,
                onChanged: (v) => setState(() => _helpfulness = v),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // Written review
          Text('Your Review', style: AppTextStyles.h4),
          const SizedBox(height: 4),
          Text('Share what you experienced (optional)',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            maxLines: 4,
            maxLength: 500,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
            decoration: InputDecoration(
              hintText:
                  'Describe your experience, treatment quality, doctor\'s approach...',
              hintStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: AppColors.textHint),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 32),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_overallRating == 0 || _submitting) ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Submit Review'),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 12, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text(
                'Your review is verified and cannot be edited after submission',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textHint),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  String _ratingLabel(double r) {
    if (r >= 5) return 'Excellent!';
    if (r >= 4) return 'Very Good';
    if (r >= 3) return 'Good';
    if (r >= 2) return 'Fair';
    return 'Poor';
  }

  Color _ratingColor(double r) {
    if (r >= 4) return const Color(0xFF2E7D32);
    if (r >= 3) return const Color(0xFFF57C00);
    return AppColors.error;
  }
}

class _StarRatingRow extends StatelessWidget {
  final double rating;
  final double size;
  final ValueChanged<double> onChanged;

  const _StarRatingRow({
    required this.rating,
    required this.size,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starVal = (i + 1).toDouble();
        return GestureDetector(
          onTap: () => onChanged(starVal),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                rating >= starVal
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                key: ValueKey('$i-${rating >= starVal}'),
                size: size,
                color: rating >= starVal ? Colors.amber : AppColors.border,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _CategoryRating extends StatelessWidget {
  final String label;
  final IconData icon;
  final double rating;
  final ValueChanged<double> onChanged;

  const _CategoryRating({
    required this.label,
    required this.icon,
    required this.rating,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: AppColors.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final v = (i + 1).toDouble();
          return GestureDetector(
            onTap: () => onChanged(v),
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                rating >= v ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 20,
                color: rating >= v ? Colors.amber : AppColors.border,
              ),
            ),
          );
        }),
      ),
    ]);
  }
}
