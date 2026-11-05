import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../caregiver/models/visit.dart';
import '../providers/care_assistant_providers.dart';
import '../widgets/care_job_widgets.dart';

/// Three live tabs — New (accept / decline), Active, History. Counts in the
/// tab labels update as requests arrive or are taken.
class CareAssistantRequestsScreen extends ConsumerWidget {
  const CareAssistantRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incoming = ref.watch(incomingCareRequestsProvider);
    final active = ref.watch(activeCareJobsProvider);
    final history = ref.watch(careJobHistoryProvider);

    return DefaultTabController(
      length: 3,
      child: SharedAppShell(
        currentRoute: AppRoutes.careAssistantRequests,
        title: 'Requests',
        body: Column(
          children: [
            Container(
              color: AppColors.surface,
              child: TabBar(
                labelColor: careAssistantTeal,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: careAssistantTeal,
                tabs: [
                  Tab(text: 'New (${incoming.length})'),
                  Tab(text: 'Active (${active.length})'),
                  const Tab(text: 'History'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _List(
                    visits: incoming,
                    emptyIcon: Icons.inbox_rounded,
                    emptyTitle: 'No new requests',
                    emptyMessage: 'New requests from patients appear here instantly.',
                    builder: (v) => CareRequestCard(visit: v),
                  ),
                  _List(
                    visits: active,
                    emptyIcon: Icons.directions_walk_rounded,
                    emptyTitle: 'No active jobs',
                    emptyMessage: 'Jobs you accept will show up here.',
                    builder: (v) => CareJobTile(visit: v),
                  ),
                  _List(
                    visits: history,
                    emptyIcon: Icons.history_rounded,
                    emptyTitle: 'No job history yet',
                    emptyMessage: 'Completed and cancelled jobs will show up here.',
                    builder: (v) => CareJobTile(visit: v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  final List<Visit> visits;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final Widget Function(Visit) builder;
  const _List({
    required this.visits,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    if (visits.isEmpty) {
      return AppEmptyState(icon: emptyIcon, title: emptyTitle, message: emptyMessage);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: visits.length,
      itemBuilder: (context, i) => builder(visits[i]),
    );
  }
}
