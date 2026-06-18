import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  static const _notifications = [
    {'emoji': '📅', 'title': 'Appointment Reminder', 'body': 'You have an appointment with Dr. Priya Sharma today at 3:00 PM', 'time': '2 hours ago', 'type': 'appointment', 'read': false},
    {'emoji': '💊', 'title': 'Prescription Ready', 'body': 'Dr. Arjun Menon has uploaded your new prescription', 'time': '5 hours ago', 'type': 'prescription', 'read': false},
    {'emoji': '💰', 'title': 'Wallet Credit', 'body': 'Your referral bonus of ₹100 has been credited to your wallet', 'time': 'Yesterday', 'type': 'wallet', 'read': false},
    {'emoji': '🏥', 'title': 'New Hospital Added', 'body': 'Manipal Hospital (Bengaluru) is now available on MedNu', 'time': '2 days ago', 'type': 'general', 'read': true},
    {'emoji': '⭐', 'title': 'Rate Your Experience', 'body': 'How was your consultation with Dr. Ravi Kumar? Share your feedback.', 'time': '3 days ago', 'type': 'feedback', 'read': true},
    {'emoji': '🎉', 'title': 'Health Milestone', 'body': 'You have completed 30 days of health tracking. Keep it up!', 'time': '5 days ago', 'type': 'health', 'read': true},
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final unread = _notifications.where((n) => n['read'] == false).length;

    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Notifications', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(width: 10),
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(20)),
                  child: Text('$unread new', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
            ]),
            Text('Stay updated on your health', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
          ])),
          TextButton(
            onPressed: () {},
            child: Text('Mark all read', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 20),
        Expanded(
          child: ListView.separated(
            itemCount: _notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _NotificationCard(data: _notifications[i]),
          ),
        ),
      ]),
    );
  }
}

class _NotificationCard extends StatefulWidget {
  final Map<String, dynamic> data;
  const _NotificationCard({required this.data});

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final unread = d['read'] == false;
    final typeColor = {
      'appointment': AppColors.primary,
      'prescription': AppColors.secondary,
      'wallet': AppColors.success,
      'general': AppColors.info,
      'feedback': const Color(0xFFFFA726),
      'health': AppColors.accent,
    }[d['type']] ?? AppColors.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: unread ? typeColor.withOpacity(0.04) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: unread ? typeColor.withOpacity(0.25) : AppColors.border),
          boxShadow: _hovered
              ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)]
              : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6)],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(d['emoji'] as String, style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  d['title'] as String,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (unread)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: typeColor, shape: BoxShape.circle),
                ),
            ]),
            const SizedBox(height: 4),
            Text(
              d['body'] as String,
              style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textSecondary, height: 1.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(d['time'] as String, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textHint)),
          ])),
        ]),
      ),
    );
  }
}
