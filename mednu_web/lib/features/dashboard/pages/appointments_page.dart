import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/gradient_button.dart';

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({super.key});

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> with SingleTickerProviderStateMixin {
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

  static const _upcoming = [
    {'doctor': 'Dr. Priya Sharma', 'specialty': 'Cardiologist', 'date': 'June 12, 2026', 'time': '3:00 PM', 'type': 'In-person', 'fee': '₹800', 'emoji': '👩‍⚕️', 'status': 'Confirmed'},
    {'doctor': 'Dr. Ravi Kumar', 'specialty': 'Orthopedic', 'date': 'June 13, 2026', 'time': '11:00 AM', 'type': 'In-person', 'fee': '₹900', 'emoji': '👨‍⚕️', 'status': 'Scheduled'},
  ];

  static const _completed = [
    {'doctor': 'Dr. Arjun Menon', 'specialty': 'Pediatrician', 'date': 'June 1, 2026', 'time': '10:00 AM', 'type': 'Video', 'fee': '₹600', 'emoji': '👨‍⚕️', 'status': 'Completed'},
    {'doctor': 'Dr. Meena Rao', 'specialty': 'Gynecologist', 'date': 'May 20, 2026', 'time': '2:00 PM', 'type': 'In-person', 'fee': '₹750', 'emoji': '👩‍⚕️', 'status': 'Completed'},
  ];

  static const _cancelled = [
    {'doctor': 'Dr. Vikram Singh', 'specialty': 'Neurologist', 'date': 'May 15, 2026', 'time': '4:00 PM', 'type': 'In-person', 'fee': '₹1200', 'emoji': '👨‍⚕️', 'status': 'Cancelled'},
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('My Appointments', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text('Track all your doctor visits', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
            ])),
            GradientButton(label: 'Book New', width: 130, height: 40, icon: Icons.add_rounded, fontSize: 13),
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
            child: TabBarView(
              controller: _tab,
              children: [
                _AppointmentList(items: _upcoming, type: 'upcoming'),
                _AppointmentList(items: _completed, type: 'completed'),
                _AppointmentList(items: _cancelled, type: 'cancelled'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentList extends StatelessWidget {
  final List<Map<String, String>> items;
  final String type;
  const _AppointmentList({required this.items, required this.type});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('📅', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        Text('No appointments', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text('Your $type appointments will appear here', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
      ]));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, i) => _AppointmentCard(data: items[i], type: type),
    );
  }
}

class _AppointmentCard extends StatefulWidget {
  final Map<String, String> data;
  final String type;
  const _AppointmentCard({required this.data, required this.type});

  @override
  State<_AppointmentCard> createState() => _AppointmentCardState();
}

class _AppointmentCardState extends State<_AppointmentCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final d = widget.data;
    final isVideo = d['type'] == 'Video';
    final statusColor = {
      'Confirmed': AppColors.success,
      'Scheduled': AppColors.info,
      'Completed': AppColors.accent,
      'Cancelled': AppColors.error,
    }[d['status']!] ?? AppColors.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hovered ? AppColors.primary.withOpacity(0.3) : AppColors.border),
          boxShadow: _hovered
              ? [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 16, offset: const Offset(0, 6))]
              : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text(d['emoji']!, style: const TextStyle(fontSize: 26))),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d['doctor']!, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(d['specialty']!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(d['status']!, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: Wrap(spacing: 24, runSpacing: 10, children: [
              _InfoItem(icon: Icons.calendar_today_rounded, label: d['date']!),
              _InfoItem(icon: Icons.access_time_rounded, label: d['time']!),
              _InfoItem(icon: isVideo ? Icons.videocam_rounded : Icons.local_hospital_outlined, label: d['type']!),
              _InfoItem(icon: Icons.currency_rupee_rounded, label: d['fee']!),
            ]),
          ),
          if (widget.type == 'upcoming') ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(color: AppColors.error.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                child: Text('Cancel', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(child: GradientButton(label: 'View Details', height: 44, fontSize: 13)),
            ]),
          ],
          if (widget.type == 'completed') ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                child: Text('View Prescription', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(child: GradientButton(label: 'Book Again', height: 44, fontSize: 13)),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: AppColors.primary),
      const SizedBox(width: 5),
      Text(label, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
    ]);
  }
}
