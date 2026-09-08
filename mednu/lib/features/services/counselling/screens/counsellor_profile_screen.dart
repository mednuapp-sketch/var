import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/ux_widgets.dart';
import '../../../../core/widgets/service_booking_sheet.dart';
import '../models/counsellor_model.dart';
import '../services/counsellor_service.dart';

const _kPlum     = Color(0xFF633058);
const _kPlumDark = Color(0xFF3D1D36);
const _kPlumBg   = Color(0xFFF3E5F5);

/// Booking a specific counsellor reuses the existing generic
/// [ServiceBookingSheet] — same pattern as
/// [PhysiotherapistProfileScreen]. The only difference from a generic "any
/// available counsellor" request is `extraFields: {'counsellorId': id}`,
/// which the Cloud Function mirror (`_buildSessionDoc`, functions/index.js)
/// honors to skip the unclaimed pool and go straight to this specific
/// counsellor.
class CounsellorProfileScreen extends StatelessWidget {
  final String counsellorId;
  const CounsellorProfileScreen({super.key, required this.counsellorId});

  void _bookNow(BuildContext context, CounsellorModel c) {
    ServiceBookingSheet.show(
      context,
      type: 'counselling',
      serviceName: 'Counselling with ${c.name}',
      themeColor: _kPlum,
      priceLabel: c.hourlyRate > 0 ? '₹${c.hourlyRate.toInt()}/session' : null,
      amount: c.hourlyRate.round(),
      paymentDescription: 'Counselling session with ${c.name}',
      serviceDetails: {
        'title': 'Counselling with ${c.name}',
        'counsellorName': c.name,
        'price': c.hourlyRate,
      },
      extraFields: {'counsellorId': c.id},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: StreamBuilder<CounsellorModel?>(
        stream: CounsellorService.counsellorStream(counsellorId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final c = snap.data;
          if (c == null) {
            return Scaffold(
              backgroundColor: context.appBackground,
              appBar: AppBar(
                leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
              ),
              body: const AppEmptyState(
                icon: Icons.person_off_outlined,
                title: 'Not found',
                message: 'This counsellor is no longer available.',
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 260,
                backgroundColor: _kPlumDark,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [_kPlumDark, _kPlum], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: c.photoUrl.isNotEmpty
                                  ? CachedNetworkImage(imageUrl: c.photoUrl, width: 88, height: 88, fit: BoxFit.cover)
                                  : Container(
                                      width: 88,
                                      height: 88,
                                      color: Colors.white24,
                                      alignment: Alignment.center,
                                      child: Text(
                                        c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 34, fontWeight: FontWeight.w700, color: Colors.white),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 12),
                            Text(c.name,
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
                            if (c.isCurrentlyOnline) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF69F0AE), shape: BoxShape.circle)),
                                  const SizedBox(width: 5),
                                  const Text('Online now',
                                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                                ]),
                              ),
                            ],
                            const SizedBox(height: 4),
                            if (c.specialties.isNotEmpty)
                              Text(c.specialties.join(' · '),
                                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 10),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              RatingBarIndicator(
                                rating: c.rating,
                                itemBuilder: (ctx, _) => const Icon(Icons.star_rounded, color: Color(0xFFF9A825)),
                                itemCount: 5,
                                itemSize: 16,
                                unratedColor: Colors.white30,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                c.totalSessions > 0 ? '${c.rating.toStringAsFixed(1)} (${c.totalSessions} sessions)' : 'New',
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Row(children: [
                      Expanded(child: _StatCard(icon: Icons.work_history_rounded, label: 'Experience', value: '${c.experienceYears} yrs')),
                      const SizedBox(width: 10),
                      Expanded(child: _StatCard(icon: Icons.event_available_rounded, label: 'Sessions', value: '${c.totalSessions}')),
                      const SizedBox(width: 10),
                      Expanded(child: _StatCard(icon: Icons.currency_rupee_rounded, label: 'Rate', value: '₹${c.hourlyRate.toInt()}')),
                    ]),
                    const SizedBox(height: 16),
                    if (c.certifications.isNotEmpty) ...[
                      _SectionCard(
                        title: 'Certifications',
                        icon: Icons.workspace_premium_outlined,
                        children: c.certifications
                            .map((cert) => _Pill(label: cert, icon: Icons.workspace_premium_outlined))
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (c.specialties.isNotEmpty) ...[
                      _SectionCard(
                        title: 'Specialties',
                        icon: Icons.psychology_rounded,
                        children: c.specialties
                            .map((s) => _Pill(label: s, icon: Icons.psychology_rounded))
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _SectionCard(
                      title: 'Session Format',
                      icon: Icons.videocam_rounded,
                      wrap: false,
                      children: const [
                        Text(
                          'Video / chat sessions — fully confidential, from anywhere.',
                          style: AppTextStyles.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () => _bookNow(context, c),
                        icon: const Icon(Icons.calendar_month_rounded, color: Colors.white),
                        label: const Text('Book Now',
                            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPlum,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Icon(icon, color: _kPlum, size: 20),
        const SizedBox(height: 6),
        Text(value, style: AppTextStyles.h4.copyWith(color: _kPlum)),
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool wrap;
  const _SectionCard({required this.title, required this.icon, required this.children, this.wrap = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: _kPlum),
            const SizedBox(width: 8),
            Text(title, style: AppTextStyles.labelMedium),
          ]),
          const SizedBox(height: 12),
          if (wrap) Wrap(spacing: 8, runSpacing: 8, children: children) else ...children,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Pill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: _kPlumBg, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: _kPlum),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: _kPlum, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
