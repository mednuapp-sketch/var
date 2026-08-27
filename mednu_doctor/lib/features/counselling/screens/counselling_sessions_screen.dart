import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/counselling_session.dart';
import '../providers/counselling_providers.dart';

/// Sessions as an "Upcoming"/"History" toggle over one shared timeline list
/// — same visual language as the Physiotherapy module's Sessions screen.
class CounsellingSessionsScreen extends ConsumerStatefulWidget {
  const CounsellingSessionsScreen({super.key});

  @override
  ConsumerState<CounsellingSessionsScreen> createState() => _CounsellingSessionsScreenState();
}

class _CounsellingSessionsScreenState extends ConsumerState<CounsellingSessionsScreen>
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
    return SharedAppShell(
      currentRoute: AppRoutes.counsellingSessions,
      title: 'Sessions',
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tab,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [Tab(text: 'Upcoming'), Tab(text: 'History')],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [_SessionTimeline(upcoming: true), _SessionTimeline(upcoming: false)],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTimeline extends ConsumerWidget {
  final bool upcoming;
  const _SessionTimeline({required this.upcoming});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = upcoming
        ? ref.watch(upcomingCounsellingSessionsProvider)
        : ref.watch(counsellingSessionHistoryProvider);

    if (sessions.isEmpty) {
      return AppEmptyState(
        icon: upcoming ? Icons.event_available_rounded : Icons.history_rounded,
        title: upcoming ? 'No upcoming sessions' : 'No session history yet',
        message: upcoming
            ? 'New and claimed sessions will appear here.'
            : 'Completed and cancelled sessions will show up here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: sessions.length,
      itemBuilder: (context, i) => _TimelineTile(session: sessions[i], isLast: i == sessions.length - 1),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final CounsellingSession session;
  final bool isLast;
  const _TimelineTile({required this.session, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: session.status.color,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: session.status.color.withValues(alpha: 0.4), blurRadius: 5)],
                  ),
                ),
                if (!isLast) Expanded(child: Container(width: 2, color: AppColors.divider)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PremiumCard(
                onTap: () => context.push(AppRoutes.counsellingSessionDetail, extra: {'sessionId': session.id}),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.sessionTitle,
                            style: AppTextStyles.labelLarge.copyWith(color: session.status.color),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        StatusBadge(label: session.status.label, color: session.status.color),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(session.patientName, style: AppTextStyles.bodyMedium),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InfoChip(
                            icon: Icons.schedule_rounded,
                            label: session.preferredDate.isNotEmpty
                                ? '${session.preferredDate}, ${session.preferredTime}'
                                : session.preferredTime,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          CurrencyFormatter.format(session.amount),
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.success),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
