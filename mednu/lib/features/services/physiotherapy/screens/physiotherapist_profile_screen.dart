import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/router/app_router.dart';
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
///
/// A physiotherapist prices online/home/in-clinic sessions separately (see
/// PhysioProfileService in mednu_doctor) — [_ConsultModeSelector] lets the
/// patient pick which one before the price/booking sheet reflects it.
/// Booking itself still goes through the same generic address-collecting
/// sheet regardless of mode (an actual in-app video call for the 'online'
/// mode is a separate, not-yet-built piece — see PENDING.md).
enum _ConsultMode { online, home, clinic }

extension on _ConsultMode {
  String get label => switch (this) {
        _ConsultMode.online => 'Online Video',
        _ConsultMode.home => 'Home Visit',
        _ConsultMode.clinic => 'In-Clinic',
      };
  IconData get icon => switch (this) {
        _ConsultMode.online => Icons.videocam_rounded,
        _ConsultMode.home => Icons.home_rounded,
        _ConsultMode.clinic => Icons.local_hospital_rounded,
      };
  String get firestoreValue => switch (this) {
        _ConsultMode.online => 'online',
        _ConsultMode.home => 'home',
        _ConsultMode.clinic => 'clinic',
      };
}

class PhysiotherapistProfileScreen extends StatefulWidget {
  final String physiotherapistId;
  const PhysiotherapistProfileScreen({super.key, required this.physiotherapistId});

  @override
  State<PhysiotherapistProfileScreen> createState() => _PhysiotherapistProfileScreenState();
}

class _PhysiotherapistProfileScreenState extends State<PhysiotherapistProfileScreen> {
  _ConsultMode? _selectedMode;
  bool _connecting = false;

  List<_ConsultMode> _offeredModes(PhysiotherapistModel p) => [
        if (p.onlineRate > 0) _ConsultMode.online,
        if (p.homeRate > 0) _ConsultMode.home,
        if (p.clinicRate > 0) _ConsultMode.clinic,
      ];

  num _rateFor(PhysiotherapistModel p, _ConsultMode mode) => switch (mode) {
        _ConsultMode.online => p.onlineRate,
        _ConsultMode.home => p.homeRate,
        _ConsultMode.clinic => p.clinicRate,
      };

  /// True only when Video is the picked mode (or the only/default one) AND
  /// this physiotherapist is actually online right now — otherwise "Book
  /// Now" still applies (a scheduled request the physio starts later from
  /// their own session list, same as before this feature).
  bool _canConnectNow(PhysiotherapistModel p) {
    final modes = _offeredModes(p);
    if (modes.isEmpty) return false;
    final mode = _selectedMode ?? modes.first;
    return mode == _ConsultMode.online && p.isCurrentlyOnline;
  }

  void _bookNow(BuildContext context, PhysiotherapistModel p) {
    final modes = _offeredModes(p);
    // A profile that hasn't been updated to per-mode pricing yet (still
    // only carries the legacy flat hourlyRate) keeps working exactly as
    // before rather than showing an empty mode selector.
    final rate = modes.isEmpty ? p.hourlyRate : _rateFor(p, _selectedMode ?? modes.first);
    final modeLabel = modes.isEmpty ? null : (_selectedMode ?? modes.first).label;
    ServiceBookingSheet.show(
      context,
      type: 'physiotherapy',
      serviceName: 'Physiotherapy with ${p.name}',
      themeColor: _kTeal,
      priceLabel: rate > 0 ? '₹${rate.toInt()}/session${modeLabel != null ? ' · $modeLabel' : ''}' : null,
      amount: rate.round(),
      paymentDescription: 'Physiotherapy session with ${p.name}',
      serviceDetails: {
        'title': 'Physiotherapy with ${p.name}',
        'physiotherapistName': p.name,
        'price': rate,
        if (modeLabel != null) 'consultationType': modeLabel,
      },
      extraFields: {
        'physiotherapistId': p.id,
        if (modes.isNotEmpty) 'consultMode': (_selectedMode ?? modes.first).firestoreValue,
      },
    );
  }

  /// Instant video call to a physiotherapist who's online right now — the
  /// same `consultations`-doc pipeline doctors' Quick Connect already uses
  /// (payment gate -> consultations/{id} created with status 'pending',
  /// callerType 'patient', doctorId holding the physio's own uid -> patient
  /// lands on OutgoingCallScreen). The physiotherapist app's existing global
  /// call listener (mednu_doctor/lib/main.dart) already keys off `doctorId
  /// == currentUid` with no role check, so it picks this up with zero
  /// changes there beyond IncomingRequestScreen routing to
  /// ProviderVideoCallScreen for a non-doctor `callerType` (see that file).
  Future<void> _connectNow(BuildContext context, PhysiotherapistModel p) async {
    if (_connecting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _connecting = true);

    var patientName = user.displayName ?? user.phoneNumber ?? 'Patient';
    String patientFcmToken = '';
    String patientPhotoUrl = '';
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final name = snap.data()?['name'] as String?;
      if (name != null && name.trim().isNotEmpty) patientName = name;
      patientFcmToken = snap.data()?['fcmToken'] as String? ?? '';
      patientPhotoUrl = snap.data()?['photoUrl'] as String? ?? '';
    } catch (_) {}

    if (!context.mounted) return;
    Map<String, dynamic>? result;
    try {
      result = await context.push<Map<String, dynamic>>(
        AppRoutes.payment,
        extra: {
          'amount': p.onlineRate.round().toString(),
          'description': 'Video consultation with ${p.name}',
          'serviceType': 'video_consultation',
          'bookingCollection': 'consultations',
          'bookingData': {
            'status': 'pending',
            'callerType': 'patient',
            // Disambiguates the provider's actual role for the receiving
            // app's IncomingRequestScreen, since `callerType` here is the
            // patient's own type, not the physio's — see that screen's
            // `_callerType` derivation for the other end of this contract.
            'providerRole': 'physiotherapist',
            'patientName': patientName,
            'patientFcmToken': patientFcmToken,
            'patientPhotoUrl': patientPhotoUrl,
            'doctorId': p.id,
            'doctorName': p.name,
            'doctorSpecialty': 'Physiotherapist',
            'doctorPhotoUrl': p.photoUrl,
            'consultationType': 'Video',
            'fee': p.onlineRate.round(),
            'chiefComplaint': '',
          },
        },
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not connect: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      if (mounted) setState(() => _connecting = false);
      return;
    }

    final consultationId = result?['bookingId'] as String?;
    if (mounted) setState(() => _connecting = false);
    if (consultationId == null || !context.mounted) return;

    context.push(AppRoutes.outgoingCall, extra: {
      'consultationId': consultationId,
      'doctorName': p.name,
      'doctorSpecialty': 'Physiotherapist',
      'doctorPhotoUrl': p.photoUrl,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: StreamBuilder<PhysiotherapistModel?>(
        stream: PhysiotherapistService.physiotherapistStream(widget.physiotherapistId),
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
                            if (p.isCurrentlyOnline) ...[
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
                      Expanded(child: _StatCard(icon: Icons.currency_rupee_rounded, label: 'From', value: '₹${p.hourlyRate.toInt()}')),
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
                    const SizedBox(height: 16),
                    if (_offeredModes(p).isNotEmpty) ...[
                      _SectionCard(
                        title: 'Choose Consultation Type',
                        icon: Icons.medical_information_outlined,
                        wrap: false,
                        children: [
                          for (final mode in _offeredModes(p)) ...[
                            _ModeOption(
                              mode: mode,
                              rate: _rateFor(p, mode),
                              selected: (_selectedMode ?? _offeredModes(p).first) == mode,
                              onTap: () => setState(() => _selectedMode = mode),
                            ),
                            if (mode != _offeredModes(p).last) const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (_canConnectNow(p)) ...[
                      Row(
                        children: [
                          const Icon(Icons.circle, size: 8, color: Color(0xFF43A047)),
                          const SizedBox(width: 6),
                          Text("They're online now — connect instantly instead of waiting for a callback.",
                              style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _connecting
                            ? null
                            : () => _canConnectNow(p) ? _connectNow(context, p) : _bookNow(context, p),
                        icon: _connecting
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(_canConnectNow(p) ? Icons.videocam_rounded : Icons.calendar_month_rounded, color: Colors.white),
                        label: Text(_canConnectNow(p) ? 'Connect Now' : 'Book Now',
                            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
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

class _ModeOption extends StatelessWidget {
  final _ConsultMode mode;
  final num rate;
  final bool selected;
  final VoidCallback onTap;
  const _ModeOption({
    required this.mode,
    required this.rate,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _kTealBg : context.appSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _kTeal : context.appBorder, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(mode.icon, size: 20, color: selected ? _kTeal : context.appTextHint),
            const SizedBox(width: 12),
            Expanded(
              child: Text(mode.label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: selected ? _kTealDark : context.appTextPrimary,
                  )),
            ),
            Text('₹${rate.toInt()}',
                style: AppTextStyles.labelLarge.copyWith(color: selected ? _kTeal : context.appTextSecondary)),
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: selected ? _kTeal : context.appTextHint,
            ),
          ],
        ),
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
