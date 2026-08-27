import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/nutrition_appointment.dart';
import '../providers/nutrition_providers.dart';
import '../services/nutrition_appointment_service.dart';

/// Full detail for a single appointment — patient card, schedule, health
/// goal, a simple provider-notes field, and a status-driven action bar.
/// Unlike Physiotherapy/Counselling, status writes here are plain updates
/// (no claim/transaction dance — `nutritionistId` never changes), matching
/// `firestore.rules`' `nutrition_appointments` update rule, which restricts
/// a nutritionist's write to `status`/`updatedAt`/`providerNotes` only.
class NutritionAppointmentDetailScreen extends ConsumerStatefulWidget {
  final String appointmentId;
  const NutritionAppointmentDetailScreen({super.key, required this.appointmentId});

  @override
  ConsumerState<NutritionAppointmentDetailScreen> createState() =>
      _NutritionAppointmentDetailScreenState();
}

class _NutritionAppointmentDetailScreenState extends ConsumerState<NutritionAppointmentDetailScreen> {
  bool _busy = false;
  final _notesCtrl = TextEditingController();
  String? _loadedFor;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _call(String phone) async {
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
    if (!opened && mounted) {
      FeedbackService.showError(context, 'Could not start a call on this device.');
    }
  }

  Future<void> _setStatus(String status, String successMessage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await NutritionAppointmentService.updateStatus(widget.appointmentId, status);
      if (mounted) FeedbackService.showSuccess(context, successMessage);
    } catch (_) {
      if (mounted) FeedbackService.showError(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveNotes() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await NutritionAppointmentService.setProviderNotes(widget.appointmentId, _notesCtrl.text.trim());
      if (mounted) FeedbackService.showSuccess(context, 'Notes saved');
    } catch (_) {
      if (mounted) FeedbackService.showError(context, 'Could not save notes. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appointment = ref.watch(nutritionAppointmentDocProvider(widget.appointmentId)).valueOrNull;

    if (appointment != null && _loadedFor != appointment.id) {
      _loadedFor = appointment.id;
      _notesCtrl.text = appointment.providerNotes ?? '';
    }

    return SharedAppShell(
      currentRoute: '',
      title: 'Appointment Details',
      showBottomNav: false,
      body: appointment == null
          ? const AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Appointment not found',
              message: 'This appointment may have been removed.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [appointment.status.color, appointment.status.color.withValues(alpha: 0.72)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(color: appointment.status.color.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.restaurant_menu_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(appointment.consultationType, style: AppTextStyles.onPrimaryH2.copyWith(fontSize: 18), overflow: TextOverflow.ellipsis),
                            Text(
                              appointment.date.isNotEmpty
                                  ? '${appointment.date} • ${appointment.timeSlot}'
                                  : appointment.timeSlot,
                              style: AppTextStyles.onPrimaryBody,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PremiumCard(
                  child: Row(
                    children: [
                      SharedProfileAvatar(name: appointment.userName, size: 46),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(appointment.userName, style: AppTextStyles.labelLarge),
                            Text(appointment.status.label, style: AppTextStyles.bodySmall.copyWith(color: appointment.status.color)),
                          ],
                        ),
                      ),
                      IconButton.filled(
                        onPressed: () => _call(appointment.userPhone),
                        icon: const Icon(Icons.call_rounded),
                        style: IconButton.styleFrom(backgroundColor: AppColors.success),
                      ),
                    ],
                  ),
                ),
                if (appointment.healthGoal.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  PremiumCard(
                    child: Row(
                      children: [
                        const Icon(Icons.flag_outlined, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Health goal: ${appointment.healthGoal}', style: AppTextStyles.bodyMedium)),
                      ],
                    ),
                  ),
                ],
                if (appointment.notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  PremiumCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notes_rounded, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(child: Text(appointment.notes, style: AppTextStyles.bodyMedium)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                PremiumCard(
                  child: Row(
                    children: [
                      const Icon(Icons.currency_rupee_rounded, color: AppColors.primary),
                      const SizedBox(width: 10),
                      const Text('Consultation Fee', style: AppTextStyles.bodyMedium),
                      const Spacer(),
                      Text(
                        CurrencyFormatter.format(appointment.fee),
                        style: AppTextStyles.labelLarge.copyWith(color: AppColors.success),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your Notes', style: AppTextStyles.labelMedium),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _notesCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Diet plan notes, follow-up reminders…',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _saveNotes,
                          child: const Text('Save Notes'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _PrimaryActions(
                  status: appointment.status,
                  busy: _busy,
                  onConfirm: () => _setStatus('confirmed', 'Appointment confirmed'),
                  onStart: () => _setStatus('in_progress', 'Appointment started'),
                  onComplete: () => _setStatus('completed', 'Appointment completed'),
                  onCancel: () => _setStatus('cancelled', 'Appointment cancelled'),
                ),
              ],
            ),
    );
  }
}

class _PrimaryActions extends StatelessWidget {
  final NutritionAppointmentStatus status;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onStart;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  const _PrimaryActions({
    required this.status,
    required this.busy,
    required this.onConfirm,
    required this.onStart,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case NutritionAppointmentStatus.pending:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onCancel,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Decline'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GradientButton(
                label: 'Confirm',
                icon: Icons.check_rounded,
                isLoading: busy,
                onTap: busy ? null : onConfirm,
              ),
            ),
          ],
        );
      case NutritionAppointmentStatus.confirmed:
        return Column(
          children: [
            GradientButton(
              label: 'Start Appointment',
              icon: Icons.play_arrow_rounded,
              isLoading: busy,
              onTap: busy ? null : onStart,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : onCancel,
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Cancel Appointment'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
            ),
          ],
        );
      case NutritionAppointmentStatus.inProgress:
        return GradientButton(
          label: 'Complete Appointment',
          icon: Icons.task_alt_rounded,
          colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
          isLoading: busy,
          onTap: busy ? null : onComplete,
        );
      case NutritionAppointmentStatus.completed:
      case NutritionAppointmentStatus.cancelled:
        return const SizedBox();
    }
  }
}
