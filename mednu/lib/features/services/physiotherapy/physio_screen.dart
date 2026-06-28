import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/service_booking_sheet.dart';
import '../../../core/widgets/ux_widgets.dart';

class PhysioScreen extends StatelessWidget {
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

  void _book(BuildContext ctx, Map<String, dynamic> svc) {
    ServiceBookingSheet.show(
      ctx,
      type: 'physiotherapy',
      serviceName: svc['name'] as String,
      themeColor: _themeColor,
      priceLabel: svc['priceLabel'] as String,
      amount: (svc['price'] as num?)?.toInt() ?? 0,
      paymentDescription: 'Physiotherapy: ${svc['name']}',
      serviceDetails: {
        'sessionType': svc['name'],
        'title':       svc['name'],
        'price':       svc['price'],
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 160,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
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
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.fitness_center_rounded, color: Colors.white, size: 36),
                      const SizedBox(height: 8),
                      Text('Physiotherapy', style: AppTextStyles.onPrimaryH2),
                      Text('Certified physiotherapists • Online & Home', style: AppTextStyles.onPrimaryBody),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Choose Service', style: AppTextStyles.h4),
                const SizedBox(height: 12),
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
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(children: [
                          Container(
                            width: 50, height: 50,
                            decoration: BoxDecoration(
                              color: _themeColor.withValues(alpha:0.1),
                              borderRadius: BorderRadius.circular(14),
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
                            onPressed: () => _book(ctx, svc),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _themeColor,
                              minimumSize: const Size(70, 36),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            child: const Text('Book', style: TextStyle(fontSize: 12)),
                          ),
                        ]),
                      );
                    }).toList());
                  },
                ),
                const SizedBox(height: 40),
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
