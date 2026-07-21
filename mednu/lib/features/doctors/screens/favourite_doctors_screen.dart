import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../core/utils/r.dart';

class FavouriteDoctorsScreen extends StatelessWidget {
  const FavouriteDoctorsScreen({super.key});

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          // ── Gradient SliverAppBar ──────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: R.h(context, 130),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
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
                      top: -R.h(context, 20),
                      right: -R.w(context, 20),
                      child: Container(
                        width: R.w(context, 110),
                        height: R.h(context, 110),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha:0.06),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: constraints.maxHeight),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 52), R.p(context, 20), R.p(context, 16)),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: R.w(context, 40),
                                          height: R.w(context, 40),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha:0.18),
                                            borderRadius: BorderRadius.circular(R.r(context, 12)),
                                          ),
                                          child: Icon(
                                            Icons.favorite_rounded,
                                            color: Colors.white,
                                            size: R.w(context, 22),
                                          ),
                                        ),
                                        SizedBox(width: R.p(context, 12)),
                                        const Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Favourite Doctors',
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                            Text(
                                              'Your saved doctors',
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
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────
          if (_uid.isEmpty)
            const SliverFillRemaining(
              child: Center(child: Text('Not logged in')),
            )
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(_uid)
                  .collection('favourite_doctors')
                  .orderBy('savedAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return SliverPadding(
                    padding: EdgeInsets.symmetric(vertical: R.p(context, 10)),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, __) => const SkeletonDoctorCard(),
                        childCount: 5,
                      ),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return SliverFillRemaining(
                    child: AppEmptyState(
                      icon: Icons.favorite_border_rounded,
                      title: 'No favourites yet',
                      message: 'Doctors you save will appear here for quick access.',
                    ),
                  );
                }
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 16), R.p(context, 16), R.p(context, 32)),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => FadeInSlide(
                        delay: Duration(milliseconds: i * 40),
                        child: _DoctorCard(doc: docs[i], uid: _uid),
                      ),
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

// ── Doctor card ───────────────────────────────────────────────────────────────

class _DoctorCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String uid;

  const _DoctorCard({required this.doc, required this.uid});

  Future<void> _removeFavourite(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 20))),
        title: const Text(
          'Remove Favourite?',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Text(
          'Remove Dr. ${doc.data()['doctorName'] ?? ''} from your favourites?',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Remove', style: TextStyle(fontFamily: 'Poppins')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('favourite_doctors')
          .doc(doc.id)
          .delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.favorite_border_rounded, color: Colors.white, size: 16),
              SizedBox(width: R.p(context, 8)),
              const Text('Removed from favourites', style: TextStyle(fontFamily: 'Poppins')),
            ]),
            backgroundColor: context.appTextSecondary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 12))),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final name      = d['doctorName']  as String? ?? 'Doctor';
    final specialty = d['specialty']   as String? ?? '';
    final rating    = (d['rating']     as num?)?.toDouble() ?? 0.0;
    final fee       = (d['fee']        as num?)?.toInt() ?? 0;
    final doctorId  = d['doctorId']    as String? ?? doc.id;

    return GestureDetector(
      onTap: () => context.push(
        AppRoutes.doctorProfile.replaceFirst(':id', doctorId),
      ),
      child: Container(
        margin: EdgeInsets.only(bottom: R.p(context, 12)),
        padding: EdgeInsets.all(R.p(context, 14)),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(R.r(context, 18)),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar with live online status
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('doctors')
                  .doc(doctorId)
                  .snapshots(),
              builder: (_, docSnap) {
                final isOnline =
                    (docSnap.data?.data() as Map<String, dynamic>?)?['isOnline']
                        as bool? ?? false;
                return Stack(
                  children: [
                    Container(
                      width: R.w(context, 56),
                      height: R.h(context, 56),
                      decoration: const BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'D',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 1, right: 1,
                      child: Container(
                        width: R.w(context, 13), height: R.h(context, 13),
                        decoration: BoxDecoration(
                          color: isOnline
                              ? AppColors.accent
                              : context.appTextHint,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            SizedBox(width: R.p(context, 14)),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dr. $name',
                    style: AppTextStyles.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (specialty.isNotEmpty) ...[
                    SizedBox(height: R.p(context, 2)),
                    Text(specialty, style: AppTextStyles.bodySmall),
                  ],
                  SizedBox(height: R.p(context, 6)),
                  Row(children: [
                    if (rating > 0) ...[
                      const Icon(Icons.star_rounded, color: Color(0xFFFFA000), size: 14),
                      SizedBox(width: R.p(context, 3)),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFFA000),
                        ),
                      ),
                      SizedBox(width: R.p(context, 10)),
                    ],
                    if (fee > 0)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: R.p(context, 8), vertical: R.p(context, 2)),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(R.r(context, 6)),
                        ),
                        child: Text(
                          '₹$fee',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                  ]),
                ],
              ),
            ),

            // Buttons
            Column(
              children: [
                GestureDetector(
                  onTap: () => _removeFavourite(context),
                  child: Container(
                    width: R.w(context, 36),
                    height: R.h(context, 36),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(R.r(context, 10)),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFFE53935),
                      size: 18,
                    ),
                  ),
                ),
                SizedBox(height: R.p(context, 6)),
                GestureDetector(
                  onTap: () => context.push(
                    AppRoutes.doctorProfile.replaceFirst(':id', doctorId),
                  ),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: R.p(context, 10), vertical: R.p(context, 7)),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(R.r(context, 10)),
                    ),
                    child: const Text(
                      'Book',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
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

// _EmptyState removed — replaced by AppEmptyState from ux_widgets.dart
