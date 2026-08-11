import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({super.key});

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _stream {
    if (_uid.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('appointments')
        .where('patientId', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('My Appointments',
                    style: GoogleFonts.poppins(
                        fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text('Track all your doctor visits',
                    style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
              ]),
            ),
          ]),
          const SizedBox(height: 24),
          TabBar(
            controller: _tab,
            isScrollable: isMobile,
            tabs: const [Tab(text: 'Upcoming'), Tab(text: 'Completed'), Tab(text: 'Cancelled')],
            labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicator: UnderlineTabIndicator(
              borderSide: const BorderSide(color: AppColors.primary, width: 2.5),
              borderRadius: BorderRadius.circular(2),
            ),
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: AppColors.border,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _uid.isEmpty
                ? const _EmptyState(type: 'upcoming')
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _stream,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Text('Error loading appointments',
                              style: GoogleFonts.poppins(color: AppColors.error)),
                        );
                      }
                      final docs = snap.data?.docs ?? [];
                      final now = DateTime.now();

                      bool isPast(Map<String, dynamic> d) {
                        final dateStr = d['date'] as String? ?? '';
                        final parsed = _parseDate(dateStr);
                        if (parsed == null) return false;
                        return parsed.isBefore(DateTime(now.year, now.month, now.day));
                      }

                      final upcoming = docs
                          .where((d) => d['status'] == 'booked' && !isPast(d.data()))
                          .map((d) => d.data())
                          .toList();
                      final completed = docs
                          .where((d) =>
                              d['status'] == 'completed' ||
                              (d['status'] == 'booked' && isPast(d.data())))
                          .map((d) => d.data())
                          .toList();
                      final cancelled = docs
                          .where((d) => d['status'] == 'cancelled')
                          .map((d) => d.data())
                          .toList();

                      return TabBarView(
                        controller: _tab,
                        children: [
                          _AppointmentList(items: upcoming, type: 'upcoming'),
                          _AppointmentList(items: completed, type: 'completed'),
                          _AppointmentList(items: cancelled, type: 'cancelled'),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

DateTime? _parseDate(String raw) {
  if (raw.isEmpty) return null;
  try {
    // try ISO yyyy-MM-dd
    final parts = raw.split('-');
    if (parts.length == 3) return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  } catch (_) {}
  try {
    // try "dd/MM/yyyy"
    final parts = raw.split('/');
    if (parts.length == 3) return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
  } catch (_) {}
  return null;
}

String _formatDate(String raw) {
  final d = _parseDate(raw);
  if (d == null) return raw;
  const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month]} ${d.year}';
}

class _AppointmentList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String type;
  const _AppointmentList({required this.items, required this.type});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _EmptyState(type: type);
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, i) => _AppointmentCard(data: items[i], type: type),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String type;
  const _EmptyState({required this.type});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('📅', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        Text('No appointments',
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text('Your $type appointments will appear here',
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _AppointmentCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String type;
  const _AppointmentCard({required this.data, required this.type});

  @override
  State<_AppointmentCard> createState() => _AppointmentCardState();
}

class _AppointmentCardState extends State<_AppointmentCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;

    final doctorName = d['doctorName'] as String? ?? 'Doctor';
    final specialty = d['doctorSpecialty'] as String? ?? '';
    final date = _formatDate(d['date'] as String? ?? '');
    final time = d['time'] as String? ?? '';
    final consultType = d['consultationType'] as String? ?? 'In-Person';
    final fee = d['fee'];
    final feeStr = fee != null ? '₹$fee' : '';
    final statusRaw = d['status'] as String? ?? 'booked';
    final status = statusRaw == 'booked' ? 'Confirmed' : _capitalize(statusRaw);
    final isVideo = consultType.toLowerCase().contains('video');

    final statusColor = {
      'Confirmed': AppColors.success,
      'booked': AppColors.success,
      'completed': AppColors.accent,
      'Completed': AppColors.accent,
      'cancelled': AppColors.error,
      'Cancelled': AppColors.error,
    }[status] ?? AppColors.info;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: _hovered
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : AppColors.border),
          boxShadow: _hovered
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 6))]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(14)),
              child: Center(
                child: Text(
                  doctorName.isNotEmpty ? doctorName[0].toUpperCase() : 'D',
                  style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(doctorName,
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if (specialty.isNotEmpty)
                  Text(specialty,
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(status,
                  style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: Wrap(spacing: 24, runSpacing: 10, children: [
              if (date.isNotEmpty) _InfoItem(icon: Icons.calendar_today_rounded, label: date),
              if (time.isNotEmpty) _InfoItem(icon: Icons.access_time_rounded, label: time),
              _InfoItem(
                  icon: isVideo ? Icons.videocam_rounded : Icons.local_hospital_outlined,
                  label: isVideo ? 'Video' : 'In-Person'),
              if (feeStr.isNotEmpty) _InfoItem(icon: Icons.currency_rupee_rounded, label: feeStr),
            ]),
          ),
        ]),
      ),
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: AppColors.primary),
      const SizedBox(width: 5),
      Text(label,
          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
    ]);
  }
}
