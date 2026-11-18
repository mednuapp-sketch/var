import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/router/app_router.dart';
import '../models/weight_loss_plan.dart';
import '../models/weight_loss_subscription.dart';
import '../providers/nutrition_provider.dart';
import '../services/weight_loss_plan_service.dart';
import '../utils/nutrition_slot_utils.dart';
import 'book_nutrition_appointment_screen.dart'
    show NutritionDateStrip, NutritionSlotGrid;

const _kGreen = Color(0xFF2E7D32);
const _kGreenBg = Color(0xFFF1F8F1);

String _fmtDate(String key) {
  try {
    return DateFormat('d MMM yyyy').format(DateTime.parse(key));
  } catch (_) {
    return key;
  }
}

String _rupees(num v) => '₹${NumberFormat.decimalPattern('en_IN').format(v)}';

String _lapseRule(WeightLossSubscription s) =>
    'Use your consultations by ${_fmtDate(s.lastDay)}. Unused consultations '
    'expire at the end of the plan and are not refunded.';

// ── Entry banner (nutrition home / diet plans / My Services) ─────────────────

/// Compact card that opens the plan screen. Renders nothing unless the patient
/// has an active weight-loss plan.
class WeightLossPlanBanner extends ConsumerWidget {
  final EdgeInsetsGeometry margin;
  const WeightLossPlanBanner({super.key, this.margin = EdgeInsets.zero});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(weightLossSubscriptionsProvider).valueOrNull;
    final active = subs?.where((s) => s.isActive).toList() ?? const [];
    if (active.isEmpty) return const SizedBox.shrink();
    final s = active.first;
    final open = s.availableCount;
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(AppRoutes.nutritionPlan),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.monitor_weight_rounded,
                    color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('My Weight-Loss Plan',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(
                        open > 0
                            ? '$open consultation${open == 1 ? '' : 's'} left to book'
                            : '${s.completedCount}/${s.months} consultations done',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Plan screen ──────────────────────────────────────────────────────────────

class MyWeightLossPlanScreen extends ConsumerWidget {
  const MyWeightLossPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(weightLossSubscriptionsProvider);
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.safeBack(),
        ),
        title: const Text('My Weight-Loss Plan', style: AppTextStyles.h3),
        centerTitle: true,
        backgroundColor: context.appSurface,
        foregroundColor: context.appTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: context.appSurface,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
            child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Could not load your plan. Please try again.',
              textAlign: TextAlign.center),
        )),
        data: (subs) {
          if (subs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.monitor_weight_outlined,
                        size: 48, color: context.appTextHint),
                    const SizedBox(height: 12),
                    Text('No weight-loss plan yet',
                        style: AppTextStyles.h4
                            .copyWith(color: context.appTextPrimary)),
                    const SizedBox(height: 6),
                    Text(
                      'Enrol from Diet Plans: pay once and get one dietician '
                      'consultation every month.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: context.appTextSecondary),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
            physics: const BouncingScrollPhysics(),
            itemCount: subs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 20),
            itemBuilder: (_, i) => _PlanCard(sub: subs[i]),
          );
        },
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final WeightLossSubscription sub;
  const _PlanCard({required this.sub});

  Future<void> _cancel(BuildContext context) async {
    final refundable = !sub.anyCompleted && sub.paymentMode == 'paid';
    final text = refundable
        ? 'You will be refunded the plan amount of ${_rupees(sub.baseTotal)}. '
            'The platform fee of ${_rupees(sub.platformFee)} is non-refundable. '
            'Booked consultations will be cancelled.'
        : sub.anyCompleted
            ? 'A consultation has already been completed, so unused '
                'consultations are not refunded. Consultations you have already '
                'booked stay scheduled.'
            : 'Booked consultations will be cancelled.';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel this plan?'),
        content: Text(text, style: AppTextStyles.bodyMedium.copyWith(height: 1.45)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep plan')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Cancel plan')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final refunded = await WeightLossPlanService.cancelPlan(sub.id);
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(refunded > 0
            ? '${_rupees(refunded)} is being refunded. The platform fee is non-refundable.'
            : 'Your plan was cancelled.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red,
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${sub.months}-month weight-loss plan',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white)),
              const SizedBox(height: 2),
              Text('with ${sub.nutritionistName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: Colors.white70)),
              const SizedBox(height: 10),
              Text(
                sub.isActive
                    ? 'Valid until ${_fmtDate(sub.lastDay)}'
                    : 'Plan ${sub.status == 'cancelled' ? 'cancelled' : 'completed'}',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.white),
              ),
              if (sub.isActive) ...[
                const SizedBox(height: 4),
                Text(_lapseRule(sub),
                    style: AppTextStyles.caption
                        .copyWith(color: Colors.white70, height: 1.4)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final c in sub.credits) ...[
          _CreditTile(sub: sub, credit: c),
          const SizedBox(height: 10),
        ],
        if (sub.isActive)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _cancel(context),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Cancel plan'),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
            ),
          ),
      ],
    );
  }
}

class _CreditTile extends StatelessWidget {
  final WeightLossSubscription sub;
  final PlanCredit credit;
  const _CreditTile({required this.sub, required this.credit});

  (String, Color) get _chip {
    switch (credit.status) {
      case 'booked':
        return ('Booked', const Color(0xFF1565C0));
      case 'completed':
        return ('Completed', _kGreen);
      case 'lapsed':
        return ('Expired', const Color(0xFF9E9E9E));
      case 'cancelled':
        return ('Cancelled', const Color(0xFF9E9E9E));
      default:
        return ('Available', const Color(0xFFE65100));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = _chip;
    final canBook = sub.isActive && credit.isAvailable;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Text('${credit.index}',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Month ${credit.index} consultation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge
                        .copyWith(color: context.appTextPrimary)),
                const SizedBox(height: 2),
                Text(
                    '${_fmtDate(credit.windowStart)} – ${_fmtDate(credit.windowEnd)}',
                    style: AppTextStyles.caption
                        .copyWith(color: context.appTextSecondary)),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ),
              ],
            ),
          ),
          if (canBook) ...[
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      PlanBookConsultationScreen(sub: sub, credit: credit))),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Book',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Book one monthly consultation (no payment) ───────────────────────────────

class PlanBookConsultationScreen extends ConsumerStatefulWidget {
  final WeightLossSubscription sub;
  final PlanCredit credit;
  const PlanBookConsultationScreen(
      {super.key, required this.sub, required this.credit});

  @override
  ConsumerState<PlanBookConsultationScreen> createState() =>
      _PlanBookConsultationScreenState();
}

class _PlanBookConsultationScreenState
    extends ConsumerState<PlanBookConsultationScreen> {
  late final List<DateTime> _dates;
  late DateTime _selected;
  String? _slot;
  String _type = 'online';
  bool _saving = false;
  // Stable per screen instance: a retry never books twice.
  final String _key = 'planbook-${DateTime.now().microsecondsSinceEpoch}';

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selected);

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    var start = DateTime(today.year, today.month, today.day)
        .add(const Duration(days: 1));
    DateTime? ws, we;
    try {
      ws = DateTime.parse(widget.credit.windowStart);
      we = DateTime.parse(widget.credit.windowEnd);
    } catch (_) {}
    if (ws != null && ws.isAfter(start)) start = ws;
    final end = we ?? start.add(const Duration(days: 30));
    final list = <DateTime>[];
    for (var d = start; !d.isAfter(end) && list.length < 45;
        d = d.add(const Duration(days: 1))) {
      list.add(d);
    }
    _dates = list;
    _selected = list.isNotEmpty ? list.first : start;
  }

  Future<void> _confirm() async {
    final slot = _slot;
    if (slot == null || _saving || _dates.isEmpty) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await WeightLossPlanService.bookConsultation(
        subscriptionId: widget.sub.id,
        date: _dateKey,
        timeSlot: slot,
        consultationType: _type,
        idempotencyKey: _key,
        planIndex: widget.credit.index,
      );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Consultation booked.'),
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _slot = null;
      });
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red,
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final nutritionist =
        ref.watch(nutritionistDetailProvider(widget.sub.nutritionistId)).valueOrNull;
    final booked = ref
            .watch(bookedSlotsProvider((widget.sub.nutritionistId, _dateKey)))
            .valueOrNull ??
        const <String>[];
    final slots = nutritionist == null
        ? <String>[]
        : nutritionSlotsFor(
            slots: nutritionist.slots,
            scheduleConfigured: nutritionist.scheduleConfigured,
            blockedSlots: nutritionist.blockedSlots,
            date: _selected,
          );
    final online = nutritionist?.isOnlineAvailable ?? true;
    final inPerson = nutritionist?.isInPersonAvailable ?? false;
    if (!online && inPerson && _type == 'online') _type = 'in_person';

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Month ${widget.credit.index} consultation',
            style: AppTextStyles.h3),
        centerTitle: true,
        backgroundColor: context.appSurface,
        foregroundColor: context.appTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: context.appSurface,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _slot == null || _saving ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Confirm booking',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: _kGreenBg, borderRadius: BorderRadius.circular(12)),
              child: Text(
                'Included in your plan with ${widget.sub.nutritionistName}. '
                'No payment needed. Pick a date between '
                '${_fmtDate(widget.credit.windowStart)} and ${_fmtDate(widget.credit.windowEnd)}.',
                style: AppTextStyles.bodySmall
                    .copyWith(color: _kGreen, height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
            if (online && inPerson) ...[
              Text('Consultation Type',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: context.appTextPrimary)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'online', label: Text('Online')),
                  ButtonSegment(value: 'in_person', label: Text('In-Person')),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
              const SizedBox(height: 16),
            ],
            Text('Select Date',
                style: AppTextStyles.labelLarge
                    .copyWith(color: context.appTextPrimary)),
            const SizedBox(height: 8),
            if (_dates.isEmpty)
              Text(
                  'This month\'s window has no bookable days left. Contact support if you need help.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: context.appTextSecondary))
            else
              NutritionDateStrip(
                dates: _dates,
                selected: _selected,
                onSelect: (d) => setState(() {
                  _selected = d;
                  _slot = null;
                }),
              ),
            const SizedBox(height: 16),
            Text('Select Time Slot',
                style: AppTextStyles.labelLarge
                    .copyWith(color: context.appTextPrimary)),
            const SizedBox(height: 8),
            NutritionSlotGrid(
              slots: slots,
              bookedSlots: booked,
              selected: _slot,
              onSelect: (s) => setState(() => _slot = s),
            ),
            const SizedBox(height: 16),
            Text(kWeightLossPlanNotice,
                style: AppTextStyles.caption
                    .copyWith(color: context.appTextSecondary, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
