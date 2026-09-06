import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/ux_widgets.dart';
import '../../../../core/widgets/service_booking_sheet.dart';
import '../models/physiotherapist_model.dart';
import '../services/physiotherapist_service.dart';

const _kTeal     = Color(0xFF00838F);
const _kTealDark = Color(0xFF006064);
const _kTealBg   = Color(0xFFE0F7FA);

/// Booking a specific physiotherapist reuses the existing generic
/// [ServiceBookingSheet] (the same one the flat physiotherapy service
/// catalog and every other on-demand service module already use) rather
/// than a bespoke slot-picker screen — physio sessions don't have discrete
/// bookable slots today (`service_requests`/`physio_sessions` just carry
/// free-text `preferredDate`/`preferredTime`). The only difference from a
/// generic "any available physiotherapist" request is `extraFields:
/// {'physiotherapistId': id}`, which the Cloud Function mirror
/// (`_buildSessionDoc`, functions/index.js) honors to skip the unclaimed
/// pool and go straight to this specific provider.
class PhysiotherapistProfileScreen extends StatelessWidget {
  final String physiotherapistId;
  const PhysiotherapistProfileScreen({super.key, required this.physiotherapistId});

  void _bookNow(BuildContext context, PhysiotherapistModel p) {
    ServiceBookingSheet.show(
      context,
      type: 'physiotherapy',
      serviceName: 'Physiotherapy with ${p.name}',
      themeColor: _kTeal,
      priceLabel: p.hourlyRate > 0 ? '₹${p.hourlyRate.toInt()}/session' : null,
      amount: p.hourlyRate.round(),
      paymentDescription: 'Physiotherapy session with ${p.name}',
      serviceDetails: {
        'title': 'Physiotherapy with ${p.name}',
        'physiotherapistName': p.name,
        'price': p.hourlyRate,
      },
      extraFields: {'physiotherapistId': p.id},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: StreamBuilder<PhysiotherapistModel?>(
        stream: PhysiotherapistService.physiotherapistStream(physiotherapistId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = snap.data;
          if (p == null) {
            return Scaffold(
              backgroundColor: context.appBackground,
              appBar: AppBar(
                leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
              ),
              body: const AppEmptyState(
                icon: Icons.person_off_outlined,
                title: 'Not found',
                message: 'This physiotherapist is no longer available.',
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 260,
                backgroundColor: _kTealDark,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [_kTealDark, _kTeal], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: p.photoUrl.isNotEmpty
                                  ? CachedNetworkImage(imageUrl: p.photoUrl, width: 88, height: 88, fit: BoxFit.cover)
                                  : Container(
                                      width: 88,
                                      height: 88,
                                      color: Colors.white24,
                                      alignment: Alignment.center,
                                      child: Text(
                                        p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
                                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 34, fontWeight: FontWeight.w700, color: Colors.white),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 12),
                            Text(p.name,
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
                            const SizedBox(height: 4),
                            if (p.specialties.isNotEmpty)
                              Text(p.specialties.join(' · '),
                                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 10),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              RatingBarIndicator(
                                rating: p.rating,
                                itemBuilder: (ctx, _) => const Icon(Icons.star_rounded, color: Color(0xFFF9A825)),
                                itemCount: 5,
                                itemSize: 16,
                                unratedColor: Colors.white30,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                p.totalSessions > 0 ? '${p.rating.toStringAsFixed(1)} (${p.totalSessions} sessions)' : 'New',
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
                      Expanded(child: _StatCard(icon: Icons.work_history_rounded, label: 'Experience', value: '${p.experienceYears} yrs')),
                      const SizedBox(width: 10),
                      Expanded(child: _StatCard(icon: Icons.event_available_rounded, label: 'Sessions', value: '${p.totalSessions}')),
                      const SizedBox(width: 10),
                      Expanded(child: _StatCard(icon: Icons.currency_rupee_rounded, label: 'Rate', value: '₹${p.hourlyRate.toInt()}')),
                    ]),
                    const SizedBox(height: 16),
                    if (p.certifications.isNotEmpty) ...[
                      _SectionCard(
                        title: 'Certifications',
                        icon: Icons.workspace_premium_outlined,
                        children: p.certifications
                            .map((c) => _Pill(label: c, icon: Icons.workspace_premium_outlined))
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (p.specialties.isNotEmpty) ...[
                      _SectionCard(
                        title: 'Specialties',
                        icon: Icons.accessibility_new_rounded,
                        children: p.specialties
                            .map((s) => _Pill(label: s, icon: Icons.accessibility_new_rounded))
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _SectionCard(
                      title: 'Languages Spoken',
                      icon: Icons.translate_rounded,
                      children: (p.languages.isEmpty ? const ['English'] : p.languages)
                          .map((l) => _Pill(label: l, icon: Icons.translate_rounded))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Service Area',
                      icon: Icons.location_on_rounded,
                      wrap: false,
                      children: [
                        Text(
                          p.city.isNotEmpty ? p.city : 'Home visits — location confirmed at booking',
                          style: AppTextStyles.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () => _bookNow(context, p),
                        icon: const Icon(Icons.calendar_month_rounded, color: Colors.white),
                        label: const Text('Book Now',
                            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kTeal,
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
        Icon(icon, color: _kTeal, size: 20),
        const SizedBox(height: 6),
        Text(value, style: AppTextStyles.h4.copyWith(color: _kTeal)),
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
            Icon(icon, size: 16, color: _kTeal),
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
      decoration: BoxDecoration(color: _kTealBg, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: _kTeal),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: _kTeal, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
