import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/launch_utils.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/utils/responsive.dart';

class _Ad {
  final String id;
  final String imageUrl;
  final String title;
  final String linkUrl;
  final DateTime? start;
  final DateTime? end;
  final DateTime? created;

  _Ad(DocumentSnapshot<Map<String, dynamic>> d)
      : id = d.id,
        imageUrl = (d.data()?['imageUrl'] as String?) ?? '',
        title = (d.data()?['title'] as String?) ?? '',
        linkUrl = (d.data()?['linkUrl'] as String?) ?? '',
        start = (d.data()?['startDate'] as Timestamp?)?.toDate(),
        end = (d.data()?['endDate'] as Timestamp?)?.toDate(),
        created = (d.data()?['createdAt'] as Timestamp?)?.toDate();

  bool liveAt(DateTime now) =>
      imageUrl.isNotEmpty && (start == null || !now.isBefore(start!)) && (end == null || now.isBefore(end!));
}

/// Ad slot in the middle of the landing page, managed from the MedNU admin
/// panel ("Web Ads"). Renders nothing — no gap at all — when no ad is live.
class AdSection extends StatefulWidget {
  const AdSection({super.key});

  @override
  State<AdSection> createState() => _AdSectionState();
}

class _AdSectionState extends State<AdSection> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = FirebaseFirestore.instance
      .collection('web_ads')
      .where('isEnabled', isEqualTo: true)
      .snapshots();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Re-evaluate schedule windows so an ad appears/expires without a reload.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final now = DateTime.now();
        final ads = snap.data!.docs.map(_Ad.new).where((a) => a.liveAt(now)).toList()
          ..sort((a, b) => (b.created ?? DateTime(0)).compareTo(a.created ?? DateTime(0)));
        if (ads.isEmpty) return const SizedBox.shrink();

        final isMobile = Responsive.isMobile(context);
        return Container(
          color: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: Responsive.horizontalPadding(context),
            vertical: isMobile ? 28 : 44,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: Responsive.maxContentWidth(context)),
              child: Column(children: [
                for (int i = 0; i < ads.length; i++) ...[
                  _AdCard(ad: ads[i]),
                  if (i < ads.length - 1) SizedBox(height: isMobile ? 16 : 24),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _AdCard extends StatefulWidget {
  final _Ad ad;
  const _AdCard({required this.ad});

  @override
  State<_AdCard> createState() => _AdCardState();
}

class _AdCardState extends State<_AdCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    final clickable = ad.linkUrl.isNotEmpty;
    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: clickable ? () => openUrl(ad.linkUrl) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          transform: Matrix4.translationValues(0, clickable && _hovered ? -4 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: _hovered ? 0.28 : 0.16),
                blurRadius: _hovered ? 36 : 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(children: [
              // Fixed 16:5 frame (recommended upload size 1600 x 500): the browser-native
              // image fallback used for CORS-less hosts can't size itself from the image.
              LayoutBuilder(builder: (context, c) {
                final h = c.maxWidth * 5 / 16;
                return NetImage(
                  url: ad.imageUrl,
                  width: c.maxWidth,
                  height: h < 120 ? 120 : h,
                  fit: BoxFit.cover,
                  placeholder: Container(height: h, color: AppColors.surfaceVariant),
                  fallback: Container(height: h, color: AppColors.surfaceVariant),
                );
              }),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(8)),
                  child: Text('Ad', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
