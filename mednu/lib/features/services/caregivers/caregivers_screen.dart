import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/service_booking_sheet.dart';
import '../../../core/widgets/ux_widgets.dart';

class CaregiversScreen extends StatefulWidget {
  const CaregiversScreen({super.key});

  @override
  State<CaregiversScreen> createState() => _CaregiversScreenState();
}

class _CaregiversScreenState extends State<CaregiversScreen> {
  // Fallback list shown only when Firestore returns empty.
  static const _fallback = [
    {'name': 'Sunita Devi',  'exp': '5 years',  'rating': 4.8, 'specialty': 'Elderly Care',       'rate': '₹500/day',  'rateNum': 500},
    {'name': 'Ramesh Kumar', 'exp': '8 years',  'rating': 4.9, 'specialty': 'Post-Surgery Care',   'rate': '₹700/day',  'rateNum': 700},
    {'name': 'Anita Singh',  'exp': '3 years',  'rating': 4.6, 'specialty': 'Child Care',          'rate': '₹400/day',  'rateNum': 400},
    {'name': 'Mohan Lal',    'exp': '10 years', 'rating': 4.9, 'specialty': 'ICU & Critical Care', 'rate': '₹900/day',  'rateNum': 900},
  ];

  static const _palette = [
    Color(0xFFC2185B), Color(0xFF1565C0), Color(0xFF2E7D32),
    Color(0xFF6A1B9A), Color(0xFF0097A7), Color(0xFFE65100),
  ];

  Color _colorFor(int i) => _palette[i % _palette.length];

  String _query = '';

  Map<String, dynamic> _normalize(Map<String, dynamic> raw, int idx) {
    final rateNum = (raw['ratePerDay'] as num?)?.toInt()
        ?? (raw['rateNum'] as num?)?.toInt()
        ?? 500;
    return {
      'name':     raw['name']     as String? ?? 'Caregiver',
      'exp':      raw['experience'] as String? ?? raw['exp'] as String? ?? '',
      'rating':   (raw['rating'] as num?)?.toDouble() ?? 0.0,
      'specialty': raw['specialty'] as String? ?? 'Home Care',
      'rate':     raw['rate'] as String? ?? '₹$rateNum/day',
      'rateNum':  rateNum,
      'color':    _colorFor(idx),
    };
  }

  void _book(Map<String, dynamic> c) {
    ServiceBookingSheet.show(
      context,
      type:        'caregivers',
      serviceName: '${c['name']} – ${c['specialty']}',
      themeColor:  c['color'] as Color,
      priceLabel:  '${c['rate']} • ${c['exp']} experience'
          '${(c['rating'] as double) > 0 ? ' • ⭐ ${(c['rating'] as double).toStringAsFixed(1)}' : ''}',
      serviceDetails: {
        'caregiverName': c['name'],
        'specialty':     c['specialty'],
        'experience':    c['exp'],
        'ratePerDay':    c['rateNum'],
        'rating':        c['rating'],
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('caregivers')
            .where('isActive', isEqualTo: true)
            .limit(50)
            .snapshots(),
        builder: (context, snap) {
          List<Map<String, dynamic>> caregivers;

          if (snap.hasError) {
            caregivers = _fallback
                .asMap()
                .entries
                .map((e) => _normalize(Map<String, dynamic>.from(e.value), e.key))
                .toList();
          } else if (!snap.hasData) {
            caregivers = [];
          } else {
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              caregivers = _fallback
                  .asMap()
                  .entries
                  .map((e) => _normalize(Map<String, dynamic>.from(e.value), e.key))
                  .toList();
            } else {
              caregivers = docs
                  .asMap()
                  .entries
                  .map((e) => _normalize(
                        Map<String, dynamic>.from(e.value.data() as Map),
                        e.key,
                      ))
                  .toList();
            }
          }

          final filtered = _query.isEmpty
              ? caregivers
              : caregivers.where((c) =>
                  (c['name'] as String).toLowerCase().contains(_query.toLowerCase()) ||
                  (c['specialty'] as String).toLowerCase().contains(_query.toLowerCase()),
                ).toList();

          return CustomScrollView(
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
                        colors: [Color(0xFFEC407A), Color(0xFF880E4F)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.elderly_rounded, color: Colors.white, size: 36),
                          const SizedBox(height: 8),
                          Text('Caregivers', style: AppTextStyles.onPrimaryH2),
                          Text('Trained & verified home caregivers', style: AppTextStyles.onPrimaryBody),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search caregivers or specialty...',
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textHint),
                                onPressed: () => setState(() => _query = ''))
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!snap.hasData && !snap.hasError)
                      Column(children: List.generate(4, (_) => const SkeletonListTile()))
                    else if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(children: [
                          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text('No caregivers found', style: AppTextStyles.bodyMedium),
                        ]),
                      )
                    else
                      ...filtered.map((c) {
                        final color = c['color'] as Color;
                        final rating = (c['rating'] as double);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Row(children: [
                            Container(
                              width: 60, height: 60,
                              decoration: BoxDecoration(
                                  color: color.withValues(alpha:0.15), shape: BoxShape.circle),
                              child: Icon(Icons.person_rounded, size: 34, color: color),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c['name'] as String, style: AppTextStyles.labelLarge),
                              Text(c['specialty'] as String, style: AppTextStyles.bodySmall),
                              const SizedBox(height: 4),
                              Row(children: [
                                if (rating > 0) ...[
                                  const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                                  const SizedBox(width: 3),
                                  Text(rating.toStringAsFixed(1), style: AppTextStyles.labelSmall),
                                  const SizedBox(width: 10),
                                ],
                                const Icon(Icons.work_outline_rounded, size: 14, color: AppColors.textHint),
                                const SizedBox(width: 3),
                                Text(c['exp'] as String, style: AppTextStyles.labelSmall),
                              ]),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(c['rate'] as String,
                                  style: AppTextStyles.labelLarge.copyWith(color: color)),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () => _book(c),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text('Book',
                                      style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                ),
                              ),
                            ]),
                          ]),
                        );
                      }),
                    const SizedBox(height: 40),
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
