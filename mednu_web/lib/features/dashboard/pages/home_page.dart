import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

final userProfileProvider = StreamProvider<Map<String, dynamic>>((ref) {
  if (_uid.isEmpty) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .snapshots()
      .map((s) => s.data() ?? {});
});

final upcomingAppointmentsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  if (_uid.isEmpty) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('appointments')
      .where('patientId', isEqualTo: _uid)
      .where('status', isEqualTo: 'booked')
      .orderBy('date')
      .limit(5)
      .snapshots()
      .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

final walletProvider = StreamProvider<double>((ref) {
  if (_uid.isEmpty) return Stream.value(0.0);
  return FirebaseFirestore.instance
      .collection('wallet')
      .doc(_uid)
      .snapshots()
      .map((s) => (s.data()?['balance'] as num?)?.toDouble() ?? 0.0);
});

// ─── Page ─────────────────────────────────────────────────────────────────────

class DashboardHomePage extends ConsumerWidget {
  const DashboardHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = Responsive.isMobile(context);
    final userAsync = ref.watch(userProfileProvider);
    final appointmentsAsync = ref.watch(upcomingAppointmentsProvider);
    final walletAsync = ref.watch(walletProvider);

    final user = userAsync.valueOrNull ?? {};
    final appointments = appointmentsAsync.valueOrNull ?? [];
    final walletBalance = walletAsync.valueOrNull ?? 0.0;
    final familyCount = (user['familyMembers'] as List?)?.length ?? 0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeCard(user: user),
          const SizedBox(height: 24),
          _QuickStats(
            isMobile: isMobile,
            upcomingCount: appointments.length,
            walletBalance: walletBalance,
            familyCount: familyCount,
          ),
          const SizedBox(height: 24),
          isMobile
              ? Column(children: [
                  _UpcomingAppointmentsCard(appointments: appointments, loading: appointmentsAsync.isLoading),
                  const SizedBox(height: 20),
                  _EmptyHealthCard(),
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: _UpcomingAppointmentsCard(appointments: appointments, loading: appointmentsAsync.isLoading)),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: _EmptyHealthCard()),
                ]),
        ],
      ),
    );
  }
}

// ─── Welcome Card ─────────────────────────────────────────────────────────────

class _WelcomeCard extends StatelessWidget {
  final Map<String, dynamic> user;
  const _WelcomeCard({required this.user});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] as String?)?.split(' ').first ?? 'there';
    final phone = user['phoneNumber'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_greeting()}! 👋', style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
                const SizedBox(height: 4),
                Text(
                  'Welcome back, $name',
                  style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, height: 1.2),
                ),
                const SizedBox(height: 8),
                Text(
                  phone.isNotEmpty ? '+91 $phone' : 'Stay healthy!',
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70, height: 1.5),
                ),
                const SizedBox(height: 16),
                const Row(children: [
                  _WelcomeChip(label: 'Book Appointment', icon: Icons.calendar_today_rounded),
                  SizedBox(width: 10),
                  _WelcomeChip(label: 'Find Doctor', icon: Icons.search_rounded),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _WelcomeChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0x4DFFFFFF)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.white),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
      ]),
    );
  }
}

// ─── Quick Stats ──────────────────────────────────────────────────────────────

class _QuickStats extends StatelessWidget {
  final bool isMobile;
  final int upcomingCount;
  final double walletBalance;
  final int familyCount;

  const _QuickStats({
    required this.isMobile,
    required this.upcomingCount,
    required this.walletBalance,
    required this.familyCount,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      {'emoji': '📅', 'value': '$upcomingCount', 'label': 'Upcoming Appointments', 'color': 0xFF42A5F5},
      {'emoji': '💰', 'value': '₹${walletBalance.toStringAsFixed(0)}', 'label': 'Wallet Balance', 'color': 0xFFFFA726},
      {'emoji': '👨‍👩‍👧', 'value': '$familyCount', 'label': 'Family Members', 'color': 0xFFEC407A},
      {'emoji': '🏥', 'value': 'MedNU', 'label': 'Healthcare Partner', 'color': 0xFF66BB6A},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 2 : 4,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: isMobile ? 1.3 : 1.5,
      ),
      itemCount: stats.length,
      itemBuilder: (context, i) => _StatCard(stat: stats[i]),
    );
  }
}

class _StatCard extends StatefulWidget {
  final Map<String, dynamic> stat;
  const _StatCard({required this.stat});

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.stat['color'] as int);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hovered ? color.withValues(alpha: 0.4) : AppColors.border),
          boxShadow: _hovered
              ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 16, offset: const Offset(0, 6))]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(widget.stat['emoji'] as String, style: const TextStyle(fontSize: 20))),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.stat['value'] as String, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                Text(widget.stat['label'] as String, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Upcoming Appointments ────────────────────────────────────────────────────

class _UpcomingAppointmentsCard extends StatelessWidget {
  final List<Map<String, dynamic>> appointments;
  final bool loading;

  const _UpcomingAppointmentsCard({required this.appointments, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Upcoming Appointments', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const Spacer(),
            if (appointments.isNotEmpty)
              TextButton(
                onPressed: () {},
                child: Text('View All', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 14),
          if (loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),)
          else if (appointments.isEmpty)
            const _EmptyState(
              emoji: '📅',
              title: 'No upcoming appointments',
              subtitle: 'Book a consultation with a doctor to get started',
            )
          else
            ...appointments.take(3).map((appt) => Column(
              children: [
                _AppointmentItem(appt: appt),
                if (appt != appointments.take(3).last) const Divider(height: 20),
              ],
            )),
        ],
      ),
    );
  }
}

class _AppointmentItem extends StatelessWidget {
  final Map<String, dynamic> appt;
  const _AppointmentItem({required this.appt});

  @override
  Widget build(BuildContext context) {
    final doctorName = appt['doctorName'] as String? ?? 'Doctor';
    final specialty = appt['doctorSpecialty'] as String? ?? '';
    final date = appt['date'] as String? ?? '';
    final time = appt['time'] as String? ?? '';
    final consultType = appt['consultationType'] as String? ?? 'clinic';
    final status = appt['status'] as String? ?? 'booked';

    return Row(children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(12)),
        child: Center(child: Icon(
          consultType == 'video' ? Icons.videocam_rounded : Icons.local_hospital_rounded,
          color: Colors.white, size: 22,
        )),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(doctorName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        Text(specialty, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.access_time_rounded, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text('$date at $time', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w500)),
        ]),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(status, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.success)),
      ),
    ]);
  }
}

// ─── Empty Health Card ────────────────────────────────────────────────────────

class _EmptyHealthCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Health Summary', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          const _EmptyState(
            emoji: '❤️',
            title: 'No health data yet',
            subtitle: 'Your vitals and health records will appear here after your first consultation',
          ),
        ],
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;

  const _EmptyState({required this.emoji, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 12),
            Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
