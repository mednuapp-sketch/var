import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/distance.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/add_to_cart_button.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../cart/providers/cart_provider.dart';
import '../../home/providers/location_provider.dart';

// ─────────────────────────────────────────────────────────────
//  Filter state
// ─────────────────────────────────────────────────────────────
class _CaregiverFilterState {
  final String type;   // 'All' | 'Nurse' | 'Maid'
  final String gender; // 'Any' | 'Male' | 'Female'

  const _CaregiverFilterState({this.type = 'All', this.gender = 'Any'});

  bool get hasActiveFilters => type != 'All' || gender != 'Any';

  _CaregiverFilterState copyWith({String? type, String? gender}) =>
      _CaregiverFilterState(
        type: type ?? this.type,
        gender: gender ?? this.gender,
      );
}

class CaregiversScreen extends ConsumerStatefulWidget {
  const CaregiversScreen({super.key});

  @override
  ConsumerState<CaregiversScreen> createState() => _CaregiversScreenState();
}

class _CaregiversScreenState extends ConsumerState<CaregiversScreen> {
  static const _palette = [
    Color(0xFF522546), Color(0xFF1565C0), Color(0xFF2E7D32),
    Color(0xFF6A1B9A), Color(0xFF0097A7), Color(0xFFE65100),
  ];

  Color _colorFor(String type) {
    switch (type.toLowerCase()) {
      case 'nurse':           return const Color(0xFF1565C0);
      case 'maid':            return const Color(0xFF522546);
      case 'attendant':       return const Color(0xFF2E7D32);
      case 'physiotherapist': return const Color(0xFFE65100);
      default:                return _palette[0];
    }
  }

  String _query       = '';
  String _locationFilter = '';    // free-text city filter
  _CaregiverFilterState _filters = const _CaregiverFilterState();

  // Placeholder displayNames that aren't real place names — never seed the
  // filter with these while GPS/reverse-geocoding is still in flight.
  static const _placeholderLocationNames = {
    'Detecting…', 'Location off', 'Select location', 'Current location',
  };

  @override
  void initState() {
    super.initState();
    // Default to the city/area picked via the app-wide location switcher, so
    // switching to e.g. Hyderabad there already scopes caregivers here —
    // still editable/clearable like any other manual filter. `preciseAddress`
    // (reverse-geocoded) may not have resolved yet at this point, so fall
    // back to `displayName`, which "Popular Cities" already sets to the
    // exact city name synchronously.
    final locState = ref.read(locationProvider);
    final city = locState.preciseAddress?.city ?? locState.displayName;
    if (city.isNotEmpty && !_placeholderLocationNames.contains(city)) {
      _locationFilter = city;
    }
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CaregiverFilterSheet(
        initial: _filters,
        onApply: (f) => setState(() => _filters = f),
      ),
    );
  }

  // Shift options: 8-hour shifts (morning/evening/night) and 12-hour shifts
  // (8am-8pm day / 8pm-8am night). Charges scale with shift length.
  static const _shiftOptions = [
    {'key': 'morning',  'label': 'Morning',  'time': '8 AM – 4 PM',  'hours': 8,  'group': '8-Hour Shift'},
    {'key': 'evening',  'label': 'Evening',  'time': '4 PM – 12 AM', 'hours': 8,  'group': '8-Hour Shift'},
    {'key': 'night',    'label': 'Night',    'time': '12 AM – 8 AM', 'hours': 8,  'group': '8-Hour Shift'},
    {'key': 'day12',    'label': 'Day',      'time': '8 AM – 8 PM',  'hours': 12, 'group': '12-Hour Shift'},
    {'key': 'night12',  'label': 'Night',    'time': '8 PM – 8 AM',  'hours': 12, 'group': '12-Hour Shift'},
  ];

  Map<String, dynamic> _shiftOption(String key) =>
      _shiftOptions.firstWhere((s) => s['key'] == key);

  Map<String, dynamic> _normalize(Map<String, dynamic> raw, String id, int idx) {
    // ratePerDay is the base rate for an 8-hour shift (morning/evening/night).
    final rateNum    = (raw['ratePerDay']  as num?)?.toInt() ?? 0;
    final rateHour   = (raw['ratePerHour'] as num?)?.toInt() ?? (rateNum > 0 ? (rateNum ~/ 8) : 0);
    final rate12     = (raw['ratePer12Hr'] as num?)?.toInt() ?? (rateHour > 0 ? rateHour * 12 : 0);
    final type       = raw['type'] as String? ?? 'Caregiver';
    final isVerified = raw['isVerified'] as bool? ?? false;
    return {
      'id':         id,
      'name':       raw['name']       as String? ?? 'Caregiver',
      'exp':        raw['experience'] as String? ?? raw['exp'] as String? ?? '',
      'rating':     (raw['rating']    as num?)?.toDouble() ?? 0.0,
      'specialty':  raw['specialty']  as String? ?? 'Home Care',
      'rate':       raw['rate']       as String? ?? (rateNum > 0 ? '₹$rateNum/8hr shift' : '—'),
      'rateNum':    rateNum,
      'rateHour':   rateHour,
      'rate12':     rate12,
      'shiftRates': {
        'morning':  rateNum,
        'evening':  rateNum,
        'night':    rateNum,
        'day12':    rate12,
        'night12':  rate12,
      },
      'type':       type,
      'gender':     raw['gender']     as String? ?? '',
      'location':   raw['location']   as String? ?? '',
      'lat':        (raw['lat'] as num?)?.toDouble(),
      'lng':        (raw['lng'] as num?)?.toDouble(),
      'color':      _colorFor(type),
      'isVerified': isVerified,
    };
  }

  int _amountFor(Map<String, dynamic> c, String shiftType) =>
      (c['shiftRates'] as Map<String, dynamic>)[shiftType] as int? ?? 0;

  String _displayRate(Map<String, dynamic> c) {
    final d = c['rateNum'] as int;
    return d > 0 ? '₹$d onwards' : (c['rate'] as String);
  }

  Future<void> _book(Map<String, dynamic> c) async {
    final shiftType = await _pickShift(c);
    if (shiftType == null || !mounted) return;

    final amount   = _amountFor(c, shiftType);
    final shiftOpt = _shiftOption(shiftType);
    ref.read(cartProvider.notifier).addItem(
          type: 'caregivers',
          serviceName: '${c['name']} – ${c['specialty']}',
          themeColor: c['color'] as Color,
          unitAmount: amount,
          serviceDetails: {
            'sourceCaregiverId': c['id'],
            'caregiverName':  c['name'],
            'specialty':      c['specialty'],
            'experience':     c['exp'],
            'ratePerDay':     c['rateNum'],
            'ratePerHour':    c['rateHour'],
            'ratePer12Hr':    c['rate12'],
            'shiftType':      shiftOpt['key'],
            'shiftLabel':     shiftOpt['label'],
            'shiftTiming':    shiftOpt['time'],
            'shiftHours':     shiftOpt['hours'],
            'rating':         c['rating'],
            'type':           c['type'],
            'gender':         c['gender'],
            'location':       c['location'],
            'isVerified':     c['isVerified'],
          },
        );
    if (mounted) {
      FeedbackService.showSuccess(context, '${c['name']} added to cart');
    }
  }

  // Shift-duration picker shown at booking time, per caregiver.
  Future<String?> _pickShift(Map<String, dynamic> c) {
    var selected = 'morning';
    final color = c['color'] as Color;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          decoration: BoxDecoration(
            color: ctx.appSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('Select Shift Duration', style: AppTextStyles.h4),
              const SizedBox(height: 2),
              Text('${c['name']} – ${c['specialty']}',
                  style: AppTextStyles.bodySmall),
              const SizedBox(height: 16),
              _ShiftSelector(
                options: _shiftOptions,
                selected: selected,
                onChanged: (v) => setModalState(() => selected = v),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.payments_outlined, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '₹${_amountFor(c, selected)} for ${_shiftOption(selected)['label']} '
                      '(${_shiftOption(selected)['hours']}h) shift',
                      style: AppTextStyles.labelLarge.copyWith(color: color),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Continue to Booking',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> list) {
    return list.where((c) {
      if (_filters.type != 'All' && (c['type'] as String) != _filters.type) return false;
      if (_filters.gender != 'Any' && (c['gender'] as String) != _filters.gender) return false;
      if (_locationFilter.isNotEmpty &&
          !(c['location'] as String).toLowerCase().contains(_locationFilter.toLowerCase())) {
        return false;
      }
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
      _filters.hasActiveFilters || _locationFilter.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
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
                      e.value.id,
                      e.key,
                    ))
                .toList();
          }

          var filtered = _applyFilters(caregivers);

          // Real distance sort/filter, same 15km convention already used by
          // pharmacy/diagnostics/doctors/physiotherapists/nutritionists —
          // layered on top of the existing city-text filter rather than
          // replacing it (a typed city still narrows the list even without
          // GPS). Falls back to unsorted when the patient or a caregiver has
          // no coordinates on file.
          final myLoc = ref.watch(locationProvider);
          if (myLoc.lat != null && myLoc.lng != null) {
            for (final c in filtered) {
              final lat = c['lat'] as double?;
              final lng = c['lng'] as double?;
              c['distanceKm'] = (lat != null && lng != null)
                  ? distanceKm(myLoc.lat!, myLoc.lng!, lat, lng)
                  : null;
            }
            filtered = filtered
                .where((c) {
                  final d = c['distanceKm'] as double?;
                  return d == null || d <= nearbyRadiusKm;
                })
                .toList()
              ..sort((a, b) {
                final da = a['distanceKm'] as double?;
                final db = b['distanceKm'] as double?;
                if (da == null && db == null) return 0;
                if (da == null) return 1;
                if (db == null) return -1;
                return da.compareTo(db);
              });
          }

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.primaryDark,
                expandedHeight: AppSpacing.headerHeight(context),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
                ),
                actions: [
                  IconButton(
                    icon: Stack(children: [
                      const Icon(Icons.tune_rounded, color: Colors.white),
                      if (_filters.hasActiveFilters)
                        Positioned(
                          top: 0, right: 0,
                          child: Container(
                            width: 8, height: 8,
                            decoration: const BoxDecoration(
                                color: Colors.amber, shape: BoxShape.circle),
                          ),
                        ),
                    ]),
                    onPressed: _openFilterSheet,
                  ),
                  const CartBadgeAction(),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
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
                                    Icon(Icons.elderly_rounded, color: Colors.white, size: AppSpacing.headerIconSize(context)),
                                    SizedBox(height: AppSpacing.headerIconGap(context)),
                                    const Text('Caregivers', style: AppTextStyles.onPrimaryH2),
                                    const Text('Trained & verified home caregivers', style: AppTextStyles.onPrimaryBody),
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
                    // Search bar
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search by name, specialty, city...',
                        prefixIcon: Icon(Icons.search_rounded, color: context.appTextHint),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear_rounded, size: 18, color: context.appTextHint),
                                onPressed: () => setState(() => _query = ''))
                            : null,
                        filled: true,
                        fillColor: context.appSurface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(R.r(context, 14)), borderSide: BorderSide.none),
                      ),
                    ),
                    SizedBox(height: R.h(context, 10)),

                    // Location filter
                    TextField(
                      onChanged: (v) => setState(() => _locationFilter = v),
                      decoration: InputDecoration(
                        hintText: 'Filter by city / location...',
                        prefixIcon: Icon(Icons.location_on_outlined, color: context.appTextHint, size: 20),
                        suffixIcon: _locationFilter.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear_rounded, size: 18, color: context.appTextHint),
                                onPressed: () => setState(() => _locationFilter = ''))
                            : null,
                        filled: true,
                        fillColor: context.appSurface,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(R.r(context, 14)), borderSide: BorderSide.none),
                      ),
                    ),
                    SizedBox(height: R.h(context, 10)),

                    // Active filter summary
                    if (_hasActiveFilters) ...[
                      Row(children: [
                        Icon(Icons.filter_list_rounded, size: 14, color: context.appTextHint),
                        const SizedBox(width: 4),
                        Text('Filters active', style: AppTextStyles.labelSmall.copyWith(color: context.appTextHint)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() {
                            _filters = const _CaregiverFilterState();
                            _locationFilter = '';
                          }),
                          child: Text('Clear all',
                              style: AppTextStyles.labelSmall.copyWith(
                                  color: const Color(0xFF522546),
                                  decoration: TextDecoration.underline)),
                        ),
                      ]),
                    ],

                    SizedBox(height: AppSpacing.sectionGap(context)),

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
                          _filters = const _CaregiverFilterState();
                          _locationFilter = '';
                        }),
                      )
                    else
                      ...filtered.map((c) {
                        final color      = c['color'] as Color;
                        final rating     = c['rating'] as double;
                        final isVerified = c['isVerified'] as bool;
                        return Container(
                          margin: EdgeInsets.only(bottom: R.h(context, 12)),
                          padding: EdgeInsets.all(R.p(context, 16)),
                          decoration: BoxDecoration(
                            color: context.appSurface,
                            borderRadius: BorderRadius.circular(R.r(context, 18)),
                            border: Border.all(
                              color: isVerified
                                  ? const Color(0xFF2E7D32).withValues(alpha: 0.35)
                                  : context.appBorder,
                            ),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Stack(children: [
                                Container(
                                  width: 56, height: 56,
                                  decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.15),
                                      shape: BoxShape.circle),
                                  child: Icon(Icons.person_rounded, size: 30, color: color),
                                ),
                                if (isVerified)
                                  Positioned(
                                    right: 0, bottom: 0,
                                    child: Container(
                                      width: 18, height: 18,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF2E7D32),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                                    ),
                                  ),
                              ]),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(c['name'] as String, style: AppTextStyles.labelLarge)),
                                  if (isVerified)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                                      ),
                                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.verified_rounded, size: 11, color: Color(0xFF2E7D32)),
                                        SizedBox(width: 3),
                                        Text('Verified', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
                                      ]),
                                    ),
                                ]),
                                const SizedBox(height: 2),
                                Text(c['specialty'] as String, style: AppTextStyles.bodySmall),
                                if ((c['distanceKm'] as double?) != null || (c['location'] as String).isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Row(children: [
                                    Icon(Icons.location_on_outlined, size: 13, color: context.appTextHint),
                                    const SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                          c['distanceKm'] != null
                                              ? '${(c['distanceKm'] as double).toStringAsFixed(1)} km away'
                                              : c['location'] as String,
                                          style: AppTextStyles.labelSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                  ]),
                                ],
                              ])),
                              const SizedBox(width: 8),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(_displayRate(c),
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
                                    child: const Text('Hire',
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
                            Wrap(spacing: 6, runSpacing: 4, children: [
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
                    SizedBox(height: R.h(context, 40)),
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
        color: selected ? const Color(0xFF522546) : context.appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? const Color(0xFF522546) : context.appBorder,
        ),
      ),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Colors.white : context.appTextSecondary)),
    ),
  );
}

class _CaregiverFilterSheet extends StatefulWidget {
  final _CaregiverFilterState initial;
  final ValueChanged<_CaregiverFilterState> onApply;
  const _CaregiverFilterSheet({required this.initial, required this.onApply});

  @override
  State<_CaregiverFilterSheet> createState() => _CaregiverFilterSheetState();
}

class _CaregiverFilterSheetState extends State<_CaregiverFilterSheet> {
  late _CaregiverFilterState _state;

  static const _typeOptions   = ['All', 'Nurse', 'Maid'];
  static const _genderOptions = ['Any', 'Male', 'Female'];

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: context.appBorder,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(children: [
            const Text('Filter Caregivers', style: AppTextStyles.h3),
            const Spacer(),
            TextButton(
              onPressed: () => setState(
                  () => _state = const _CaregiverFilterState()),
              child: const Text('Reset All'),
            ),
          ]),
          const SizedBox(height: 16),

          // Caregiver type
          const Text('Caregiver Type', style: AppTextStyles.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _typeOptions.map((t) => _Chip(
              label: t,
              selected: _state.type == t,
              onTap: () => setState(() => _state = _state.copyWith(type: t)),
            )).toList(),
          ),
          const SizedBox(height: 20),

          // Gender
          const Text('Gender', style: AppTextStyles.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _genderOptions.map((g) => _Chip(
              label: g,
              selected: _state.gender == g,
              onTap: () => setState(() => _state = _state.copyWith(gender: g)),
            )).toList(),
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.onApply(_state);
                Navigator.pop(context);
              },
              child: const Text('Apply Filters'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ShiftSelector extends StatelessWidget {
  final List<Map<String, Object>> options;
  final String selected;
  final void Function(String) onChanged;
  const _ShiftSelector({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, Object>>>{};
    for (final o in options) {
      groups.putIfAbsent(o['group'] as String, () => []).add(o);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.key,
                  style: AppTextStyles.labelSmall.copyWith(color: context.appTextHint)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: entry.value.map((o) {
                  final key        = o['key'] as String;
                  final isSelected = selected == key;
                  return GestureDetector(
                    onTap: () => onChanged(key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF522546) : context.appSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF522546) : context.appBorder,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            o['label'] as String,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? Colors.white : context.appTextSecondary,
                            ),
                          ),
                          Text(
                            o['time'] as String,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 9,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _CaregiverCardSkeleton extends StatelessWidget {
  const _CaregiverCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
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
