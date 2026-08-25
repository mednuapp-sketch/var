import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../core/utils/r.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Constants
// ─────────────────────────────────────────────────────────────────────────────

const _kGreen = Color(0xFF2E7D32);
const _kOrange = Color(0xFFE65100);
const _kOrangeLight = Color(0xFFFF8A65);

// ─────────────────────────────────────────────────────────────────────────────
//  Status model
// ─────────────────────────────────────────────────────────────────────────────

enum BookingStatus { booked, confirmed, inProgress, completed, cancelled }

extension BookingStatusExt on BookingStatus {
  String get label {
    switch (this) {
      case BookingStatus.booked:
        return 'Booked';
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.inProgress:
        return 'In Progress';
      case BookingStatus.completed:
        return 'Completed';
      case BookingStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case BookingStatus.booked:
        return const Color(0xFF1565C0);
      case BookingStatus.confirmed:
        return _kGreen;
      case BookingStatus.inProgress:
        return _kOrange;
      case BookingStatus.completed:
        return _kGreen;
      case BookingStatus.cancelled:
        return AppColors.error;
    }
  }

  IconData get icon {
    switch (this) {
      case BookingStatus.booked:
        return Icons.calendar_today_rounded;
      case BookingStatus.confirmed:
        return Icons.check_circle_rounded;
      case BookingStatus.inProgress:
        return Icons.medical_services_rounded;
      case BookingStatus.completed:
        return Icons.task_alt_rounded;
      case BookingStatus.cancelled:
        return Icons.cancel_rounded;
    }
  }

  bool get canCancel =>
      this == BookingStatus.booked || this == BookingStatus.confirmed;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stepper step model
// ─────────────────────────────────────────────────────────────────────────────

class _TrackStep {
  final String title, desc;
  final IconData icon;
  final bool done;
  final bool active;
  final bool cancelled;
  final String? timestamp;

  const _TrackStep({
    required this.title,
    required this.desc,
    required this.icon,
    this.done = false,
    this.active = false,
    this.cancelled = false,
    this.timestamp,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  OrderTrackingScreen
// ─────────────────────────────────────────────────────────────────────────────

class OrderTrackingScreen extends StatefulWidget {
  /// Shape: {orderId, serviceType, serviceName, bookingDate,
  ///         status, estimatedTime, provider: {name, photo, rating, contact},
  ///         items, total}
  final Map<String, dynamic>? orderData;
  const OrderTrackingScreen({super.key, this.orderData});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _shimmerCtrl;

  late String _orderId;
  late String _serviceType;
  late String _serviceName;
  late String _bookingDate;
  late BookingStatus _status;
  late String _estimatedTime;
  late String _providerName;
  late String _providerPhoto;
  late double _providerRating;
  late String _providerContact;
  late List<Map<String, dynamic>> _orderItems;
  late int _subtotal;

  bool _isCancelling = false;

  static const _serviceTypeIcons = {
    'consultation': Icons.video_call_rounded,
    'appointment': Icons.calendar_month_rounded,
    'medicine': Icons.local_shipping_rounded,
    'lab': Icons.science_rounded,
    'caregiver': Icons.accessibility_new_rounded,
    'ambulance': Icons.emergency_rounded,
  };

  List<_TrackStep> get _steps {
    final isCancelled = _status == BookingStatus.cancelled;
    if (isCancelled) {
      return [
        const _TrackStep(
          title: 'Booking Placed',
          desc: 'Your booking was received',
          icon: Icons.calendar_today_rounded,
          done: true,
        ),
        const _TrackStep(
          title: 'Booking Cancelled',
          desc: 'This booking has been cancelled',
          icon: Icons.cancel_rounded,
          active: true,
          cancelled: true,
        ),
      ];
    }

    final statusIndex = _status.index;
    return [
      _TrackStep(
        title: 'Booked',
        desc: 'Your booking was placed successfully',
        icon: Icons.calendar_today_rounded,
        done: statusIndex >= BookingStatus.booked.index,
        active: _status == BookingStatus.booked,
        timestamp: statusIndex >= BookingStatus.booked.index ? _bookingDate : null,
      ),
      _TrackStep(
        title: 'Confirmed',
        desc: 'Service provider confirmed your booking',
        icon: Icons.check_circle_rounded,
        done: statusIndex > BookingStatus.confirmed.index,
        active: _status == BookingStatus.confirmed,
      ),
      _TrackStep(
        title: 'In Progress',
        desc: 'Your service is currently underway',
        icon: Icons.medical_services_rounded,
        done: statusIndex > BookingStatus.inProgress.index,
        active: _status == BookingStatus.inProgress,
      ),
      _TrackStep(
        title: 'Completed',
        desc: 'Service delivered successfully',
        icon: Icons.task_alt_rounded,
        done: _status == BookingStatus.completed,
        active: _status == BookingStatus.completed,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _parseOrderData();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  void _parseOrderData() {
    final d = widget.orderData ?? {};
    _orderId = d['orderId'] as String? ??
        'MED-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    _serviceType = d['serviceType'] as String? ?? 'consultation';
    _serviceName = d['serviceName'] as String? ?? 'Doctor Consultation';
    _bookingDate = d['bookingDate'] as String? ?? _formatDate(DateTime.now());
    _estimatedTime = d['estimatedTime'] as String? ?? 'Today, 3:00 PM';

    final statusStr = d['status'] as String? ?? 'confirmed';
    _status = BookingStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => BookingStatus.confirmed,
    );

    final provider = (d['provider'] as Map?)?.cast<String, dynamic>() ?? {};
    _providerName = provider['name'] as String? ?? 'Dr. Anjali Sharma';
    _providerPhoto = provider['photo'] as String? ?? '';
    _providerRating = (provider['rating'] as num?)?.toDouble() ?? 4.8;
    _providerContact = provider['contact'] as String? ?? '+91 98765 43210';

    final rawItems = d['items'] as List?;
    _orderItems = rawItems != null
        ? rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : [
            {'name': 'General Consultation', 'qty': 1, 'price': 500},
          ];
    _subtotal =
        d['total'] as int? ?? 500;
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Future<void> _callProvider() async {
    final digits = _providerContact.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: digits);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not dial $_providerContact'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _cancelBooking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(ctx, 20))),
        title: const Text(
          'Cancel Booking?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Are you sure you want to cancel this booking? This action cannot be undone.',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: ctx.appTextSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Booking',
                style: TextStyle(fontFamily: 'Poppins')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(R.r(ctx, 10))),
            ),
            child: const Text('Cancel Booking',
                style: TextStyle(fontFamily: 'Poppins')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _isCancelling = true;
      _status = BookingStatus.cancelled;
      _isCancelling = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Booking cancelled successfully.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 12))),
          margin: EdgeInsets.all(R.p(context, 16)),
        ),
      );
    }
  }

  void _showHelpSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderSupportSheet(orderId: _orderId),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 16), R.p(context, 16), R.p(context, 40)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderCard(),
                  SizedBox(height: R.h(context, 16)),
                  _buildStatusBadge(),
                  SizedBox(height: R.h(context, 20)),
                  const Text('Progress', style: AppTextStyles.h4),
                  SizedBox(height: R.h(context, 12)),
                  _buildStepper(),
                  SizedBox(height: R.h(context, 20)),
                  _buildProviderCard(),
                  SizedBox(height: R.h(context, 20)),
                  if (_orderItems.isNotEmpty) ...[
                    const Text('Order Details', style: AppTextStyles.h4),
                    SizedBox(height: R.h(context, 12)),
                    _buildOrderDetails(),
                    SizedBox(height: R.h(context, 20)),
                  ],
                  _buildActionButtons(),
                  SizedBox(height: R.h(context, 16)),
                  if (_status.canCancel) _buildCancelButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────
  SliverAppBar _buildAppBar() {
    final serviceIcon =
        _serviceTypeIcons[_serviceType] ?? Icons.medical_services_rounded;
    return SliverAppBar(
      pinned: true,
      expandedHeight: R.h(context, 160),
      backgroundColor: _kGreen,
      leading: Padding(
        padding: EdgeInsets.all(R.p(context, 8)),
        child: Material(
          color: Colors.white.withValues(alpha: 0.15),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: EdgeInsets.all(R.p(context, 8)),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: R.w(context, 18)),
            ),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: EdgeInsets.only(right: R.p(context, 8)),
          child: IconButton(
            icon: Icon(Icons.headset_mic_rounded,
                color: Colors.white, size: R.w(context, 22)),
            onPressed: _showHelpSheet,
            tooltip: 'Need Help?',
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1B5E20), _kGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 52), R.p(context, 20), R.p(context, 16)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: R.w(context, 52), height: R.h(context, 52),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(R.r(context, 16)),
                            ),
                            child: Icon(serviceIcon, color: Colors.white, size: R.w(context, 28)),
                          ),
                          SizedBox(width: R.w(context, 14)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _serviceName,
                                  style: AppTextStyles.onPrimaryH2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const Text(
                                  'Track your booking',
                                  style: AppTextStyles.onPrimaryBody,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── Header Card ────────────────────────────────────────
  Widget _buildHeaderCard() {
    return Container(
      padding: EdgeInsets.all(R.p(context, 16)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 18)),
        border: Border.all(color: context.appBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.receipt_rounded,
            label: 'Order ID',
            value: _orderId,
            valueColor: AppColors.primary,
          ),
          const Divider(height: 16),
          _InfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Booking Date',
            value: _bookingDate,
          ),
          const Divider(height: 16),
          _InfoRow(
            icon: Icons.access_time_rounded,
            label: 'Estimated Time',
            value: _estimatedTime,
            valueColor: _kGreen,
          ),
        ],
      ),
    );
  }

  // ── Status Badge ───────────────────────────────────────
  Widget _buildStatusBadge() {
    final color = _status.color;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: R.p(context, 18), vertical: R.p(context, 14)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.r(context, 16)),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Pulsing indicator for active statuses
          if (_status == BookingStatus.inProgress ||
              _status == BookingStatus.confirmed)
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Container(
                width: R.w(context, 10), height: R.h(context, 10),
                margin: EdgeInsets.only(right: R.p(context, 10)),
                decoration: BoxDecoration(
                  color: color.withValues(
                      alpha: 0.5 + _pulseCtrl.value * 0.5),
                  shape: BoxShape.circle,
                ),
              ),
            )
          else
            Container(
              width: R.w(context, 10), height: R.h(context, 10),
              margin: EdgeInsets.only(right: R.p(context, 10)),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          Icon(_status.icon, color: color, size: R.w(context, 20)),
          SizedBox(width: R.w(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Status',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: color.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _status.label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: R.p(context, 12), vertical: R.p(context, 5)),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(R.r(context, 20)),
            ),
            child: Text(
              _status.label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Custom Stepper ─────────────────────────────────────
  Widget _buildStepper() {
    final steps = _steps;
    return Container(
      padding: EdgeInsets.all(R.p(context, 18)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 18)),
        border: Border.all(color: context.appBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: steps.asMap().entries.map((entry) {
          final i = entry.key;
          final step = entry.value;
          final isLast = i == steps.length - 1;
          return _buildStepRow(step, isLast);
        }).toList(),
      ),
    );
  }

  Widget _buildStepRow(_TrackStep step, bool isLast) {
    final Color stepColor;
    if (step.cancelled) {
      stepColor = AppColors.error;
    } else if (step.done || step.active) {
      stepColor = step.active && !step.done ? _kOrange : _kGreen;
    } else {
      stepColor = context.appBorder;
    }

    Widget stepIcon;
    if (step.cancelled) {
      stepIcon = Container(
        width: R.w(context, 40), height: R.h(context, 40),
        decoration: const BoxDecoration(
          color: AppColors.error,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.close_rounded, color: Colors.white, size: R.w(context, 20)),
      );
    } else if (step.done && !step.active) {
      stepIcon = Container(
        width: R.w(context, 40), height: R.h(context, 40),
        decoration: const BoxDecoration(
          color: _kGreen,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check_rounded, color: Colors.white, size: R.w(context, 20)),
      );
    } else if (step.active) {
      stepIcon = AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, __) => Container(
          width: R.w(context, 40), height: R.h(context, 40),
          decoration: BoxDecoration(
            color: Color.lerp(_kOrange, _kOrangeLight, _pulseCtrl.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _kOrange.withValues(
                    alpha: 0.3 + _pulseCtrl.value * 0.2),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(step.icon, color: Colors.white, size: R.w(context, 18)),
        ),
      );
    } else {
      stepIcon = Container(
        width: R.w(context, 40), height: R.h(context, 40),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: context.appBorder, width: 2),
          color: context.appSurface,
        ),
        child: Icon(step.icon, color: context.appTextHint, size: R.w(context, 18)),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            stepIcon,
            if (!isLast)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 2, height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      stepColor.withValues(alpha: 0.8),
                      stepColor.withValues(alpha: 0.1),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
        SizedBox(width: R.w(context, 14)),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              top: R.p(context, 8),
              bottom: isLast ? 0 : R.p(context, 24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      step.title,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: step.cancelled
                            ? AppColors.error
                            : (step.done || step.active)
                                ? (step.active && !step.done
                                    ? _kOrange
                                    : _kGreen)
                                : context.appTextHint,
                      ),
                    ),
                    if (step.active && !step.cancelled) ...[
                      SizedBox(width: R.w(context, 8)),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: R.p(context, 7), vertical: R.p(context, 2)),
                        decoration: BoxDecoration(
                          color: _kOrange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(R.r(context, 8)),
                        ),
                        child: const Text(
                          'CURRENT',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: _kOrange,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  step.desc,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: context.appTextSecondary,
                    height: 1.4,
                  ),
                ),
                if (step.timestamp != null) ...[
                  SizedBox(height: R.h(context, 3)),
                  Text(
                    step.timestamp!,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      color: context.appTextHint,
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

  // ── Provider Card ──────────────────────────────────────
  Widget _buildProviderCard() {
    return Container(
      padding: EdgeInsets.all(R.p(context, 16)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 18)),
        border: Border.all(color: context.appBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Service Provider', style: AppTextStyles.h4),
          SizedBox(height: R.h(context, 14)),
          Row(
            children: [
              // Provider avatar
              Stack(
                children: [
                  Container(
                    width: R.w(context, 58), height: R.h(context, 58),
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: _providerPhoto.isNotEmpty
                        ? ClipOval(
                            child: Image.network(_providerPhoto,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                    Icons.person_rounded,
                                    color: Colors.white, size: R.w(context, 30))),
                          )
                        : Center(
                            child: Text(
                              _providerName.isNotEmpty
                                  ? _providerName[0].toUpperCase()
                                  : 'D',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    bottom: 1, right: 1,
                    child: Container(
                      width: R.w(context, 16), height: R.h(context, 16),
                      decoration: const BoxDecoration(
                        color: _kGreen,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(width: R.w(context, 14)),

              // Provider info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_providerName,
                        style: AppTextStyles.labelLarge,
                        overflow: TextOverflow.ellipsis),
                    SizedBox(height: R.h(context, 3)),
                    Row(
                      children: [
                        Icon(Icons.star_rounded,
                            size: R.w(context, 14), color: Colors.amber),
                        SizedBox(width: R.w(context, 3)),
                        Text(
                          '$_providerRating',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.appTextPrimary,
                          ),
                        ),
                        SizedBox(width: R.w(context, 6)),
                        Text('·',
                            style: TextStyle(color: context.appTextHint)),
                        SizedBox(width: R.w(context, 6)),
                        Flexible(
                          child: Text(_providerContact,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: _kGreen,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Call button
              GestureDetector(
                onTap: _callProvider,
                child: Container(
                  width: R.w(context, 46), height: R.h(context, 46),
                  decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.call_rounded,
                      color: _kGreen, size: R.w(context, 22)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Order Details ──────────────────────────────────────
  Widget _buildOrderDetails() {
    return Container(
      padding: EdgeInsets.all(R.p(context, 16)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 18)),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        children: [
          ..._orderItems.asMap().entries.map((e) {
            final item = e.value;
            final isLast = e.key == _orderItems.length - 1;
            return Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: R.w(context, 40), height: R.h(context, 40),
                      decoration: BoxDecoration(
                        color: _kGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(R.r(context, 10)),
                      ),
                      child: Icon(Icons.medical_services_rounded,
                          color: _kGreen, size: R.w(context, 20)),
                    ),
                    SizedBox(width: R.w(context, 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name'] as String? ?? '',
                            style: AppTextStyles.labelLarge,
                          ),
                          if ((item['qty'] as int? ?? 1) > 1)
                            Text(
                              'Qty: ${item['qty']}',
                              style: AppTextStyles.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${item['price']}',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kGreen,
                      ),
                    ),
                  ],
                ),
                if (!isLast) const Divider(height: 16),
              ],
            );
          }),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Paid',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
                  )),
              Text(
                '₹$_subtotal',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _kGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Action Buttons ─────────────────────────────────────
  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _callProvider,
            icon: Icon(Icons.call_rounded, size: R.w(context, 18)),
            label: const Text(
              'Call Provider',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kGreen,
              side: const BorderSide(color: _kGreen, width: 1.5),
              padding: EdgeInsets.symmetric(vertical: R.p(context, 13)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(R.r(context, 14))),
            ),
          ),
        ),
        SizedBox(width: R.w(context, 12)),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _showHelpSheet,
            icon: Icon(Icons.headset_mic_rounded, size: R.w(context, 18)),
            label: const Text(
              'Need Help?',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: R.p(context, 13)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(R.r(context, 14))),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  // ── Cancel Button ──────────────────────────────────────
  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isCancelling ? null : _cancelBooking,
        icon: _isCancelling
            ? SizedBox(
                width: R.w(context, 16), height: R.h(context, 16),
                child: const CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.error))
            : Icon(Icons.cancel_outlined, size: R.w(context, 18)),
        label: Text(
          _isCancelling ? 'Cancelling…' : 'Cancel Booking',
          style: const TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
          padding: EdgeInsets.symmetric(vertical: R.p(context, 13)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 14))),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Info Row helper
// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color? valueColor;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            size: R.w(context, 16),
            color: context.appTextHint),
        SizedBox(width: R.w(context, 10)),
        Text(label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: context.appTextSecondary,
            )),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? context.appTextPrimary,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Support Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _OrderSupportSheet extends StatefulWidget {
  final String orderId;
  const _OrderSupportSheet({required this.orderId});

  @override
  State<_OrderSupportSheet> createState() => _OrderSupportSheetState();
}

class _OrderSupportSheetState extends State<_OrderSupportSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  String get _chatPath => 'order_chats/${widget.orderId}/messages';
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    await FirebaseFirestore.instance.collection(_chatPath).add({
      'text': text,
      'senderId': _uid,
      'senderRole': 'patient',
      'timestamp': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            width: R.w(context, 40), height: R.h(context, 4),
            margin: EdgeInsets.only(top: R.p(context, 12), bottom: R.p(context, 4)),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(R.r(context, 2)),
            ),
          ),

          // Header
          Padding(
            padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 12), R.p(context, 20), R.p(context, 12)),
            child: Row(
              children: [
                Container(
                  width: R.w(context, 40), height: R.h(context, 40),
                  decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(R.r(context, 12)),
                  ),
                  child: Icon(Icons.support_agent_rounded,
                      color: _kGreen, size: R.w(context, 20)),
                ),
                SizedBox(width: R.w(context, 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Order Support',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          )),
                      Text(
                        'Order #${widget.orderId}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: context.appTextHint,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded,
                      color: context.appTextHint),
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
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return ListView(
                    padding: EdgeInsets.all(R.p(context, 16)),
                    children: List.generate(
                        3, (_) => const _ChatBubbleSkeleton()),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(R.p(context, 32)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: R.w(context, 70), height: R.h(context, 70),
                            decoration: BoxDecoration(
                              color: _kGreen.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.support_agent_rounded,
                                color: _kGreen, size: R.w(context, 34)),
                          ),
                          SizedBox(height: R.h(context, 14)),
                          const Text('Support Chat',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              )),
                          SizedBox(height: R.h(context, 8)),
                          Text(
                            'Send us a message about your order.\nOur team responds within minutes.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: context.appTextHint,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());
                return ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.all(R.p(context, 16)),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == _uid;
                    final text = data['text'] as String? ?? '';
                    final ts = data['timestamp'] as Timestamp?;
                    final time = ts != null
                        ? '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                        : '';
                    return Padding(
                      padding: EdgeInsets.only(bottom: R.p(context, 12)),
                      child: Row(
                        mainAxisAlignment: isMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isMe) ...[
                            Container(
                              width: R.w(context, 30), height: R.h(context, 30),
                              decoration: BoxDecoration(
                                color: _kGreen.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.support_agent_rounded,
                                  color: _kGreen, size: R.w(context, 15)),
                            ),
                            SizedBox(width: R.w(context, 8)),
                          ],
                          Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Container(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.65,
                                ),
                                padding: EdgeInsets.symmetric(
                                    horizontal: R.p(context, 14), vertical: R.p(context, 10)),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? _kGreen
                                      : const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(R.r(context, 16)),
                                    topRight: Radius.circular(R.r(context, 16)),
                                    bottomLeft: Radius.circular(isMe ? R.r(context, 16) : R.r(context, 4)),
                                    bottomRight: Radius.circular(isMe ? R.r(context, 4) : R.r(context, 16)),
                                  ),
                                ),
                                child: Text(
                                  text,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    color: isMe
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              SizedBox(height: R.h(context, 3)),
                              Text(
                                time,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 9,
                                  color: context.appTextHint,
                                ),
                              ),
                            ],
                          ),
                          if (isMe) SizedBox(width: R.w(context, 8)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Input bar
          Container(
            padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 10), R.p(context, 16), R.p(context, 20)),
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
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Type your message…',
                      hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: context.appTextHint,
                      ),
                      filled: true,
                      fillColor: context.appBackground,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: R.p(context, 16), vertical: R.p(context, 12)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(R.r(context, 24)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: R.w(context, 10)),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: R.w(context, 46), height: R.h(context, 46),
                    decoration: BoxDecoration(
                      color: _kGreen,
                      borderRadius: BorderRadius.circular(R.r(context, 14)),
                    ),
                    child: _sending
                        ? Padding(
                            padding: EdgeInsets.all(R.p(context, 12)),
                            child: const CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(Icons.send_rounded,
                            color: Colors.white, size: R.w(context, 20)),
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

// ─────────────────────────────────────────────────────────────────────────────
//  Chat bubble skeleton
// ─────────────────────────────────────────────────────────────────────────────

class _ChatBubbleSkeleton extends StatelessWidget {
  const _ChatBubbleSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: R.p(context, 10)),
      child: AppShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: EdgeInsets.only(right: R.p(context, 60)),
              padding: EdgeInsets.all(R.p(context, 12)),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(R.r(context, 14)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: double.infinity, height: 12, radius: 4),
                  SizedBox(height: 5),
                  SkeletonBox(width: 160, height: 12, radius: 4),
                ],
              ),
            ),
            SizedBox(height: R.h(context, 6)),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                margin: EdgeInsets.only(left: R.p(context, 60)),
                padding: EdgeInsets.all(R.p(context, 12)),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(R.r(context, 14)),
                ),
                child: const SkeletonBox(width: 140, height: 12, radius: 4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
