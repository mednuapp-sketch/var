import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  CollectionReference<Map<String, dynamic>> _items(String uid) =>
      FirebaseFirestore.instance
          .collection('patient_notifications')
          .doc(uid)
          .collection('items');

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream(String uid) {
    if (uid.isEmpty) return const Stream.empty();
    return _items(uid)
        .orderBy('deliverAt', descending: true)
        .limit(60)
        .snapshots();
  }

  Future<void> _markAllRead(String uid) async {
    if (uid.isEmpty) return;
    final snap = await _items(uid).where('isRead', isEqualTo: false).get();
    if (snap.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    final isMobile = Responsive.isMobile(context);
    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Notifications',
                  style: GoogleFonts.poppins(
                      fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text('Stay updated on your health',
                  style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
            ]),
          ),
          TextButton(
            onPressed: () => _markAllRead(uid),
            child: Text('Mark all read',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 20),
        Expanded(
          child: uid.isEmpty
              ? _emptyState()
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _stream(uid),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Text('Error loading notifications',
                            style: GoogleFonts.poppins(color: AppColors.error)),
                      );
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) return _emptyState();
                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        return _NotificationCard(
                          docId: doc.id,
                          data: doc.data(),
                        );
                      },
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🔔', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        Text('No notifications',
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text('Your notifications will appear here',
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _NotificationCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  const _NotificationCard({required this.docId, required this.data});

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  bool _hovered = false;

  Future<void> _markRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('patient_notifications')
        .doc(uid)
        .collection('items')
        .doc(widget.docId)
        .update({'isRead': true});
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final title = d['title'] as String? ?? '';
    final body = d['body'] as String? ?? '';
    final typeRaw = d['type'] as String? ?? '';
    final isRead = d['isRead'] as bool? ?? false;
    final deliverAt = d['deliverAt'];
    final timeStr = deliverAt is Timestamp ? _relativeTime(deliverAt.toDate()) : '';

    final typeColor = _colorForType(typeRaw);
    final icon = _iconForType(typeRaw);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: isRead ? null : _markRead,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isRead ? Colors.white : typeColor.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isRead
                    ? AppColors.border
                    : typeColor.withValues(alpha: 0.25)),
            boxShadow: _hovered
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6)],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: typeColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: isRead ? FontWeight.w600 : FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (!isRead)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: typeColor, shape: BoxShape.circle),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: AppColors.textSecondary, height: 1.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(timeStr,
                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textHint)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

Color _colorForType(String type) {
  if (type.contains('appointment')) return AppColors.primary;
  if (type.contains('prescription')) return AppColors.secondary;
  if (type.contains('referral') || type.contains('wallet') || type.contains('bonus')) {
    return AppColors.success;
  }
  if (type.contains('lab') || type.contains('report')) return AppColors.info;
  if (type.contains('ambulance')) return AppColors.error;
  if (type.contains('pregnancy') || type.contains('health')) return AppColors.accent;
  return AppColors.primary;
}

IconData _iconForType(String type) {
  if (type.contains('appointment')) return Icons.calendar_today_rounded;
  if (type.contains('prescription')) return Icons.medication_rounded;
  if (type.contains('referral')) return Icons.card_giftcard_rounded;
  if (type.contains('wallet') || type.contains('bonus')) return Icons.account_balance_wallet_rounded;
  if (type.contains('lab') || type.contains('report')) return Icons.science_rounded;
  if (type.contains('ambulance')) return Icons.emergency_rounded;
  if (type.contains('pregnancy')) return Icons.pregnant_woman_rounded;
  if (type.contains('health')) return Icons.favorite_rounded;
  return Icons.notifications_rounded;
}

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${dt.day} ${months[dt.month]}';
}
