import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/add_to_cart_button.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../cart/providers/cart_provider.dart';
import 'models/physiotherapist_model.dart';
import 'services/physiotherapist_service.dart';

class PhysioScreen extends ConsumerWidget {
  const PhysioScreen({super.key});

  static const _themeColor = Color(0xFF1565C0);

  static const _icons = [
    Icons.video_call_rounded, Icons.home_rounded, Icons.local_hospital_rounded,
    Icons.fitness_center_rounded, Icons.directions_walk_rounded, Icons.accessibility_new_rounded,
    Icons.sports_gymnastics_rounded, Icons.healing_rounded, Icons.medical_services_rounded,
  ];

  IconData _iconAt(int i) => _icons[i % _icons.length];

  String _priceLabel(Map<String, dynamic> d) {
    final price = (d['price'] as num?)?.toInt() ?? 0;
    final unit = d['priceUnit'] as String? ?? 'per_session';
    final label = switch (unit) {
      'per_hour'    => '/hr',
      'per_day'     => '/day',
      'per_month'   => '/month',
      'onwards'     => ' onwards',
      _             => '/session',
    };
    return '₹$price$label';
  }

  // Sentinel for "Any available physiotherapist" — distinct from the `null`
  // showModalBottomSheet returns when the sheet is dismissed without a
  // choice (back button / tap outside), so the two cases can't be confused:
  // "any" should still add to cart, "dismissed" should abort the add.
  static const Object _anyPhysio = Object();

  /// "Talk to a Physiotherapist Now" — finds whoever's online right now
  /// (via the same `isCurrentlyOnline` staleness check the list screen
  /// sorts by) and jumps straight to their profile's "Book Now", which
  /// pre-assigns them via `extraFields: {'physiotherapistId': id}` — the
  /// existing Cloud Function mirror (`_buildSessionDoc`) marks a
  /// pre-assigned booking already 'accepted' immediately, skipping the
  /// unclaimed pool. If nobody is online, falls back to the browsable list
  /// (already online-sorted) rather than blocking the patient outright.
  Future<void> _talkToPhysioNow(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    List<PhysiotherapistModel> list;
    try {
      list = await PhysiotherapistService.physiotherapistsStream().first;
    } catch (_) {
      list = const [];
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog

    final online = list.where((p) => p.isCurrentlyOnline).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    if (!context.mounted) return;
    if (online.isNotEmpty) {
      context.push(AppRoutes.physioTherapistProfile.replaceFirst(':id', online.first.id));
    } else {
      FeedbackService.showError(
        context,
        'No physiotherapist is online right now — showing everyone you can book.',
      );
      context.push(AppRoutes.physioTherapistList);
    }
  }

  Future<void> _book(BuildContext ctx, WidgetRef ref, Map<String, dynamic> svc) async {
    // Optional — lets the patient tie this booking to a specific
    // physiotherapist (same catalog, same fee) instead of an unassigned
    // request. Skippable via "Any available physiotherapist".
    final chosen = await _pickPhysiotherapist(ctx);
    if (chosen == null) return; // dismissed without deciding — abort the add

    if (!ctx.mounted) return;
    ref.read(cartProvider.notifier).addItem(
          type: 'physiotherapy',
          serviceName: svc['name'] as String,
          themeColor: _themeColor,
          unitAmount: (svc['price'] as num?)?.toInt() ?? 0,
          serviceDetails: {
            'sessionType': svc['name'],
            'title':       svc['name'],
            'price':       svc['price'],
            if (chosen is PhysiotherapistModel) ...{
              'physiotherapistId':   chosen.id,
              'physiotherapistName': chosen.name,
            },
          },
        );
    FeedbackService.showSuccess(ctx, '${svc['name']} added to cart');
  }

  /// Returns a [PhysiotherapistModel] if the patient picked one, [_anyPhysio]
  /// if they chose "Any available physiotherapist", or `null` if they
  /// dismissed the sheet without deciding (caller should abort the add).
  Future<Object?> _pickPhysiotherapist(BuildContext ctx) async {
    final result = await showModalBottomSheet<Object?>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Choose a physiotherapist (optional)', style: AppTextStyles.h4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: GestureDetector(
                  onTap: () => Navigator.pop(sheetCtx, _anyPhysio),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _themeColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.shuffle_rounded, color: _themeColor, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Any available physiotherapist',
                            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13, color: _themeColor)),
                      ),
                      Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
                    ]),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<PhysiotherapistModel>>(
                  stream: PhysiotherapistService.physiotherapistsStream(),
                  builder: (context, snap) {
                    final list = snap.data ?? const [];
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (list.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No physiotherapists available right now', style: AppTextStyles.bodySmall),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[100]),
                      itemBuilder: (context, i) {
                        final p = list[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: _themeColor.withValues(alpha: 0.12),
                            child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P', style: const TextStyle(color: _themeColor)),
                          ),
                          title: Text(p.name, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: Text(
                            p.specialties.isNotEmpty ? p.specialties.join(' · ') : p.city,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(sheetCtx, p),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF0D47A1),
            expandedHeight: AppSpacing.headerHeight(context),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
            ),
            actions: const [CartBadgeAction()],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF42A5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: Padding(
                            padding: AppSpacing.headerPadding(context),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fitness_center_rounded, color: Colors.white, size: AppSpacing.headerIconSize(context)),
                                SizedBox(height: AppSpacing.headerIconGap(context)),
                                const Text('Physiotherapy', style: AppTextStyles.onPrimaryH2),
                                const Text('Certified physiotherapists • Online & Home', style: AppTextStyles.onPrimaryBody),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: AppSpacing.page(context),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Talk to a Physiotherapist Now ───────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.sectionGap(context)),
                    child: ElevatedButton.icon(
                      onPressed: () => _talkToPhysioNow(context),
                      icon: const Icon(Icons.bolt_rounded, size: 20),
                      label: const Text('Talk to a Physiotherapist Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _themeColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15),
                        elevation: 3,
                        shadowColor: _themeColor.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
                // Find a specific physiotherapist banner
                Container(
                  margin: EdgeInsets.only(bottom: AppSpacing.sectionGap(context)),
                  child: GestureDetector(
                    onTap: () => context.push(AppRoutes.physioTherapistList),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFE0F7FA), Color(0xFFE3F2FD)]),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF00838F).withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00838F).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_search_rounded, color: Color(0xFF00838F), size: 26),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Find a Physiotherapist', style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700,
                              color: Color(0xFF00838F))),
                          Text('Browse by language, city & specialty',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: context.appTextSecondary)),
                        ])),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF00838F)),
                      ]),
                    ),
                  ),
                ),
                // Progress info banner
                Container(
                  margin: EdgeInsets.only(bottom: AppSpacing.sectionGap(context)),
                  padding: EdgeInsets.all(R.p(context, 14)),
                  decoration: BoxDecoration(
                    color: _themeColor.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(R.r(context, 14)),
                    border: Border.all(color: _themeColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, color: const Color(0xFF1565C0), size: R.w(context, 18)),
                      SizedBox(width: R.p(context, 10)),
                      Expanded(
                        child: Text(
                          'Physiotherapy works best over multiple sessions. Most patients see improvement in 4–6 sessions.',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: R.sp(context, 12),
                              color: const Color(0xFF1565C0), height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const Text('Choose Service', style: AppTextStyles.h4),
                SizedBox(height: R.h(context, 12)),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('services')
                      .where('type', isEqualTo: 'physiotherapy')
                      .where('isEnabled', isEqualTo: true)
                      .snapshots(),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return _buildSkeleton();
                    }
                    if (snap.hasError) {
                      return _buildError();
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return _buildEmpty();
                    }
                    final services = docs.asMap().entries.map((e) {
                      final d = e.value.data() as Map<String, dynamic>;
                      return {
                        'id':          e.value.id,
                        'name':        (d['name'] as String? ?? '').trim(),
                        'price':       (d['price'] as num?)?.toInt() ?? 0,
                        'priceLabel':  _priceLabel(d),
                        'description': (d['description'] as String? ?? '').trim(),
                        'duration':    (d['duration'] as String? ?? '').trim(),
                        'icon':        _iconAt(e.key),
                      };
                    }).toList();

                    return Column(children: services.map((svc) {
                      final icon = svc['icon'] as IconData;
                      final desc = svc['description'] as String;
                      final duration = svc['duration'] as String;
                      final subtitle = desc.isNotEmpty ? desc : (duration.isNotEmpty ? duration : '');
                      return Container(
                        margin: EdgeInsets.only(bottom: R.h(context, 12)),
                        padding: EdgeInsets.all(R.p(context, 16)),
                        decoration: BoxDecoration(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(R.r(context, 16)),
                          border: Border.all(color: context.appBorder),
                        ),
                        child: Row(children: [
                          Container(
                            width: 50, height: 50,
                            decoration: BoxDecoration(
                              color: _themeColor.withValues(alpha:0.1),
                              borderRadius: BorderRadius.circular(R.r(context, 14)),
                            ),
                            child: Icon(icon, color: _themeColor, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(svc['name'] as String, style: AppTextStyles.labelLarge),
                            if (subtitle.isNotEmpty)
                              Text(subtitle, style: AppTextStyles.bodySmall),
                            const SizedBox(height: 4),
                            Text(svc['priceLabel'] as String, style: AppTextStyles.labelMedium.copyWith(color: _themeColor)),
                          ])),
                          ElevatedButton(
                            onPressed: () => _book(ctx, ref, svc),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _themeColor,
                              minimumSize: const Size(70, 36),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            child: const Text('Add', style: TextStyle(fontSize: 12)),
                          ),
                        ]),
                      );
                    }).toList());
                  },
                ),
                SizedBox(height: R.h(context, 40)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return AppShimmer(
      child: Column(children: List.generate(3, (_) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 82,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      ))),
    );
  }

  Widget _buildError() => const AppErrorState(message: 'Could not load services. Please try again.');

  Widget _buildEmpty() => const AppEmptyState(
    icon: Icons.fitness_center_outlined,
    title: 'No Services Available',
    message: 'Physiotherapy services will appear here once added.',
    iconColor: _themeColor,
  );
}
