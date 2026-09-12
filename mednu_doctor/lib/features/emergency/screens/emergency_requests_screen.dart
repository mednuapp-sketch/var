import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';

/// Lists every "Emergency Doctor" SOS request (`service_requests` where
/// `type == 'emergency_doctor'`) from the last 24 hours, newest first.
///
/// This screen closing a real gap: `onEmergencyDoctorRequest`
/// (functions/index.js) already broadcasts a critical push + writes a
/// `doctor_notifications` item to every active doctor the moment a patient
/// triggers SOS, and tapping that notification already routed here
/// (see doctor_notifications_screen.dart's `_routeFor` — previously pointed
/// at IncomingRequestScreen, which queries `consultations` by `doctorId` and
/// could never show an emergency request, since these broadcast to every
/// doctor rather than being assigned to one). Nothing anywhere actually
/// read `service_requests[type=emergency_doctor]` back for display — a
/// doctor got a loud, urgent alert with no way to act on it in-app.
///
/// Deliberately no claim/accept transaction: for a genuine emergency, any
/// number of doctors independently calling the patient is safer than
/// gating response behind a single "first claimer wins" lock the way a
/// routine booking would. "Mark Handled" only declutters *this* doctor's
/// own list (touches `status` only — firestore.rules already lets any
/// doctor update any service_requests doc) — it does not hide the request
/// from other doctors.
class EmergencyRequestsScreen extends ConsumerWidget {
  const EmergencyRequestsScreen({super.key});

  static final _requestsStream = FirebaseFirestore.instance
      .collection('service_requests')
      .where('type', isEqualTo: 'emergency_doctor')
      .where('createdAt', isGreaterThan: Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 24))))
      .orderBy('createdAt', descending: true)
      .snapshots();

  Future<void> _call(BuildContext context, String phone) async {
    if (phone.isEmpty) {
      FeedbackService.showError(context, 'No phone number on file for this patient.');
      return;
    }
    var opened = false;
    try {
      opened = await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      FeedbackService.showError(context, 'Could not start a call on this device.');
    }
  }

  Future<void> _openDirections(BuildContext context, double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      FeedbackService.showError(context, 'Could not open maps on this device.');
    }
  }

  Future<void> _markHandled(BuildContext context, String requestId) async {
    try {
      await FirebaseFirestore.instance.collection('service_requests').doc(requestId).update({
        'status': 'acknowledged',
        'reason': 'Marked handled by a doctor',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (context.mounted) {
        FeedbackService.showError(context, 'Could not update this request: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SharedAppShell(
      currentRoute: '',
      title: 'Emergency Requests',
      showBottomNav: false,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _requestsStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return const AppErrorState();

          final docs = snap.data?.docs
                  .where((d) => (d.data()['status'] as String?) == 'pending')
                  .toList() ??
              const [];

          if (docs.isEmpty) {
            return const AppEmptyState(
              icon: Icons.emergency_rounded,
              title: 'No emergency requests',
              message: 'Urgent patient SOS requests from the last 24 hours will appear here.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final requestId = docs[i].id;
              final patientName = d['patientName'] as String? ?? 'Patient';
              final patientPhone = d['patientPhone'] as String? ?? '';
              final lat = (d['latitude'] as num?)?.toDouble();
              final lng = (d['longitude'] as num?)?.toDouble();
              final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
              final ageMinutes =
                  createdAt == null ? null : DateTime.now().difference(createdAt).inMinutes;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: AppColors.error.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 6)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('URGENT',
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.4)),
                        ),
                        const Spacer(),
                        Text(
                          ageMinutes == null ? '' : '$ageMinutes min ago',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SharedProfileAvatar(name: patientName, size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(patientName, style: AppTextStyles.labelLarge),
                        ),
                      ],
                    ),
                    if (lat != null && lng != null) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => _openDirections(context, lat, lng),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on_rounded, size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text('Open location in Maps',
                                style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.primary, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: GradientButton(
                            label: 'Call Patient',
                            icon: Icons.call_rounded,
                            colors: const [AppColors.error, Color(0xFFE57373)],
                            onTap: () => _call(context, patientPhone),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: () => _markHandled(context, requestId),
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary),
                          child: const Text('Mark Handled'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
