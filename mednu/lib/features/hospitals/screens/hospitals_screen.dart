import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mednu/core/constants/app_colors.dart';
import 'package:mednu/core/constants/app_text_styles.dart';
import 'package:mednu/core/router/app_router.dart';
import 'package:mednu/core/widgets/ux_widgets.dart';
import 'package:mednu/core/utils/r.dart';
import '../services/hospital_service.dart';
import '../services/nearby_hospital_service.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum _LocStatus { idle, loading, denied, ready }

enum _SortMode { distance, rating }

enum _HospitalFilter { all, nearby, openNow, emergency, specialty }

extension _FilterLabel on _HospitalFilter {
  String get label {
    switch (this) {
      case _HospitalFilter.all:       return 'All';
      case _HospitalFilter.nearby:    return 'Nearby';
      case _HospitalFilter.openNow:   return 'Open Now';
      case _HospitalFilter.emergency: return 'Emergency 24/7';
      case _HospitalFilter.specialty: return 'MedNU Partner';
    }
  }

  IconData get icon {
    switch (this) {
      case _HospitalFilter.all:       return Icons.apps_rounded;
      case _HospitalFilter.nearby:    return Icons.near_me_rounded;
      case _HospitalFilter.openNow:   return Icons.access_time_rounded;
      case _HospitalFilter.emergency: return Icons.emergency_rounded;
      case _HospitalFilter.specialty: return Icons.verified_rounded;
    }
  }
}

// ── Main Screen ───────────────────────────────────────────────────────────────

class HospitalsScreen extends StatefulWidget {
  final String? initialQuery;
  const HospitalsScreen({super.key, this.initialQuery});

  @override
  State<HospitalsScreen> createState() => _HospitalsScreenState();
}

class _HospitalsScreenState extends State<HospitalsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  _LocStatus _locStatus = _LocStatus.idle;
  double? _userLat;
  double? _userLng;

  List<Hospital> _mednuHospitals = [];
  StreamSubscription<List<Hospital>>? _mednuSub;

  List<Map<String, dynamic>>? _rawGooglePlaces;
  List<NearbyHospital>? _mergedHospitals;
  bool _isFetchingNearby = false;
  String? _fetchError;

  String _query = '';
  double _radiusKm = 0;
  _SortMode _sort = _SortMode.distance;
  _HospitalFilter _activeFilter = _HospitalFilter.all;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _query = widget.initialQuery!.toLowerCase();
      _searchController.text = widget.initialQuery!;
    }
    _mednuSub = HospitalService.stream().listen((hospitals) {
      if (!mounted) return;
      _mednuHospitals = hospitals;
      if (_rawGooglePlaces != null && _userLat != null && _userLng != null) {
        final merged = nearbyHospitalService.mergeResults(
          userLat: _userLat!,
          userLng: _userLng!,
          rawGooglePlaces: _rawGooglePlaces!,
          mednuHospitals: _mednuHospitals,
        );
        setState(() => _mergedHospitals = merged);
      } else if (_mergedHospitals == null) {
        setState(() {});
      }
    });
    _initLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mednuSub?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = v.toLowerCase());
    });
  }

  Future<void> _initLocation() async {
    setState(() => _locStatus = _LocStatus.loading);
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _locStatus = _LocStatus.denied);
      return;
    }
    var status = await Permission.locationWhenInUse.status;
    if (status.isDenied) status = await Permission.locationWhenInUse.request();
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      if (mounted) setState(() => _locStatus = _LocStatus.denied);
      return;
    }
    if (!status.isGranted) {
      if (mounted) setState(() => _locStatus = _LocStatus.denied);
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 12),
      );
      if (!mounted) return;
      _userLat = pos.latitude;
      _userLng = pos.longitude;
      setState(() => _locStatus = _LocStatus.ready);
      await _fetchNearby();
    } catch (_) {
      if (mounted) setState(() => _locStatus = _LocStatus.denied);
    }
  }

  Future<void> _fetchNearby() async {
    if (_userLat == null || _isFetchingNearby) return;
    setState(() {
      _isFetchingNearby = true;
      _fetchError = null;
    });
    try {
      final raw = await nearbyHospitalService.fetchRawGoogle(
        userLat: _userLat!,
        userLng: _userLng!,
        radiusMeters: 15000,
      );
      if (!mounted) return;
      _rawGooglePlaces = raw;
      final merged = nearbyHospitalService.mergeResults(
        userLat: _userLat!,
        userLng: _userLng!,
        rawGooglePlaces: raw,
        mednuHospitals: _mednuHospitals,
      );
      setState(() => _mergedHospitals = merged);
    } catch (e) {
      if (mounted) setState(() => _fetchError = e.toString());
    } finally {
      if (mounted) setState(() => _isFetchingNearby = false);
    }
  }

  List<NearbyHospital> get _displayList {
    var src = _mergedHospitals ??
        _mednuHospitals
            .map((h) => NearbyHospital(
                  id: h.id,
                  name: h.name,
                  address: h.address,
                  phone: h.phone,
                  mapsUrl: h.mapsUrl,
                  isEmergency: h.isEmergency,
                  isMednu: true,
                ))
            .toList();

    if (_query.isNotEmpty) {
      src = src
          .where((h) =>
              h.name.toLowerCase().contains(_query) ||
              h.address.toLowerCase().contains(_query))
          .toList();
    }
    if (_radiusKm > 0) {
      src = src
          .where((h) => h.distanceKm == null || h.distanceKm! <= _radiusKm)
          .toList();
    }
    switch (_activeFilter) {
      case _HospitalFilter.nearby:
        src = src.where((h) => h.distanceKm != null && h.distanceKm! <= 5.0).toList();
        break;
      case _HospitalFilter.openNow:
        break;
      case _HospitalFilter.emergency:
        src = src.where((h) => h.isEmergency).toList();
        break;
      case _HospitalFilter.specialty:
        src = src.where((h) => h.isMednu).toList();
        break;
      case _HospitalFilter.all:
        break;
    }
    src.sort((a, b) {
      if (_sort == _SortMode.rating) {
        return (b.rating ?? 0).compareTo(a.rating ?? 0);
      }
      return (a.distanceKm ?? double.infinity)
          .compareTo(b.distanceKm ?? double.infinity);
    });
    return src;
  }

  Future<void> _call(String phone) async {
    final clean = phone.replaceAll(RegExp(r'\s'), '');
    if (clean.isEmpty) return;
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _directions(NearbyHospital h) async {
    Uri uri;
    if (h.lat != null && h.lng != null) {
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=${h.lat},${h.lng}');
    } else if (h.mapsUrl.isNotEmpty) {
      uri = Uri.parse(h.mapsUrl);
    } else {
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(h.name)}');
    }
    try {
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      final fallback = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(h.name)}');
      if (await canLaunchUrl(fallback)) {
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hospitals = _displayList;
    final mednuCount = hospitals.where((h) => h.isMednu).length;
    final isLoading = (_locStatus == _LocStatus.loading || _locStatus == _LocStatus.idle) ||
        (_isFetchingNearby && _mergedHospitals == null);

    return Scaffold(
      backgroundColor: context.appBackground,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          if (_locStatus == _LocStatus.ready) await _fetchNearby();
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            // ── App Bar ──────────────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              expandedHeight: R.h(context, 200),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 20),
                onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
              ),
              actions: [
                // Sort toggle
                GestureDetector(
                  onTap: () => setState(() => _sort = _sort == _SortMode.distance
                      ? _SortMode.rating
                      : _SortMode.distance),
                  child: Container(
                    margin: EdgeInsets.only(right: R.p(context, 4)),
                    padding: EdgeInsets.symmetric(horizontal: R.p(context, 10), vertical: R.p(context, 5)),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(R.r(context, 20)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _sort == _SortMode.distance
                              ? Icons.near_me_rounded
                              : Icons.star_rounded,
                          color: Colors.white,
                          size: R.w(context, 13),
                        ),
                        SizedBox(width: R.p(context, 4)),
                        Text(
                          _sort == _SortMode.distance ? 'Distance' : 'Rating',
                          style: AppTextStyles.labelSmall
                              .copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_locStatus == _LocStatus.ready)
                  IconButton(
                    icon: _isFetchingNearby
                        ? SizedBox(
                            width: R.w(context, 18),
                            height: R.h(context, 18),
                            child: const CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Icon(Icons.refresh_rounded,
                            color: Colors.white, size: R.w(context, 22)),
                    onPressed: _isFetchingNearby ? null : _fetchNearby,
                    tooltip: 'Refresh',
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: _HospitalHeader(
                  totalCount: hospitals.length,
                  mednuCount: mednuCount,
                  isLoading: isLoading,
                  locStatus: _locStatus,
                ),
              ),
            ),

            // ── Search + filters ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
                padding: EdgeInsets.fromLTRB(R.p(context, 16), 0, R.p(context, 16), R.p(context, 16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search bar
                    TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: AppTextStyles.bodyLarge,
                      decoration: InputDecoration(
                        hintText: 'Search hospitals by name or area...',
                        hintStyle: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textHint),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppColors.textHint),
                        suffixIcon: _query.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                child: Icon(Icons.close_rounded,
                                    color: AppColors.textHint, size: R.w(context, 18)),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding:
                            EdgeInsets.symmetric(vertical: R.p(context, 14)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.r(context, 14)),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.r(context, 14)),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.r(context, 14)),
                          borderSide: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              width: 1.5),
                        ),
                      ),
                    ),
                    SizedBox(height: R.h(context, 10)),

                    // Filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _HospitalFilter.values.map((chip) {
                          final isSelected = _activeFilter == chip;
                          return Padding(
                            padding: EdgeInsets.only(right: R.p(context, 8)),
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _activeFilter = chip),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: EdgeInsets.symmetric(
                                    horizontal: R.p(context, 12), vertical: R.p(context, 7)),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(R.r(context, 20)),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(chip.icon,
                                        size: R.w(context, 12),
                                        color: isSelected
                                            ? AppColors.primary
                                            : Colors.white70),
                                    SizedBox(width: R.p(context, 5)),
                                    Text(
                                      chip.label,
                                      style: AppTextStyles.labelSmall.copyWith(
                                        color: isSelected
                                            ? AppColors.primary
                                            : Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // Distance radius chips (only when location ready)
                    if (_locStatus == _LocStatus.ready) ...[
                      SizedBox(height: R.h(context, 8)),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _RadiusChip(
                              label: 'All',
                              icon: Icons.public_rounded,
                              selected: _radiusKm == 0,
                              onTap: () => setState(() => _radiusKm = 0),
                            ),
                            SizedBox(width: R.p(context, 8)),
                            for (final km in [2.0, 5.0, 10.0, 20.0]) ...[
                              _RadiusChip(
                                label: '${km.toInt()} km',
                                icon: Icons.near_me_rounded,
                                selected: _radiusKm == km,
                                onTap: () => setState(() => _radiusKm = km),
                              ),
                              SizedBox(width: R.p(context, 8)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Location denied banner ────────────────────────────────────────
            if (_locStatus == _LocStatus.denied)
              SliverToBoxAdapter(
                child: _LocationBanner(onRetry: _initLocation),
              ),

            // ── Loading skeletons ─────────────────────────────────────────────
            if (isLoading)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 12), R.p(context, 16), R.p(context, 24)),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, __) => const _HospitalCardSkeleton(),
                    childCount: 4,
                  ),
                ),
              )

            // ── Fetch error ───────────────────────────────────────────────────
            else if (_fetchError != null && _mergedHospitals == null)
              SliverFillRemaining(
                child: AppErrorState(
                  message:
                      'Unable to load nearby hospitals.\nCheck your connection and try again.',
                  onRetry: _fetchNearby,
                ),
              )

            // ── Empty state ───────────────────────────────────────────────────
            else if (hospitals.isEmpty)
              SliverFillRemaining(
                child: AppEmptyState(
                  icon: Icons.local_hospital_outlined,
                  title: _query.isNotEmpty
                      ? 'No results for "$_query"'
                      : 'No hospitals found',
                  message: _query.isNotEmpty
                      ? 'Try a different search term or clear the filter.'
                      : _radiusKm > 0
                          ? 'No hospitals within ${_radiusKm.toInt()} km. Try a larger radius.'
                          : 'Hospitals will appear once location is available.',
                  actionLabel: _query.isNotEmpty
                      ? 'Clear Search'
                      : _radiusKm > 0
                          ? 'Show All'
                          : null,
                  onAction: _query.isNotEmpty
                      ? () {
                          _searchController.clear();
                          setState(() => _query = '');
                        }
                      : _radiusKm > 0
                          ? () => setState(() => _radiusKm = 0)
                          : null,
                ),
              )

            // ── Hospital list ─────────────────────────────────────────────────
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 12), R.p(context, 16), R.p(context, 32)),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => FadeInSlide(
                      delay: Duration(milliseconds: i * 50),
                      child: _NearbyHospitalCard(
                        hospital: hospitals[i],
                        onCall: () => _call(hospitals[i].phone),
                        onDirections: () => _directions(hospitals[i]),
                      ),
                    ),
                    childCount: hospitals.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _HospitalHeader extends StatelessWidget {
  final int totalCount;
  final int mednuCount;
  final bool isLoading;
  final _LocStatus locStatus;

  const _HospitalHeader({
    required this.totalCount,
    required this.mednuCount,
    required this.isLoading,
    required this.locStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary, AppColors.secondaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30, right: -30,
            child: Container(
              width: R.w(context, 140), height: R.h(context, 140),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 30, left: -20,
            child: Container(
              width: R.w(context, 90), height: R.h(context, 90),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
              padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 56), R.p(context, 20), R.p(context, 16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: R.w(context, 44), height: R.h(context, 44),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(R.r(context, 14)),
                        ),
                        child: Icon(Icons.local_hospital_rounded,
                            color: Colors.white, size: R.w(context, 24)),
                      ),
                      SizedBox(width: R.p(context, 12)),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hospitals & Centres',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Find nearby hospitals & MedNU partners',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (locStatus == _LocStatus.ready)
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: R.p(context, 8), vertical: R.p(context, 4)),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(R.r(context, 8)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.my_location_rounded,
                                  color: Colors.white70, size: R.w(context, 11)),
                              SizedBox(width: R.p(context, 4)),
                              const Text(
                                'Near You',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (!isLoading && totalCount > 0) ...[
                    SizedBox(height: R.h(context, 14)),
                    Row(
                      children: [
                        _StatPill(
                          icon: Icons.apartment_rounded,
                          label: '$totalCount Hospitals',
                        ),
                        SizedBox(width: R.p(context, 10)),
                        if (mednuCount > 0)
                          _StatPill(
                            icon: Icons.verified_rounded,
                            label: '$mednuCount MedNU',
                            isGreen: true,
                          ),
                      ],
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
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isGreen;
  const _StatPill({required this.icon, required this.label, this.isGreen = false});

  @override
  Widget build(BuildContext context) {
    final Color bg, border, fg;
    if (isGreen) {
      bg = const Color(0xFF2E7D32).withValues(alpha: 0.25);
      border = const Color(0xFF43A047).withValues(alpha: 0.5);
      fg = const Color(0xFFA5D6A7);
    } else {
      bg = Colors.white.withValues(alpha: 0.15);
      border = Colors.white.withValues(alpha: 0.25);
      fg = Colors.white;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: R.p(context, 10), vertical: R.p(context, 5)),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.r(context, 20)),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: R.w(context, 12), color: fg),
          SizedBox(width: R.p(context, 5)),
          Text(label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fg,
              )),
        ],
      ),
    );
  }
}

// ── Radius Chip ───────────────────────────────────────────────────────────────

class _RadiusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RadiusChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: R.p(context, 12), vertical: R.p(context, 6)),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(R.r(context, 20)),
          border: Border.all(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: R.w(context, 11),
                color: selected ? AppColors.primary : Colors.white70),
            SizedBox(width: R.p(context, 4)),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.primary : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Location Banner ───────────────────────────────────────────────────────────

class _LocationBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _LocationBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 12), R.p(context, 16), 0),
      padding: EdgeInsets.symmetric(horizontal: R.p(context, 14), vertical: R.p(context, 12)),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(R.r(context, 14)),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_off_rounded,
              color: const Color(0xFFE65100), size: R.w(context, 22)),
          SizedBox(width: R.p(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Location access needed',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE65100),
                  ),
                ),
                SizedBox(height: R.h(context, 2)),
                const Text(
                  'Enable location to find hospitals near you',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Color(0xFFBF360C),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE65100),
              padding: EdgeInsets.symmetric(horizontal: R.p(context, 12), vertical: R.p(context, 6)),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Enable',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Skeleton Card ─────────────────────────────────────────────────────────────

class _HospitalCardSkeleton extends StatelessWidget {
  const _HospitalCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: R.h(context, 14)),
      child: AppShimmer(
        child: Container(
          padding: EdgeInsets.all(R.p(context, 16)),
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(R.r(context, 20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonBox(width: R.w(context, 52), height: R.h(context, 52), radius: R.r(context, 14)),
                  SizedBox(width: R.p(context, 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: double.infinity, height: R.h(context, 14), radius: R.r(context, 7)),
                        SizedBox(height: R.h(context, 8)),
                        SkeletonBox(width: R.w(context, 180), height: R.h(context, 11), radius: R.r(context, 5)),
                        SizedBox(height: R.h(context, 6)),
                        SkeletonBox(width: R.w(context, 120), height: R.h(context, 11), radius: R.r(context, 5)),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: R.h(context, 14)),
              Row(
                children: [
                  Expanded(child: SkeletonBox(width: double.infinity, height: R.h(context, 38), radius: R.r(context, 10))),
                  SizedBox(width: R.p(context, 10)),
                  Expanded(child: SkeletonBox(width: double.infinity, height: R.h(context, 38), radius: R.r(context, 10))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hospital Card ─────────────────────────────────────────────────────────────

class _NearbyHospitalCard extends StatelessWidget {
  final NearbyHospital hospital;
  final VoidCallback onCall;
  final VoidCallback onDirections;

  const _NearbyHospitalCard({
    required this.hospital,
    required this.onCall,
    required this.onDirections,
  });

  String get _distanceLabel {
    final d = hospital.distanceKm;
    if (d == null) return '';
    if (d < 1) return '${(d * 1000).round()} m';
    return '${d.toStringAsFixed(1)} km';
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }

  String get _typeBadge {
    final name = hospital.name.toLowerCase();
    if (name.contains('lab') || name.contains('diagnostic')) return 'Lab';
    if (name.contains('clinic')) return 'Clinic';
    return 'Hospital';
  }

  Color get _typeBadgeColor {
    final name = hospital.name.toLowerCase();
    if (name.contains('lab') || name.contains('diagnostic')) return AppColors.accent;
    if (name.contains('clinic')) return AppColors.secondary;
    return AppColors.primary;
  }

  Color get _accentColor => hospital.isMednu ? AppColors.success : AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: R.h(context, 14)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 20)),
        border: Border.all(
          color: hospital.isMednu
              ? const Color(0xFF43A047).withValues(alpha: 0.35)
              : context.appBorder,
          width: hospital.isMednu ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(R.r(context, 20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top accent strip
            if (hospital.isEmergency)
              Container(
                height: 3,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFB71C1C), Color(0xFFE53935)],
                  ),
                ),
              )
            else if (hospital.isMednu)
              Container(
                height: 3,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
                  ),
                ),
              ),

            Padding(
              padding: EdgeInsets.all(R.p(context, 16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Hospital icon
                      Container(
                        width: R.w(context, 52), height: R.h(context, 52),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _accentColor.withValues(alpha: 0.15),
                              _accentColor.withValues(alpha: 0.07),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(R.r(context, 14)),
                        ),
                        child: Icon(Icons.local_hospital_rounded,
                            color: _accentColor, size: R.w(context, 26)),
                      ),
                      SizedBox(width: R.p(context, 12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name + badges row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    hospital.name,
                                    style: AppTextStyles.h4.copyWith(
                                      color: context.appTextPrimary,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                SizedBox(width: R.p(context, 6)),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    // Type badge
                                    _BadgePill(
                                      label: _typeBadge,
                                      color: _typeBadgeColor,
                                    ),
                                    if (hospital.isMednu) ...[
                                      SizedBox(height: R.h(context, 4)),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: R.p(context, 7), vertical: R.p(context, 3)),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                                          ),
                                          borderRadius: BorderRadius.circular(R.r(context, 6)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.verified_rounded,
                                                color: Colors.white, size: R.w(context, 9)),
                                            SizedBox(width: R.p(context, 3)),
                                            const Text('MedNU',
                                                style: TextStyle(
                                                    fontFamily: 'Poppins',
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (hospital.isEmergency) ...[
                                      SizedBox(height: R.h(context, 4)),
                                      const _BadgePill(
                                        label: '24/7',
                                        color: AppColors.error,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),

                            // Address
                            if (hospital.address.isNotEmpty) ...[
                              SizedBox(height: R.h(context, 5)),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.location_on_rounded,
                                      size: R.w(context, 13), color: context.appTextHint),
                                  SizedBox(width: R.p(context, 3)),
                                  Expanded(
                                    child: Text(
                                      hospital.address,
                                      style: AppTextStyles.bodySmall.copyWith(
                                          color: context.appTextSecondary),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            // Distance + rating chips
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (_distanceLabel.isNotEmpty)
                                  _InfoChip(
                                    icon: Icons.near_me_rounded,
                                    label: _distanceLabel,
                                    bg: const Color(0xFFE8F5E9),
                                    fg: AppColors.success,
                                  ),
                                if (hospital.rating != null)
                                  _InfoChip(
                                    icon: Icons.star_rounded,
                                    label: hospital.userRatingsTotal != null
                                        ? '${hospital.rating!.toStringAsFixed(1)} (${_formatCount(hospital.userRatingsTotal!)})'
                                        : hospital.rating!.toStringAsFixed(1),
                                    bg: const Color(0xFFFFF8E1),
                                    fg: const Color(0xFFF57F17),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: _HospitalActionBtn(
                          icon: Icons.call_rounded,
                          label: 'Call',
                          enabled: hospital.phone.isNotEmpty,
                          filled: false,
                          color: AppColors.primary,
                          onTap: hospital.phone.isNotEmpty ? onCall : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _HospitalActionBtn(
                          icon: Icons.directions_rounded,
                          label: 'Directions',
                          enabled: true,
                          filled: true,
                          color: AppColors.primary,
                          onTap: onDirections,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Badge Pill ────────────────────────────────────────────────────────────────

class _BadgePill extends StatelessWidget {
  final String label;
  final Color color;
  const _BadgePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── Info Chip ─────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fg),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fg,
              )),
        ],
      ),
    );
  }
}

// ── Hospital Action Button ────────────────────────────────────────────────────

class _HospitalActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final bool filled;
  final Color color;
  final VoidCallback? onTap;

  const _HospitalActionBtn({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.filled,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : context.appTextHint;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          gradient: filled && enabled
              ? LinearGradient(colors: [color, color.withValues(alpha: 0.85)])
              : null,
          color: filled && !enabled ? context.appBorder : null,
          border: !filled
              ? Border.all(color: effectiveColor.withValues(alpha: 0.5))
              : null,
          borderRadius: BorderRadius.circular(11),
          boxShadow: filled && enabled
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: filled ? Colors.white : effectiveColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: filled ? Colors.white : effectiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
