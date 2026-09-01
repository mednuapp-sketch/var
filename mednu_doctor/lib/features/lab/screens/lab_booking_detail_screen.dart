import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/diagnostic_booking.dart';
import '../providers/lab_providers.dart';
import '../services/lab_booking_service.dart';
import '../services/lab_profile_service.dart';

/// Every status transition in the Lab module's pipeline happens from this
/// one screen — accept/reject, assign technician, mark sample collected,
/// mark processing, upload report, mark completed. Each action is a single
/// `LabBookingService` call; the realtime `bookingDetailProvider` stream is
/// what actually updates the UI, not the action's return value, so this
/// screen never goes stale even if another device/tab changes the booking.
class LabBookingDetailScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const LabBookingDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<LabBookingDetailScreen> createState() => _LabBookingDetailScreenState();
}

class _LabBookingDetailScreenState extends ConsumerState<LabBookingDetailScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? successMessage}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (successMessage != null && mounted) {
        FeedbackService.showSuccess(context, successMessage);
      }
    } on LabBookingConflictException catch (e) {
      // The realtime `bookingDetailProvider` stream will refresh this
      // screen to the booking's actual current state momentarily — this
      // message just explains *why* the tap didn't do what was expected.
      if (mounted) FeedbackService.showError(context, e.message);
    } catch (e) {
      if (mounted) FeedbackService.showError(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assignTechnician(DiagnosticBooking booking) async {
    final nameCtrl = TextEditingController();
    DateTime? pickedTime;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setSheetState) => AlertDialog(
          title: const Text('Assign Technician'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Technician name'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text(pickedTime == null
                    ? 'Pick collection time'
                    : '${pickedTime!.day}/${pickedTime!.month} ${pickedTime!.hour}:${pickedTime!.minute.toString().padLeft(2, '0')}'),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: dialogContext,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (date == null || !dialogContext.mounted) return;
                  final time = await showTimePicker(
                    context: dialogContext,
                    initialTime: TimeOfDay.now(),
                  );
                  if (time == null) return;
                  setSheetState(() {
                    pickedTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: nameCtrl.text.trim().isEmpty && pickedTime == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || nameCtrl.text.trim().isEmpty || pickedTime == null) return;

    final uid = LabProfileService.currentUid;
    if (uid == null) return;

    await _run(
      () => LabBookingService.assignTechnician(
        booking.id,
        labId: uid,
        technicianName: nameCtrl.text.trim(),
        collectionTime: pickedTime!,
      ),
      successMessage: 'Technician assigned',
    );
  }

  static const _allowedReportExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

  Future<void> _uploadReport(DiagnosticBooking booking) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedReportExtensions,
    );
    final picked = result?.files.single;
    final path = picked?.path;
    if (path == null || picked == null) return;

    // FilePicker's allowedExtensions is a filter hint to the OS picker, not
    // a hard guarantee (some platforms/pickers let users override it) — so
    // re-validate type and size before it ever reaches the upload call.
    final extension = picked.extension ?? '';
    final typeError = Validators.fileType(extension, _allowedReportExtensions);
    if (typeError != null) {
      if (mounted) FeedbackService.showError(context, typeError);
      return;
    }
    final sizeError = Validators.fileSize(await File(path).length());
    if (sizeError != null) {
      if (mounted) FeedbackService.showError(context, sizeError);
      return;
    }

    final uid = LabProfileService.currentUid;
    if (uid == null) return;

    await _run(
      () => LabBookingService.uploadReport(
        bookingId: booking.id,
        labId: uid,
        patientId: booking.patientId,
        patientName: booking.patientName,
        testName: booking.testName,
        file: File(path),
      ),
      successMessage: 'Report uploaded',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingAsync = ref.watch(bookingDetailProvider(widget.bookingId));
    final uid = LabProfileService.currentUid;

    return SharedAppShell(
      currentRoute: '',
      title: 'Booking Details',
      showBottomNav: false,
      body: bookingAsync.when(
        loading: () => const PageLoadingState(),
        error: (_, __) => const NetworkErrorState(),
        data: (booking) {
          if (booking == null) {
            return const AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Booking not found',
              message: 'This booking may have been removed.',
            );
          }
          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(booking.testName, style: AppTextStyles.h4),
                          ),
                          StatusBadge(label: booking.status.label, color: booking.status.color),
                        ],
                      ),
                      const SizedBox(height: 12),
                      InfoChip(icon: Icons.person_outline_rounded, label: booking.patientName),
                      const SizedBox(height: 8),
                      if (booking.patientPhone.isNotEmpty)
                        InfoChip(icon: Icons.call_outlined, label: booking.patientPhone),
                      const SizedBox(height: 8),
                      InfoChip(
                        icon: Icons.calendar_today_outlined,
                        label: '${booking.preferredDate} • ${booking.preferredTime}',
                      ),
                      const SizedBox(height: 8),
                      if (booking.address.isNotEmpty)
                        InfoChip(icon: Icons.location_on_outlined, label: booking.address),
                      const SizedBox(height: 8),
                      InfoChip(
                        icon: Icons.currency_rupee_rounded,
                        label: CurrencyFormatter.format(booking.amount),
                      ),
                      if (booking.technicianName != null) ...[
                        const SizedBox(height: 8),
                        InfoChip(
                          icon: Icons.badge_outlined,
                          label: 'Technician: ${booking.technicianName}',
                          color: AppColors.secondary,
                        ),
                      ],
                      if (booking.notes.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('Notes', style: AppTextStyles.labelMedium),
                        const SizedBox(height: 4),
                        Text(booking.notes, style: AppTextStyles.bodyMedium),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ..._buildActions(booking, uid),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildActions(DiagnosticBooking booking, String? uid) {
    if (uid == null) return const [];
    final isMine = booking.labId == uid;

    switch (booking.status) {
      case DiagnosticBookingStatus.pending:
        // A booking made from this lab's own test catalogue arrives already
        // pinned (`labId == uid`) — there's nothing to claim, so it needs a
        // different transition than an unclaimed pool booking (`labId ==
        // null`) does. See LabBookingService.acceptAssignedBooking.
        final isAssignedToMe = booking.labId == uid;
        return [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _run(() => LabBookingService.rejectBooking(booking.id, uid)),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GradientButton(
                  label: isAssignedToMe ? 'Accept' : 'Accept Booking',
                  isLoading: _busy,
                  onTap: () => _run(
                    () => isAssignedToMe
                        ? LabBookingService.acceptAssignedBooking(booking.id, uid)
                        : LabBookingService.acceptBooking(booking.id, uid),
                    successMessage: 'Booking accepted',
                  ),
                ),
              ),
            ],
          ),
        ];
      case DiagnosticBookingStatus.accepted:
        return isMine
            ? [
                GradientButton(
                  label: 'Assign Technician',
                  icon: Icons.person_add_alt_rounded,
                  isLoading: _busy,
                  onTap: () => _assignTechnician(booking),
                ),
              ]
            : const [];
      case DiagnosticBookingStatus.technicianAssigned:
        return isMine
            ? [
                GradientButton(
                  label: 'Mark Sample Collected',
                  icon: Icons.check_circle_outline_rounded,
                  isLoading: _busy,
                  onTap: () => _run(
                    () => LabBookingService.markSampleCollected(booking.id, labId: uid),
                    successMessage: 'Sample marked as collected',
                  ),
                ),
              ]
            : const [];
      case DiagnosticBookingStatus.sampleCollected:
        return isMine
            ? [
                GradientButton(
                  label: 'Start Processing',
                  icon: Icons.science_outlined,
                  isLoading: _busy,
                  onTap: () => _run(
                    () => LabBookingService.markProcessing(booking.id, labId: uid),
                    successMessage: 'Marked as processing',
                  ),
                ),
              ]
            : const [];
      case DiagnosticBookingStatus.processing:
        return isMine
            ? [
                GradientButton(
                  label: 'Upload Report',
                  icon: Icons.upload_file_rounded,
                  isLoading: _busy,
                  onTap: () => _uploadReport(booking),
                ),
              ]
            : const [];
      case DiagnosticBookingStatus.reportUploaded:
        return isMine
            ? [
                if (booking.reportUrl != null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: InfoChip(
                      icon: Icons.description_outlined,
                      label: 'Report uploaded',
                      color: AppColors.success,
                    ),
                  ),
                GradientButton(
                  label: 'Mark Completed',
                  icon: Icons.task_alt_rounded,
                  isLoading: _busy,
                  onTap: () => _run(
                    () => LabBookingService.markCompleted(booking.id, labId: uid),
                    successMessage: 'Booking completed',
                  ),
                ),
              ]
            : const [];
      case DiagnosticBookingStatus.completed:
      case DiagnosticBookingStatus.rejected:
      case DiagnosticBookingStatus.cancelled:
      case DiagnosticBookingStatus.expired:
      case DiagnosticBookingStatus.unknown:
        return const [];
    }
  }
}
