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
  static const _palette = [
    Color(0xFFC2185B), Color(0xFF1565C0), Color(0xFF2E7D32),
    Color(0xFF6A1B9A), Color(0xFF0097A7), Color(0xFFE65100),
  ];

  Color _colorFor(String type) {
    switch (type.toLowerCase()) {
      case 'nurse':           return const Color(0xFF1565C0);
      case 'maid':            return const Color(0xFFC2185B);
      case 'attendant':       return const Color(0xFF2E7D32);
      case 'physiotherapist': return const Color(0xFFE65100);
      default:                return _palette[0];
    }
  }

  String _query       = '';
  String _typeFilter  = 'all';    // all / Nurse / Maid / Attendant / Physiotherapist
  String _genderFilter = 'all';   // all / Male / Female / Other
  String _locationFilter = '';    // free-text city filter

  static const _typeOptions    = ['all', 'Nurse', 'Maid', 'Attendant', 'Physiotherapist'];
  static const _genderOptions  = ['all', 'Female', 'Male', 'Other'];

  Map<String, dynamic> _normalize(Map<String, dynamic> raw, int idx) {
    final rateNum = (raw['ratePerDay'] as num?)?.toInt() ?? 0;
    final type    = raw['type'] as String? ?? 'Caregiver';
    return {
      'name':      raw['name']       as String? ?? 'Caregiver',
      'exp':       raw['experience'] as String? ?? raw['exp'] as String? ?? '',
      'rating':    (raw['rating']    as num?)?.toDouble() ?? 0.0,
      'specialty': raw['specialty']  as String? ?? 'Home Care',
      'rate':      raw['rate']       as String? ?? (rateNum > 0 ? '₹$rateNum/day' : '—'),
      'rateNum':   rateNum,
      'type':      type,
      'gender':    raw['gender']     as String? ?? '',
      'location':  raw['location']   as String? ?? '',
      'color':     _colorFor(type),
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
      amount: (c['rateNum'] as num?)?.toInt() ?? 0,
      paymentDescription: 'Caregiver: ${c['name']} – ${c['specialty']}',
      serviceDetails: {
        'caregiverName': c['name'],
        'specialty':     c['specialty'],
        'experience':    c['exp'],
        'ratePerDay':    c['rateNum'],
        'rating':        c['rating'],
        'type':          c['type'],
        'gender':        c['gender'],
        'location':      c['location'],
      },
    );
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> list) {
    return list.where((c) {
      if (_typeFilter != 'all' && (c['type'] as String) != _typeFilter) return false;
      if (_genderFilter != 'all' && (c['gender'] as String) != _genderFilter) return false;
      if (_locationFilter.isNotEmpty &&
          !(c['location'] as String).toLowerCase().contains(_locationFilter.toLowerCase())) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        return (c['name'] as String).toLowerCase().contains(q) ||
               (c['specialty'] as String).toLowerCase().contains(q) ||
               (c['location'] as String).toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  bool get _hasActiveFilters =>
      _typeFilter != 'all' || _genderFilter != 'all' || _locationFilter.isNotEmpty;

  Widget _filterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        // Type filters
        ..._typeOptions.map((t) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _Chip(
            label: t == 'all' ? 'All Types' : t,
            selected: _typeFilter == t,
            onTap: () => setState(() => _typeFilter = t),
          ),
        )),
        const SizedBox(width: 4),
        Container(width: 1, height: 24, color: AppColors.divider),
        const SizedBox(width: 8),
        // Gender filters
        ..._genderOptions.map((g) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _Chip(
            label: g == 'all' ? 'Any Gender' : g,
            selected: _genderFilter == g,
            onTap: () => setState(() => _genderFilter = g),
          ),
        )),
      ]),
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
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snap) {
          List<Map<String, dynamic>> caregivers;

          if (snap.hasError) {
            caregivers = [];
          } else if (!snap.hasData) {
            caregivers = [];
          } else {
            caregivers = snap.data!.docs
                .asMap()
                .entries
                .map((e) => _normalize(
                      Map<String, dynamic>.from(e.value.data() as Map),
                      e.key,
                    ))
                .toList();
          }

          final filtered = _applyFilters(caregivers);

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
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Search bar
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search by name, specialty, city...',
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
                    const SizedBox(height: 10),

                    // Location filter
                    TextField(
                      onChanged: (v) => setState(() => _locationFilter = v),
                      decoration: InputDecoration(
                        hintText: 'Filter by city / location...',
                        prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.textHint, size: 20),
                        suffixIcon: _locationFilter.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textHint),
                                onPressed: () => setState(() => _locationFilter = ''))
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Type + Gender chip filters
                    _filterChips(),

                    // Active filter summary
                    if (_hasActiveFilters) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.filter_list_rounded, size: 14, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text('Filters active', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textHint)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() {
                            _typeFilter = 'all';
                            _genderFilter = 'all';
                            _locationFilter = '';
                          }),
                          child: Text('Clear all',
                              style: AppTextStyles.labelSmall.copyWith(
                                  color: const Color(0xFFC2185B),
                                  decoration: TextDecoration.underline)),
                        ),
                      ]),
                    ],

                    const SizedBox(height: 16),

                    // Content
                    if (!snap.hasData && !snap.hasError)
                      Column(children: List.generate(4, (_) => const _CaregiverCardSkeleton()))
                    else if (snap.hasError)
                      AppEmptyState(
                        icon: Icons.wifi_off_rounded,
                        title: 'Could not load caregivers',
                        message: 'Check your internet connection and try again.',
                        actionLabel: 'Retry',
                        onAction: () => setState(() {}),
                      )
                    else if (caregivers.isEmpty)
                      const AppEmptyState(
                        icon: Icons.health_and_safety_outlined,
                        title: 'No caregivers available',
                        message: 'Caregiver listings will appear here soon.',
                      )
                    else if (filtered.isEmpty)
                      AppEmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No matches found',
                        message: 'Try adjusting your search or filters.',
                        actionLabel: 'Clear Filters',
                        onAction: () => setState(() {
                          _query = '';
                          _typeFilter = 'all';
                          _genderFilter = 'all';
                          _locationFilter = '';
                        }),
                      )
                    else
                      ...filtered.map((c) {
                        final color  = c['color'] as Color;
                        final rating = c['rating'] as double;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                width: 56, height: 56,
                                decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    shape: BoxShape.circle),
                                child: Icon(Icons.person_rounded, size: 30, color: color),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(c['name'] as String, style: AppTextStyles.labelLarge),
                                const SizedBox(height: 2),
                                Text(c['specialty'] as String, style: AppTextStyles.bodySmall),
                                if ((c['location'] as String).isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Row(children: [
                                    Icon(Icons.location_on_outlined, size: 13, color: AppColors.textHint),
                                    const SizedBox(width: 2),
                                    Text(c['location'] as String, style: AppTextStyles.labelSmall),
                                  ]),
                                ],
                              ])),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(c['rate'] as String,
                                    style: AppTextStyles.labelLarge.copyWith(color: color)),
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () => _book(c),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
                            const SizedBox(height: 10),
                            Wrap(spacing: 6, children: [
                              _Badge(label: c['type'] as String, color: color),
                              if ((c['gender'] as String).isNotEmpty)
                                _Badge(label: c['gender'] as String, color: const Color(0xFF6A1B9A)),
                              if ((c['exp'] as String).isNotEmpty)
                                _Badge(label: '${c['exp']} exp', color: const Color(0xFF0097A7)),
                              if (rating > 0)
                                _Badge(label: '⭐ ${rating.toStringAsFixed(1)}', color: Colors.amber.shade700),
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

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label,
        style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color)),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFC2185B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? const Color(0xFFC2185B) : AppColors.divider,
        ),
      ),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Colors.white : AppColors.textSecondary)),
    ),
  );
}

class _CaregiverCardSkeleton extends StatelessWidget {
  const _CaregiverCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: const AppShimmer(
        child: Row(children: [
          SkeletonCircle(size: 56),
          SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: double.infinity, height: 14, radius: 4),
            SizedBox(height: 6),
            SkeletonBox(width: 160, height: 11, radius: 4),
            SizedBox(height: 6),
            SkeletonBox(width: 100, height: 11, radius: 4),
          ])),
          SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            SkeletonBox(width: 60, height: 16, radius: 4),
            SizedBox(height: 10),
            SkeletonBox(width: 56, height: 30, radius: 10),
          ]),
        ]),
      ),
    );
  }
}
