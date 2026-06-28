import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/service_booking_sheet.dart';
import '../../../core/widgets/ux_widgets.dart';

class CareAssistantScreen extends StatelessWidget {
  const CareAssistantScreen({super.key});

  static const _themeColor = Color(0xFFE65100);

  static const _icons = [
    Icons.local_hospital_rounded, Icons.science_rounded, Icons.medication_rounded,
    Icons.directions_walk_rounded, Icons.support_agent_rounded, Icons.elderly_rounded,
    Icons.home_rounded, Icons.monitor_heart_rounded, Icons.healing_rounded,
  ];

  IconData _iconAt(int i) => _icons[i % _icons.length];

  String _priceLabel(Map<String, dynamic> d) {
    final price = (d['price'] as num?)?.toInt() ?? 0;
    final unit = d['priceUnit'] as String? ?? 'per_visit';
    final label = switch (unit) {
      'per_hour'    => '/hr',
      'per_day'     => '/day',
      'per_session' => '/session',
      'per_month'   => '/month',
      _             => '/visit',
    };
    return '₹$price$label';
  }

  void _book(BuildContext ctx, Map<String, dynamic> task) {
    ServiceBookingSheet.show(
      ctx,
      type: 'care_assistant',
      serviceName: task['name'] as String,
      themeColor: _themeColor,
      priceLabel: '${task['priceLabel']} per visit',
      amount: (task['price'] as num?)?.toInt() ?? 0,
      paymentDescription: 'Care Assistant: ${task['name']}',
      serviceDetails: {
        'taskType': task['name'],
        'taskDesc': task['description'],
        'price':    task['price'],
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
            expandedHeight: 180,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE65100), Color(0xFFFFA726)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.support_agent_rounded, color: Colors.white, size: 36),
                      const SizedBox(height: 8),
                      Text('Care Assistant', style: AppTextStyles.onPrimaryH2),
                      Text('Book a trusted person to help your loved ones', style: AppTextStyles.onPrimaryBody),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _themeColor.withValues(alpha:0.07),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _themeColor.withValues(alpha:0.2)),
                  ),
                  child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('What is Care Assistant?',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: _themeColor)),
                    SizedBox(height: 8),
                    Text(
                      'Book a verified person who will physically accompany your family member to hospital, collect reports, pick up medicines, or any other healthcare task — when you can\'t be there yourself.',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary, height: 1.6),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                Text('Select Task', style: AppTextStyles.h4),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('services')
                      .where('type', isEqualTo: 'care_assistant')
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
                    final tasks = docs.asMap().entries.map((e) {
                      final d = e.value.data() as Map<String, dynamic>;
                      return {
                        'id':          e.value.id,
                        'name':        (d['name'] as String? ?? '').trim(),
                        'price':       (d['price'] as num?)?.toInt() ?? 0,
                        'priceUnit':   d['priceUnit'] as String? ?? 'per_visit',
                        'priceLabel':  _priceLabel(d),
                        'description': (d['description'] as String? ?? '').trim(),
                        'icon':        _iconAt(e.key),
                      };
                    }).toList();

                    return Column(children: tasks.map((task) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(children: [
                        Container(
                          width: 46, height: 46,
                          decoration: BoxDecoration(color: _themeColor.withValues(alpha:0.1), borderRadius: BorderRadius.circular(12)),
                          child: Icon(task['icon'] as IconData, color: _themeColor, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(task['name'] as String, style: AppTextStyles.labelLarge),
                          if ((task['description'] as String).isNotEmpty)
                            Text(task['description'] as String, style: AppTextStyles.bodySmall),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(task['priceLabel'] as String, style: AppTextStyles.labelLarge.copyWith(color: _themeColor)),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => _book(ctx, task),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: _themeColor, borderRadius: BorderRadius.circular(8)),
                              child: const Text('Book', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                        ]),
                      ]),
                    )).toList());
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
      child: Column(children: List.generate(4, (_) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 78,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      ))),
    );
  }

  Widget _buildError() => AppErrorState(message: 'Could not load tasks. Please try again.');

  Widget _buildEmpty() => const AppEmptyState(
    icon: Icons.support_agent_outlined,
    title: 'No Tasks Available',
    message: 'Care assistant tasks will appear here once added.',
    iconColor: _themeColor,
  );
}
