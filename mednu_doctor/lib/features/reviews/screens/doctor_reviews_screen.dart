import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/ux_widgets.dart';

class DoctorReviewsScreen extends StatefulWidget {
  const DoctorReviewsScreen({super.key});
  @override
  State<DoctorReviewsScreen> createState() => _DoctorReviewsScreenState();
}

class _DoctorReviewsScreenState extends State<DoctorReviewsScreen> {
  final _db = FirebaseFirestore.instance;
  String get _doctorId => FirebaseAuth.instance.currentUser?.uid ?? '';

  int _filterStar = 0; // 0 = All

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _summaryStream =>
      _db.collection('doctor_rating_summary').doc(_doctorId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> get _reviewsStream =>
      _db
          .collection('doctor_reviews')
          .where('doctorId', isEqualTo: _doctorId)
          .where('isFlagged', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots();

  Future<void> _closeReview(String docId) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _DismissReviewSheet(),
    );
    if (confirmed == true) {
      await _db
          .collection('doctor_reviews')
          .doc(docId)
          .update({'doctorDismissed': true});
    }
  }

  String _sentimentLabel(double rating) {
    if (rating >= 4.5) return 'Excellent';
    if (rating >= 3.5) return 'Good';
    if (rating >= 2.5) return 'Average';
    return 'Poor';
  }

  Color _sentimentColor(double rating) {
    if (rating >= 4.5) return AppColors.success;
    if (rating >= 3.5) return const Color(0xFF0277BD);
    if (rating >= 2.5) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          GradientSliverAppBar(
            headerIcon: Icons.star_rounded,
            title: 'My Reviews',
            subtitle: 'Patient feedback & ratings',
          ),

          // ── Rating Summary Card ──────────────────────────
          SliverToBoxAdapter(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _summaryStream,
              builder: (context, snap) {
                final data =
                    snap.data?.exists == true ? snap.data!.data()! : null;
                final avg = (data?['averageRating'] as num?)?.toDouble() ?? 0;
                final total = (data?['totalReviews'] as num?)?.toInt() ?? 0;
                final rawDist = data?['ratingDistribution'] as Map?;
                final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
                rawDist?.forEach((k, v) {
                  final key = int.tryParse(k.toString());
                  if (key != null) dist[key] = (v as num?)?.toInt() ?? 0;
                });

                return FadeInSlide(
                  child: _RatingSummaryCard(
                    avg: avg,
                    total: total,
                    dist: dist,
                  ),
                );
              },
            ),
          ),

          // ── Star Filter Chips ────────────────────────────
          SliverToBoxAdapter(
            child: FadeInSlide(
              delay: const Duration(milliseconds: 80),
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _StarFilterChip(
                      label: 'All',
                      selected: _filterStar == 0,
                      onTap: () => setState(() => _filterStar = 0),
                    ),
                    ...List.generate(5, (i) {
                      final star = 5 - i;
                      return _StarFilterChip(
                        label: '★ $star',
                        selected: _filterStar == star,
                        onTap: () => setState(
                            () => _filterStar = _filterStar == star ? 0 : star),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ── Reviews List ─────────────────────────────────
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _reviewsStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, __) => const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: SkeletonCard(height: 120),
                    ),
                    childCount: 4,
                  ),
                );
              }

              if (snap.hasError) {
                return SliverFillRemaining(
                  child: AppErrorState(onRetry: () => setState(() {})),
                );
              }

              var docs = (snap.data?.docs ?? [])
                  .where((d) => d.data()['doctorDismissed'] != true)
                  .toList();

              if (_filterStar > 0) {
                docs = docs.where((d) {
                  final r = (d.data()['rating'] as num?)?.round() ?? 0;
                  return r == _filterStar;
                }).toList();
              }

              if (docs.isEmpty) {
                return SliverToBoxAdapter(
                  child: FadeInSlide(
                    child: AppEmptyState(
                      icon: Icons.rate_review_outlined,
                      title: _filterStar > 0
                          ? 'No $_filterStar-star reviews'
                          : 'No reviews yet',
                      message: _filterStar > 0
                          ? 'No reviews with this rating found.'
                          : 'Reviews from verified patients will appear here after consultations.',
                      iconColor: Colors.amber,
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final docId = docs[i].id;
                      final d = docs[i].data();
                      return FadeInSlide(
                        delay: Duration(milliseconds: i * 50),
                        child: _ReviewCard(
                          docId: docId,
                          data: d,
                          onClose: () => _closeReview(docId),
                          sentimentLabel: _sentimentLabel,
                          sentimentColor: _sentimentColor,
                        ),
                      );
                    },
                    childCount: docs.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Rating Summary Card
// ──────────────────────────────────────────────────────────────

class _RatingSummaryCard extends StatelessWidget {
  final double avg;
  final int total;
  final Map<int, int> dist;

  const _RatingSummaryCard({
    required this.avg,
    required this.total,
    required this.dist,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
            const SizedBox(width: 8),
            const Text(
              'Patient Satisfaction',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
            const Spacer(),
            if (total > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.verified_rounded, size: 11, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    '$total verified',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ]),
              ),
          ]),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                total > 0 ? avg.toStringAsFixed(1) : '—',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 58,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10, left: 6),
                child: Text(
                  '/5',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const Spacer(),
              if (total > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [5, 4, 3, 2, 1].map((star) {
                    final count = dist[star] ?? 0;
                    final fraction = total > 0 ? count / total : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          '$star',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(Icons.star_rounded,
                            size: 9, color: Colors.amber),
                        const SizedBox(width: 7),
                        SizedBox(
                          width: 88,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: fraction,
                              minHeight: 6,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.18),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                star >= 4
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 22,
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ]),
                    );
                  }).toList(),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ...List.generate(5, (i) {
                return Icon(
                  i < avg.floor()
                      ? Icons.star_rounded
                      : (i < avg && avg % 1 >= 0.5)
                          ? Icons.star_half_rounded
                          : Icons.star_outline_rounded,
                  size: 18,
                  color: Colors.amber,
                );
              }),
              if (total > 0) ...[
                const SizedBox(width: 8),
                Text(
                  _quality(avg),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _quality(double r) {
    if (r >= 4.5) return '· Excellent';
    if (r >= 3.5) return '· Very Good';
    if (r >= 2.5) return '· Good';
    if (r >= 1.5) return '· Fair';
    return '';
  }
}

// ──────────────────────────────────────────────────────────────
// Star Filter Chip
// ──────────────────────────────────────────────────────────────

class _StarFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StarFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
                )
              : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : AppColors.border,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Review Card
// ──────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final VoidCallback onClose;
  final String Function(double) sentimentLabel;
  final Color Function(double) sentimentColor;

  const _ReviewCard({
    required this.docId,
    required this.data,
    required this.onClose,
    required this.sentimentLabel,
    required this.sentimentColor,
  });

  @override
  Widget build(BuildContext context) {
    final ts = data['createdAt'];
    final created = ts is Timestamp ? ts.toDate() : DateTime.now();
    final rating = (data['rating'] as num?)?.toDouble() ?? 0;
    final patientName = data['patientName'] as String? ?? 'Patient';
    final reviewText = data['reviewText'] as String? ?? '';
    final consultationType = data['consultationType'] as String? ?? 'Video';
    final sentiment = sentimentLabel(rating);
    final sentColor = sentimentColor(rating);

    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(children: [
            AppAvatar(name: patientName, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        patientName,
                        style: AppTextStyles.labelLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.verified_rounded,
                            size: 9, color: AppColors.success),
                        const SizedBox(width: 3),
                        Text(
                          'Verified',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                          ),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    _timeAgo(created),
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            // Right side: stars + close
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                ...List.generate(
                  5,
                  (si) => Icon(
                    si < rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 14,
                    color: Colors.amber,
                  ),
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                rating.toStringAsFixed(1),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.amber.shade700,
                ),
              ),
            ]),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onClose,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close_rounded,
                    size: 15, color: Colors.red.shade400),
              ),
            ),
          ]),

          // Review text
          if (reviewText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '"$reviewText"',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.55,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],

          // Category chips
          _buildCategories(data['categories']),

          // Footer: consultation type + sentiment
          const SizedBox(height: 10),
          Row(children: [
            InfoChip(
              icon: Icons.video_call_rounded,
              label: consultationType,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                sentiment,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: sentColor,
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildCategories(dynamic raw) {
    if (raw == null) return const SizedBox.shrink();
    final cats = raw as Map<dynamic, dynamic>;
    final pairs = <String, double>{};
    cats.forEach((k, v) {
      final val = (v as num?)?.toDouble() ?? 0;
      if (val > 0) pairs[k.toString()] = val;
    });
    if (pairs.isEmpty) return const SizedBox.shrink();

    final labels = {
      'communication': 'Communication',
      'treatment': 'Treatment',
      'waitTime': 'Wait Time',
      'professionalism': 'Professionalism',
      'helpfulness': 'Helpfulness',
    };

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: pairs.entries.map((e) {
          final label = labels[e.key] ?? e.key;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: Colors.amber.withValues(alpha: 0.25)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                label,
                style: AppTextStyles.caption
                    .copyWith(color: Colors.amber.shade800),
              ),
              const SizedBox(width: 4),
              Text(
                '${e.value.toStringAsFixed(0)}★',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.amber.shade700,
                ),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 30) {
      final months = (diff.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    }
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

// ──────────────────────────────────────────────────────────────
// Dismiss Review Bottom Sheet
// ──────────────────────────────────────────────────────────────

class _DismissReviewSheet extends StatelessWidget {
  const _DismissReviewSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.hide_source_rounded,
                color: Colors.red.shade400, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            'Hide This Review?',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This review will be hidden from your list. Your overall rating is not affected.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text(
                  'Hide Review',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
