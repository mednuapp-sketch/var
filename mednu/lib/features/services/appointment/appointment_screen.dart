import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';

// Converts "09:00 AM" / "02:30 PM" to total minutes since midnight for sorting.
int _slotToMinutes(String t) {
  try {
    final p = t.trim().split(' ');
    final hm = p[0].split(':');
    int h = int.parse(hm[0]);
    final m = int.parse(hm[1]);
    if (p.length > 1 && p[1].toUpperCase() == 'PM' && h != 12) h += 12;
    if (p.length > 1 && p[1].toUpperCase() == 'AM' && h == 12) h = 0;
    return h * 60 + m;
  } catch (_) {
    return 0;
  }
}

int _apptSortKey(Map<String, dynamic> d) {
  final dateStr = d['date'] as String? ?? '';
  final timeStr = d['time'] as String? ?? '';
  try {
    final date = DateTime.parse(dateStr);
    return date.millisecondsSinceEpoch + _slotToMinutes(timeStr) * 60000;
  } catch (_) {
    return 0;
  }
}

class AppointmentScreen extends StatefulWidget {
  const AppointmentScreen({super.key});
  @override
  State<AppointmentScreen> createState() => _AppointmentScreenState();
}

class _AppointmentScreenState extends State<AppointmentScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  static DateTime? _parseApptDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    try { return DateTime.parse(dateStr); } catch (_) {}
    for (final fmt in [
      DateFormat('EEE, d MMM yyyy'),
      DateFormat('EEE, dd MMM yyyy'),
      DateFormat('d MMM yyyy'),
    ]) {
      try { return fmt.parse(dateStr); } catch (_) {}
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'My Appointments',
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Past'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      // Outer stream reacts to auth state so we always have the right UID.
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnap) {
          // Use authStateChanges data, with currentUser as immediate fallback
          // so there's no loading flash when the user is already signed in.
          final uid = authSnap.data?.uid ??
              FirebaseAuth.instance.currentUser?.uid;

          if (uid == null) {
            if (authSnap.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: List.generate(5, (_) => const SkeletonListTile()),
              );
            }
            return const AppEmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Not logged in',
              message: 'Please log in to view your appointments.',
            );
          }

          // ValueKey(uid) keeps this StreamBuilder's subscription stable
          // across parent rebuilds as long as the same user is logged in.
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            key: ValueKey(uid),
            stream: FirebaseFirestore.instance
                .collection('appointments')
                .where('patientId', isEqualTo: uid)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  children: List.generate(5, (_) => const SkeletonListTile()),
                );
              }
              if (snap.hasError) {
                return AppErrorState(
                  onRetry: () => context.go(AppRoutes.appointment),
                );
              }

              final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(snap.data?.docs ?? []);

              final today = DateTime.now();
              final todayDate = DateTime(today.year, today.month, today.day);

              bool _isDatePast(Map<String, dynamic> d) {
                final dateStr = d['date'] as String? ?? '';
                final apptDate = _parseApptDate(dateStr);
                if (apptDate == null) return false;
                return apptDate.isBefore(todayDate);
              }

              // Upcoming: booked & date is today or future — sorted closest first
              final upcoming = docs
                  .where((d) =>
                      d['status'] == 'booked' && !_isDatePast(d.data()))
                  .toList()
                ..sort((a, b) => _apptSortKey(a.data()).compareTo(_apptSortKey(b.data())));
              // Past: completed OR booked but date already passed — newest first
              final past = docs
                  .where((d) =>
                      d['status'] == 'completed' ||
                      (d['status'] == 'booked' && _isDatePast(d.data())))
                  .toList()
                ..sort((a, b) => _apptSortKey(b.data()).compareTo(_apptSortKey(a.data())));
              final cancelled = docs
                  .where((d) => d['status'] == 'cancelled')
                  .toList()
                ..sort((a, b) => _apptSortKey(b.data()).compareTo(_apptSortKey(a.data())));

              return TabBarView(
                controller: _tab,
                children: [
                  _buildList(upcoming, 'Confirmed'),
                  _buildList(past, 'Completed'),
                  _buildList(cancelled, 'Cancelled'),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.doctors),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Book Appointment',
            style: TextStyle(
                color: Colors.white,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> appointments,
    String statusLabel,
  ) {
    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text('No appointments',
                style:
                    AppTextStyles.h4.copyWith(color: AppColors.textHint)),
            const SizedBox(height: 8),
            Text('Book an appointment with a doctor',
                style: AppTextStyles.bodyMedium),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: appointments.length,
      itemBuilder: (_, i) {
        final data = appointments[i].data();
        final actualStatus = data['status'] as String? ?? '';
        final isUpcoming = statusLabel == 'Confirmed';
        final isCompleted = statusLabel == 'Completed';
        // Past tab may contain booked-but-past appointments — show correct badge
        final badgeLabel = (isCompleted && actualStatus == 'booked')
            ? 'Past'
            : statusLabel;

        final dateStr = data['date'] as String? ?? '';
        final parsedDate = _parseApptDate(dateStr);
        String displayDate = dateStr;
        if (parsedDate != null) {
          final today = DateTime.now();
          final tomorrow = today.add(const Duration(days: 1));
          if (parsedDate.year == today.year &&
              parsedDate.month == today.month &&
              parsedDate.day == today.day) {
            displayDate = 'Today';
          } else if (parsedDate.year == tomorrow.year &&
              parsedDate.month == tomorrow.month &&
              parsedDate.day == tomorrow.day) {
            displayDate = 'Tomorrow';
          } else {
            displayDate = DateFormat('EEE, d MMM yyyy').format(parsedDate);
          }
        }

        final doctorName = data['doctorName'] as String? ?? 'Doctor';
        final specialty = data['doctorSpecialty'] as String? ?? '';
        final time = data['time'] as String? ?? '';
        final type = data['consultationType'] as String? ?? 'Video';

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: isUpcoming
                    ? AppColors.primary.withValues(alpha:0.3)
                    : AppColors.divider),
            boxShadow: isUpcoming
                ? [
                    BoxShadow(
                        color: AppColors.primary.withValues(alpha:0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha:0.12),
                      borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.person_rounded,
                      size: 30, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(doctorName, style: AppTextStyles.labelLarge),
                        if (specialty.isNotEmpty)
                          Text(specialty,
                              style: AppTextStyles.bodySmall),
                      ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isUpcoming
                        ? AppColors.accent.withValues(alpha:0.1)
                        : isCompleted
                            ? (badgeLabel == 'Past'
                                ? AppColors.textHint.withValues(alpha:0.15)
                                : AppColors.primary.withValues(alpha:0.1))
                            : AppColors.error.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isUpcoming
                          ? AppColors.accent
                          : isCompleted
                              ? (badgeLabel == 'Past'
                                  ? AppColors.textHint
                                  : AppColors.primary)
                              : AppColors.error,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(child: _AptDetail(Icons.calendar_today_rounded, displayDate)),
                    Container(width: 1, height: 30, color: AppColors.border),
                    Expanded(child: _AptDetail(Icons.access_time_rounded, time)),
                    Container(width: 1, height: 30, color: AppColors.border),
                    Expanded(child: _AptDetail(
                      type == 'Video'
                          ? Icons.video_call_rounded
                          : type == 'Audio'
                              ? Icons.phone_in_talk_rounded
                              : type == 'In-Person'
                                  ? Icons.local_hospital_rounded
                                  : Icons.chat_bubble_rounded,
                      type,
                    )),
                  ],
                ),
              ),
              if (isUpcoming) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon:
                          const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Cancel'),
                      onPressed: () =>
                          _cancelAppointment(appointments[i].id),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: Icon(
                          type == 'Video'
                              ? Icons.video_call_rounded
                              : type == 'Audio'
                                  ? Icons.phone_in_talk_rounded
                                  : type == 'Chat'
                                      ? Icons.chat_bubble_rounded
                                      : Icons.directions_rounded,
                          size: 16),
                      label: Text(
                          (type == 'Video' || type == 'Audio')
                              ? 'Join Call'
                              : type == 'Chat'
                                  ? 'Chat Now'
                                  : 'Directions'),
                      onPressed: () {
                        if (type == 'Video' || type == 'Audio') {
                          final callId = (data['consultationId'] as String?)?.isNotEmpty == true
                              ? data['consultationId'] as String
                              : appointments[i].id;
                          context.push(
                            '/consultation/video/$callId',
                            extra: {
                              'name': doctorName,
                              'specialty': specialty,
                            },
                          );
                        }
                      },
                    ),
                  ),
                ]),
              ],
              if (isCompleted) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                        icon: const Icon(Icons.receipt_long_rounded,
                            size: 16),
                        label: const Text('Prescription'),
                        onPressed: () => _viewPrescription(
                          appointments[i].id,
                          data,
                        )),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                        icon: const Icon(Icons.replay_rounded, size: 16),
                        label: const Text('Book Again'),
                        onPressed: () {
                          final doctorId = data['doctorId'] as String? ?? '';
                          if (doctorId.isNotEmpty) {
                            context.push('/doctors/$doctorId');
                          } else {
                            context.push(AppRoutes.doctors);
                          }
                        }),
                  ),
                ]),
                const SizedBox(height: 10),
                // Rate Doctor button — shown only for completed appointments
                // that haven't been reviewed yet.
                _RateButton(
                  appointmentId: appointments[i].id,
                  doctorId: data['doctorId'] as String? ?? '',
                  doctorName: doctorName,
                  doctorSpecialty: specialty,
                  consultationType: type,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _viewPrescription(String apptId, Map<String, dynamic> data) async {
    final consultationId = (data['consultationId'] as String?)?.isNotEmpty == true
        ? data['consultationId'] as String
        : apptId;

    // Try fetching prescription linked to this appointment/consultation
    final snap = await FirebaseFirestore.instance
        .collection('prescriptions')
        .where('appointmentId', isEqualTo: apptId)
        .limit(1)
        .get();

    Map<String, dynamic>? rxData;
    if (snap.docs.isNotEmpty) {
      rxData = snap.docs.first.data();
    } else {
      // Fallback: check by consultationId
      final snap2 = await FirebaseFirestore.instance
          .collection('prescriptions')
          .where('consultationId', isEqualTo: consultationId)
          .limit(1)
          .get();
      if (snap2.docs.isNotEmpty) rxData = snap2.docs.first.data();
    }

    if (!mounted) return;
    if (rxData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No prescription found for this appointment')),
      );
      return;
    }
    context.push(AppRoutes.prescriptionViewer, extra: {
      ...rxData,
      'doctorName': data['doctorName'],
      'doctorSpecialty': data['doctorSpecialty'],
      'date': data['date'],
    });
  }

  Future<void> _cancelAppointment(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Appointment?',
            style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text(
            'This will free up the slot for other patients.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Appointment'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      if (!mounted) return;
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(docId)
          .update({
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Slot availability is derived from appointments where status == 'booked';
      // cancelled appointments are automatically excluded from that query.
    }
  }
}

class _AptDetail extends StatelessWidget {
  final IconData icon;
  final String label;
  const _AptDetail(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      );
}

// Realtime button: streams appointment_reviews/{id} to show Rate/Rated state.
class _RateButton extends StatelessWidget {
  final String appointmentId;
  final String doctorId;
  final String doctorName;
  final String doctorSpecialty;
  final String consultationType;

  const _RateButton({
    required this.appointmentId,
    required this.doctorId,
    required this.doctorName,
    required this.doctorSpecialty,
    required this.consultationType,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('appointment_reviews')
          .doc(appointmentId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final reviewed =
            snap.data?.exists == true && snap.data?.data()?['reviewed'] == true;
        if (reviewed) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha:0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.accent.withValues(alpha:0.3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.check_circle_rounded,
                  size: 15, color: AppColors.accent),
              const SizedBox(width: 6),
              Text('Review Submitted',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.accent)),
            ]),
          );
        }
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.amber.shade700,
              side: BorderSide(color: Colors.amber.shade300),
              backgroundColor: Colors.amber.withValues(alpha:0.05),
            ),
            icon: const Icon(Icons.star_rounded, size: 16),
            label: const Text('Rate Doctor'),
            onPressed: () => context.push<bool>(
              AppRoutes.submitReview,
              extra: {
                'appointmentId': appointmentId,
                'doctorId': doctorId,
                'doctorName': doctorName,
                'doctorSpecialty': doctorSpecialty,
                'consultationType': consultationType,
              },
            ),
          ),
        );
      },
    );
  }
}
