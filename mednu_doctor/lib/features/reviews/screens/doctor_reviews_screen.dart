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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Gradient header ──────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 130,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -20,
                      right: -20,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha:0.06),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha:0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.star_rounded,
                                  color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'My Reviews',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Patient feedback & ratings',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Rating Summary Card
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

                return Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha:0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.star_rounded,
                            color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        Text('Patient Satisfaction',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha:0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.verified_rounded,
                                    size: 11, color: Colors.white),
                                const SizedBox(width: 4),
                                Text('$total verified',
                                    style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                              ]),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            total > 0 ? avg.toStringAsFixed(1) : '—',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 52,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10, left: 6),
                            child: Text('/5',
                                style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 18,
                                    color: Colors.white60)),
                          ),
                          const Spacer(),
                          // Distribution bars
                          if (total > 0)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [5, 4, 3, 2, 1].map((star) {
                                final count = dist[star] ?? 0;
                                final fraction =
                                    total > 0 ? count / total : 0.0;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('$star',
                                            style: const TextStyle(
                                                fontFamily: 'Poppins',
                                                fontSize: 10,
                                                color: Colors.white60)),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.star_rounded,
                                            size: 9, color: Colors.amber),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          width: 90,
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: fraction,
                                              minHeight: 5,
                                              backgroundColor:
                                                  Colors.white.withValues(alpha:0.2),
                                              valueColor:
                                                  const AlwaysStoppedAnimation<
                                                      Color>(Colors.white),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          width: 20,
                                          child: Text('$count',
                                              style: const TextStyle(
                                                  fontFamily: 'Poppins',
                                                  fontSize: 10,
                                                  color: Colors.white70)),
                                        ),
                                      ]),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: List.generate(5, (i) {
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
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Reviews list
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _reviewsStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, __) => const SkeletonListTile(),
                    childCount: 5,
                  ),
                );
              }

              final docs = snap.data?.docs ?? [];

              if (docs.isEmpty) {
                return SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(children: [
                        Icon(Icons.rate_review_outlined,
                            size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text('No reviews yet',
                            style: AppTextStyles.h4
                                .copyWith(color: AppColors.textHint)),
                        const SizedBox(height: 8),
                        Text(
                            'Reviews from verified patients will appear here after consultations',
                            style: AppTextStyles.bodySmall,
                            textAlign: TextAlign.center),
                      ]),
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final d = docs[i].data();
                      final ts = d['createdAt'];
                      final created = ts is Timestamp
                          ? ts.toDate()
                          : DateTime.now();
                      final rating =
                          (d['rating'] as num?)?.toDouble() ?? 0;
                      final patientName =
                          d['patientName'] as String? ?? 'Patient';
                      final reviewText =
                          d['reviewText'] as String? ?? '';
                      final consultationType =
                          d['consultationType'] as String? ?? 'Video';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: const Color(0xFFF5F5F5)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha:0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha:0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    patientName.isNotEmpty
                                        ? patientName[0].toUpperCase()
                                        : 'P',
                                    style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Text(patientName,
                                          style: AppTextStyles.labelMedium),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent
                                              .withValues(alpha:0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                          const Icon(Icons.verified_rounded,
                                              size: 9,
                                              color: AppColors.accent),
                                          const SizedBox(width: 3),
                                          Text('Verified',
                                              style: TextStyle(
                                                  fontFamily: 'Poppins',
                                                  fontSize: 9,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  color: AppColors.accent)),
                                        ]),
                                      ),
                                    ]),
                                    Text(_timeAgo(created),
                                        style: AppTextStyles.caption
                                            .copyWith(
                                                color:
                                                    AppColors.textHint)),
                                  ],
                                ),
                              ),
                              // Star display
                              Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(
                                      5,
                                      (si) => Icon(
                                            si < rating
                                                ? Icons.star_rounded
                                                : Icons.star_outline_rounded,
                                            size: 14,
                                            color: Colors.amber,
                                          )),
                                ),
                                Text(rating.toStringAsFixed(1),
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.amber.shade700)),
                              ]),
                            ]),
                            if (reviewText.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(reviewText,
                                  style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.textSecondary,
                                      height: 1.5)),
                            ],
                            const SizedBox(height: 10),
                            // Category ratings if present
                            _buildCategories(d['categories']),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha:0.07),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(consultationType,
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.primary)),
                              ),
                            ]),
                          ],
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: pairs.entries.map((e) {
          final label = labels[e.key] ?? e.key;
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha:0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amber.withValues(alpha:0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: AppTextStyles.caption
                      .copyWith(color: Colors.amber.shade800)),
              const SizedBox(width: 4),
              Text('${e.value.toStringAsFixed(0)}★',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.amber.shade700)),
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
    if (diff.inDays >= 1) {
      return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    }
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
