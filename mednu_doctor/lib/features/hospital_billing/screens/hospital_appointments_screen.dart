import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../services/hospital_appointment_service.dart';
import '../services/hospital_profile_service.dart';

/// The hospital billing desk's OP token queue: every `hospital_appointments`
/// booking for this hospital, live, with check-in / complete / no-show
/// actions. Mirrors HospitalPaymentsScreen's profile-stream-then-list shape.
class HospitalAppointmentsScreen extends StatelessWidget {
  const HospitalAppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          const GradientSliverAppBar(
            headerIcon: Icons.event_note_rounded,
            title: 'OP Appointments',
            subtitle: 'Live walk-in queue',
            expandedHeight: 110,
          ),
          SliverToBoxAdapter(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: HospitalProfileService.profileStream(uid),
              builder: (context, profileSnap) {
                final profile = profileSnap.data?.data();
                final hospitalId = profile?['hospitalId'] as String?;
                final hospitalName = profile?['hospitalName'] as String?;

                if (profileSnap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (hospitalId == null || hospitalId.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(20, 48, 20, 20),
                    child: Column(
                      children: [
                        Icon(Icons.hourglass_top_rounded, size: 48, color: AppColors.textHint),
                        SizedBox(height: 16),
                        Text('Awaiting hospital link', style: AppTextStyles.h4, textAlign: TextAlign.center),
                        SizedBox(height: 8),
                        Text(
                          'Our team is confirming which hospital this account represents. '
                          'OP bookings will appear here once that\'s done.',
                          style: AppTextStyles.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return _QueueList(hospitalId: hospitalId, hospitalName: hospitalName);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueList extends StatelessWidget {
  final String hospitalId;
  final String? hospitalName;
  const _QueueList({required this.hospitalId, required this.hospitalName});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(hospitalName ?? 'Your hospital', style: AppTextStyles.sectionTitle),
        ),
        StreamBuilder<List<HospitalAppointment>>(
          stream: HospitalAppointmentService.streamForHospital(hospitalId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final appointments = snap.data ?? const <HospitalAppointment>[];
            if (appointments.isEmpty) {
              return const AppEmptyState(
                icon: Icons.event_note_outlined,
                title: 'No OP appointments yet',
                message: 'New bookings will show up here the moment a patient pays.',
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
                children: appointments
                    .map((a) => _AppointmentCard(appointment: a, hospitalId: hospitalId))
                    .toList(),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AppointmentCard extends StatefulWidget {
  final HospitalAppointment appointment;
  final String hospitalId;
  const _AppointmentCard({required this.appointment, required this.hospitalId});

  @override
  State<_AppointmentCard> createState() => _AppointmentCardState();
}

class _AppointmentCardState extends State<_AppointmentCard> {
  bool _busy = false;

  static const _statusMeta = {
    'booked': (label: 'Booked', color: AppColors.info),
    'checked_in': (label: 'Checked In', color: AppColors.warning),
    'completed': (label: 'Completed', color: AppColors.success),
    'no_show': (label: 'No Show', color: AppColors.error),
    'cancelled': (label: 'Cancelled', color: AppColors.textHint),
  };

  Future<void> _act(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this appointment. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final meta = _statusMeta[a.status] ?? (label: a.status, color: AppColors.textHint);

    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.confirmation_number_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.patientName, style: AppTextStyles.labelLarge),
                    Text(a.opToken, style: AppTextStyles.caption),
                  ],
                ),
              ),
              StatusBadge(label: meta.label, color: meta.color),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textHint),
              const SizedBox(width: 6),
              Text('${a.date} · ${a.time}', style: AppTextStyles.bodySmall),
            ],
          ),
          if (a.reasonForVisit.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(a.reasonForVisit, style: AppTextStyles.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          if (a.status == 'booked' || a.status == 'checked_in') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (a.status == 'booked')
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _act(() => HospitalAppointmentService.checkIn(a.id, hospitalId: widget.hospitalId)),
                      icon: const Icon(Icons.how_to_reg_rounded, size: 16),
                      label: const Text('Check In'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.warning, side: const BorderSide(color: AppColors.warning)),
                    ),
                  ),
                if (a.status == 'checked_in')
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _act(() => HospitalAppointmentService.markCompleted(a.id, hospitalId: widget.hospitalId)),
                      icon: const Icon(Icons.task_alt_rounded, size: 16),
                      label: const Text('Complete'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.success, side: const BorderSide(color: AppColors.success)),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _act(() => HospitalAppointmentService.markNoShow(a.id, hospitalId: widget.hospitalId)),
                    icon: const Icon(Icons.person_off_outlined, size: 16),
                    label: const Text('No Show'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
