import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/op_slip_service.dart';
import '../../../core/utils/r.dart';
import '../models/unified_booking.dart';
import '../providers/my_services_provider.dart';
import '../services/my_services_service.dart';

class ServiceDetailScreen extends ConsumerStatefulWidget {
  final UnifiedBooking booking;
  const ServiceDetailScreen({super.key, required this.booking});

  @override
  ConsumerState<ServiceDetailScreen> createState() =>
      _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends ConsumerState<ServiceDetailScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryAnim;

  // Rating state
  double _userRating = 0;
  final _reviewCtrl = TextEditingController();
  bool _submittingReview = false;
  bool _reviewSubmitted = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _entryAnim = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _entryCtrl.dispose();
    _reviewCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveAsync = ref.watch(bookingDetailProvider(widget.booking));
    final live = liveAsync.valueOrNull ?? widget.booking;

    return FadeTransition(
      opacity: _entryAnim,
      child: Scaffold(
        backgroundColor: context.appBackground,
        body: CustomScrollView(
          slivers: [
            _buildSliverAppBar(context, live),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  R.p(context, 16),
                  R.p(context, 20),
                  R.p(context, 16),
                  R.p(context, 100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatusCard(context, live),
                    SizedBox(height: R.h(context, 16)),
                    _buildTimeline(context, live),
                    SizedBox(height: R.h(context, 16)),
                    if (live.providerName != null) ...[
                      _buildProviderCard(context, live),
                      SizedBox(height: R.h(context, 16)),
                    ],
                    _buildBookingInfo(context, live),
                    SizedBox(height: R.h(context, 16)),
                    _buildPaymentInfo(context, live),
                    SizedBox(height: R.h(context, 16)),
                    if (live.isCompleted && !_reviewSubmitted)
                      _buildRatingSection(context),
                    if (live.isCompleted && !_reviewSubmitted)
                      SizedBox(height: R.h(context, 16)),
                    _buildActionButtons(context, live),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── SliverAppBar ─────────────────────────────────────────────────────────────

  SliverAppBar _buildSliverAppBar(BuildContext context, UnifiedBooking live) {
    final info = _ServiceInfo.from(live);
    return SliverAppBar(
      pinned: true,
      expandedHeight: 190,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => context.pop(),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.share_rounded, color: Colors.white),
          onPressed: () => _shareBooking(live),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          decoration: BoxDecoration(gradient: info.gradient),
          child: Stack(
            children: [
              // Decorative circles
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 54, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    child: Icon(
                                      info.icon,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          live.serviceType,
                                          style: AppTextStyles.h3.copyWith(
                                            color: Colors.white,
                                          ),
                                        ),
                                        if (live.providerName != null)
                                          Text(
                                            live.providerName!,
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                                  color: Colors.white70,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  _AppBarChip(
                                    icon: Icons.tag_rounded,
                                    label: live.id
                                        .substring(
                                          0,
                                          live.id.length.clamp(0, 8),
                                        )
                                        .toUpperCase(),
                                  ),
                                  const SizedBox(width: 8),
                                  _LiveStatusDot(
                                    status: live.status,
                                    pulse: _pulseCtrl,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    live.status.label,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Status Card ──────────────────────────────────────────────────────────────

  Widget _buildStatusCard(BuildContext context, UnifiedBooking live) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg) = _statusCardColors(live.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : bg.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : bg.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: live.isActive
                    ? Color.lerp(
                        bg.withValues(alpha: 0.15),
                        bg.withValues(alpha: 0.3),
                        _pulseCtrl.value,
                      )!
                    : bg.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(_statusIcon(live.status), color: fg, size: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Status',
                  style: AppTextStyles.caption.copyWith(
                    color: context.appTextHint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  live.status.label,
                  style: AppTextStyles.labelLarge.copyWith(color: fg),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusSubtext(live.status),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.appTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (live.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bg.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: fg.withValues(
                          alpha: 0.5 + _pulseCtrl.value * 0.5,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Timeline ─────────────────────────────────────────────────────────────────

  Widget _buildTimeline(BuildContext context, UnifiedBooking live) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final steps = live.timeline;

    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.timeline_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Text('Progress Timeline', style: AppTextStyles.h4),
            ],
          ),
          const SizedBox(height: 16),
          ...steps.asMap().entries.map(
            (e) => _TimelineStep(
              step: e.value,
              isLast: e.key == steps.length - 1,
              pulseCtrl: _pulseCtrl,
            ),
          ),
        ],
      ),
    );
  }

  // ── Provider Card ─────────────────────────────────────────────────────────────

  Widget _buildProviderCard(BuildContext context, UnifiedBooking live) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Text('Service Provider', style: AppTextStyles.h4),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Provider photo
              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child:
                    live.providerPhoto != null && live.providerPhoto!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: live.providerPhoto!,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _providerAvatar(),
                        errorWidget: (_, __, ___) => _providerAvatar(),
                      )
                    : _providerAvatar(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      live.providerName ?? 'Provider',
                      style: AppTextStyles.labelLarge,
                    ),
                    if (live.providerSpecialty != null)
                      Text(
                        live.providerSpecialty!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.appTextSecondary,
                        ),
                      ),
                    const SizedBox(height: 4),
                    // Static 4-star rating display
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < 4
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 14,
                          color: i < 4
                              ? const Color(0xFFF57F17)
                              : context.appTextHint,
                        ),
                      ),
                    ),
                    if (live.providerPhone != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.phone_rounded,
                            size: 12,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            live.providerPhone!,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (live.providerPhone != null)
                GestureDetector(
                  onTap: () => _callProvider(live.providerPhone!),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.call_rounded,
                      color: AppColors.success,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _providerAvatar() => Container(
    width: 52,
    height: 52,
    decoration: const BoxDecoration(
      gradient: AppColors.primaryGradient,
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
  );

  // ── Booking Info ──────────────────────────────────────────────────────────────

  Widget _buildBookingInfo(BuildContext context, UnifiedBooking live) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = <_DetailItem>[];

    if (live.date.isNotEmpty) {
      items.add(
        _DetailItem(
          icon: Icons.calendar_today_rounded,
          label: 'Date',
          value: _formatDate(live.date),
          color: const Color(0xFF1565C0),
        ),
      );
    }
    if (live.time.isNotEmpty) {
      items.add(
        _DetailItem(
          icon: Icons.access_time_rounded,
          label: 'Time',
          value: live.time,
          color: const Color(0xFF6A1B9A),
        ),
      );
    }
    if (live.address != null && live.address!.isNotEmpty) {
      items.add(
        _DetailItem(
          icon: Icons.location_on_rounded,
          label: 'Location',
          value: live.address!,
          color: AppColors.error,
        ),
      );
    }
    if (live.notes != null && live.notes!.isNotEmpty) {
      items.add(
        _DetailItem(
          icon: Icons.notes_rounded,
          label: 'Notes',
          value: live.notes!,
          color: AppColors.warning,
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.event_note_rounded,
                  color: Color(0xFF1565C0),
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Text('Booking Info', style: AppTextStyles.h4),
            ],
          ),
          const SizedBox(height: 16),
          for (final e in items.asMap().entries) ...[
            _DetailRow(item: e.value),
            if (e.key < items.length - 1) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: context.appDivider),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }

  // ── Payment Info ─────────────────────────────────────────────────────────────

  Widget _buildPaymentInfo(BuildContext context, UnifiedBooking live) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (live.amount == null) return const SizedBox.shrink();

    // Derive payment fields from rawData if available
    final rawMethod =
        live.rawData['paymentMethod'] as String? ?? 'Online Payment';
    final txnId = live.rawData['transactionId'] as String?;
    final isPaid = live.rawData['paymentStatus'] as String? ?? 'Paid';

    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: AppColors.success,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Text('Payment Info', style: AppTextStyles.h4),
            ],
          ),
          const SizedBox(height: 16),

          // Amount row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Amount',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: context.appTextSecondary,
                ),
              ),
              Text(
                '₹${live.amount!.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: context.appDivider),
          const SizedBox(height: 12),

          _PaymentRow(
            label: 'Payment Method',
            value: rawMethod,
            icon: Icons.credit_card_rounded,
          ),
          const SizedBox(height: 10),
          if (txnId != null) ...[
            _PaymentRow(
              label: 'Transaction ID',
              value: txnId,
              icon: Icons.tag_rounded,
            ),
            const SizedBox(height: 10),
          ],
          _PaymentRow(
            label: 'Status',
            value: isPaid,
            icon: Icons.check_circle_outline_rounded,
            isSuccess: true,
          ),
        ],
      ),
    );
  }

  // ── Rating & Review Section ───────────────────────────────────────────────────

  Widget _buildRatingSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF57F17).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFF57F17),
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Text('Rate & Review', style: AppTextStyles.h4),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'How was your experience? Your feedback helps us improve.',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.appTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: RatingBar.builder(
              initialRating: _userRating,
              minRating: 1,
              direction: Axis.horizontal,
              allowHalfRating: true,
              itemCount: 5,
              itemSize: 36,
              glow: false,
              itemPadding: const EdgeInsets.symmetric(horizontal: 4),
              itemBuilder: (_, __) =>
                  const Icon(Icons.star_rounded, color: Color(0xFFF57F17)),
              onRatingUpdate: (r) => setState(() => _userRating = r),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _reviewCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Write a review (optional)...',
              hintStyle: AppTextStyles.bodySmall.copyWith(
                color: context.appTextHint,
              ),
              filled: true,
              fillColor: isDark
                  ? AppColors.darkCardElevated
                  : context.appBackground,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _userRating == 0 || _submittingReview
                  ? null
                  : () => _submitReview(context),
              icon: _submittingReview
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(
                _submittingReview ? 'Submitting...' : 'Submit Review',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF57F17),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Action Buttons ────────────────────────────────────────────────────────────

  Widget _buildActionButtons(BuildContext context, UnifiedBooking live) {
    final canCancel =
        live.isActive &&
        live.status != BookingStatus.inProgress &&
        live.status != BookingStatus.consultationStarted;

    // In-person doctor appointments get the same OP slip + directions
    // actions here as on the My Appointments card, so they work the same
    // wherever the patient finds the booking.
    final isInPersonAppointment =
        live.source == BookingSource.appointment &&
        (live.rawData['consultationType'] as String?) == 'In-Person';

    return Column(
      children: [
        if (isInPersonAppointment) ...[
          _ActionButton(
            icon: Icons.picture_as_pdf_rounded,
            label: 'Download OP Slip',
            color: AppColors.primary,
            onTap: () => OpSlipService.openSlip(
              context,
              appointmentId: live.id,
              appointmentData: live.rawData,
            ),
          ),
          if (live.isActive) ...[
            const SizedBox(height: 10),
            _ActionButton(
              icon: Icons.directions_rounded,
              label: 'Directions to Clinic',
              color: AppColors.info,
              outlined: true,
              onTap: () => OpSlipService.openDirections(
                context,
                appointmentData: live.rawData,
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],
        if (live.isActive || live.isCompleted)
          _ActionButton(
            icon: Icons.headset_mic_rounded,
            label: 'Contact Support',
            color: AppColors.primary,
            onTap: () => _contactSupport(context, live),
          ),
        if (live.isActive) ...[
          const SizedBox(height: 10),
          _ActionButton(
            icon: Icons.event_repeat_rounded,
            label: 'Reschedule Booking',
            color: AppColors.info,
            outlined: true,
            onTap: () => _rescheduleBooking(context, live),
          ),
        ],
        if (canCancel) ...[
          const SizedBox(height: 10),
          _ActionButton(
            icon: Icons.cancel_outlined,
            label: 'Cancel Booking',
            color: AppColors.error,
            outlined: true,
            onTap: () => _confirmCancel(context, live),
          ),
        ],
        if (live.isCompleted) ...[
          const SizedBox(height: 10),
          _ActionButton(
            icon: Icons.refresh_rounded,
            label: 'Rebook This Service',
            color: AppColors.success,
            onTap: () =>
                FeedbackService.showInfo(context, 'Redirecting to booking…'),
          ),
          const SizedBox(height: 10),
          _ActionButton(
            icon: Icons.download_rounded,
            label: 'Download Receipt',
            color: context.appTextSecondary,
            outlined: true,
            onTap: () => FeedbackService.showInfo(
              context,
              'Receipt download coming soon.',
            ),
          ),
        ],
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String _formatDate(String raw) {
    if (raw.isEmpty) return '—';
    try {
      return DateFormat('EEEE, dd MMMM yyyy').format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  Future<void> _callProvider(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: digits);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _shareBooking(UnifiedBooking live) {
    final text =
        'My ${live.serviceType} booking (#${live.id.substring(0, 8).toUpperCase()}) — Status: ${live.status.label}. Booked via MedNU.';
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      FeedbackService.showSuccess(context, 'Booking info copied to clipboard');
    }
  }

  Future<void> _submitReview(BuildContext context) async {
    setState(() => _submittingReview = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() {
        _submittingReview = false;
        _reviewSubmitted = true;
      });
      if (context.mounted) {
        FeedbackService.showSuccess(context, 'Thank you for your review!');
      }
    }
  }

  // Only doctor appointments can be rescheduled from here — the flow needs a
  // doctorId + slot picker, which other service types (medicine, lab tests,
  // equipment, etc.) don't have.
  void _rescheduleBooking(BuildContext context, UnifiedBooking live) {
    final doctorId = live.rawData['doctorId'] as String? ?? '';
    if (live.source != BookingSource.appointment || doctorId.isEmpty) {
      FeedbackService.showInfo(context, 'Reschedule coming soon.');
      return;
    }
    final type = live.rawData['consultationType'] as String? ?? 'Video';
    context.push(Uri(
      path: '/doctors/$doctorId',
      queryParameters: {
        'rescheduleId': live.id,
        'rescheduleType': type,
      },
    ).toString());
  }

  void _contactSupport(BuildContext context, UnifiedBooking live) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupportChatSheet(booking: live),
    );
  }

  Future<void> _confirmCancel(BuildContext context, UnifiedBooking live) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Cancel Booking',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to cancel this booking?\nThis action cannot be undone.',
          style: TextStyle(fontFamily: 'Poppins', height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Booking'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Cancel Booking',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted && context.mounted) {
      FeedbackService.showLoading(context, 'Cancelling booking...');
      try {
        await MyServicesService.updateStatus(live, 'cancelled');
        if (mounted && context.mounted) {
          FeedbackService.dismiss(context);
          FeedbackService.showSuccess(
            context,
            'Booking cancelled successfully',
          );
          GoRouter.of(context).pop();
        }
      } catch (e) {
        if (mounted && context.mounted) {
          FeedbackService.showError(
            context,
            'Failed to cancel booking. Please try again.',
            onRetry: () => _confirmCancel(context, live),
          );
        }
      }
    }
  }

  (Color, Color) _statusCardColors(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
      case BookingStatus.requested:
        return (const Color(0xFFFF6F00), const Color(0xFFE65100));
      case BookingStatus.confirmed:
        return (const Color(0xFF1565C0), const Color(0xFF0D47A1));
      case BookingStatus.assigned:
        return (const Color(0xFF6A1B9A), const Color(0xFF3D1D36));
      case BookingStatus.onTheWay:
        return (const Color(0xFF00695C), const Color(0xFF004D40));
      case BookingStatus.inProgress:
      case BookingStatus.consultationStarted:
        return (const Color(0xFF00838F), const Color(0xFF006064));
      case BookingStatus.sampleCollected:
      case BookingStatus.delivered:
      case BookingStatus.completed:
        return (AppColors.success, const Color(0xFF1B5E20));
      case BookingStatus.cancelled:
        return (AppColors.error, const Color(0xFFB71C1C));
      case BookingStatus.rescheduled:
        return (const Color(0xFFF57F17), const Color(0xFFE65100));
    }
  }

  IconData _statusIcon(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
      case BookingStatus.requested:
        return Icons.hourglass_empty_rounded;
      case BookingStatus.confirmed:
        return Icons.check_circle_outline_rounded;
      case BookingStatus.assigned:
        return Icons.person_pin_circle_rounded;
      case BookingStatus.onTheWay:
        return Icons.directions_run_rounded;
      case BookingStatus.inProgress:
      case BookingStatus.consultationStarted:
        return Icons.medical_services_rounded;
      case BookingStatus.sampleCollected:
        return Icons.science_rounded;
      case BookingStatus.delivered:
        return Icons.local_shipping_rounded;
      case BookingStatus.completed:
        return Icons.check_circle_rounded;
      case BookingStatus.cancelled:
        return Icons.cancel_rounded;
      case BookingStatus.rescheduled:
        return Icons.event_repeat_rounded;
    }
  }

  String _statusSubtext(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
      case BookingStatus.requested:
        return 'Waiting for provider confirmation';
      case BookingStatus.confirmed:
        return 'Your booking has been confirmed';
      case BookingStatus.assigned:
        return 'A provider has been assigned to you';
      case BookingStatus.onTheWay:
        return 'Provider is on the way to you';
      case BookingStatus.inProgress:
        return 'Service is currently in progress';
      case BookingStatus.consultationStarted:
        return 'Consultation is live right now';
      case BookingStatus.sampleCollected:
        return 'Sample has been collected successfully';
      case BookingStatus.delivered:
        return 'Service has been delivered to you';
      case BookingStatus.completed:
        return 'Service completed successfully';
      case BookingStatus.cancelled:
        return 'This booking was cancelled';
      case BookingStatus.rescheduled:
        return 'Your booking has been rescheduled';
    }
  }
}

// ── Section Card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const _SectionCard({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : context.appBorder,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: child,
    );
  }
}

// ── Timeline Step ─────────────────────────────────────────────────────────────

class _TimelineStep extends StatelessWidget {
  final BookingStatusEvent step;
  final bool isLast;
  final AnimationController pulseCtrl;

  const _TimelineStep({
    required this.step,
    required this.isLast,
    required this.pulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final Widget dot;
    final Color lineColor;

    if (step.isCompleted) {
      lineColor = AppColors.success;
      dot = Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          color: AppColors.success,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
      );
    } else if (step.isActive) {
      lineColor = context.appBorder;
      dot = AnimatedBuilder(
        animation: pulseCtrl,
        builder: (_, __) => Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Color.lerp(
              AppColors.primary,
              AppColors.primaryLight,
              pulseCtrl.value,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(
                  alpha: 0.3 + pulseCtrl.value * 0.2,
                ),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.radio_button_checked_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      );
    } else {
      lineColor = context.appBorder;
      dot = Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: context.appBorder, width: 2),
        ),
        child: Icon(
          Icons.radio_button_unchecked_rounded,
          size: 14,
          color: context.appTextHint,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            dot,
            if (!isLast) Container(width: 2, height: 44, color: lineColor),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 10, top: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: step.isCompleted
                        ? AppColors.success
                        : step.isActive
                        ? AppColors.primary
                        : context.appTextHint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.description,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.appTextSecondary,
                    height: 1.4,
                  ),
                ),
                if (step.timestamp != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('dd MMM yyyy, hh:mm a').format(step.timestamp!),
                    style: AppTextStyles.caption.copyWith(
                      color: context.appTextHint,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Detail Row ────────────────────────────────────────────────────────────────

class _DetailItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

class _DetailRow extends StatelessWidget {
  final _DetailItem item;
  const _DetailRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(item.icon, size: 17, color: item.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                style: AppTextStyles.caption.copyWith(
                  color: context.appTextHint,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.value,
                style: AppTextStyles.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Payment Row ───────────────────────────────────────────────────────────────

class _PaymentRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isSuccess;

  const _PaymentRow({
    required this.label,
    required this.value,
    required this.icon,
    this.isSuccess = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: isSuccess ? AppColors.success : context.appTextHint,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: context.appTextSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSuccess ? AppColors.success : context.appTextPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Action Button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool outlined;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(label),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
    );
  }
}

// ── App Bar Chip ──────────────────────────────────────────────────────────────

class _AppBarChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _AppBarChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live Status Dot ───────────────────────────────────────────────────────────

class _LiveStatusDot extends StatelessWidget {
  final BookingStatus status;
  final AnimationController pulse;
  const _LiveStatusDot({required this.status, required this.pulse});

  static const _liveStatuses = {
    BookingStatus.confirmed,
    BookingStatus.assigned,
    BookingStatus.onTheWay,
    BookingStatus.inProgress,
    BookingStatus.consultationStarted,
  };

  @override
  Widget build(BuildContext context) {
    if (!_liveStatuses.contains(status)) {
      return Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Colors.white54,
          shape: BoxShape.circle,
        ),
      );
    }
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5 + pulse.value * 0.5),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: pulse.value * 0.4),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Service Info ──────────────────────────────────────────────────────────────

class _ServiceInfo {
  final IconData icon;
  final LinearGradient gradient;
  const _ServiceInfo({required this.icon, required this.gradient});

  static _ServiceInfo from(UnifiedBooking b) {
    switch (b.source) {
      case BookingSource.appointment:
        return const _ServiceInfo(
          icon: Icons.medical_services_rounded,
          gradient: AppColors.appointmentGrad,
        );
      case BookingSource.consultation:
        return const _ServiceInfo(
          icon: Icons.videocam_rounded,
          gradient: AppColors.consultGrad,
        );
      case BookingSource.nutrition:
        return const _ServiceInfo(
          icon: Icons.restaurant_menu_rounded,
          gradient: AppColors.nutritionGrad,
        );
      case BookingSource.serviceRequest:
        switch ((b.rawData['type'] as String? ?? '').toLowerCase()) {
          case 'ambulance':
            return const _ServiceInfo(
              icon: Icons.emergency_rounded,
              gradient: AppColors.ambulanceGrad,
            );
          case 'diagnostics':
          case 'lab_test':
            return const _ServiceInfo(
              icon: Icons.biotech_rounded,
              gradient: AppColors.diagnosticGrad,
            );
          case 'caregiver':
          case 'caregivers':
            return const _ServiceInfo(
              icon: Icons.elderly_rounded,
              gradient: AppColors.caregiverGrad,
            );
          case 'care_assistant':
            return const _ServiceInfo(
              icon: Icons.support_agent_rounded,
              gradient: AppColors.careAssistGrad,
            );
          case 'physiotherapy':
          case 'physio':
            return const _ServiceInfo(
              icon: Icons.accessibility_new_rounded,
              gradient: AppColors.physioGrad,
            );
          case 'counselling':
            return const _ServiceInfo(
              icon: Icons.psychology_rounded,
              gradient: AppColors.counselGrad,
            );
          case 'equipment':
            return const _ServiceInfo(
              icon: Icons.medical_information_rounded,
              gradient: AppColors.equipmentGrad,
            );
          case 'medicine':
            return const _ServiceInfo(
              icon: Icons.local_pharmacy_rounded,
              gradient: AppColors.medicineGrad,
            );
          default:
            return const _ServiceInfo(
              icon: Icons.health_and_safety_rounded,
              gradient: AppColors.primaryGradient,
            );
        }
    }
  }
}

// ── Support Chat Sheet ────────────────────────────────────────────────────────

class _SupportChatSheet extends StatefulWidget {
  final UnifiedBooking booking;
  const _SupportChatSheet({required this.booking});

  @override
  State<_SupportChatSheet> createState() => _SupportChatSheetState();
}

class _SupportChatSheetState extends State<_SupportChatSheet> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  String get _chatPath => 'booking_support/${widget.booking.id}/messages';

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _textCtrl.clear();
    try {
      await FirebaseFirestore.instance.collection(_chatPath).add({
        'text': text,
        'role': 'patient',
        'ts': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    if (mounted) {
      setState(() => _sending = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.headset_mic_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Support Chat',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Booking #${widget.booking.id.substring(0, widget.booking.id.length.clamp(0, 8)).toUpperCase()}',
                        style: AppTextStyles.caption.copyWith(
                          color: context.appTextHint,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: context.appTextHint),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Messages
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(_chatPath)
                  .orderBy('ts')
                  .snapshots(),
              builder: (_, snap) {
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.headset_mic_rounded,
                            color: AppColors.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Send us a message',
                          style: AppTextStyles.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            'Our support team will respond shortly.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: context.appTextSecondary,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final isMe = data['role'] == 'patient';
                    final text = data['text'] as String? ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisAlignment: isMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          if (!isMe) ...[
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.support_agent_rounded,
                                size: 14,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Container(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.65,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? AppColors.primary
                                  : const Color(0xFFFCE4EC),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isMe ? 16 : 4),
                                bottomRight: Radius.circular(isMe ? 4 : 16),
                              ),
                            ),
                            child: Text(
                              text,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                color: isMe
                                    ? Colors.white
                                    : context.appTextPrimary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // Input
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: context.appSurface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      hintStyle: AppTextStyles.bodySmall,
                      filled: true,
                      fillColor: context.appBackground,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
