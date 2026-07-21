import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/add_to_cart_button.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../cart/providers/cart_provider.dart';

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

  void _book(BuildContext ctx, WidgetRef ref, Map<String, dynamic> svc) {
    ref.read(cartProvider.notifier).addItem(
          type: 'physiotherapy',
          serviceName: svc['name'] as String,
          themeColor: _themeColor,
          unitAmount: (svc['price'] as num?)?.toInt() ?? 0,
          serviceDetails: {
            'sessionType': svc['name'],
            'title':       svc['name'],
            'price':       svc['price'],
          },
        );
    FeedbackService.showSuccess(ctx, '${svc['name']} added to cart');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: AppSpacing.headerHeight(context),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
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
                                Text('Physiotherapy', style: AppTextStyles.onPrimaryH2),
                                Text('Certified physiotherapists • Online & Home', style: AppTextStyles.onPrimaryBody),
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
                Text('Choose Service', style: AppTextStyles.h4),
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

  Widget _buildError() => AppErrorState(message: 'Could not load services. Please try again.');

  Widget _buildEmpty() => AppEmptyState(
    icon: Icons.fitness_center_outlined,
    title: 'No Services Available',
    message: 'Physiotherapy services will appear here once added.',
    iconColor: _themeColor,
  );
}
