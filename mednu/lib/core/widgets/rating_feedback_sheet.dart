import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_colors.dart';

const _kPrefKey = 'app_rating_submitted';

/// Returns true if the user has already submitted an app rating.
Future<bool> hasUserSubmittedRating() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kPrefKey) ?? false;
}

/// Shows the rating sheet if the user hasn't rated yet.
/// Call this after a successful service booking.
Future<void> maybeShowRatingSheet(BuildContext context, {Color themeColor = AppColors.primary}) async {
  final alreadyRated = await hasUserSubmittedRating();
  if (alreadyRated) return;
  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RatingFeedbackSheet(themeColor: themeColor),
  );
}

class _RatingFeedbackSheet extends StatefulWidget {
  final Color themeColor;
  const _RatingFeedbackSheet({required this.themeColor});

  @override
  State<_RatingFeedbackSheet> createState() => _RatingFeedbackSheetState();
}

class _RatingFeedbackSheetState extends State<_RatingFeedbackSheet> {
  int _stars = 0;
  final _commentCtrl = TextEditingController();
  bool _busy = false;
  bool _done = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) return;
    setState(() => _busy = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('app_ratings').add({
        'uid': user?.uid,
        'phone': user?.phoneNumber,
        'stars': _stars,
        'comment': _commentCtrl.text.trim(),
        'submittedAt': FieldValue.serverTimestamp(),
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefKey, true);

      if (mounted) setState(() { _busy = false; _done = true; });

      await Future.delayed(const Duration(milliseconds: 1400));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: _done ? _buildThanks() : _buildForm(),
    );
  }

  Widget _buildThanks() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.favorite_rounded, color: AppColors.success, size: 32),
      ),
      const SizedBox(height: 14),
      const Text(
        'Thank you!',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      const Text(
        'Your feedback helps us improve MedNU.',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF6B7280)),
        textAlign: TextAlign.center,
      ),
    ],
  );

  Widget _buildForm() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      // drag handle
      Center(
        child: Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          color: widget.themeColor.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.star_rounded, color: widget.themeColor, size: 28),
      ),
      const SizedBox(height: 14),
      const Text(
        'Rate Your Experience',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      const Text(
        'How was your MedNU experience so far?',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: Color(0xFF6B7280)),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      // Stars
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (i) {
          final filled = i < _stars;
          return GestureDetector(
            onTap: () => setState(() => _stars = i + 1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 42,
                color: filled ? const Color(0xFFFBBF24) : const Color(0xFFD1D5DB),
              ),
            ),
          );
        }),
      ),
      if (_stars > 0) ...[
        const SizedBox(height: 6),
        Text(
          _starLabel(_stars),
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: widget.themeColor,
          ),
        ),
      ],
      const SizedBox(height: 18),
      // Optional comment
      TextField(
        controller: _commentCtrl,
        maxLines: 3,
        maxLength: 200,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Share your thoughts (optional)...',
          hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Color(0xFFADB5BD)),
          filled: true,
          fillColor: const Color(0xFFF8F9FA),
          counterStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          // Skip
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                'Later',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF6B7280)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Submit
          Expanded(
            child: ElevatedButton(
              onPressed: (_busy || _stars == 0) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.themeColor,
                disabledBackgroundColor: const Color(0xFFE5E7EB),
                minimumSize: const Size(double.infinity, 48),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Submit',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    ],
  );

  String _starLabel(int s) => switch (s) {
    1 => 'Poor',
    2 => 'Fair',
    3 => 'Good',
    4 => 'Great',
    _ => 'Excellent!',
  };
}
