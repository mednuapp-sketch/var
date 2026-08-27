import 'dart:async';
import 'dart:math' show asin, cos, pi, sin, sqrt;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/therapy_specialties.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../home/providers/location_provider.dart';
import '../../home/providers/home_nav_provider.dart';

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLng / 2) *
          sin(dLng / 2);
  return r * 2 * asin(sqrt(a));
}

// ─────────────────────────────────────────────────────────────
//  Filter state
// ─────────────────────────────────────────────────────────────
class _FilterState {
  final String sortBy; // 'relevance' | 'fee_asc' | 'fee_desc'
  final int maxFee; // 0 = any
  final String gender; // 'Any' | 'Male' | 'Female'
  final bool availableNow; // filter to online doctors only

  const _FilterState({
    this.sortBy = 'relevance',
    this.maxFee = 0,
    this.gender = 'Any',
    this.availableNow = false,
  });

  bool get hasActiveFilters =>
      sortBy != 'relevance' ||
      maxFee > 0 ||
      gender != 'Any' ||
      availableNow;

  _FilterState copyWith({
    String? sortBy,
    int? maxFee,
    String? gender,
    bool? availableNow,
  }) =>
      _FilterState(
        sortBy: sortBy ?? this.sortBy,
        maxFee: maxFee ?? this.maxFee,
        gender: gender ?? this.gender,
        availableNow: availableNow ?? this.availableNow,
      );
}

// ─────────────────────────────────────────────────────────────
//  Main Screen
// ─────────────────────────────────────────────────────────────
class DoctorsListScreen extends ConsumerStatefulWidget {
  final String? initialSpecialty;
  final String? initialMode; // 'video' | 'inperson'
  final String? initialType; // 'therapist' | null (any professional type)
  final int? initialDuration; // preferred session length in minutes, carried from the booking flow
  final bool showBackButton;

  const DoctorsListScreen({
    super.key,
    this.initialSpecialty,
    this.initialMode,
    this.initialType,
    this.initialDuration,
    this.showBackButton = true,
  });

  @override
  ConsumerState<DoctorsListScreen> createState() => _DoctorsListScreenState();
}

class _DoctorsListScreenState extends ConsumerState<DoctorsListScreen>
    with SingleTickerProviderStateMixin {
  late String _selectedSpecialty;
  // 'video' = online/global | 'inperson' = location-filtered
  late String _consultationMode;
  late bool _therapistsOnly;
  String _search = '';
  String _debouncedSearch = '';
  Timer? _searchDebounce;
  _FilterState _filters = const _FilterState();
  late TabController _tabController;
  final ScrollController _specialtyScrollController = ScrollController();

  static const _specialties = [
    'All', 'Available Now', 'General', 'Cardiology', 'Endocrinology',
    'Gastroenterology', 'Nephrology', 'Urology', 'Neurology',
    'Pulmonology', 'Gynaecology', 'Dermatology', 'General Surgery',
    'Orthopaedics', 'Ophthalmology', 'ENT', 'Paediatrics',
    'Psychiatry', 'Dental', 'Rheumatology', 'Oncology',
  ];

  // Shown instead of _specialties when browsing therapists only.
  static const _therapistSpecialties = [
    'All', 'Available Now', ...kTherapySpecialties,
  ];

  List<String> get _activeSpecialties =>
      _therapistsOnly ? _therapistSpecialties : _specialties;

  // Selected specialty is pulled to the front of the chip row; everything
  // else keeps its original relative order. Falls back to the normal order
  // when 'All' is selected or the selection isn't in the current list.
  List<String> get _displaySpecialties {
    final base = _activeSpecialties;
    if (_selectedSpecialty == 'All' || !base.contains(_selectedSpecialty)) {
      return base;
    }
    return [
      _selectedSpecialty,
      ...base.where((s) => s != _selectedSpecialty),
    ];
  }

  void _selectSpecialty(String specialty) {
    setState(() => _selectedSpecialty = specialty);
    if (_specialtyScrollController.hasClients) {
      _specialtyScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _therapistsOnly = widget.initialType == 'therapist';
    _selectedSpecialty = widget.initialSpecialty ?? 'All';
    _consultationMode = widget.initialMode == 'inperson' ? 'inperson' : 'video';
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _consultationMode == 'inperson' ? 1 : 0,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() {
          _consultationMode = _tabController.index == 0 ? 'video' : 'inperson';
        });
      }
    });
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    setState(() => _search = v.toLowerCase());
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      if (mounted) setState(() => _debouncedSearch = _search);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _specialtyScrollController.dispose();
    super.dispose();
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        initial: _filters,
        onApply: (f) => setState(() => _filters = f),
      ),
    );
  }

  void _openLocationOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha:0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.edit_location_alt_rounded,
                    color: AppColors.primary, size: 20),
              ),
              title: const Text('Change Location',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              subtitle: const Text('Search for area, city or landmark',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24))),
                  builder: (_) => ProviderScope(
                    child: _LocationChangeSheet(),
                  ),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha:0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.my_location_rounded,
                    color: Colors.teal, size: 20),
              ),
              title: const Text('Use Current Location',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              subtitle: const Text('Detect my location automatically',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                ref.read(locationProvider.notifier).fetchCurrent();
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locState = ref.watch(locationProvider);
    final isInPerson = _consultationMode == 'inperson';
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: Text(
          _therapistsOnly ? 'Find Therapists' : 'Find Doctors',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                tooltip: 'Back',
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    ref.read(bottomNavIndexProvider.notifier).state = 0;
                  }
                },
              )
            : null,
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
            tooltip: 'Filter doctors',
            onPressed: _openFilterSheet,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Container(
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.video_call_rounded, size: 16),
                      SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Video / Online',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_on_rounded, size: 16),
                      SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'In-Person',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(children: [
        // ── Search ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search doctors, specialities…',
              prefixIcon:
                  Icon(Icons.search_rounded, color: context.appTextHint),
              filled: true,
              fillColor: context.appSurface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),

        // ── Context banner ─────────────────────────────────────
        if (isInPerson)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: GestureDetector(
              onTap: _openLocationOptions,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: locState.hasCoordinates
                      ? AppColors.primary.withValues(alpha:0.07)
                      : Colors.orange.withValues(alpha:0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: locState.hasCoordinates
                        ? AppColors.primary.withValues(alpha:0.2)
                        : Colors.orange.withValues(alpha:0.3),
                  ),
                ),
                child: Row(children: [
                  Icon(
                    locState.hasCoordinates
                        ? Icons.location_on_rounded
                        : Icons.location_off_rounded,
                    size: 15,
                    color: locState.hasCoordinates
                        ? AppColors.primary
                        : Colors.orange.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      locState.hasCoordinates
                          ? 'Showing doctors near ${locState.displayName}'
                          : 'Set location to find nearby clinics & hospitals',
                      style: AppTextStyles.caption.copyWith(
                        color: locState.hasCoordinates
                            ? AppColors.primary
                            : Colors.orange.shade800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    locState.hasCoordinates ? 'Change' : 'Set Location',
                    style: AppTextStyles.caption.copyWith(
                      color: locState.hasCoordinates
                          ? AppColors.primary
                          : Colors.orange.shade800,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ]),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha:0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.withValues(alpha:0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.public_rounded, size: 15, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Video consultations available across India',
                    style: AppTextStyles.caption
                        .copyWith(color: Colors.teal.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ),

        // ── Specialty chips ────────────────────────────────────
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView.builder(
            controller: _specialtyScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _displaySpecialties.length,
            itemBuilder: (_, i) {
              final chip = _displaySpecialties[i];
              final isAvailableNow = chip == 'Available Now';
              final selected = isAvailableNow
                  ? _filters.availableNow
                  : _selectedSpecialty == chip;
              final isNotAll = chip != 'All' && !isAvailableNow;
              return GestureDetector(
                key: ValueKey(chip),
                onTap: () {
                  if (isAvailableNow) {
                    setState(() => _filters = _filters.copyWith(
                        availableNow: !_filters.availableNow));
                  } else {
                    _selectSpecialty(chip);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  padding: EdgeInsets.only(
                    left: 14,
                    right: selected && isNotAll ? 8 : 14,
                  ),
                  decoration: BoxDecoration(
                    gradient: selected ? AppColors.primaryGradient : null,
                    color: selected ? null : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : context.appBorder),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isAvailableNow && !selected)
                          Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Icon(Icons.bolt_rounded, size: 13, color: context.appTextSecondary),
                          ),
                        if (isAvailableNow && selected)
                          const Padding(
                            padding: EdgeInsets.only(right: 5),
                            child: Icon(Icons.bolt_rounded, size: 13, color: Colors.white),
                          ),
                        Text(
                          chip,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : context.appTextSecondary,
                          ),
                        ),
                        if (selected && isNotAll) ...[
                          const SizedBox(width: 5),
                          GestureDetector(
                            onTap: () => _selectSpecialty('All'),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ],
                        if (selected && isAvailableNow) ...[
                          const SizedBox(width: 5),
                          GestureDetector(
                            onTap: () => setState(() => _filters = _filters.copyWith(availableNow: false)),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),

        // ── Active filter chips ────────────────────────────────
        if (_filters.hasActiveFilters) ...[
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (_filters.sortBy != 'relevance')
                  _ActiveFilterChip(
                    label: _sortLabel(_filters.sortBy),
                    onRemove: () => setState(
                        () => _filters = _filters.copyWith(sortBy: 'relevance')),
                  ),
                if (_filters.maxFee > 0)
                  _ActiveFilterChip(
                    label: 'Fee ≤₹${_filters.maxFee}',
                    onRemove: () =>
                        setState(() => _filters = _filters.copyWith(maxFee: 0)),
                  ),
                if (_filters.gender != 'Any')
                  _ActiveFilterChip(
                    label: _filters.gender,
                    onRemove: () => setState(
                        () => _filters = _filters.copyWith(gender: 'Any')),
                  ),
                if (_filters.availableNow)
                  _ActiveFilterChip(
                    label: 'Available Now',
                    onRemove: () => setState(
                        () => _filters = _filters.copyWith(availableNow: false)),
                  ),
                // Clear all button
                GestureDetector(
                  onTap: () => setState(() => _filters = const _FilterState()),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.clear_all_rounded, size: 13, color: context.appTextSecondary),
                      const SizedBox(width: 4),
                      Text('Clear All',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.appTextSecondary)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],

        // ── Doctor list ────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: TabBarView(
            controller: _tabController,
            children: [
              // Video / Online tab — global, no location filter
              _DoctorListView(
                specialty: _selectedSpecialty,
                search: _debouncedSearch,
                filters: _filters,
                locationMode: _LocationMode.global,
                therapistsOnly: _therapistsOnly,
                duration: widget.initialDuration,
              ),
              // In-Person tab — requires location
              locState.isDetecting
                  ? ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      itemCount: 5,
                      itemBuilder: (_, __) => const SkeletonDoctorCard(),
                    )
                  : !locState.hasCoordinates
                      ? _LocationRequiredView(
                          onEnable: () => ref
                              .read(locationProvider.notifier)
                              .fetchCurrent(),
                        )
                      : _DoctorListView(
                          specialty: _selectedSpecialty,
                          search: _debouncedSearch,
                          filters: _filters,
                          locationMode: _LocationMode.nearby(
                              locState.lat ?? 0, locState.lng ?? 0),
                          isInPerson: true,
                          therapistsOnly: _therapistsOnly,
                          duration: widget.initialDuration,
                        ),
            ],
          ),
          ),
        ),
      ]),
    );
  }

  String _sortLabel(String s) {
    switch (s) {
      case 'fee_asc':
        return 'Fee: Low';
      case 'fee_desc':
        return 'Fee: High';
      default:
        return s;
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  Location mode
// ─────────────────────────────────────────────────────────────
class _LocationMode {
  final bool isGlobal;
  final double? lat;
  final double? lng;
  static const double maxKm = 15.0;

  const _LocationMode._(this.isGlobal, this.lat, this.lng);
  static const _LocationMode global = _LocationMode._(true, null, null);
  factory _LocationMode.nearby(double lat, double lng) =>
      _LocationMode._(false, lat, lng);
}

// ─────────────────────────────────────────────────────────────
//  Doctor list view (StreamBuilder)
// ─────────────────────────────────────────────────────────────
class _DoctorListView extends StatelessWidget {
  final String specialty;
  final String search;
  final _FilterState filters;
  final _LocationMode locationMode;
  final bool isInPerson;
  final bool therapistsOnly;
  final int? duration;

  const _DoctorListView({
    required this.specialty,
    required this.search,
    required this.filters,
    required this.locationMode,
    this.isInPerson = false,
    this.therapistsOnly = false,
    this.duration,
  });

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('doctors')
        .where('status', isEqualTo: 'active');

    if (specialty != 'All') {
      // A specific chip is always drawn from the active specialty list, so
      // when browsing therapists only it's already scoped to a therapy
      // specialty — no need to also apply the broader whereIn below.
      q = q.where('specialty', isEqualTo: specialty);
    } else if (therapistsOnly) {
      q = q.where('specialty', whereIn: kTherapySpecialties);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: 5,
            itemBuilder: (_, __) => const SkeletonDoctorCard(),
          );
        }
        if (snap.hasError) {
          return const AppErrorState(
            message: 'Unable to load doctors. Check your connection.',
          );
        }

        var list = snap.data?.docs ?? [];

        // ── Location filter (in-person / nearby only) ─────────
        List<MapEntry<QueryDocumentSnapshot<Map<String, dynamic>>, double?>>
            withDistance;

        if (!locationMode.isGlobal &&
            locationMode.lat != null &&
            locationMode.lng != null) {
          withDistance = list
              .map((doc) {
                final gp = doc.data()['location'] as GeoPoint?;
                if (gp == null) return null;
                final km = _haversineKm(locationMode.lat!, locationMode.lng!,
                    gp.latitude, gp.longitude);
                return km <= _LocationMode.maxKm
                    ? MapEntry(doc, km)
                    : null;
              })
              .whereType<MapEntry<QueryDocumentSnapshot<Map<String, dynamic>>,
                  double?>>()
              .toList();
        } else {
          withDistance = list.map((doc) => MapEntry(doc, null)).toList();
        }

        // ── Search ───────────────────────────────────────────
        if (search.isNotEmpty) {
          withDistance = withDistance.where((e) {
            final d = e.key.data();
            final name = (d['name'] as String? ?? '').toLowerCase();
            final spec = (d['specialty'] as String? ?? '').toLowerCase();
            final qual = (d['qualifications'] as String? ?? '').toLowerCase();
            return name.contains(search) ||
                spec.contains(search) ||
                qual.contains(search);
          }).toList();
        }

        // ── Client-side filters ───────────────────────────────
        if (filters.maxFee > 0) {
          withDistance = withDistance.where((e) {
            final fee = e.key.data()['fee'];
            final f = fee is int
                ? fee
                : int.tryParse(fee?.toString() ?? '0') ?? 0;
            return f <= filters.maxFee;
          }).toList();
        }

        if (filters.gender != 'Any') {
          withDistance = withDistance.where((e) {
            final g = (e.key.data()['gender'] as String? ?? '').toLowerCase();
            return g == filters.gender.toLowerCase();
          }).toList();
        }

        if (filters.availableNow) {
          withDistance = withDistance.where((e) {
            return e.key.data()['isOnline'] == true;
          }).toList();
        }

        // ── Sort ─────────────────────────────────────────────
        switch (filters.sortBy) {
          case 'fee_asc':
            withDistance.sort((a, b) {
              final fa = a.key.data()['fee'];
              final fb = b.key.data()['fee'];
              final ia = fa is int ? fa : int.tryParse(fa?.toString() ?? '0') ?? 0;
              final ib = fb is int ? fb : int.tryParse(fb?.toString() ?? '0') ?? 0;
              return ia.compareTo(ib);
            });
            break;
          case 'fee_desc':
            withDistance.sort((a, b) {
              final fa = a.key.data()['fee'];
              final fb = b.key.data()['fee'];
              final ia = fa is int ? fa : int.tryParse(fa?.toString() ?? '0') ?? 0;
              final ib = fb is int ? fb : int.tryParse(fb?.toString() ?? '0') ?? 0;
              return ib.compareTo(ia);
            });
            break;
          default:
            // For in-person with location: sort by distance
            if (!locationMode.isGlobal) {
              withDistance.sort(
                  (a, b) => (a.value ?? 999).compareTo(b.value ?? 999));
            } else {
              // Relevance: online doctors first, then by verified rating
              withDistance.sort((a, b) {
                final ao = a.key.data()['isOnline'] == true ? 0 : 1;
                final bo = b.key.data()['isOnline'] == true ? 0 : 1;
                if (ao != bo) return ao.compareTo(bo);
                final aRev = (a.key.data()['totalReviews'] as num?)?.toInt() ?? 0;
                final bRev = (b.key.data()['totalReviews'] as num?)?.toInt() ?? 0;
                final ra = aRev > 0 ? (a.key.data()['rating'] as num?)?.toDouble() ?? 0 : 0;
                final rb = bRev > 0 ? (b.key.data()['rating'] as num?)?.toDouble() ?? 0 : 0;
                return rb.compareTo(ra);
              });
            }
        }

        if (withDistance.isEmpty) {
          return AppEmptyState(
            icon: isInPerson
                ? Icons.location_searching_rounded
                : Icons.people_outline_rounded,
            title: isInPerson && !locationMode.isGlobal
                ? (therapistsOnly ? 'No nearby therapists' : 'No nearby doctors')
                : search.isNotEmpty
                    ? 'No results for "$search"'
                    : filters.hasActiveFilters
                        ? (therapistsOnly ? 'No therapists match your filters' : 'No doctors match your filters')
                        : (therapistsOnly ? 'No therapists available' : 'No doctors available'),
            message: isInPerson && !locationMode.isGlobal
                ? 'No ${therapistsOnly ? 'therapists' : 'doctors'} found within ${_LocationMode.maxKm.toInt()} km. Try adjusting your location or filters.'
                : filters.hasActiveFilters || search.isNotEmpty
                    ? 'No ${therapistsOnly ? 'therapists' : 'doctors'} match your search. Try different filters or a broader specialty.'
                    : 'No ${therapistsOnly ? 'therapists' : 'doctors'} available right now. Check back soon.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Results count badge ───────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${withDistance.length} doctor${withDistance.length == 1 ? '' : 's'} found',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.appTextSecondary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                itemCount: withDistance.length,
                itemBuilder: (_, i) {
                  final entry = withDistance[i];
                  return FadeInSlide(
                    delay: Duration(milliseconds: i * 35),
                    child: _DoctorCard(
                      data: entry.key.data(),
                      docId: entry.key.id,
                      distanceKm: entry.value,
                      isInPerson: isInPerson,
                      duration: duration,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Doctor card
// ─────────────────────────────────────────────────────────────
class _DoctorCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final double? distanceKm;
  final bool isInPerson;
  final int? duration;

  const _DoctorCard({
    required this.data,
    required this.docId,
    this.distanceKm,
    this.isInPerson = false,
    this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Doctor';
    final specialty = data['specialty'] as String? ?? '';
    final qual = data['qualifications'] as String? ?? '';
    final feeRaw = data['fee'];
    final fee = feeRaw is int
        ? feeRaw
        : int.tryParse(feeRaw?.toString() ?? '') ?? 0;
    final isOnline = data['isOnline'] as bool? ?? false;
    final photoUrl = data['photoUrl'] as String? ?? '';
    final hospital = data['hospital'] as String? ??
        data['hospitalAffiliation'] as String? ?? '';
    final isVerified = data['verified'] as bool? ?? true;
    final profilePath = duration != null ? '/doctors/$docId?duration=$duration' : '/doctors/$docId';

    return TapScale(
      onTap: () => context.push(profilePath),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOnline
                ? AppColors.accent.withValues(alpha: 0.2)
                : context.appDivider,
          ),
          boxShadow: [
            BoxShadow(
              color: isOnline
                  ? AppColors.accent.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Photo ──────────────────────────────────────────
                Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.12),
                          AppColors.secondary.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: photoUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: CachedNetworkImage(
                              imageUrl: photoUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const SkeletonBox(
                                  width: 72, height: 72, radius: 18),
                              errorWidget: (_, __, ___) => const Icon(
                                  Icons.person_rounded,
                                  size: 38,
                                  color: AppColors.primary),
                            ),
                          )
                        : const Icon(Icons.person_rounded,
                            size: 38, color: AppColors.primary),
                  ),
                  // Online indicator
                  if (isOnline)
                    Positioned(
                      bottom: -2, right: -2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.circle,
                            size: 8, color: Colors.white),
                      ),
                    ),
                ]),
                const SizedBox(width: 14),

                // ── Info ──────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + badges row
                      Row(children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: context.appTextPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Online/Offline badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: isOnline
                                ? AppColors.accent.withValues(alpha: 0.12)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isOnline
                                  ? AppColors.accent.withValues(alpha: 0.3)
                                  : Colors.grey.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isOnline
                                    ? AppColors.accent
                                    : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isOnline
                                    ? AppColors.accent
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ]),
                        ),
                      ]),

                      const SizedBox(height: 2),

                      // Specialty + qualification
                      Row(children: [
                        Expanded(
                          child: Text(
                            qual.isNotEmpty ? '$specialty · $qual' : specialty,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: context.appTextSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified_rounded,
                              size: 15, color: Color(0xFF1565C0)),
                        ],
                      ]),

                      const SizedBox(height: 8),

                      // Stats row
                      Wrap(
                        spacing: 12,
                        children: [
                          _statChip(
                            context,
                            icon: Icons.currency_rupee_rounded,
                            label: fee > 0 ? '$fee' : 'Free',
                            color: AppColors.accent,
                            bold: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ]),
            ),

            // ── Hospital & distance row ──────────────────────────
            if (hospital.isNotEmpty || distanceKm != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                child: Divider(
                    height: 1, color: context.appDivider.withValues(alpha: 0.6)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(children: [
                  if (hospital.isNotEmpty) ...[
                    Icon(Icons.local_hospital_rounded,
                        size: 13, color: context.appTextHint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        hospital,
                        style: AppTextStyles.caption
                            .copyWith(color: context.appTextHint),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (distanceKm != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.near_me_rounded,
                            size: 11, color: AppColors.primary),
                        const SizedBox(width: 3),
                        Text(
                          distanceKm! < 1
                              ? '${(distanceKm! * 1000).toInt()} m'
                              : '${distanceKm!.toStringAsFixed(1)} km',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700),
                        ),
                      ]),
                    ),
                  ],
                ]),
              ),
            ],

            // ── Action buttons ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Row(children: [
                // Quick Connect — only shown when doctor is online
                if (isOnline) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => context.push('/doctors/$docId',
                          extra: {'mode': 'quickConnect'}),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.flash_on_rounded,
                                size: 15, color: AppColors.primary),
                            SizedBox(width: 5),
                            Text(
                              'Quick Connect',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                // Book Appointment button
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push(profilePath),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_month_rounded,
                              size: 15, color: Colors.white),
                          SizedBox(width: 5),
                          Text(
                            'Book Now',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    bool bold = false,
  }) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: bold ? color : context.appTextSecondary,
          ),
        ),
      ]);
}

// ─────────────────────────────────────────────────────────────
//  Active filter chip
// ─────────────────────────────────────────────────────────────
class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _ActiveFilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha:0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary)),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                size: 13, color: AppColors.primary),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────
//  Empty state
// ─────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────
//  Advanced filter bottom sheet
// ─────────────────────────────────────────────────────────────
class _FilterSheet extends StatefulWidget {
  final _FilterState initial;
  final ValueChanged<_FilterState> onApply;
  const _FilterSheet({required this.initial, required this.onApply});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late _FilterState _state;

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
          // Handle
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
            const Text('Filter Doctors', style: AppTextStyles.h3),
            const Spacer(),
            TextButton(
              onPressed: () => setState(
                  () => _state = const _FilterState()),
              child: const Text('Reset All'),
            ),
          ]),
          const SizedBox(height: 16),

          // Sort by
          const Text('Sort By', style: AppTextStyles.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              _sortChip('relevance', 'Relevance'),
              _sortChip('fee_asc', 'Fee: Low → High'),
              _sortChip('fee_desc', 'Fee: High → Low'),
            ],
          ),
          const SizedBox(height: 20),

          // Max fee
          const Text('Consultation Fee', style: AppTextStyles.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              _feeChip(0, 'Any'),
              _feeChip(300, 'Under ₹300'),
              _feeChip(500, 'Under ₹500'),
              _feeChip(1000, 'Under ₹1000'),
            ],
          ),
          const SizedBox(height: 20),

          // Gender
          const Text('Doctor Gender', style: AppTextStyles.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              _genderChip('Any'),
              _genderChip('Male'),
              _genderChip('Female'),
            ],
          ),
          const SizedBox(height: 20),

          // Available Now toggle
          Row(children: [
            const Text('Available Now', style: AppTextStyles.labelLarge),
            const Spacer(),
            Switch(
              value: _state.availableNow,
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.primary,
              onChanged: (v) => setState(() => _state = _state.copyWith(availableNow: v)),
            ),
          ]),
          Text('Show only doctors who are currently online',
              style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
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

  Widget _sortChip(String value, String label) {
    final sel = _state.sortBy == value;
    return GestureDetector(
      onTap: () => setState(() => _state = _state.copyWith(sortBy: value)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: sel ? AppColors.primaryGradient : null,
          color: sel ? null : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: sel ? Colors.white : context.appTextSecondary)),
      ),
    );
  }

  Widget _feeChip(int value, String label) {
    final sel = _state.maxFee == value;
    return GestureDetector(
      onTap: () => setState(() => _state = _state.copyWith(maxFee: value)),
      child: _buildChip(label, sel),
    );
  }

  Widget _genderChip(String value) {
    final sel = _state.gender == value;
    return GestureDetector(
      onTap: () => setState(() => _state = _state.copyWith(gender: value)),
      child: _buildChip(value, sel),
    );
  }

  Widget _buildChip(String label, bool selected) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha:0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha:0.4)
                : Colors.transparent,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.primary : context.appTextSecondary)),
      );
}

// ─────────────────────────────────────────────────────────────
//  Location-change sheet (unchanged from original)
// ─────────────────────────────────────────────────────────────
class _LocationChangeSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_LocationChangeSheet> createState() =>
      _LocationChangeSheetState();
}

class _LocationChangeSheetState extends ConsumerState<_LocationChangeSheet> {
  final _ctrl = TextEditingController();
  final _dio = Dio();
  List<LocationSuggestion> _results = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.removeListener(_onChange);
    _ctrl.dispose();
    _dio.close(force: true);
    super.dispose();
  }

  void _onChange() {
    final q = _ctrl.text.trim();
    if (q.length < 2) {
      _debounce?.cancel();
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 450), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await _dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': q, 'format': 'json',
          'addressdetails': 1, 'limit': 8, 'countrycodes': 'in',
        },
        options: Options(
          headers: {'User-Agent': 'MedNUApp/1.0'},
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      final results = (res.data as List).map((item) {
        final placeName = (item['name'] as String?)?.trim() ?? '';
        final shortName = placeName.isNotEmpty
            ? placeName
            : (item['display_name'] as String).split(',').first.trim();
        final raw = item['display_name'] as String;
        final displayAddr = raw
            .split(',')
            .map((s) => s.trim())
            .where((s) =>
                s.isNotEmpty &&
                s != 'India' &&
                !RegExp(r'^\d{5,6}$').hasMatch(s))
            .take(4)
            .join(', ');
        return LocationSuggestion(
          displayName: displayAddr,
          shortName: shortName,
          lat: double.parse(item['lat'] as String),
          lng: double.parse(item['lon'] as String),
        );
      }).toList();
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Text('Change Location', style: AppTextStyles.h4),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search area, city…',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              await ref.read(locationProvider.notifier).fetchCurrent();
              if (context.mounted) Navigator.pop(context);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha:0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.my_location_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 12),
                Text('Use Current Location',
                    style: AppTextStyles.labelLarge
                        .copyWith(color: AppColors.primary)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            Column(children: List.generate(3, (_) => const _LocationResultSkeleton()))
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (_, i) {
                  final s = _results[i];
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    leading: const Icon(Icons.location_on_rounded,
                        color: AppColors.primary),
                    title: Text(s.shortName,
                        style: AppTextStyles.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(s.displayName,
                        style: AppTextStyles.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    onTap: () {
                      ref
                          .read(locationProvider.notifier)
                          .setFromSuggestion(s);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Location required prompt (in-person tab, no GPS yet)
// ─────────────────────────────────────────────────────────────
class _LocationRequiredView extends StatelessWidget {
  final VoidCallback onEnable;

  const _LocationRequiredView({required this.onEnable});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha:0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_searching_rounded,
                  size: 42, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'Enable Location',
              style: AppTextStyles.h3.copyWith(
                  color: context.appTextPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'We need your GPS location to find doctors near you. '
              'Tap below to detect your current position.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: context.appTextSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onEnable,
                icon: const Icon(Icons.gps_fixed_rounded,
                    size: 18, color: Colors.white),
                label: const Text(
                  'Detect My Location',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'In-person consultations require location access\nto show doctors within 15 km.',
              style: AppTextStyles.caption
                  .copyWith(color: context.appTextHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationResultSkeleton extends StatelessWidget {
  const _LocationResultSkeleton();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: AppShimmer(
        child: Row(children: [
          SkeletonBox(width: 36, height: 36, radius: 10),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: double.infinity, height: 13, radius: 4),
            SizedBox(height: 5),
            SkeletonBox(width: 200, height: 11, radius: 4),
          ])),
        ]),
      ),
    );
  }
}
