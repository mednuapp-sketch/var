import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../../../core/widgets/ux_widgets.dart';

class DoctorEarningsScreen extends StatefulWidget {
  const DoctorEarningsScreen({super.key});

  @override
  State<DoctorEarningsScreen> createState() => _DoctorEarningsScreenState();
}

class _DoctorEarningsScreenState extends State<DoctorEarningsScreen> {
  int _retryKey = 0;

  @override
  Widget build(BuildContext context) {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: KeyedSubtree(
        key: ValueKey(_retryKey),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('appointments')
              .where('doctorId', isEqualTo: uid)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return _LoadingBody();
            }
            if (snap.hasError) {
              return _ErrorBody(onRetry: () => setState(() => _retryKey++));
            }
            final cutoff = DateTime.now().subtract(const Duration(days: 365));
            final allDocs = (snap.data?.docs ?? []).where((doc) {
              final ts = doc.data()['createdAt'] as Timestamp?;
              if (ts == null) return true;
              return ts.toDate().isAfter(cutoff);
            }).toList();
            return _EarningsBody(uid: uid, allDocs: allDocs);
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading / Error States
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        _GradientAppBar(),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SkeletonBox(width: double.infinity, height: 100, radius: 20),
              const SizedBox(height: 16),
              const SkeletonBox(width: double.infinity, height: 180, radius: 20),
              const SizedBox(height: 16),
              ...List.generate(4, (_) => const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: SkeletonListTile(),
              )),
            ]),
          ),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorBody({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        _GradientAppBar(),
        SliverFillRemaining(
          child: AppErrorState(onRetry: onRetry),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gradient SliverAppBar
// ─────────────────────────────────────────────────────────────────────────────

class _GradientAppBar extends StatelessWidget {
  final num? lifetime;
  final num? today;
  final num? week;
  final num? month;

  const _GradientAppBar({this.lifetime, this.today, this.week, this.month});

  @override
  Widget build(BuildContext context) {
    final hasData = lifetime != null;
    return SliverAppBar(
      expandedHeight: hasData ? 220 : 80,
      pinned: true,
      leading: const BackButton(color: Colors.white),
      backgroundColor: AppColors.primary,
      elevation: 0,
      title: const Text(
        'Earnings & Analytics',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A0030), Color(0xFFC2185B), Color(0xFF7B1FA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Positioned(
              top: -50,
              right: -50,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Positioned(
              bottom: -30,
              left: -30,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            if (hasData)
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      reverse: true,
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Last 12 Months',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 10,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '₹${_formatAmount(lifetime!)}',
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 38,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(children: [
                                Expanded(
                                    child: _HeroStat(
                                        _formatAmount(today!), 'Today')),
                                _heroDivider(),
                                Expanded(
                                    child: _HeroStat(
                                        _formatAmount(week!), 'This Week')),
                                _heroDivider(),
                                Expanded(
                                    child: _HeroStat(
                                        _formatAmount(month!), 'This Month')),
                              ]),
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
    );
  }

  Widget _heroDivider() => Container(
        width: 1,
        height: 36,
        color: Colors.white24,
        margin: const EdgeInsets.symmetric(horizontal: 14),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Body
// ─────────────────────────────────────────────────────────────────────────────

class _EarningsBody extends StatelessWidget {
  final String uid;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs;

  const _EarningsBody({required this.uid, required this.allDocs});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartStr = DateFormat('yyyy-MM-dd').format(weekStart);
    final monthStart =
        DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month, 1));

    // ── Partition by status ──────────────────────────────────────────────────
    final completed =
        allDocs.where((d) => d.data()['status'] == 'completed').toList();
    final cancelled =
        allDocs.where((d) => d.data()['status'] == 'cancelled').toList();
    final upcoming = allDocs.where((d) {
      final s = d.data()['status'] as String? ?? '';
      return s == 'upcoming' ||
          s == 'scheduled' ||
          s == 'confirmed' ||
          s == 'booked';
    }).toList();

    // ── Earnings aggregation ─────────────────────────────────────────────────
    num lifetime = 0, monthE = 0, weekE = 0, todayE = 0;
    for (final doc in completed) {
      final d = doc.data();
      final fee = (d['fee'] as num?) ?? 0;
      final dateStr = d['date'] as String? ?? '';
      lifetime += fee;
      if (dateStr.compareTo(monthStart) >= 0) {
        monthE += fee;
        if (dateStr.compareTo(weekStartStr) >= 0) {
          weekE += fee;
          if (dateStr == today) todayE += fee;
        }
      }
    }

    // ── Consult type split ───────────────────────────────────────────────────
    final videoCount = completed.where((d) {
      final t = (d.data()['consultationType'] as String? ?? '').toLowerCase();
      return t.contains('video') || t.contains('online');
    }).length;
    final inPersonCount = completed.length - videoCount;

    // ── Unique patients ──────────────────────────────────────────────────────
    final uniquePatients = <String>{};
    for (final d in allDocs) {
      final pid = d.data()['patientId'] as String? ?? '';
      if (pid.isNotEmpty) uniquePatients.add(pid);
    }

    // ── Avg per consultation ─────────────────────────────────────────────────
    final avgPerConsult =
        completed.isNotEmpty ? (lifetime / completed.length).round() : 0;

    // ── Completion rate ──────────────────────────────────────────────────────
    final completionRate = allDocs.isNotEmpty
        ? '${((completed.length / allDocs.length) * 100).round()}%'
        : '–';

    // ── Weekly bar chart (last 7 days, index 0=oldest, 6=today) ─────────────
    final weeklyMap = <int, double>{for (var i = 0; i < 7; i++) i: 0};
    for (final doc in completed) {
      final d = doc.data();
      try {
        final dt = DateTime.parse(d['date'] as String? ?? '');
        final diff = now.difference(dt).inDays;
        if (diff >= 0 && diff < 7) {
          final idx = 6 - diff;
          weeklyMap[idx] =
              (weeklyMap[idx] ?? 0) + ((d['fee'] as num?) ?? 0).toDouble();
        }
      } catch (_) {}
    }

    // ── 30-day line chart ────────────────────────────────────────────────────
    final monthlyMap = <int, double>{for (var i = 0; i < 30; i++) i: 0};
    for (final doc in completed) {
      final d = doc.data();
      try {
        final dt = DateTime.parse(d['date'] as String? ?? '');
        final diff = now.difference(dt).inDays;
        if (diff >= 0 && diff < 30) {
          final idx = 29 - diff;
          monthlyMap[idx] =
              (monthlyMap[idx] ?? 0) + ((d['fee'] as num?) ?? 0).toDouble();
        }
      } catch (_) {}
    }

    // ── Peak booking hour ─────────────────────────────────────────────────────
    String peakHour = '–';
    final hourCounts = <int, int>{};
    for (final doc in allDocs) {
      final timeStr = doc.data()['time'] as String? ?? '';
      try {
        final parts = timeStr.trim().split(':');
        if (parts.length >= 2) {
          var h = int.parse(parts[0]);
          final rest = parts[1].split(' ');
          final ampm = rest.length > 1 ? rest[1].toUpperCase() : '';
          if (ampm == 'PM' && h != 12) h += 12;
          if (ampm == 'AM' && h == 12) h = 0;
          hourCounts[h] = (hourCounts[h] ?? 0) + 1;
        }
      } catch (_) {}
    }
    if (hourCounts.isNotEmpty) {
      final peak =
          hourCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
      final h = peak.key;
      final ampm = h >= 12 ? 'PM' : 'AM';
      final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      peakHour = '$displayH:00 $ampm';
    }

    // ── Recent 20 transactions ────────────────────────────────────────────────
    final recent = [...completed]
      ..sort((a, b) {
        final aTs =
            (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final bTs =
            (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return bTs.compareTo(aTs);
      });
    final recentSlice = recent.take(20).toList();

    return CustomScrollView(
      slivers: [
        _GradientAppBar(
          lifetime: lifetime,
          today: todayE,
          week: weekE,
          month: monthE,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Quick Stats ────────────────────────────────────────────
                FadeInSlide(
                  child: Row(children: [
                    _QuickStatCard(
                      label: 'Avg/Consult',
                      value: '₹$avgPerConsult',
                      icon: Icons.bar_chart_rounded,
                      color: AppColors.info,
                    ),
                    const SizedBox(width: 10),
                    _QuickStatCard(
                      label: 'Completion',
                      value: completionRate,
                      icon: Icons.check_circle_outline_rounded,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 10),
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: DoctorAuthService.profileStream(uid),
                      builder: (ctx, ps) {
                        final rating =
                            (ps.data?.data()?['rating'] as num?)
                                ?.toStringAsFixed(1) ??
                            '–';
                        return _QuickStatCard(
                          label: 'Rating',
                          value: '$rating ⭐',
                          icon: Icons.star_rounded,
                          color: AppColors.warning,
                        );
                      },
                    ),
                  ]),
                ),
                const SizedBox(height: 22),

                // ── Consultation Analytics ─────────────────────────────────
                FadeInSlide(
                  delay: const Duration(milliseconds: 60),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(title: 'Consultation Analytics'),
                      const SizedBox(height: 12),
                      _ConsultGrid(
                        total: allDocs.length,
                        completed: completed.length,
                        cancelled: cancelled.length,
                        upcoming: upcoming.length,
                        video: videoCount,
                        inPerson: inPersonCount,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // ── Weekly Bar Chart ───────────────────────────────────────
                FadeInSlide(
                  delay: const Duration(milliseconds: 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(
                        title: 'Weekly Earnings',
                        subtitle: 'Last 7 days',
                      ),
                      const SizedBox(height: 12),
                      _WeeklyBarChart(weeklyMap: weeklyMap, now: now),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // ── 30-Day Trend ───────────────────────────────────────────
                FadeInSlide(
                  delay: const Duration(milliseconds: 140),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(
                        title: '30-Day Trend',
                        subtitle: 'Daily earnings over last 30 days',
                      ),
                      const SizedBox(height: 12),
                      _MonthlyTrendChart(monthlyMap: monthlyMap),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // ── Appointment Insights ───────────────────────────────────
                FadeInSlide(
                  delay: const Duration(milliseconds: 180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(title: 'Appointment Insights'),
                      const SizedBox(height: 12),
                      Row(children: [
                        _InsightCard(
                          icon: Icons.upcoming_rounded,
                          color: AppColors.info,
                          label: 'Upcoming',
                          value: '${upcoming.length}',
                        ),
                        const SizedBox(width: 10),
                        _InsightCard(
                          icon: Icons.people_outline_rounded,
                          color: AppColors.success,
                          label: 'Patients',
                          value: '${uniquePatients.length}',
                        ),
                        const SizedBox(width: 10),
                        _InsightCard(
                          icon: Icons.schedule_rounded,
                          color: const Color(0xFF6A1B9A),
                          label: 'Peak Hour',
                          value: peakHour,
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // ── Wallet Section ─────────────────────────────────────────
                FadeInSlide(
                  delay: const Duration(milliseconds: 220),
                  child: _WalletSection(uid: uid, pendingEarnings: monthE),
                ),
                const SizedBox(height: 22),

                // ── Recent Transactions ────────────────────────────────────
                FadeInSlide(
                  delay: const Duration(milliseconds: 260),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(
                        title: 'Recent Transactions',
                        subtitle:
                            'Last ${recentSlice.length} completed consultations',
                      ),
                      const SizedBox(height: 12),
                      if (recentSlice.isEmpty)
                        const AppEmptyState(
                          icon: Icons.receipt_long_rounded,
                          title: 'No Transactions Yet',
                          message:
                              'Completed consultations will appear here.',
                        )
                      else
                        ...recentSlice.map((doc) => _TransactionTile(doc: doc)),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wallet Section
// ─────────────────────────────────────────────────────────────────────────────

class _WalletSection extends StatelessWidget {
  final String uid;
  final num pendingEarnings;

  const _WalletSection({required this.uid, required this.pendingEarnings});

  @override
  Widget build(BuildContext context) {
    final pending = pendingEarnings;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Wallet & Payouts',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            _WalletStat('₹${_formatAmount(pending)}', 'This Month',
                Icons.pending_rounded),
            _walletDivider(),
            const _WalletStat('Coming soon', 'Wallet Balance',
                Icons.savings_rounded),
            _walletDivider(),
            const _WalletStat('Coming soon', 'Withdrawn', Icons.south_rounded),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: pending > 0
                  ? () => _showWithdrawDialog(context, pending)
                  : null,
              icon: const Icon(Icons.send_rounded, size: 16),
              label: Text(
                pending > 0
                    ? 'Request Withdrawal  ₹${_formatAmount(pending)}'
                    : 'No Pending Payout',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1565C0),
                disabledBackgroundColor: Colors.white30,
                disabledForegroundColor: Colors.white60,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _walletDivider() => Container(
        width: 1,
        height: 40,
        color: Colors.white24,
        margin: const EdgeInsets.symmetric(horizontal: 10),
      );

  void _showWithdrawDialog(BuildContext context, num amount) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Request Withdrawal', style: AppTextStyles.h4),
        content: Text(
          'Submit a withdrawal request for ₹${_formatAmount(amount)}?\n\nProcessing takes 3–5 business days.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Withdrawal of ₹${_formatAmount(amount)} requested. Processing in 3–5 business days.'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.success,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child:
                const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Weekly Bar Chart (fl_chart)
// ─────────────────────────────────────────────────────────────────────────────

class _WeeklyBarChart extends StatelessWidget {
  final Map<int, double> weeklyMap;
  final DateTime now;

  const _WeeklyBarChart({required this.weeklyMap, required this.now});

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final maxY = weeklyMap.values.fold(0.0, (a, b) => b > a ? b : a);
    final double chartMax = maxY > 0 ? maxY * 1.3 : 500.0;

    final dayLabels = List<String>.generate(7, (i) {
      final daysAgo = 6 - i;
      final dayOfWeek = (now.weekday - 1 - daysAgo) % 7;
      final idx = dayOfWeek < 0 ? dayOfWeek + 7 : dayOfWeek;
      return _dayLabels[idx];
    });

    final groups = List<BarChartGroupData>.generate(7, (i) {
      final isToday = i == 6;
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: weeklyMap[i] ?? 0,
            gradient: isToday
                ? const LinearGradient(
                    colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  )
                : const LinearGradient(
                    colors: [Color(0xFFE91E8C), Color(0xFF9C27B0)],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
            width: 22,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: chartMax,
              color: AppColors.divider,
            ),
          ),
        ],
      );
    });

    return PremiumCard(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        children: [
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: chartMax,
                barGroups: groups,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        final isToday = idx == 6;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            idx >= 0 && idx < dayLabels.length
                                ? dayLabels[idx]
                                : '',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: isToday
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: isToday
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                        BarTooltipItem(
                      '₹${_formatAmount(rod.toY)}',
                      const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'Today highlighted',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: AppColors.textHint,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 30-Day Line Chart (fl_chart)
// ─────────────────────────────────────────────────────────────────────────────

class _MonthlyTrendChart extends StatelessWidget {
  final Map<int, double> monthlyMap;

  const _MonthlyTrendChart({required this.monthlyMap});

  @override
  Widget build(BuildContext context) {
    final spots = List<FlSpot>.generate(
      30,
      (i) => FlSpot(i.toDouble(), monthlyMap[i] ?? 0),
    );
    final maxY = monthlyMap.values.fold(0.0, (a, b) => b > a ? b : a);
    final double chartMax = maxY > 0 ? maxY * 1.2 : 500.0;

    return PremiumCard(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: SizedBox(
        height: 140,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: 29,
            minY: 0,
            maxY: chartMax,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: chartMax / 4,
              getDrawingHorizontalLine: (v) =>
                  FlLine(color: AppColors.divider, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              show: true,
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              bottomTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: chartMax / 4,
                  getTitlesWidget: (value, meta) => Text(
                    '₹${_formatAmount(value)}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 9,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.35,
                color: AppColors.primary,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.25),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (touchedSpots) => touchedSpots
                    .map((s) => LineTooltipItem(
                          '₹${_formatAmount(s.y)}',
                          const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Consultation Grid (3-column, 2 rows)
// ─────────────────────────────────────────────────────────────────────────────

class _ConsultGrid extends StatelessWidget {
  final int total, completed, cancelled, upcoming, video, inPerson;

  const _ConsultGrid({
    required this.total,
    required this.completed,
    required this.cancelled,
    required this.upcoming,
    required this.video,
    required this.inPerson,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _GridItem('Total', '$total', Icons.list_alt_rounded, AppColors.info),
      _GridItem('Completed', '$completed', Icons.check_circle_rounded,
          AppColors.success),
      _GridItem('Cancelled', '$cancelled', Icons.cancel_rounded,
          AppColors.error),
      _GridItem('Upcoming', '$upcoming', Icons.upcoming_rounded,
          AppColors.warning),
      _GridItem('Video', '$video', Icons.videocam_rounded,
          const Color(0xFF6A1B9A)),
      _GridItem('In-Person', '$inPerson', Icons.person_pin_circle_rounded,
          AppColors.accent),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.1,
      ),
      itemBuilder: (context, i) {
        final item = items[i];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      item.color.withValues(alpha: 0.18),
                      item.color.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, color: item.color, size: 18),
              ),
              const SizedBox(height: 6),
              Text(
                item.value,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: item.color,
                ),
              ),
              Text(
                item.label,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GridItem {
  final String label, value;
  final IconData icon;
  final Color color;
  const _GridItem(this.label, this.value, this.icon, this.color);
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: subtitle != null ? 36 : 20,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.secondary],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.h4),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: AppTextStyles.caption),
              ],
            ],
          ),
        ],
      );
}

class _HeroStat extends StatelessWidget {
  final String value, label;
  const _HeroStat(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '₹$value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              color: Colors.white70,
            ),
          ),
        ],
      );
}

class _QuickStatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _QuickStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.18),
                    color.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: AppColors.textHint,
              ),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );
}

class _InsightCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  const _InsightCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.18),
                    color.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: AppColors.textHint,
              ),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );
}

class _WalletStat extends StatelessWidget {
  final String value, label;
  final IconData icon;
  const _WalletStat(this.value, this.label, this.icon);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 9,
              color: Colors.white60,
            ),
            textAlign: TextAlign.center,
          ),
        ]),
      );
}

class _TransactionTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _TransactionTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final name = d['patientName'] as String? ?? 'Patient';
    final type = d['consultationType'] as String? ?? 'Consultation';
    final fee = d['fee'] as num? ?? 0;
    final dateStr = d['date'] as String? ?? '';
    final time = d['time'] as String? ?? '';

    String displayDate = dateStr;
    try {
      final dt = DateTime.parse(dateStr);
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      if (dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day) {
        displayDate = 'Today';
      } else if (dt.year == yesterday.year &&
          dt.month == yesterday.month &&
          dt.day == yesterday.day) {
        displayDate = 'Yesterday';
      } else {
        displayDate = DateFormat('d MMM').format(dt);
      }
    } catch (_) {}

    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 16,
      child: Row(children: [
        AppAvatar(name: name, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(name, style: AppTextStyles.labelLarge),
            Text(type, style: AppTextStyles.bodySmall),
            Text(
              '$displayDate${time.isNotEmpty ? ' • $time' : ''}',
              style: AppTextStyles.caption,
            ),
          ]),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '+₹$fee',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

String _formatAmount(num v) {
  if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return v.toStringAsFixed(0);
}
