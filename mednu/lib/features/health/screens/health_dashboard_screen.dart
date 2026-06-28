import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/water_tracker_provider.dart';
import '../../../core/widgets/ux_widgets.dart';

// â”€â”€â”€ Entry point â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//
// HealthDashboardScreen is a plain StatelessWidget.
// All Riverpod access is inside _DashboardContent (a ConsumerWidget that
// only receives uid – never a stored WidgetRef or BuildContext).
// Auth state is handled by StreamBuilder<User?> so the screen always
// rebuilds when Firebase restores the session.

class HealthDashboardScreen extends StatelessWidget {
  const HealthDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          // Use cached currentUser so there is no loading flash when the
          // user is already signed in (common case).
          final uid = snap.data?.uid
              ?? FirebaseAuth.instance.currentUser?.uid;

          if (uid == null) {
            // Still waiting for Firebase to restore the session.
            if (snap.connectionState == ConnectionState.waiting) {
              return _FullPageLoader();
            }
            // Genuinely not signed in.
            return _NotSignedIn();
          }

          // Signed in – hand off to the ConsumerWidget.
          return _DashboardContent(uid: uid);
        },
      ),
    );
  }
}

// â”€â”€â”€ Full-page loader â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _FullPageLoader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('Health Dashboard',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          leading: IconButton(
            icon:
                const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => context.pop(),
          ),
        ),
        body: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: double.infinity, height: 140, radius: 20),
              const SizedBox(height: 16),
              const Row(children: [
                Expanded(child: SkeletonBox(width: double.infinity, height: 90, radius: 16)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(width: double.infinity, height: 90, radius: 16)),
              ]),
              const SizedBox(height: 16),
              const SkeletonBox(width: double.infinity, height: 200, radius: 20),
              const SizedBox(height: 16),
              ...List.generate(3, (_) => const _HealthItemSkeleton()),
            ],
          ),
        ),
      );
}

// â”€â”€â”€ Not signed in â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _NotSignedIn extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('Health Dashboard',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          leading: IconButton(
            icon:
                const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.monitor_heart_rounded,
                      color: Colors.white, size: 36),
                ),
                const SizedBox(height: 20),
                Text('Sign in to view your Health Dashboard',
                    textAlign: TextAlign.center,
                    style:
                        AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Text(
                  'Track vitals, appointments, prescriptions and more.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
}

// â”€â”€â”€ Dashboard content â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _DashboardContent extends ConsumerWidget {
  final String uid;
  const _DashboardContent({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waterState    = ref.watch(waterTrackerProvider);
    final waterNotifier = ref.read(waterTrackerProvider.notifier);
    final userDocAsync  = ref.watch(userDocProvider(uid));
    final userName =
        userDocAsync.value?['name'] as String? ?? '';
    final gender =
        (userDocAsync.value?['gender'] as String? ?? '').toLowerCase();
    final isMale = gender == 'male';

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        _appBar(context, userName),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // â”€â”€ Vitals â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              _SecHead('Health Summary', Icons.monitor_heart_rounded,
                  AppColors.error,
                  btn: _btn('Log Vitals',
                      () => _logVitalsSheet(context))),
              const SizedBox(height: 10),
              _VitalsSection(uid: uid),
              const SizedBox(height: 22),

              // â”€â”€ Water â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              _SecHead('Water Intake', Icons.water_drop_rounded,
                  const Color(0xFF1565C0)),
              const SizedBox(height: 10),
              _WaterCard(state: waterState, notifier: waterNotifier),
              const SizedBox(height: 22),

              // â”€â”€ Appointments â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              _SecHead('Upcoming Appointments',
                  Icons.calendar_today_rounded, AppColors.info,
                  btn: _btn('View All',
                      () => context.push(AppRoutes.appointment))),
              const SizedBox(height: 10),
              _AppointmentsSection(uid: uid),
              const SizedBox(height: 22),

              // â”€â”€ Prescriptions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              _SecHead('Active Prescriptions', Icons.medication_rounded,
                  const Color(0xFF2E7D32),
                  btn: _btn(
                      'View All', () => context.push(AppRoutes.records))),
              const SizedBox(height: 10),
              _PrescriptionsSection(uid: uid),
              const SizedBox(height: 22),

              // â”€â”€ Health Records Quick Links â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              _SecHead('Health Records', Icons.folder_open_rounded,
                  const Color(0xFF6A1B9A)),
              const SizedBox(height: 10),
              _QuickActions(uid: uid),
              const SizedBox(height: 22),

              // â”€â”€ Women's Health â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              if (!isMale) ...[
                _SecHead("Women's Health", Icons.favorite_rounded,
                    AppColors.primary),
                const SizedBox(height: 10),
                _WomensHealth(),
                const SizedBox(height: 22),
              ],

              // â”€â”€ BMI â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              _SecHead('BMI Calculator', Icons.monitor_weight_rounded,
                  const Color(0xFF2E7D32)),
              const SizedBox(height: 10),
              _BMICard(uid: uid),
            ]),
          ),
        ),
      ],
    );
  }

  SliverAppBar _appBar(BuildContext context, String name) {
    final h = DateTime.now().hour;
    final greet =
        h < 12 ? 'Good Morning' : h < 17 ? 'Good Afternoon' : 'Good Evening';
    final first =
        name.isNotEmpty ? ', ${name.split(' ').first}' : '';
    return SliverAppBar(
      pinned: true,
      expandedHeight: 150,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => context.pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Container(
          decoration:
              const BoxDecoration(gradient: AppColors.primaryGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 44, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha:0.2),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.monitor_heart_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$greet$first',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Colors.white70)),
                        const Text('Health Dashboard',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: Colors.white54)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary)),
      );

  void _logVitalsSheet(BuildContext context) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _LogVitalsSheet(uid: uid),
      );
}

// â”€â”€â”€ Section header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SecHead extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget? btn;
  const _SecHead(this.title, this.icon, this.color, {this.btn});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (btn != null) btn!,
        ],
      );
}

// â”€â”€â”€ Vitals section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _VitalsSection extends StatelessWidget {
  final String uid;
  const _VitalsSection({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('health_data')
          .doc(uid)
          .collection('vitals')
          .orderBy('recordedAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _vitalsLoading();
        }
        if (snap.hasError || snap.data == null) {
          return _InfoCard(
            icon: Icons.error_outline_rounded,
            iconColor: AppColors.error,
            text: 'Could not load vitals. Tap "Log Vitals" to add your first reading.',
          );
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return _InfoCard(
            icon: Icons.monitor_heart_outlined,
            iconColor: AppColors.error,
            text: 'No vitals recorded yet. Tap "Log Vitals" to track BP, heart rate, blood sugar & more.',
          );
        }
        return _VitalsGrid(data: docs.first.data());
      },
    );
  }

  Widget _vitalsLoading() => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        childAspectRatio: 1.45,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        children: List.generate(
          4,
          (_) => const SkeletonBox(
              width: double.infinity, height: double.infinity, radius: 16),
        ),
      );
}

class _VitalsGrid extends StatelessWidget {
  final Map<String, dynamic> data;
  const _VitalsGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    final hr     = data['heartRate'] as num?;
    final bpS    = data['bpSystolic'] as num?;
    final bpD    = data['bpDiastolic'] as num?;
    final sugar  = data['bloodSugar'] as num?;
    final spo2   = data['spo2'] as num?;
    final weight = data['weight'] as num?;
    final ts     = (data['recordedAt'] as Timestamp?)?.toDate();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.45,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            _VCard('Heart Rate', hr != null ? '${hr.round()}' : '–',
                'bpm', Icons.favorite_rounded, const Color(0xFFE53935),
                _hrStatus(hr)),
            _VCard(
                'Blood Pressure',
                (bpS != null && bpD != null)
                    ? '${bpS.round()}/${bpD.round()}'
                    : '–',
                'mmHg',
                Icons.monitor_heart_rounded,
                const Color(0xFF1565C0),
                _bpStatus(bpS)),
            _VCard('Blood Sugar',
                sugar != null ? '${sugar.round()}' : '–', 'mg/dL',
                Icons.water_drop_rounded, const Color(0xFFE65100),
                _sugarStatus(sugar)),
            _VCard('SpO2', spo2 != null ? '${spo2.round()}' : '–',
                '%', Icons.air_rounded, const Color(0xFF2E7D32),
                _spo2Status(spo2)),
          ],
        ),
        if (weight != null || ts != null) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider)),
            child: Row(
              children: [
                if (weight != null) ...[
                  const Icon(Icons.monitor_weight_rounded,
                      color: Color(0xFF6A1B9A), size: 16),
                  const SizedBox(width: 6),
                  Text('${weight.toStringAsFixed(1)} kg',
                      style: AppTextStyles.labelLarge
                          .copyWith(color: AppColors.textPrimary)),
                ],
                const Spacer(),
                if (ts != null)
                  Text('Updated ${_ago(ts)}',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textHint)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _hrStatus(num? v) {
    if (v == null) return '–';
    if (v < 60) return 'Low';
    if (v <= 100) return 'Normal';
    return 'High';
  }

  String _bpStatus(num? v) {
    if (v == null) return '–';
    if (v < 90) return 'Low';
    if (v <= 120) return 'Normal';
    if (v <= 139) return 'Elevated';
    return 'High';
  }

  String _sugarStatus(num? v) {
    if (v == null) return '–';
    if (v < 70) return 'Low';
    if (v <= 99) return 'Normal';
    if (v <= 125) return 'Pre-DM';
    return 'High';
  }

  String _spo2Status(num? v) {
    if (v == null) return '–';
    if (v >= 95) return 'Normal';
    if (v >= 90) return 'Low';
    return 'Critical';
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'yesterday';
    return DateFormat('d MMM').format(t);
  }
}

class _VCard extends StatelessWidget {
  final String label, value, unit, status;
  final IconData icon;
  final Color color;
  const _VCard(
      this.label, this.value, this.unit, this.icon, this.color, this.status);

  @override
  Widget build(BuildContext context) {
    final sc = status == 'High' || status == 'Critical'
        ? AppColors.error
        : (status == 'Low' || status == 'Elevated' || status == 'Pre-DM')
            ? AppColors.warning
            : const Color(0xFF2E7D32);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha:0.06),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 17),
            const Spacer(),
            if (status != '–')
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                    color: sc.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(5)),
                child: Text(status,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: sc)),
              ),
          ]),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: value.length > 7 ? 16 : 22,
                  fontWeight: FontWeight.w800,
                  color: color)),
          Text(unit,
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.textHint)),
          const SizedBox(height: 2),
          Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// â”€â”€â”€ Water card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _WaterCard extends StatelessWidget {
  final WaterTrackerState state;
  final WaterTrackerNotifier notifier;
  const _WaterCard(
      {required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    const c = Color(0xFF1565C0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
                color: c.withValues(alpha:0.06),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${state.glassesLogged} / ${state.goalGlasses} glasses',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: c)),
                Text('${state.totalMl} ml of ${state.goalMl} ml',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textHint)),
              ]),
              const Spacer(),
              if (state.goalReached)
                _pill('Goal!', Icons.check_circle_rounded,
                    const Color(0xFF2E7D32)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 8,
              backgroundColor: c.withValues(alpha:0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(c),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(
                state.goalGlasses.clamp(1, 12),
                (i) => GestureDetector(
                  onTap: () async {
                    for (int j = state.glassesLogged; j < i + 1; j++) {
                      await notifier.logWater();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Icon(Icons.water_drop_rounded,
                        size: 22,
                        color: i < state.glassesLogged
                            ? c
                            : c.withValues(alpha:0.18)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: c,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: state.goalReached
                    ? null
                    : () async {
                        await notifier.logWater();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content:
                                Text('ðŸ’§ ${state.glassSizeMl} ml logged!'),
                            backgroundColor: c,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            duration: const Duration(seconds: 1),
                          ));
                        }
                      },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                    state.goalReached ? 'Goal Reached!' : 'Log a Glass',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: c),
                foregroundColor: c,
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => context.push(AppRoutes.waterReminder),
              child: const Text('Details',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _pill(String text, IconData icon, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ]),
      );
}

// â”€â”€â”€ Appointments section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AppointmentsSection extends StatelessWidget {
  final String uid;
  const _AppointmentsSection({required this.uid});

  @override
  Widget build(BuildContext context) {
    final todayFloor = DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // patientId + createdAt index already exists — order newest first and
      // cap at 20 so we never download the patient's full appointment history.
      // Status + date filtering is done in client code below.
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('patientId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _loadingCard(70);
        }
        if (snap.hasError) {
          return _InfoCard(
              icon: Icons.calendar_today_rounded,
              iconColor: AppColors.info,
              text: 'Could not load appointments.');
        }

        final upcoming = (snap.data?.docs ?? []).where((doc) {
          final d = doc.data();
          if ((d['status'] as String? ?? '') != 'booked') return false;
          final dt = _parseDate(d['date'] as String? ?? '');
          if (dt == null) return false;
          return !DateTime(dt.year, dt.month, dt.day).isBefore(todayFloor);
        }).take(3).toList();

        if (upcoming.isEmpty) {
          return _InfoCard(
            icon: Icons.calendar_today_rounded,
            iconColor: AppColors.info,
            text: 'No upcoming appointments.',
            cta: 'Book Now',
            onCta: () => context.push(AppRoutes.doctors),
          );
        }

        return Column(
          children: upcoming
              .map((doc) => _ApptTile(data: doc.data()))
              .toList(),
        );
      },
    );
  }

  static DateTime? _parseDate(String s) {
    if (s.isEmpty) return null;
    try { return DateTime.parse(s); } catch (_) {}
    for (final f in [
      DateFormat('EEE, d MMM yyyy'),
      DateFormat('EEE, dd MMM yyyy'),
      DateFormat('d MMM yyyy'),
    ]) {
      try { return f.parse(s); } catch (_) {}
    }
    return null;
  }
}

class _ApptTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ApptTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final doctor     = data['doctorName'] as String? ?? 'Doctor';
    final speciality = data['doctorSpecialty'] as String? ?? '';
    final date       = data['date'] as String? ?? '';
    final time       = data['time'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider)),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              gradient: AppColors.appointmentGrad,
              borderRadius: BorderRadius.circular(12)),
          child:
              const Icon(Icons.person_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(doctor,
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (speciality.isNotEmpty)
              Text(speciality,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(date,
              style: AppTextStyles.caption.copyWith(
                  color: AppColors.primary, fontWeight: FontWeight.w600)),
          if (time.isNotEmpty)
            Text(time,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textHint)),
        ]),
      ]),
    );
  }
}

// â”€â”€â”€ Prescriptions section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PrescriptionsSection extends StatelessWidget {
  final String uid;
  const _PrescriptionsSection({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('prescriptions')
          .where('patientId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _loadingCard(70);
        }
        if (snap.hasError) {
          return _InfoCard(
              icon: Icons.medication_rounded,
              iconColor: const Color(0xFF2E7D32),
              text: 'Could not load prescriptions.');
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _InfoCard(
            icon: Icons.medication_rounded,
            iconColor: const Color(0xFF2E7D32),
            text: 'No prescriptions on record.',
            cta: 'View Records',
            onCta: () => context.push(AppRoutes.records),
          );
        }
        return Column(
          children:
              docs.map((doc) => _RxTile(data: doc.data())).toList(),
        );
      },
    );
  }
}

class _RxTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RxTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final doctor    = data['doctorName'] as String? ?? 'Doctor';
    final meds      = data['medicines'] as List? ?? [];
    final ts        = data['createdAt'] as Timestamp?;
    final dateStr   = ts != null
        ? DateFormat('d MMM yyyy').format(ts.toDate())
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider)),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              gradient: AppColors.medicineGrad,
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.medication_rounded,
              color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dr. $doctor',
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(
                meds.isNotEmpty
                    ? '${meds.length} medicine${meds.length > 1 ? 's' : ''}'
                    : 'View details',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ]),
        ),
        if (dateStr.isNotEmpty)
          Text(dateStr,
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.textHint)),
      ]),
    );
  }
}

// â”€â”€â”€ Quick actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _QuickActions extends StatelessWidget {
  final String uid;
  const _QuickActions({required this.uid});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Prescriptions', Icons.receipt_long_rounded, AppColors.medicineGrad,
          () => context.push(AppRoutes.records)),
      ('Lab Reports', Icons.science_rounded, AppColors.appointmentGrad,
          () => context.push(AppRoutes.records)),
      ('Consultations', Icons.history_rounded, AppColors.consultGrad,
          () => context.push(AppRoutes.appointment)),
      ('Prescription Viewer', Icons.pageview_rounded, AppColors.primaryGradient,
          () => context.push(AppRoutes.prescriptionViewer)),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.35,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: items.map((item) {
        final (label, icon, gradient, onTap) = item;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

// â”€â”€â”€ Women's health â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _WomensHealth extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(children: [
        GestureDetector(
          onTap: () => context.push(AppRoutes.periodTracker),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                const Color(0xFF880E4F).withValues(alpha:0.08),
                const Color(0xFFE91E8C).withValues(alpha:0.08),
              ]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFFE91E8C).withValues(alpha:0.3)),
            ),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF880E4F), Color(0xFFE91E8C)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                    child: Text('ðŸŒ¸', style: TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Period Tracker',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textPrimary)),
                      Text('Track cycle, symptoms & mood',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFE91E8C)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => context.push(AppRoutes.pregnancy),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFC2185B).withValues(alpha:0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.2),
                    shape: BoxShape.circle),
                child: const Icon(Icons.pregnant_woman_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pregnancy Tracking',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: Colors.white)),
                      Text('Weekly updates Â· Nutrition Â· Doctor care',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: Colors.white70)),
                    ]),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white70, size: 15),
            ]),
          ),
        ),
      ]);
}

// â”€â”€â”€ BMI card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _BMICard extends StatelessWidget {
  final String uid;
  const _BMICard({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('health_data')
          .doc(uid)
          .collection('vitals')
          .orderBy('recordedAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        double? w, h;
        if (snap.hasData && (snap.data?.docs ?? []).isNotEmpty) {
          final d = snap.data!.docs.first.data();
          w = (d['weight'] as num?)?.toDouble();
          h = (d['height'] as num?)?.toDouble();
        }

        double? bmi;
        String bmiLabel = '';
        Color bmiColor = const Color(0xFF2E7D32);
        if (w != null && h != null && h > 0) {
          final hm = h / 100;
          bmi = w / (hm * hm);
          if (bmi < 18.5) { bmiLabel = 'Underweight'; bmiColor = const Color(0xFF1565C0); }
          else if (bmi < 25) { bmiLabel = 'Normal'; bmiColor = const Color(0xFF2E7D32); }
          else if (bmi < 30) { bmiLabel = 'Overweight'; bmiColor = const Color(0xFFE65100); }
          else { bmiLabel = 'Obese'; bmiColor = AppColors.error; }
        }

        return Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider)),
          child: Column(children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BMICat('Under\nweight', '< 18.5', Color(0xFF1565C0)),
                _BMICat('Normal',       '18.5–24.9', Color(0xFF2E7D32)),
                _BMICat('Over\nweight', '25–29.9', Color(0xFFE65100)),
                _BMICat('Obese',        '≥ 30', AppColors.error),
              ],
            ),
            const SizedBox(height: 12),
            if (bmi != null)
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                    color: bmiColor.withValues(alpha:0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: bmiColor, size: 17),
                      const SizedBox(width: 7),
                      Text(
                          'BMI ${bmi.toStringAsFixed(1)} – $bmiLabel',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: bmiColor)),
                    ]),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                    'Log your weight & height via "Log Vitals" to see your BMI here.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary),
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.calculate_rounded, size: 17),
                label: const Text('Open BMI Calculator',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                onPressed: () => _calcSheet(context),
              ),
            ),
          ]),
        );
      },
    );
  }

  void _calcSheet(BuildContext context) {
    double h = 165, w = 65;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 14),
              Text('BMI Calculator', style: AppTextStyles.h3),
              const SizedBox(height: 18),
              Text('Height: ${h.round()} cm', style: AppTextStyles.labelLarge),
              Slider(
                  value: h,
                  min: 130,
                  max: 210,
                  onChanged: (v) => set(() => h = v),
                  activeColor: AppColors.primary),
              Text('Weight: ${w.round()} kg', style: AppTextStyles.labelLarge),
              Slider(
                  value: w,
                  min: 25,
                  max: 200,
                  onChanged: (v) => set(() => w = v),
                  activeColor: AppColors.primary),
              const SizedBox(height: 10),
              Builder(builder: (_) {
                final hm = h / 100;
                final bmi = w / (hm * hm);
                final Color col;
                final String lbl;
                if (bmi < 18.5) { col = const Color(0xFF1565C0); lbl = 'Underweight'; }
                else if (bmi < 25) { col = const Color(0xFF2E7D32); lbl = 'Normal'; }
                else if (bmi < 30) { col = const Color(0xFFE65100); lbl = 'Overweight'; }
                else { col = AppColors.error; lbl = 'Obese'; }
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: col.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.monitor_weight_rounded,
                            color: col, size: 20),
                        const SizedBox(width: 8),
                        Text(
                            'BMI: ${bmi.toStringAsFixed(1)} – $lbl',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: col)),
                      ]),
                );
              }),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BMICat extends StatelessWidget {
  final String label, range;
  final Color color;
  const _BMICat(this.label, this.range, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              range,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 9,
                color: AppColors.textHint,
              ),
            ),
          ]),
        ),
      );
}

// â”€â”€â”€ Log Vitals sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _LogVitalsSheet extends StatefulWidget {
  final String uid;
  const _LogVitalsSheet({required this.uid});

  @override
  State<_LogVitalsSheet> createState() => _LogVitalsSheetState();
}

class _LogVitalsSheetState extends State<_LogVitalsSheet> {
  final _hr     = TextEditingController();
  final _bpS    = TextEditingController();
  final _bpD    = TextEditingController();
  final _sugar  = TextEditingController();
  final _spo2   = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_hr, _bpS, _bpD, _sugar, _spo2, _weight, _height]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final vitals = <String, dynamic>{
        'recordedAt': FieldValue.serverTimestamp(),
      };
      void add(String key, TextEditingController c,
          {bool decimal = false}) {
        final t = c.text.trim();
        if (t.isEmpty) return;
        final parsed = decimal ? double.tryParse(t) : int.tryParse(t);
        if (parsed == null) return;
        vitals[key] = parsed;
      }
      add('heartRate', _hr);
      add('bpSystolic', _bpS);
      add('bpDiastolic', _bpD);
      add('bloodSugar', _sugar);
      add('spo2', _spo2);
      add('weight', _weight, decimal: true);
      add('height', _height, decimal: true);

      await FirebaseFirestore.instance
          .collection('health_data')
          .doc(widget.uid)
          .collection('vitals')
          .add(vitals);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Vitals saved!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to save. Please try again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 14),
                  Text('Log Today\'s Vitals', style: AppTextStyles.h3),
                  const SizedBox(height: 4),
                  Text('Fill in any or all fields',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _VF(_hr, 'Heart Rate', '72', 'bpm')),
                    const SizedBox(width: 10),
                    Expanded(child: _VF(_spo2, 'SpO2', '98', '%')),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: _VF(_bpS, 'BP Systolic', '120', 'mmHg')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _VF(_bpD, 'BP Diastolic', '80', 'mmHg')),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: _VF(_sugar, 'Blood Sugar', '95', 'mg/dL')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _VF(_weight, 'Weight', '65.0', 'kg',
                            decimal: true)),
                  ]),
                  const SizedBox(height: 10),
                  _VF(_height, 'Height', '170', 'cm', decimal: true),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Save Vitals',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Colors.white)),
                    ),
                  ),
                ]),
          ),
        ),
      );
}

class _VF extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint, suffix;
  final bool decimal;
  const _VF(this.ctrl, this.label, this.hint, this.suffix,
      {this.decimal = false});

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffix,
          labelStyle: AppTextStyles.bodySmall
              .copyWith(color: AppColors.textSecondary),
          suffixStyle:
              AppTextStyles.caption.copyWith(color: AppColors.textHint),
          filled: true,
          fillColor: AppColors.background,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5)),
        ),
      );
}

// â”€â”€â”€ Shared helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final String? cta;
  final VoidCallback? onCta;
  const _InfoCard(
      {required this.icon,
      required this.iconColor,
      required this.text,
      this.cta,
      this.onCta});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider)),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: iconColor.withValues(alpha:0.1), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ),
          if (cta != null && onCta != null) ...[
            const SizedBox(width: 6),
            TextButton(
              onPressed: onCta,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(cta!,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: AppColors.primary)),
            ),
          ],
        ]),
      );
}

Widget _loadingCard(double height) =>
    SkeletonBox(width: double.infinity, height: height, radius: 14);

class _HealthItemSkeleton extends StatelessWidget {
  const _HealthItemSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 6)],
      ),
      child: const AppShimmer(
        child: Row(children: [
          SkeletonBox(width: 44, height: 44, radius: 12),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: double.infinity, height: 13, radius: 4),
            SizedBox(height: 6),
            SkeletonBox(width: 160, height: 11, radius: 4),
          ])),
          SizedBox(width: 8),
          SkeletonBox(width: 50, height: 22, radius: 8),
        ]),
      ),
    );
  }
}
