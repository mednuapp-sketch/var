import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/diagnostic_report.dart';
import '../providers/lab_providers.dart';

class LabReportsScreen extends ConsumerWidget {
  const LabReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(labReportsProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.labReports,
      title: 'Reports',
      body: reports.when(
        loading: () => const ListLoadingState(hasAvatar: false),
        error: (_, __) => const NetworkErrorState(),
        data: (list) {
          if (list.isEmpty) {
            return const AppEmptyState(
              icon: Icons.description_outlined,
              title: 'No reports uploaded yet',
              message: 'Reports you upload for completed bookings appear here.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, i) => _ReportTile(report: list[i]),
          );
        },
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final DiagnosticReport report;
  const _ReportTile({required this.report});

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(report.fileUrl);
    var opened = false;
    if (uri != null) {
      // launchUrl *throws* (ACTIVITY_NOT_FOUND) when no viewer/browser is
      // installed rather than returning false — catching keeps that from
      // becoming an unhandled async error.
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && context.mounted) {
      FeedbackService.showError(context, 'Could not open this report.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => _open(context),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              report.fileType == 'pdf' ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        report.testName,
                        style: AppTextStyles.labelLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (report.version > 1) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'v${report.version}',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${report.patientName} • ${DateFormat('d MMM, h:mm a').format(report.uploadedAt)}',
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.open_in_new_rounded, color: AppColors.textHint, size: 18),
        ],
      ),
    );
  }
}
