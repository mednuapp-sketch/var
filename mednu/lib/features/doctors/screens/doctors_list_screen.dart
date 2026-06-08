import 'dart:async';
import 'dart:math' show asin, cos, pi, sin, sqrt;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../home/providers/location_provider.dart';

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
  final String sortBy; // 'relevance' | 'rating' | 'experience' | 'fee_asc' | 'fee_desc'
  final double minRating; // 0 = any
  final int minExperience; // 0 = any  (years)
  final int maxFee; // 0 = any
  final String gender; // 'Any' | 'Male' | 'Female'

  const _FilterState({
    this.sortBy = 'relevance',
    this.minRating = 0,
    this.minExperience = 0,
    this.maxFee = 0,
    this.gender = 'Any',
  });

  bool get hasActiveFilters =>
      sortBy != 'relevance' ||
      minRating > 0 ||
      minExperience > 0 ||
      maxFee > 0 ||
      gender != 'Any';

  _FilterState copyWith({
    String? sortBy,
    double? minRating,
    int? minExperience,
    int? maxFee,
    String? gender,
  }) =>
      _FilterState(
        sortBy: sortBy ?? this.sortBy,
        minRating: minRating ?? this.minRating,
        minExperience: minExperience ?? this.minExperience,
        maxFee: maxFee ?? this.maxFee,
        gender: gender ?? this.gender,
      );
}

// ─────────────────────────────────────────────────────────────
//  Main Screen
// ─────────────────────────────────────────────────────────────
class DoctorsListScreen extends ConsumerStatefulWidget {
  final String? initialSpecialty;
  final String? initialMode; // 'video' | 'inperson'

  const DoctorsListScreen({super.key, this.initialSpecialty, this.initialMode});

  @override
  ConsumerState<DoctorsListScreen> createState() => _DoctorsListScreenState();
}

class _DoctorsListScreenState extends ConsumerState<DoctorsListScreen>
    with SingleTickerProviderStateMixin {
  late String _selectedSpecialty;
  // 'video' = online/global | 'inperson' = location-filtered
  late String _consultationMode;
  String _search = '';
  _FilterState _filters = const _FilterState();
  late TabController _tabController;

  static const _specialties = [
    'All', 'General', 'Cardiology', 'Dermatology',
    'Gynaecology', 'Paediatrics', 'ENT', 'Orthopaedics',
    'Neurology', 'Ophthalmology', 'Psychiatry',
    'Endocrinology', 'Gastroenterology',
  ];

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _tabController.dispose();
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
                    color: AppColors.primary.withOpacity(0.1),
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
                  builder: (ctx) => ProviderScope(
                    parent: ProviderScope.containerOf(ctx),
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
                    color: Colors.teal.withOpacity(0.1),
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Find Doctors',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
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
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Container(
            color: AppColors.primary,
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.video_call_rounded, size: 16),
                      SizedBox(width: 5),
                      Text('Video / Online'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on_rounded, size: 16),
                      SizedBox(width: 5),
                      Text('In-Person'),
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
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search doctors, specialities…',
              prefixIcon:
                  const Icon(Icons.search_rounded, color: AppColors.textHint),
              filled: true,
              fillColor: Colors.white,
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
                      ? AppColors.primary.withOpacity(0.07)
                      : Colors.orange.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: locState.hasCoordinates
                        ? AppColors.primary.withOpacity(0.2)
                        : Colors.orange.withOpacity(0.3),
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
                color: Colors.teal.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.public_rounded, size: 15, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Video consultations available globally — no location needed',
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
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _specialties.length,
            itemBuilder: (_, i) {
              final selected = _selectedSpecialty == _specialties[i];
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedSpecialty = _specialties[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    gradient: selected ? AppColors.primaryGradient : null,
                    color: selected ? null : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : AppColors.border),
                  ),
                  child: Center(
                    child: Text(
                      _specialties[i],
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
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
                if (_filters.minRating > 0)
                  _ActiveFilterChip(
                    label: '${_filters.minRating.toStringAsFixed(1)}+ ★',
                    onRemove: () => setState(
                        () => _filters = _filters.copyWith(minRating: 0)),
                  ),
                if (_filters.minExperience > 0)
                  _ActiveFilterChip(
                    label: '${_filters.minExperience}+ yrs',
                    onRemove: () => setState(
                        () => _filters = _filters.copyWith(minExperience: 0)),
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
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],

        // ── Doctor list ────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Video / Online tab — global, no location filter
              _DoctorListView(
                specialty: _selectedSpecialty,
                search: _search,
                filters: _filters,
                locationMode: _LocationMode.global,
              ),
              // In-Person tab — requires location
              locState.isDetecting
                  ? const Center(child: CircularProgressIndicator())
                  : !locState.hasCoordinates
                      ? _LocationRequiredView(
                          onEnable: () => ref
                              .read(locationProvider.notifier)
                              .fetchCurrent(),
                        )
                      : _DoctorListView(
                          specialty: _selectedSpecialty,
                          search: _search,
                          filters: _filters,
                          locationMode: _LocationMode.nearby(
                              locState.lat!, locState.lng!),
                          isInPerson: true,
                        ),
            ],
          ),
        ),
      ]),
    );
  }

  String _sortLabel(String s) {
    switch (s) {
      case 'rating':
        return 'Top Rated';
      case 'experience':
        return 'Most Experienced';
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

  const _DoctorListView({
    required this.specialty,
    required this.search,
    required this.filters,
    required this.locationMode,
    this.isInPerson = false,
  });

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('doctors')
        .where('status', isEqualTo: 'active');

    if (specialty != 'All') {
      q = q.where('specialty', isEqualTo: specialty);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: AppColors.textHint),
              const SizedBox(height: 8),
              Text('Error loading doctors',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textHint)),
            ]),
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
        if (filters.minRating > 0) {
          withDistance = withDistance.where((e) {
            final reviews = (e.key.data()['totalReviews'] as num?)?.toInt() ?? 0;
            if (reviews == 0) return false; // no verified rating — exclude from rating filters
            final r = (e.key.data()['rating'] as num?)?.toDouble() ?? 0;
            return r >= filters.minRating;
          }).toList();
        }

        if (filters.minExperience > 0) {
          withDistance = withDistance.where((e) {
            final exp = e.key.data()['experience'];
            final yrs = exp is int
                ? exp
                : int.tryParse(exp?.toString() ?? '0') ?? 0;
            return yrs >= filters.minExperience;
          }).toList();
        }

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

        // ── Sort ─────────────────────────────────────────────
        switch (filters.sortBy) {
          case 'rating':
            withDistance.sort((a, b) {
              final aReviews = (a.key.data()['totalReviews'] as num?)?.toInt() ?? 0;
              final bReviews = (b.key.data()['totalReviews'] as num?)?.toInt() ?? 0;
              final ra = aReviews > 0 ? (a.key.data()['rating'] as num?)?.toDouble() ?? 0 : 0;
              final rb = bReviews > 0 ? (b.key.data()['rating'] as num?)?.toDouble() ?? 0 : 0;
              return rb.compareTo(ra);
            });
            break;
          case 'experience':
            withDistance.sort((a, b) {
              final ea = a.key.data()['experience'];
              final eb = b.key.data()['experience'];
              final ia = ea is int ? ea : int.tryParse(ea?.toString() ?? '0') ?? 0;
              final ib = eb is int ? eb : int.tryParse(eb?.toString() ?? '0') ?? 0;
              return ib.compareTo(ia);
            });
            break;
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
          return _EmptyState(
            message: isInPerson && !locationMode.isGlobal
                ? 'No doctors found within ${_LocationMode.maxKm.toInt()} km.\nTry adjusting your location or filters.'
                : search.isNotEmpty
                    ? 'No doctors match "$search".\nTry a different search term.'
                    : 'No doctors available right now.\nCheck back soon.',
            icon: isInPerson
                ? Icons.location_searching_rounded
                : Icons.people_outline_rounded,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
          itemCount: withDistance.length,
          itemBuilder: (_, i) {
            final entry = withDistance[i];
            return _DoctorCard(
              data: entry.key.data(),
              docId: entry.key.id,
              distanceKm: entry.value,
              isInPerson: isInPerson,
            );
          },
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

  const _DoctorCard({
    required this.data,
    required this.docId,
    this.distanceKm,
    this.isInPerson = false,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Doctor';
    final specialty = data['specialty'] as String? ?? '';
    final qual = data['qualifications'] as String? ?? '';
    final ratingNum = (data['rating'] as num?)?.toDouble() ?? 0;
    final totalReviews = (data['totalReviews'] as num?)?.toInt() ?? 0;
    // Only show rating when there are real verified reviews; never show seeded defaults
    final rating = (ratingNum > 0 && totalReviews > 0) ? ratingNum.toStringAsFixed(1) : '–';
    final expRaw = data['experience'];
    final exp = expRaw is int
        ? expRaw
        : int.tryParse(expRaw?.toString() ?? '') ?? 0;
    final feeRaw = data['fee'];
    final fee = feeRaw is int
        ? feeRaw
        : int.tryParse(feeRaw?.toString() ?? '') ?? 0;
    final isOnline = data['isOnline'] as bool? ?? false;
    final photoUrl = data['photoUrl'] as String? ?? '';
    final hospital = data['hospital'] as String? ??
        data['hospitalAffiliation'] as String? ?? '';

    return GestureDetector(
      onTap: () => context.push('/doctors/$docId'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Photo
                Stack(children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: photoUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.person_rounded,
                                      size: 36, color: AppColors.primary),
                            ),
                          )
                        : const Icon(Icons.person_rounded,
                            size: 36, color: AppColors.primary),
                  ),
                  if (isOnline)
                    Positioned(
                      bottom: 4, right: 4,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Expanded(
                        child: Text(name,
                            style: AppTextStyles.labelLarge,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (isOnline ? AppColors.accent : Colors.grey)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isOnline ? AppColors.accent : Colors.grey,
                          ),
                        ),
                      ),
                    ]),
                    Text(
                      qual.isNotEmpty ? '$specialty · $qual' : specialty,
                      style: AppTextStyles.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      if (ratingNum > 0 && totalReviews > 0) ...[
                        const Icon(Icons.star_rounded,
                            size: 13, color: Colors.amber),
                        const SizedBox(width: 3),
                        Text(rating, style: AppTextStyles.labelSmall),
                        const SizedBox(width: 10),
                      ],
                      if (exp > 0) ...[
                        const Icon(Icons.work_outline_rounded,
                            size: 13, color: AppColors.textHint),
                        const SizedBox(width: 3),
                        Text('$exp yrs', style: AppTextStyles.labelSmall),
                        const SizedBox(width: 10),
                      ],
                      const Spacer(),
                      Text(
                        fee > 0 ? '₹$fee' : 'Free',
                        style: AppTextStyles.labelLarge
                            .copyWith(color: AppColors.primary),
                      ),
                    ]),
                  ]),
                ),
              ]),

              // Hospital & distance row
              if (hospital.isNotEmpty || distanceKm != null) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(children: [
                  if (hospital.isNotEmpty) ...[
                    const Icon(Icons.local_hospital_rounded,
                        size: 13, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        hospital,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textHint),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else const Spacer(),
                  if (distanceKm != null) ...[
                    const Icon(Icons.near_me_rounded,
                        size: 13, color: AppColors.primary),
                    const SizedBox(width: 3),
                    Text(
                      distanceKm! < 1
                          ? '${(distanceKm! * 1000).toInt()} m away'
                          : '${distanceKm!.toStringAsFixed(1)} km away',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.primary),
                    ),
                  ],
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
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
class _EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  const _EmptyState(
      {required this.message, this.icon = Icons.people_outline_rounded});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 60, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textHint, height: 1.6)),
          ]),
        ),
      );
}

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
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(children: [
            Text('Filter Doctors', style: AppTextStyles.h3),
            const Spacer(),
            TextButton(
              onPressed: () => setState(
                  () => _state = const _FilterState()),
              child: const Text('Reset All'),
            ),
          ]),
          const SizedBox(height: 16),

          // Sort by
          Text('Sort By', style: AppTextStyles.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              _sortChip('relevance', 'Relevance'),
              _sortChip('rating', 'Top Rated'),
              _sortChip('experience', 'Most Experienced'),
              _sortChip('fee_asc', 'Fee: Low → High'),
              _sortChip('fee_desc', 'Fee: High → Low'),
            ],
          ),
          const SizedBox(height: 20),

          // Min rating
          Row(children: [
            Text('Minimum Rating', style: AppTextStyles.labelLarge),
            const Spacer(),
            Text(
              _state.minRating > 0
                  ? '${_state.minRating.toStringAsFixed(1)} ★'
                  : 'Any',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.primary),
            ),
          ]),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              _ratingChip(0, 'Any'),
              _ratingChip(3.0, '3.0+'),
              _ratingChip(4.0, '4.0+'),
              _ratingChip(4.5, '4.5+'),
            ],
          ),
          const SizedBox(height: 20),

          // Experience
          Text('Experience', style: AppTextStyles.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              _expChip(0, 'Any'),
              _expChip(5, '5+ years'),
              _expChip(10, '10+ years'),
              _expChip(15, '15+ years'),
            ],
          ),
          const SizedBox(height: 20),

          // Max fee
          Text('Consultation Fee', style: AppTextStyles.labelLarge),
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
          Text('Doctor Gender', style: AppTextStyles.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              _genderChip('Any'),
              _genderChip('Male'),
              _genderChip('Female'),
            ],
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
                color: sel ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }

  Widget _ratingChip(double value, String label) {
    final sel = _state.minRating == value;
    return GestureDetector(
      onTap: () => setState(() => _state = _state.copyWith(minRating: value)),
      child: _buildChip(label, sel),
    );
  }

  Widget _expChip(int value, String label) {
    final sel = _state.minExperience == value;
    return GestureDetector(
      onTap: () =>
          setState(() => _state = _state.copyWith(minExperience: value)),
      child: _buildChip(label, sel),
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
              ? AppColors.primary.withOpacity(0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary.withOpacity(0.4)
                : Colors.transparent,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.primary : AppColors.textSecondary)),
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
      final res = await Dio().get(
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
          Text('Change Location', style: AppTextStyles.h4),
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
                color: AppColors.primary.withOpacity(0.07),
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
            const Center(child: CircularProgressIndicator())
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
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.location_searching_rounded,
                  size: 42, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'Enable Location',
              style: AppTextStyles.h3.copyWith(
                  color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'We need your GPS location to find doctors near you. '
              'Tap below to detect your current position.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
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
                  .copyWith(color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
