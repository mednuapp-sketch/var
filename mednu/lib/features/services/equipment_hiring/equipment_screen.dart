import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/service_booking_sheet.dart';

class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({super.key});

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  int _retryKey = 0;

  static const _palette = [
    Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF0097A7),
    Color(0xFF7B1FA2), Color(0xFFE65100), Color(0xFFC2185B),
    Color(0xFF37474F), Color(0xFF4527A0), Color(0xFF00838F),
  ];

  static const _icons = [
    Icons.accessible_rounded, Icons.bed_rounded, Icons.air_rounded,
    Icons.masks_rounded, Icons.accessibility_new_rounded, Icons.monitor_heart_rounded,
    Icons.medical_services_rounded, Icons.local_hospital_rounded, Icons.healing_rounded,
  ];

  static Color _colorAt(int i) => _palette[i % _palette.length];
  static IconData _iconAt(int i) => _icons[i % _icons.length];

  static String _priceLabel(Map<String, dynamic> d) {
    final price = (d['price'] as num?)?.toInt() ?? 0;
    final unit = d['priceUnit'] as String? ?? 'per_week';
    final unitLabel = switch (unit) {
      'per_day'     => '/day',
      'per_month'   => '/month',
      'per_hour'    => '/hour',
      'per_session' => '/session',
      _             => '/week',
    };
    return '₹$price$unitLabel';
  }

  static void _rent(BuildContext ctx, Map<String, dynamic> eq) {
    final deposit = (eq['deposit'] as num?)?.toInt() ?? 0;
    final depositStr = deposit > 0 ? '₹$deposit refundable deposit' : 'No deposit required';
    ServiceBookingSheet.show(
      ctx,
      type: 'equipment',
      serviceName: eq['name'] as String,
      themeColor: eq['color'] as Color,
      priceLabel: '${eq['priceLabel']} rental • $depositStr',
      serviceDetails: {
        'equipmentName': eq['name'],
        'weeklyPrice':   eq['price'],
        'deposit':       deposit,
        'deliveryFree':  true,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        key: ValueKey(_retryKey),
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
                    colors: [Color(0xFF263238), Color(0xFF78909C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.medical_services_rounded, color: Colors.white, size: 36),
                      const SizedBox(height: 8),
                      Text('Medical Equipment', style: AppTextStyles.onPrimaryH2),
                      Text('Rent quality equipment • Free delivery', style: AppTextStyles.onPrimaryBody),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('services')
                  .where('type', isEqualTo: 'equipment')
                  .where('isEnabled', isEqualTo: true)
                  .snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _buildSkeleton();
                }
                if (snap.hasError) {
                  return _buildError(context);
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _buildEmpty();
                }
                final items = docs.asMap().entries.map((e) {
                  final d = e.value.data() as Map<String, dynamic>;
                  return {
                    'id':         e.value.id,
                    'name':       (d['name'] as String? ?? '').trim(),
                    'price':      (d['price'] as num?)?.toInt() ?? 0,
                    'priceUnit':  d['priceUnit'] as String? ?? 'per_week',
                    'priceLabel': _priceLabel(d),
                    'deposit':    (d['deposit'] as num?)?.toInt() ?? 0,
                    'description': (d['description'] as String? ?? '').trim(),
                    'color':      _colorAt(e.key),
                    'icon':       _iconAt(e.key),
                  };
                }).toList();

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Available Equipment', style: AppTextStyles.h4),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.82,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final eq = items[i];
                        final color = eq['color'] as Color;
                        final deposit = (eq['deposit'] as int);
                        final desc = (eq['description'] as String);
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 46, height: 46,
                              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                              child: Icon(eq['icon'] as IconData, color: color, size: 26),
                            ),
                            const SizedBox(height: 10),
                            Text(eq['name'] as String, style: AppTextStyles.labelLarge),
                            const SizedBox(height: 4),
                            Text(eq['priceLabel'] as String, style: AppTextStyles.labelMedium.copyWith(color: color)),
                            if (deposit > 0)
                              Text('Deposit: ₹$deposit', style: AppTextStyles.caption)
                            else if (desc.isNotEmpty)
                              Text(desc, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                            const Spacer(),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => _rent(ctx, eq),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: color,
                                  minimumSize: const Size(double.infinity, 32),
                                  padding: EdgeInsets.zero,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Rent Now', style: TextStyle(fontSize: 12, fontFamily: 'Poppins')),
                              ),
                            ),
                          ]),
                        );
                      },
                    ),
                    const SizedBox(height: 40),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 160, height: 16, margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8))),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 0.82,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: List.generate(4, (_) => Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
          )),
        ),
      ]),
    );
  }

  Widget _buildError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text('Could not load equipment', style: AppTextStyles.bodyMedium),
        const SizedBox(height: 8),
        TextButton(onPressed: () => setState(() => _retryKey++), child: const Text('Retry')),
      ]),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(children: [
        Icon(Icons.medical_services_outlined, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text('No equipment listed yet', style: AppTextStyles.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Equipment will appear here once added by the team', style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
      ]),
    );
  }
}
