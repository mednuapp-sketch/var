import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';

class PostConsultationScreen extends StatefulWidget {
  final String? consultationId;
  final String? doctorId;
  final String? doctorName;
  final String? doctorSpecialty;
  // "immediate" = right after call, "followup" = day-1/day-2 follow-up
  final String type;

  const PostConsultationScreen({
    super.key,
    this.consultationId,
    this.doctorId,
    this.doctorName,
    this.doctorSpecialty,
    this.type = 'followup',
  });

  @override
  State<PostConsultationScreen> createState() => _PostConsultationScreenState();
}

class _PostConsultationScreenState extends State<PostConsultationScreen>
    with TickerProviderStateMixin {
  // ── Form state ────────────────────────────────────────────────────────────
  String? _selectedFeeling;
  int _painLevel = 0;
  int _rating = 0;
  bool _submitting = false;
  bool _submitted = false;
  bool _alreadySubmitted = false;
  bool _checking = true;
  final _notesCtrl = TextEditingController();
  final List<String> _selectedSymptoms = [];

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _successCtrl;
  late Animation<double> _successScale;
  late Animation<double> _successOpacity;
  late AnimationController _checkCtrl;
  late Animation<double> _checkAnim;
  Timer? _navTimer;

  bool get _isImmediate => widget.type == 'immediate';

  final List<Map<String, dynamic>> _feelings = [
    {'emoji': '😊', 'label': 'Much Better', 'value': 'much_better', 'color': const Color(0xFF2E7D32)},
    {'emoji': '🙂', 'label': 'Better',      'value': 'better',      'color': const Color(0xFF66BB6A)},
    {'emoji': '😐', 'label': 'Same',        'value': 'same',        'color': const Color(0xFFE65100)},
    {'emoji': '😔', 'label': 'Worse',       'value': 'worse',       'color': const Color(0xFFB71C1C)},
  ];

  final List<String> _symptoms = [
    'Fever', 'Headache', 'Body Pain', 'Cough',
    'Nausea', 'Fatigue', 'Dizziness', 'Breathing Issues',
    'Chest Pain', 'Rash', 'Swelling', 'Weakness',
  ];

  @override
  void initState() {
    super.initState();

    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut);
    _successOpacity = CurvedAnimation(parent: _successCtrl, curve: Curves.easeIn);

    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _checkAnim = CurvedAnimation(parent: _checkCtrl, curve: Curves.easeInOut);

    _checkAlreadySubmitted();
  }

  Future<void> _checkAlreadySubmitted() async {
    if ((widget.consultationId ?? '').isEmpty) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('feedbacks')
          .where('consultationId', isEqualTo: widget.consultationId)
          .where('patientId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
          .limit(1)
          .get();
      if (mounted) {
        setState(() {
          _alreadySubmitted = snap.docs.isNotEmpty;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _successCtrl.dispose();
    _checkCtrl.dispose();
    _navTimer?.cancel();
    super.dispose();
  }

  bool get _canSubmit {
    if (_submitting || _submitted) return false;
    if (_isImmediate) return _rating > 0;
    return _selectedFeeling != null;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';

      String patientName = user?.displayName ?? 'Patient';
      if (uid.isNotEmpty) {
        try {
          final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          patientName = snap.data()?['name'] as String? ??
                        snap.data()?['displayName'] as String? ??
                        patientName;
        } catch (_) {}
      }

      final doctorId = widget.doctorId ?? '';
      final data = <String, dynamic>{
        'type': widget.type,
        'consultationId': widget.consultationId ?? '',
        'doctorId': doctorId,
        'doctorName': widget.doctorName ?? '',
        'doctorSpecialty': widget.doctorSpecialty ?? '',
        'patientId': uid,
        'patientName': patientName,
        'rating': _rating,
        'feeling': _selectedFeeling ?? '',
        'painLevel': _painLevel,
        'symptoms': _selectedSymptoms,
        'comment': _notesCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      // Write feedback document
      final fbRef = db.collection('feedbacks').doc();
      batch.set(fbRef, data);

      // Update doctor rating atomically via transaction (separate — batch can't do reads)
      await batch.commit();

      // Update doctor rating if applicable
      if (_rating > 0 && doctorId.isNotEmpty) {
        _updateDoctorRating(doctorId);
      }

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });

      // Animate success
      await _successCtrl.forward();
      _checkCtrl.forward();

      // Auto-navigate after 3 seconds
      _navTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) context.go(AppRoutes.home);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Submission failed: ${e.toString().split(']').last.trim()}')),
            ],
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _updateDoctorRating(String doctorId) async {
    try {
      final db = FirebaseFirestore.instance;
      final doctorRef = db.collection('doctors').doc(doctorId);
      final summaryRef = db.collection('doctor_rating_summary').doc(doctorId);

      await db.runTransaction((txn) async {
        final doctorSnap = await txn.get(doctorRef);
        final summarySnap = await txn.get(summaryRef);

        if (!doctorSnap.exists) return;
        final d = doctorSnap.data()!;
        final currentTotal = ((d['rating'] as num?)?.toDouble() ?? 0) *
            ((d['totalReviews'] as int?) ?? 0);
        final newCount = ((d['totalReviews'] as int?) ?? 0) + 1;
        final newAvg = double.parse(
            ((currentTotal + _rating) / newCount).toStringAsFixed(1));

        // Update doctors collection (patient-side reads)
        txn.update(doctorRef, {
          'rating': newAvg,
          'totalReviews': newCount,
        });

        // Update doctor_rating_summary (what the doctor dashboard + reviews screen reads)
        final starKey = _rating.toString();
        if (summarySnap.exists) {
          final sd = summarySnap.data()!;
          final dist = Map<String, dynamic>.from(
            (sd['ratingDistribution'] as Map<String, dynamic>?) ?? {},
          );
          dist[starKey] = ((dist[starKey] as num?)?.toInt() ?? 0) + 1;
          txn.update(summaryRef, {
            'averageRating': newAvg,
            'totalReviews': newCount,
            'ratingDistribution': dist,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        } else {
          // First review ever — create the summary document
          txn.set(summaryRef, {
            'averageRating': newAvg,
            'totalReviews': 1,
            'ratingDistribution': {
              '1': _rating == 1 ? 1 : 0,
              '2': _rating == 2 ? 1 : 0,
              '3': _rating == 3 ? 1 : 0,
              '4': _rating == 4 ? 1 : 0,
              '5': _rating == 5 ? 1 : 0,
            },
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (_) {}
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _checking
          ? SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(16),
              child: Column(children: [
                const SizedBox(height: 40),
                ...List.generate(4, (_) => const Padding(padding: EdgeInsets.only(bottom: 16), child: SkeletonBox(width: double.infinity, height: 64, radius: 16))),
              ]))
          : _submitted
              ? _buildSuccessView()
              : _alreadySubmitted
                  ? _buildAlreadySubmittedView()
                  : _buildForm(),
    );
  }

  // ── Success view ──────────────────────────────────────────────────────────

  Widget _buildSuccessView() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF0D2050)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated checkmark circle
            ScaleTransition(
              scale: _successScale,
              child: FadeTransition(
                opacity: _successOpacity,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30, width: 2),
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 64),
                ),
              ),
            ),
            const SizedBox(height: 32),
            FadeTransition(
              opacity: _successOpacity,
              child: Column(
                children: [
                  Text(
                    _isImmediate ? 'Feedback Submitted!' : 'Follow-up Submitted!',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      _isImmediate
                          ? 'Thank you! Your feedback helps us improve the quality of care.'
                          : 'Your doctor has been notified and will review your follow-up.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        color: Colors.white70,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Star rating display
                  if (_rating > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) => Icon(
                        i < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: i < _rating ? const Color(0xFFFFA000) : Colors.white30,
                        size: 32,
                      )),
                    ),
                    const SizedBox(height: 24),
                  ],
                  // Auto-nav hint
                  Text(
                    'Returning to home in 3 seconds...',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.home),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha:0.15),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text(
                      'Go to Home',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Already submitted view ────────────────────────────────────────────────

  Widget _buildAlreadySubmittedView() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('Follow-up', style: TextStyle(fontFamily: 'Poppins', color: Colors.white)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha:0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 54),
              ),
              const SizedBox(height: 24),
              const Text(
                'Already Submitted',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const Text(
                'You have already submitted feedback for this consultation. Thank you for sharing your experience!',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.grey, height: 1.6),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go(AppRoutes.home),
                  child: const Text('Back to Home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Main form ─────────────────────────────────────────────────────────────

  Widget _buildForm() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 170,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 52, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha:0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _isImmediate ? Icons.star_rounded : Icons.health_and_safety_rounded,
                            color: Colors.white, size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              _isImmediate ? 'Rate Your Doctor' : 'How Are You Feeling?',
                              style: AppTextStyles.onPrimaryH2,
                            ),
                            Text(
                              _isImmediate
                                  ? 'Your feedback helps improve care quality'
                                  : 'Post-consultation follow-up for ${widget.doctorName ?? 'your doctor'}',
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ]),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Doctor card
                _buildDoctorCard(),
                const SizedBox(height: 20),

                // Star rating
                _buildSection(
                  title: 'Rate Your Doctor',
                  required: _isImmediate,
                  child: _buildStarRating(),
                ),
                const SizedBox(height: 20),

                // Feeling selector (follow-up mode)
                _buildSection(
                  title: 'Overall, how are you feeling today?',
                  required: !_isImmediate,
                  child: _buildFeelingSelector(),
                ),
                const SizedBox(height: 20),

                // Pain level
                _buildSection(
                  title: 'Pain Level',
                  child: _buildPainSlider(),
                ),
                const SizedBox(height: 20),

                // Symptoms
                _buildSection(
                  title: 'Current Symptoms',
                  subtitle: 'Select all that apply',
                  child: _buildSymptomChips(),
                ),
                const SizedBox(height: 20),

                // Notes
                _buildSection(
                  title: _isImmediate ? 'Comments' : 'Additional Notes',
                  subtitle: 'Optional',
                  child: _buildNotesField(),
                ),
                const SizedBox(height: 24),

                // Submit button
                _buildSubmitButton(),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Section wrapper ───────────────────────────────────────────────────────

  Widget _buildSection({
    required String title,
    String? subtitle,
    bool required = false,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(title, style: AppTextStyles.h4),
          if (required) ...[
            const SizedBox(width: 4),
            const Text('*', style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.w700)),
          ],
          if (subtitle != null) ...[
            const SizedBox(width: 6),
            Text(subtitle,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.grey)),
          ],
        ]),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  // ── Doctor card ───────────────────────────────────────────────────────────

  Widget _buildDoctorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_rounded, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            widget.doctorName != null ? 'Dr. ${widget.doctorName}' : 'Your Doctor',
            style: AppTextStyles.labelLarge,
          ),
          if (widget.doctorSpecialty != null)
            Text(widget.doctorSpecialty!, style: AppTextStyles.bodySmall),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _isImmediate ? 'Rate Now' : 'Follow-up',
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.accent,
            ),
          ),
        ),
      ]),
    );
  }

  // ── Star rating ───────────────────────────────────────────────────────────

  Widget _buildStarRating() {
    const labels = ['', 'Poor', 'Fair', 'Good', 'Very Good', 'Excellent!'];
    const colors = [
      Colors.transparent,
      Color(0xFFE53935),
      Color(0xFFE65100),
      Color(0xFFFFA000),
      Color(0xFF66BB6A),
      Color(0xFF2E7D32),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isImmediate && _rating == 0 ? const Color(0xFFFFCDD2) : AppColors.divider,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final filled = i < _rating;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _rating = i + 1);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: filled ? const Color(0xFFFFA000) : AppColors.textHint,
                  size: 46,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _rating == 0 ? 'Tap a star to rate' : labels[_rating],
            key: ValueKey(_rating),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _rating == 0 ? AppColors.textHint : colors[_rating],
            ),
          ),
        ),
        if (_isImmediate && _rating == 0) ...[
          const SizedBox(height: 8),
          const Text(
            'Rating is required to submit',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Color(0xFFE53935)),
          ),
        ],
      ]),
    );
  }

  // ── Feeling selector ──────────────────────────────────────────────────────

  Widget _buildFeelingSelector() {
    return Column(
      children: [
        Row(
          children: _feelings.map((f) => Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedFeeling = f['value'] as String);
                if (f['value'] == 'worse') _showWorseAlert(context);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _selectedFeeling == f['value']
                      ? (f['color'] as Color).withValues(alpha:0.12)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _selectedFeeling == f['value']
                        ? f['color'] as Color
                        : AppColors.border,
                    width: _selectedFeeling == f['value'] ? 2 : 1,
                  ),
                  boxShadow: _selectedFeeling == f['value']
                      ? [BoxShadow(color: (f['color'] as Color).withValues(alpha:0.2), blurRadius: 8)]
                      : null,
                ),
                child: Column(children: [
                  Text(f['emoji'] as String, style: const TextStyle(fontSize: 26)),
                  const SizedBox(height: 5),
                  Text(
                    f['label'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600,
                      color: _selectedFeeling == f['value']
                          ? f['color'] as Color
                          : AppColors.textSecondary,
                    ),
                  ),
                ]),
              ),
            ),
          )).toList(),
        ),
        if (!_isImmediate && _selectedFeeling == null) ...[
          const SizedBox(height: 8),
          const Row(children: [
            Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFFE53935)),
            SizedBox(width: 4),
            Text(
              'Please select how you are feeling',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Color(0xFFE53935)),
            ),
          ]),
        ],
      ],
    );
  }

  // ── Pain slider ───────────────────────────────────────────────────────────

  Widget _buildPainSlider() {
    final painColor = _painLevel < 4
        ? const Color(0xFF2E7D32)
        : _painLevel < 7
            ? const Color(0xFFE65100)
            : const Color(0xFFB71C1C);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Pain Level',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600)),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: painColor.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: painColor.withValues(alpha:0.3)),
            ),
            child: Text(
              _painLevel == 0 ? 'No Pain' : '$_painLevel / 10',
              style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13, color: painColor,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
          ),
          child: Slider(
            value: _painLevel.toDouble(),
            min: 0, max: 10, divisions: 10,
            activeColor: painColor,
            inactiveColor: painColor.withValues(alpha:0.15),
            onChanged: (v) => setState(() => _painLevel = v.round()),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('No Pain 😊', style: AppTextStyles.caption),
          Text('Moderate 😐', style: AppTextStyles.caption),
          Text('Severe 😣', style: AppTextStyles.caption),
        ]),
      ]),
    );
  }

  // ── Symptom chips ─────────────────────────────────────────────────────────

  Widget _buildSymptomChips() {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: _symptoms.map((s) {
        final selected = _selectedSymptoms.contains(s);
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => selected ? _selectedSymptoms.remove(s) : _selectedSymptoms.add(s));
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary.withValues(alpha:0.1) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: AppColors.primary.withValues(alpha:0.15), blurRadius: 6)]
                  : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 13, color: AppColors.primary),
                const SizedBox(width: 4),
              ],
              Text(
                s,
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }

  // ── Notes field ───────────────────────────────────────────────────────────

  Widget _buildNotesField() {
    return TextField(
      controller: _notesCtrl,
      maxLines: 4,
      maxLength: 500,
      decoration: InputDecoration(
        hintText: _isImmediate
            ? 'Share your experience with this doctor...'
            : 'Describe any new symptoms, concerns, or how your recovery is going...',
        hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.black38),
        filled: true,
        fillColor: Colors.white,
        counterStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.grey),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Submit button ─────────────────────────────────────────────────────────

  Widget _buildSubmitButton() {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: _canSubmit ? AppColors.primaryGradient : null,
            color: _canSubmit ? null : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _canSubmit
                ? [BoxShadow(color: AppColors.primary.withValues(alpha:0.35), blurRadius: 16, offset: const Offset(0, 6))]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _canSubmit ? _submit : null,
              child: Center(
                child: _submitting
                    ? const SizedBox(
                        height: 22, width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          _isImmediate ? Icons.star_rounded : Icons.send_rounded,
                          color: _canSubmit ? Colors.white : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isImmediate ? 'Submit Feedback' : 'Submit Follow-up',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _canSubmit ? Colors.white : Colors.grey,
                          ),
                        ),
                      ]),
              ),
            ),
          ),
        ),
        if (!_canSubmit && !_submitting) ...[
          const SizedBox(height: 8),
          Text(
            _isImmediate ? 'Please rate the doctor to continue' : 'Please select how you are feeling to continue',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.grey),
          ),
        ],
      ],
    );
  }

  // ── Worse alert ───────────────────────────────────────────────────────────

  void _showWorseAlert(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFB71C1C), size: 24),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Condition Worsening',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  color: Color(0xFFB71C1C), fontSize: 16),
            ),
          ),
        ]),
        content: const Text(
          'We noticed your condition may have worsened since your last consultation. Please consider:\n\n• Contacting your doctor immediately\n• Booking a follow-up appointment\n• Visiting the nearest clinic if urgent',
          style: TextStyle(fontFamily: 'Poppins', height: 1.6, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue Form', style: TextStyle(fontFamily: 'Poppins')),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.notifications_active_rounded, size: 16),
            label: const Text('Alert Doctor', style: TextStyle(fontFamily: 'Poppins')),
            onPressed: () {
              Navigator.pop(context);
              _alertDoctor();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB71C1C)),
          ),
        ],
      ),
    );
  }

  Future<void> _alertDoctor() async {
    final doctorId = widget.doctorId ?? '';
    if (doctorId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('doctor_notifications')
          .doc(doctorId)
          .collection('items')
          .add({
        'type': 'condition_alert',
        'title': '⚠️ Patient Condition Alert',
        'body': '${widget.doctorName != null ? "A patient of Dr. ${widget.doctorName}" : "A patient"} reports their condition has worsened since the last consultation.',
        'consultationId': widget.consultationId ?? '',
        'patientId': FirebaseAuth.instance.currentUser?.uid ?? '',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'deliverAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not alert doctor: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text('Doctor has been alerted', style: TextStyle(fontFamily: 'Poppins')),
        ]),
        backgroundColor: const Color(0xFFB71C1C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }
}
