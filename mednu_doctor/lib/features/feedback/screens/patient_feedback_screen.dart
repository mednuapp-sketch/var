import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class PatientFeedbackScreen extends StatefulWidget {
  const PatientFeedbackScreen({super.key});

  @override
  State<PatientFeedbackScreen> createState() => _PatientFeedbackScreenState();
}

class _PatientFeedbackScreenState extends State<PatientFeedbackScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Patient Feedback',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle:
              const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          tabs: const [
            Tab(text: 'Reviews'),
            Tab(text: 'Follow-ups'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _ReviewsList(doctorId: uid),
          _FollowupsList(doctorId: uid),
        ],
      ),
    );
  }
}

// ─── Reviews Tab ──────────────────────────────────────────────────────────────

class _ReviewsList extends StatelessWidget {
  final String doctorId;
  const _ReviewsList({required this.doctorId});

  @override
  Widget build(BuildContext context) {
    if (doctorId.isEmpty) {
      return const Center(child: Text('Not logged in'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('feedbacks')
          .where('doctorId', isEqualTo: doctorId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          // Fallback — try doctor_reviews collection
          return _DoctorReviewsFallback(doctorId: doctorId);
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return _DoctorReviewsFallback(doctorId: doctorId);
        }

        final ratings = docs
            .map((d) => (d.data()['rating'] as int?) ?? 0)
            .where((r) => r > 0)
            .toList();
        final avgRating = ratings.isEmpty
            ? 0.0
            : ratings.reduce((a, b) => a + b) / ratings.length;

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _RatingSummaryCard(
                avg: avgRating,
                total: docs.length,
                label: 'Total Reviews',
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _FeedbackCard(data: docs[i].data()),
                childCount: docs.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }
}

class _DoctorReviewsFallback extends StatelessWidget {
  final String doctorId;
  const _DoctorReviewsFallback({required this.doctorId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('doctor_reviews')
          .where('doctorId', isEqualTo: doctorId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_outline_rounded,
                      size: 56, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  Text('No reviews yet',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textHint)),
                ],
              ),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_outline_rounded,
                      size: 56, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  Text('No reviews yet',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textHint),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Reviews from your patients will appear here.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textHint),
                  ),
                ],
              ),
            ),
          );
        }

        final ratings = docs
            .map((d) => (d.data()['rating'] as num?)?.toDouble() ?? 0.0)
            .where((r) => r > 0)
            .toList();
        final avg =
            ratings.isEmpty ? 0.0 : ratings.reduce((a, b) => a + b) / ratings.length;

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _RatingSummaryCard(avg: avg, total: docs.length, label: 'Total Reviews'),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _FeedbackCard(data: docs[i].data()),
                childCount: docs.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }
}

// ─── Follow-ups Tab ───────────────────────────────────────────────────────────

class _FollowupsList extends StatelessWidget {
  final String doctorId;
  const _FollowupsList({required this.doctorId});

  @override
  Widget build(BuildContext context) {
    if (doctorId.isEmpty) {
      return const Center(child: Text('Not logged in'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('prescriptions')
          .where('doctorId', isEqualTo: doctorId)
          .where('followUpRequired', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text('Could not load follow-ups.',
                      style: AppTextStyles.bodyMedium),
                  const SizedBox(height: 8),
                  Text('Ensure Firestore index is set up.',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textHint)),
                ],
              ),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.health_and_safety_outlined,
                      size: 56, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  Text('No follow-ups scheduled',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textHint),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Prescriptions with follow-up reminders will appear here.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textHint),
                  ),
                ],
              ),
            ),
          );
        }

        final upcoming = docs.where((d) {
          final days = (d.data()['followUpDays'] as int?) ?? 0;
          final ts = d.data()['createdAt'] as Timestamp?;
          if (ts == null) return false;
          final dueDate = ts.toDate().add(Duration(days: days));
          return dueDate.isAfter(DateTime.now());
        }).length;

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      '${docs.length}',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'Total Follow-ups',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$upcoming upcoming',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                  const Spacer(),
                  const Icon(Icons.calendar_month_rounded,
                      color: Colors.white, size: 44),
                ]),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _FollowupCard(data: docs[i].data()),
                childCount: docs.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _RatingSummaryCard extends StatelessWidget {
  final double avg;
  final int total;
  final String label;
  const _RatingSummaryCard(
      {required this.avg, required this.total, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              avg > 0 ? avg.toStringAsFixed(1) : '—',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
            Row(
              children: List.generate(
                5,
                (i) => Icon(
                  i < avg.round()
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$total $label',
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
            ),
          ]),
          const Spacer(),
          const Icon(Icons.reviews_rounded, color: Colors.white, size: 44),
        ]),
      );
}

class _FollowupCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _FollowupCard({required this.data});

  static const _avatarColors = [
    Color(0xFFC2185B), Color(0xFF7B1FA2),
    Color(0xFF1565C0), Color(0xFF2E7D32),
    Color(0xFFE65100), Color(0xFF00695C),
  ];

  Color _colorFor(String name) =>
      _avatarColors[name.isEmpty ? 0 : name.codeUnitAt(0) % _avatarColors.length];

  @override
  Widget build(BuildContext context) {
    final patientName = data['patientName'] as String? ?? 'Patient';
    final diagnosis = data['diagnosis'] as String? ?? '';
    final followUpDays = (data['followUpDays'] as int?) ?? 7;
    final rxId = data['rxId'] as String? ?? '';
    final createdAt = data['createdAt'] as Timestamp?;

    DateTime? dueDate;
    String prescribedOn = '';
    String dueDateStr = '';
    bool isOverdue = false;

    if (createdAt != null) {
      final created = createdAt.toDate();
      prescribedOn = DateFormat('d MMM yyyy').format(created);
      dueDate = created.add(Duration(days: followUpDays));
      dueDateStr = DateFormat('d MMM yyyy').format(dueDate);
      isOverdue = dueDate.isBefore(DateTime.now());
    }

    final avatarColor = _colorFor(patientName);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOverdue
              ? AppColors.error.withOpacity(0.2)
              : AppColors.divider,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: avatarColor,
            child: Text(
              patientName.isNotEmpty ? patientName[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(patientName, style: AppTextStyles.labelLarge),
              if (rxId.isNotEmpty)
                Text(rxId,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textHint)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isOverdue
                  ? AppColors.error.withOpacity(0.08)
                  : AppColors.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              isOverdue ? 'Overdue' : 'Upcoming',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isOverdue ? AppColors.error : AppColors.success,
              ),
            ),
          ),
        ]),
        if (diagnosis.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.medical_services_outlined,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  diagnosis,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _InfoChip(
              icon: Icons.calendar_today_outlined,
              label: 'Prescribed',
              value: prescribedOn,
              color: AppColors.info,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _InfoChip(
              icon: Icons.event_rounded,
              label: 'Follow-up due',
              value: dueDateStr,
              color: isOverdue ? AppColors.error : AppColors.success,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              'Follow-up in $followUpDays day${followUpDays != 1 ? 's' : ''}',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _InfoChip(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 2),
          Text(
            value.isNotEmpty ? value : '—',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
        ]),
      );
}

// ─── Feedback card (reviews) ──────────────────────────────────────────────────

class _FeedbackCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _FeedbackCard({required this.data});

  static const _avatarColors = [
    Color(0xFFC2185B), Color(0xFF7B1FA2),
    Color(0xFF1565C0), Color(0xFF2E7D32),
    Color(0xFFE65100), Color(0xFF00695C),
  ];

  Color _colorFor(String name) =>
      _avatarColors[name.isEmpty ? 0 : name.codeUnitAt(0) % _avatarColors.length];

  String _formatDate(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as Timestamp).toDate();
      return DateFormat('d MMM yyyy, h:mm a').format(dt);
    } catch (_) {
      return '';
    }
  }

  Color _feelingColor(String feeling) {
    switch (feeling) {
      case 'Much Better': return const Color(0xFF2E7D32);
      case 'Better':      return const Color(0xFF66BB6A);
      case 'Same':        return const Color(0xFFE65100);
      case 'Worse':       return const Color(0xFFB71C1C);
      default:            return AppColors.textHint;
    }
  }

  String _feelingEmoji(String feeling) {
    switch (feeling) {
      case 'Much Better': return '😊';
      case 'Better':      return '🙂';
      case 'Same':        return '😐';
      case 'Worse':       return '😔';
      default:            return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName = data['patientName'] as String? ?? 'Patient';
    final rating = (data['rating'] as num?)?.toInt() ?? 0;
    final feeling = data['feeling'] as String? ?? '';
    final painLevel = (data['painLevel'] as num?)?.toInt() ?? 0;
    final comment = data['comment'] as String? ?? '';
    final symptoms = (data['symptoms'] as List?)?.cast<String>() ?? [];
    final createdAt = data['createdAt'];
    final avatarColor = _colorFor(patientName);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: avatarColor,
            child: Text(
              patientName.isNotEmpty ? patientName[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(patientName, style: AppTextStyles.labelLarge),
                Text(_formatDate(createdAt),
                    style:
                        AppTextStyles.caption.copyWith(color: AppColors.textHint)),
              ])),
          if (rating > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star_rounded,
                    color: Color(0xFFFFA000), size: 16),
                const SizedBox(width: 3),
                Text(
                  '$rating / 5',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFFFFA000),
                  ),
                ),
              ]),
            ),
        ]),
        if (feeling.isNotEmpty || painLevel > 0) ...[
          const SizedBox(height: 12),
          Row(children: [
            if (feeling.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _feelingColor(feeling).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _feelingColor(feeling).withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_feelingEmoji(feeling),
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 5),
                  Text(
                    feeling,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _feelingColor(feeling),
                    ),
                  ),
                ]),
              ),
            if (feeling.isNotEmpty && painLevel > 0) const SizedBox(width: 8),
            if (painLevel > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Pain: $painLevel/10',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ]),
        ],
        if (symptoms.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: symptoms
                .map((s) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Text(s, style: AppTextStyles.caption),
                    ))
                .toList(),
          ),
        ],
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '"$comment"',
              style: AppTextStyles.bodySmall.copyWith(
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
