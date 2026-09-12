import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/visit.dart';
import '../providers/caregiver_providers.dart';

/// Visits as a connected timeline (an "Upcoming"/"History" toggle over one
/// shared timeline list) — the same visual language as the Ambulance
/// module's Trip History, since both are fundamentally "a sequence of
/// scheduled events," just applied to a different domain.
class CaregiverAssignedVisitsScreen extends ConsumerStatefulWidget {
  const CaregiverAssignedVisitsScreen({super.key});

  @override
  ConsumerState<CaregiverAssignedVisitsScreen> createState() => _CaregiverAssignedVisitsScreenState();
}

class _CaregiverAssignedVisitsScreenState extends ConsumerState<CaregiverAssignedVisitsScreen>
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
      currentRoute: AppRoutes.caregiverAssignedVisits,
      title: 'Assigned Visits',
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
              children: const [_VisitTimeline(upcoming: true), _VisitTimeline(upcoming: false)],
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitTimeline extends ConsumerWidget {
  final bool upcoming;
  const _VisitTimeline({required this.upcoming});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visits = upcoming ? ref.watch(upcomingVisitsProvider) : ref.watch(visitHistoryProvider);

    if (visits.isEmpty) {
      return AppEmptyState(
        icon: upcoming ? Icons.event_available_rounded : Icons.history_rounded,
        title: upcoming ? 'No upcoming visits' : 'No visit history yet',
        message: upcoming ? 'New assignments will appear here.' : 'Completed and missed visits will show up here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: visits.length,
      itemBuilder: (context, i) => _TimelineTile(visit: visits[i], isLast: i == visits.length - 1),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final Visit visit;
  final bool isLast;
  const _TimelineTile({required this.visit, required this.isLast});

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
                    color: visit.type.color,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: visit.type.color.withValues(alpha: 0.4), blurRadius: 5)],
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
                onTap: () => context.push(AppRoutes.caregiverVisitDetail, extra: {'visitId': visit.id}),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(visit.type.label, style: AppTextStyles.labelLarge.copyWith(color: visit.type.color))),
                        StatusBadge(label: visit.status.label, color: visit.status.color),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(visit.patientName, style: AppTextStyles.bodyMedium),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Wrap, not a fixed Row: two InfoChips (a formatted
                        // date-time string plus a duration) sitting next to
                        // an unwrapped fare Text with no Flexible anywhere
                        // could exceed the card's width on narrow phones —
                        // Wrap flows to a second line instead of throwing a
                        // RenderFlex overflow, and keeps the fare amount
                        // fully visible rather than risking an ellipsis
                        // truncating money.
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              InfoChip(icon: Icons.schedule_rounded, label: DateFormat('d MMM, h:mm a').format(visit.scheduledAt)),
                              InfoChip(icon: Icons.timer_outlined, label: '${visit.durationMinutes} min'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(CurrencyFormatter.format(visit.fare), style: AppTextStyles.labelLarge.copyWith(color: AppColors.success)),
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
