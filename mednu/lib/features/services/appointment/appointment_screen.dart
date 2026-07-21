import 'dart:async';
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
      backgroundColor: context.appBackground,
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
            Tab(
              child: Text('Upcoming',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Tab(
              child: Text('Past',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Tab(
              child: Text('Cancelled',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                children: List.generate(4, (_) => const _AppointmentCardSkeleton()),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  children: List.generate(4, (_) => const _AppointmentCardSkeleton()),
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
      if (statusLabel == 'Confirmed') {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.12),
                        AppColors.secondary.withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.calendar_today_outlined,
                      size: 44, color: AppColors.primary),
                ),
                const SizedBox(height: 24),
                Text(
                  'No Upcoming Appointments',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Stay on top of your health.\nBook a consultation with a specialist today.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: context.appTextSecondary,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 28),
                GestureDetector(
                  onTap: () => context.push(AppRoutes.doctors),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 15),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded,
                            size: 18, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Book Your First Appointment',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return AppEmptyState(
        icon: statusLabel == 'Cancelled'
            ? Icons.cancel_presentation_rounded
            : Icons.event_available_rounded,
        title: statusLabel == 'Cancelled'
            ? 'No cancelled appointments'
            : 'No completed appointments',
        message:
            'Your ${statusLabel.toLowerCase()} appointments will appear here.',
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

        final accentColor = isUpcoming
            ? AppColors.accent
            : isCompleted
                ? (badgeLabel == 'Past' ? AppColors.textHint : const Color(0xFF43A047))
                : AppColors.error;

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: accentColor.withValues(alpha: isUpcoming ? 0.12 : 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.15),
                          AppColors.secondary.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16)),
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
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accentColor.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                    color: context.appBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.appBorder.withValues(alpha: 0.5))),
                child: Row(
                  children: [
                    Expanded(child: _AptDetail(Icons.calendar_today_rounded, displayDate)),
                    Container(width: 1, height: 28, color: context.appBorder),
                    Expanded(child: _AptDetail(Icons.access_time_rounded, time)),
                    Container(width: 1, height: 28, color: context.appBorder),
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
                _ScheduledJoinSection(
                  appointmentId: appointments[i].id,
                  data: data,
                  type: type,
                  doctorName: doctorName,
                  specialty: specialty,
                  onCancel: () => _cancelAppointment(appointments[i].id),
                ),
                const SizedBox(height: 10),
                // ── Reschedule button ──────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondary,
                      side: BorderSide(
                          color: AppColors.secondary.withValues(alpha: 0.5)),
                      backgroundColor:
                          AppColors.secondary.withValues(alpha: 0.04),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                    label: const Text('Reschedule',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        )),
                    onPressed: () {
                      final doctorId =
                          data['doctorId'] as String? ?? '';
                      if (doctorId.isNotEmpty) {
                        context.push('/doctors/$doctorId');
                      } else {
                        context.push(AppRoutes.doctors);
                      }
                    },
                  ),
                ),
              ],
              if (isCompleted) ...[
                const SizedBox(height: 12),
                // ── Status timeline ────────────────────────────────────────
                _StatusTimeline(
                  steps: const ['Booked', 'Consulting', 'Completed'],
                  currentIndex: actualStatus == 'completed' ? 2 : 1,
                ),
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
                      ),  // Column
                    ),    // Padding
                  ),      // Expanded
                ],        // Row children
              ),          // Row
            ),            // IntrinsicHeight
          ),              // ClipRRect
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

class _AppointmentCardSkeleton extends StatelessWidget {
  const _AppointmentCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: const IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppShimmer(child: SizedBox(width: 4, height: double.infinity)),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: AppShimmer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          SkeletonBox(width: 56, height: 56, radius: 16),
                          SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SkeletonBox(width: double.infinity, height: 14, radius: 4),
                            SizedBox(height: 6),
                            SkeletonBox(width: 140, height: 11, radius: 4),
                          ])),
                          SizedBox(width: 8),
                          SkeletonBox(width: 64, height: 24, radius: 12),
                        ]),
                        SizedBox(height: 14),
                        SkeletonBox(width: double.infinity, height: 44, radius: 12),
                        SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: SkeletonBox(width: double.infinity, height: 40, radius: 10)),
                          SizedBox(width: 10),
                          Expanded(child: SkeletonBox(width: double.infinity, height: 40, radius: 10)),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                  .copyWith(color: context.appTextPrimary),
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

// ── Status timeline for completed appointments ────────────────────────────────

class _StatusTimeline extends StatelessWidget {
  final List<String> steps;
  final int currentIndex;
  const _StatusTimeline({required this.steps, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          final filled = (i ~/ 2) < currentIndex;
          return Expanded(
            child: Container(
              height: 2,
              color: filled
                  ? const Color(0xFF43A047)
                  : context.appBorder,
            ),
          );
        }
        final stepIdx = i ~/ 2;
        final isDone = stepIdx < currentIndex;
        final isCurrent = stepIdx == currentIndex;
        final color = isDone || isCurrent
            ? const Color(0xFF43A047)
            : AppColors.textHint;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isDone || isCurrent ? color : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              steps[stepIdx],
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 9,
                fontWeight:
                    isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ── Scheduled join section ────────────────────────────────────────────────────
//
// Shows a time-gated "Join Now" button for Video/Audio appointments.
// Join window: 10 minutes before the slot through 30 minutes after.
// Outside the window a subtle countdown chip shows when joining opens.
//
class _ScheduledJoinSection extends StatefulWidget {
  final String appointmentId;
  final Map<String, dynamic> data;
  final String type;
  final String doctorName;
  final String specialty;
  final VoidCallback onCancel;

  const _ScheduledJoinSection({
    required this.appointmentId,
    required this.data,
    required this.type,
    required this.doctorName,
    required this.specialty,
    required this.onCancel,
  });

  @override
  State<_ScheduledJoinSection> createState() => _ScheduledJoinSectionState();
}

class _ScheduledJoinSectionState extends State<_ScheduledJoinSection>
    with SingleTickerProviderStateMixin {
  Timer? _ticker;
  late AnimationController _pulseCtrl;
  bool _joining = false;

  // ── Join window constants ──────────────────────────────────────────────────
  static const _openBeforeMin  = 10;  // window opens 10 min before slot
  static const _closeAfterMin  = 30;  // window closes 30 min after slot
  static const _alertBeforeMin = 15;  // show countdown chip from 15 min out

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    // Rebuild every 30 s so time-based UI stays fresh.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Time helpers ───────────────────────────────────────────────────────────

  static DateTime? _parseSlot(String dateStr, String timeStr) {
    if (dateStr.isEmpty || timeStr.isEmpty) return null;
    try {
      DateTime? date;
      try { date = DateTime.parse(dateStr); } catch (_) {
        for (final fmt in [
          DateFormat('EEE, d MMM yyyy'),
          DateFormat('EEE, dd MMM yyyy'),
          DateFormat('d MMM yyyy'),
        ]) {
          try { date = fmt.parse(dateStr); break; } catch (_) {}
        }
      }
      if (date == null) return null;
      final parts = timeStr.trim().split(' ');
      final hm    = parts[0].split(':');
      int h       = int.parse(hm[0]);
      final m     = int.parse(hm[1]);
      if (parts.length > 1 && parts[1].toUpperCase() == 'PM' && h != 12) h += 12;
      if (parts.length > 1 && parts[1].toUpperCase() == 'AM' && h == 12) h = 0;
      return DateTime(date.year, date.month, date.day, h, m);
    } catch (_) { return null; }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> _joinCall() async {
    if (_joining) return;
    setState(() => _joining = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { setState(() => _joining = false); return; }

    final data        = widget.data;
    final doctorName  = widget.doctorName;
    final specialty   = widget.specialty;
    final photoUrl    = data['doctorPhotoUrl'] as String? ?? '';
    final type        = data['consultationType'] as String? ?? 'Video';
    final db          = FirebaseFirestore.instance;

    // Re-read appointment to get the freshest consultationId (doctor may have
    // already started the consultation from their side).
    String? consultationId;
    String? existingStatus;
    try {
      final snap = await db.collection('appointments').doc(widget.appointmentId).get();
      consultationId = (snap.data()?['consultationId'] as String?)
          ?.trim()
          .replaceAll('', '');
      if (consultationId != null && consultationId.isNotEmpty) {
        final cSnap = await db.collection('consultations').doc(consultationId).get();
        existingStatus = cSnap.data()?['status'] as String?;
      }
    } catch (_) {}

    if (!mounted) { setState(() => _joining = false); return; }

    // Doctor already made the call active — jump straight to video.
    if (consultationId != null &&
        consultationId.isNotEmpty &&
        existingStatus == 'active') {
      context.push(
        AppRoutes.videoCall.replaceFirst(':id', consultationId),
        extra: {'name': doctorName, 'specialty': specialty},
      );
      setState(() => _joining = false);
      return;
    }

    // Doctor created a consultation (status pending/scheduled_waiting) — use it.
    if (consultationId != null && consultationId.isNotEmpty) {
      context.push(
        AppRoutes.outgoingCall,
        extra: {
          'consultationId': consultationId,
          'doctorName':     doctorName,
          'doctorSpecialty': specialty,
          'doctorPhotoUrl': photoUrl,
          'isScheduled':    true,
        },
      );
      setState(() => _joining = false);
      return;
    }

    // Neither side has created a consultation yet — patient goes first.
    String patientName = user.displayName ?? user.phoneNumber ?? 'Patient';
    try {
      final uSnap = await db.collection('users').doc(user.uid).get();
      final n = (uSnap.data()?['name'] as String?)?.trim() ?? '';
      if (n.isNotEmpty) patientName = n;
    } catch (_) {}

    final consultRef = db.collection('consultations').doc();
    final now        = FieldValue.serverTimestamp();
    try {
      final batch = db.batch();
      batch.set(consultRef, {
        'appointmentId':   widget.appointmentId,
        'channelName':     widget.appointmentId, // stable channel = appointment doc ID
        'doctorId':        data['doctorId']      ?? '',
        'doctorName':      doctorName,
        'doctorSpecialty': specialty,
        'doctorPhotoUrl':  photoUrl,
        'patientId':       user.uid,
        'patientName':     patientName,
        'consultationType': type,
        'chiefComplaint':  data['chiefComplaint'] ?? '',
        'callerType':      'patient',
        'isScheduled':     true,
        'status':          'scheduled_waiting',
        'createdAt':       now,
        'updatedAt':       now,
      });
      batch.update(db.collection('appointments').doc(widget.appointmentId), {
        'consultationId': consultRef.id,
      });
      await batch.commit();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not join: ${e.toString()}'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
      setState(() => _joining = false);
      return;
    }

    if (!mounted) { setState(() => _joining = false); return; }
    context.push(
      AppRoutes.outgoingCall,
      extra: {
        'consultationId':  consultRef.id,
        'doctorName':      doctorName,
        'doctorSpecialty': specialty,
        'doctorPhotoUrl':  photoUrl,
        'isScheduled':     true,
      },
    );
    setState(() => _joining = false);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dateStr = widget.data['date'] as String? ?? '';
    final timeStr = widget.data['time'] as String? ?? '';
    final type    = widget.type;

    // Non-video/audio types get simple static buttons.
    if (type != 'Video' && type != 'Audio') {
      return _buildStaticActionRow(context, type);
    }

    final slot = _parseSlot(dateStr, timeStr);
    final now  = DateTime.now();

    if (slot == null) {
      // Can't parse time — show static join button as fallback.
      return _buildActionRow(context, inWindow: true);
    }

    final diffMin = slot.difference(now).inMinutes; // negative = slot is past

    // ── In join window ─────────────────────────────────────────────────────
    if (diffMin >= -_closeAfterMin && diffMin <= _openBeforeMin) {
      final consultationId =
          (widget.data['consultationId'] as String?)?.trim() ?? '';
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        key: ValueKey(consultationId),
        stream: _consultationStream(),
        builder: (context, snap) {
          final cData   = snap.data?.data();
          final cStatus = cData?['status'] as String?;

          // Doctor already made the session active — show "Rejoin" instantly.
          if (cStatus == 'active') {
            return _buildActionRow(context, inWindow: true, label: 'Rejoin Call');
          }

          // Patient is already waiting in OutgoingCallScreen — show status chip.
          if (cStatus == 'scheduled_waiting') {
            return _buildWaitingRow(context);
          }

          // Doctor initiated from their side (callerType: 'doctor', pending).
          if (cStatus == 'pending' &&
              (cData?['callerType'] as String?) == 'doctor') {
            return _buildDoctorCallingRow(context, snap.data?.id ?? '');
          }

          return _buildActionRow(context, inWindow: true);
        },
      );
    }

    // ── Approaching window (show countdown) ────────────────────────────────
    if (diffMin > _openBeforeMin && diffMin <= _alertBeforeMin) {
      return _buildCountdownRow(context, diffMin);
    }

    // ── Far out — show soft "opens at" chip + cancel ───────────────────────
    return _buildFarOutRow(context, slot);
  }

  // ── Sub-builders ───────────────────────────────────────────────────────────

  Widget _buildActionRow(BuildContext context, {
    required bool inWindow,
    String label = 'Join Now',
  }) {
    return Row(children: [
      Expanded(child: _cancelBtn()),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, child) => Transform.scale(
            scale: inWindow ? (1.0 + _pulseCtrl.value * 0.03) : 1.0,
            child: child,
          ),
          child: GestureDetector(
            onTap: _joining ? null : _joinCall,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: inWindow
                    ? [BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      )]
                    : null,
              ),
              child: _joining
                  ? const Center(child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white)))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.video_call_rounded,
                          size: 18, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(label,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          )),
                    ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildWaitingRow(BuildContext context) {
    return Row(children: [
      Expanded(child: _cancelBtn()),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Waiting for doctor',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w600, color: AppColors.primary)),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildDoctorCallingRow(BuildContext context, String consultationId) {
    return Row(children: [
      Expanded(child: _cancelBtn()),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: GestureDetector(
          onTap: () => context.push(
            AppRoutes.incomingCall,
            extra: {
              'consultationId':   consultationId,
              'doctorName':       widget.doctorName,
              'doctorSpecialty':  widget.specialty,
              'consultationType': widget.data['consultationType'] ?? 'Video',
              'doctorPhotoUrl':   widget.data['doctorPhotoUrl']   ?? '',
            },
          ),
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, child) => Transform.scale(
              scale: 1.0 + _pulseCtrl.value * 0.03,
              child: child,
            ),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF43A047), Color(0xFF1B5E20)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(
                  color: const Color(0xFF43A047).withValues(alpha: 0.4),
                  blurRadius: 14, offset: const Offset(0, 4),
                )],
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.phone_in_talk_rounded, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text('Doctor is calling',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildCountdownRow(BuildContext context, int diffMin) {
    return Row(children: [
      Expanded(child: _cancelBtn()),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.access_time_rounded, size: 15, color: Colors.orange),
            const SizedBox(width: 6),
            Text(
              'Opens in $diffMin min',
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w600, color: Colors.orange),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildFarOutRow(BuildContext context, DateTime slot) {
    final label = DateFormat('h:mm a').format(
      slot.subtract(const Duration(minutes: _openBeforeMin)));
    return Row(children: [
      Expanded(child: _cancelBtn()),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: context.appBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.appBorder),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.lock_clock_rounded,
                size: 14, color: context.appTextHint),
            const SizedBox(width: 6),
            Text(
              'Join opens at $label',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w500, color: context.appTextHint),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildStaticActionRow(BuildContext context, String type) {
    final icon = type == 'Chat' ? Icons.chat_bubble_rounded : Icons.directions_rounded;
    final label = type == 'Chat' ? 'Chat Now' : 'Directions';
    return Row(children: [
      Expanded(child: _cancelBtn()),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: GestureDetector(
          onTap: () {
            if (type == 'Chat') {
              context.push(AppRoutes.consultation);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Please visit the clinic at your scheduled time.'),
                behavior: SnackBarBehavior.floating,
              ));
            }
          },
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 5),
              Text(label,
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _cancelBtn() => GestureDetector(
    onTap: widget.onCancel,
    child: Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.cancel_outlined, size: 15, color: AppColors.error),
        SizedBox(width: 5),
        Text('Cancel',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12,
              fontWeight: FontWeight.w600, color: AppColors.error)),
      ]),
    ),
  );

  Stream<DocumentSnapshot<Map<String, dynamic>>> _consultationStream() {
    final consultationId =
        (widget.data['consultationId'] as String?)?.trim() ?? '';
    if (consultationId.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('consultations')
        .doc(consultationId)
        .snapshots();
  }
}
