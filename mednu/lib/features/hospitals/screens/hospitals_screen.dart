import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../services/hospital_service.dart';
import '../services/nearby_hospital_service.dart';

enum _LocStatus { idle, loading, denied, ready }

class HospitalsScreen extends StatefulWidget {
  final String? initialQuery;
  const HospitalsScreen({super.key, this.initialQuery});

  @override
  State<HospitalsScreen> createState() => _HospitalsScreenState();
}

class _HospitalsScreenState extends State<HospitalsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

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
  double _radiusKm = 0; // 0 = all

  static const _blue = Color(0xFF1565C0);

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
      // Re-merge if we already have Google data without re-fetching
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
    _mednuSub?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
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
    final src = _mergedHospitals ??
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

    return src.where((h) {
      final matchesSearch = _query.isEmpty ||
          h.name.toLowerCase().contains(_query) ||
          h.address.toLowerCase().contains(_query);
      final matchesRadius = _radiusKm == 0 ||
          h.distanceKm == null ||
          h.distanceKm! <= _radiusKm;
      return matchesSearch && matchesRadius;
    }).toList();
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
      // Lat/lng available from Google Places — opens Google Maps navigation to exact location
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=${h.lat},${h.lng}');
    } else if (h.mapsUrl.isNotEmpty) {
      // Admin-stored maps URL for MedNu hospitals without a Google match
      uri = Uri.parse(h.mapsUrl);
    } else {
      // Last resort: search by hospital name
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(h.name)}');
    }
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
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
    final isLocLoading = _locStatus == _LocStatus.loading ||
        _locStatus == _LocStatus.idle;
    final isNearbyLoading = _isFetchingNearby && _mergedHospitals == null;
    final isLoading = isLocLoading || isNearbyLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── App bar ─────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 210,
            backgroundColor: _blue,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => context.pop(),
            ),
            actions: [
              if (_locStatus == _LocStatus.ready)
                IconButton(
                  icon: _isFetchingNearby
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 22),
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

          // ── Search + filter ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: _blue,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (v) =>
                        setState(() => _query = v.toLowerCase()),
                    style:
                        const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search hospitals by name or area...',
                      hintStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: AppColors.textHint),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.textHint),
                      suffixIcon: _query.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              child: const Icon(Icons.close_rounded,
                                  color: AppColors.textHint, size: 18),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: _blue.withValues(alpha: 0.3), width: 1.5),
                      ),
                    ),
                  ),
                  // Distance filter chips (only when location is ready)
                  if (_locStatus == _LocStatus.ready) ...[
                    const SizedBox(height: 10),
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
                          const SizedBox(width: 8),
                          for (final km in [2.0, 5.0, 10.0, 20.0]) ...[
                            _RadiusChip(
                              label: '${km.toInt()} km',
                              icon: Icons.near_me_rounded,
                              selected: _radiusKm == km,
                              onTap: () => setState(() => _radiusKm = km),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Location denied banner ───────────────────────────────────────
          if (_locStatus == _LocStatus.denied)
            SliverToBoxAdapter(
              child: _LocationBanner(onRetry: _initLocation),
            ),

          // ── Loading skeletons ─────────────────────────────────────────
          if (isLoading)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, __) => const _HospitalCardSkeleton(),
                  childCount: 6,
                ),
              ),
            )

          // ── Fetch error ────────────────────────────────────────────────
          else if (_fetchError != null && _mergedHospitals == null)
            SliverFillRemaining(
              child: AppErrorState(
                message:
                    'Unable to load nearby hospitals.\nCheck your connection and try again.',
                onRetry: _fetchNearby,
              ),
            )

          // ── Empty state ────────────────────────────────────────────────
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

          // ── Hospital list ─────────────────────────────────────────────
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => FadeInSlide(
                    delay: Duration(milliseconds: i * 55),
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

  static const _blue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D47A1), _blue, Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30, right: -30,
            child: Container(
              width: 140, height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 30, left: -20,
            child: Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.local_hospital_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
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
                              'Find nearby hospitals & MedNu partners',
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.my_location_rounded,
                                  color: Colors.white70, size: 11),
                              SizedBox(width: 4),
                              Text(
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
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _StatChip(
                          icon: Icons.apartment_rounded,
                          label: '$totalCount Hospitals',
                        ),
                        const SizedBox(width: 10),
                        if (mednuCount > 0)
                          _StatChip(
                            icon: Icons.verified_rounded,
                            label: '$mednuCount MedNu',
                            isGreen: true,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isGreen;

  const _StatChip({
    required this.icon,
    required this.label,
    this.isGreen = false,
  });

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Radius filter chip ──────────────────────────────────────────────────────

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

  static const _blue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              selected ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 11,
                color: selected ? _blue : Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? _blue : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Location denied banner ──────────────────────────────────────────────────

class _LocationBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _LocationBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off_rounded,
              color: Color(0xFFE65100), size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location access needed',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE65100),
                  ),
                ),
                SizedBox(height: 2),
                Text(
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

// ── Hospital card skeleton ──────────────────────────────────────────────────

class _HospitalCardSkeleton extends StatelessWidget {
  const _HospitalCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: const AppShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SkeletonBox(width: 52, height: 52, radius: 14),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(
                          width: double.infinity, height: 14, radius: 4),
                      SizedBox(height: 6),
                      SkeletonBox(width: 200, height: 11, radius: 4),
                      SizedBox(height: 4),
                      SkeletonBox(width: 140, height: 11, radius: 4),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                    child: SkeletonBox(
                        width: double.infinity, height: 38, radius: 10)),
                SizedBox(width: 10),
                Expanded(
                    child: SkeletonBox(
                        width: double.infinity, height: 38, radius: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Nearby hospital card ────────────────────────────────────────────────────

class _NearbyHospitalCard extends StatelessWidget {
  final NearbyHospital hospital;
  final VoidCallback onCall;
  final VoidCallback onDirections;

  const _NearbyHospitalCard({
    required this.hospital,
    required this.onCall,
    required this.onDirections,
  });

  static const _blue = Color(0xFF1565C0);
  static const _green = Color(0xFF2E7D32);

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

  @override
  Widget build(BuildContext context) {
    final accentColor = hospital.isMednu ? _green : _blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hospital.isMednu
              ? const Color(0xFF43A047).withValues(alpha: 0.35)
              : AppColors.divider,
          width: hospital.isMednu ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accentColor.withValues(alpha: 0.15),
                              accentColor.withValues(alpha: 0.07),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.local_hospital_rounded,
                          color: accentColor,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name row + badges
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    hospital.name,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1A1A2E),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (hospital.isMednu)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF2E7D32),
                                              Color(0xFF43A047)
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.verified_rounded,
                                                color: Colors.white, size: 9),
                                            SizedBox(width: 3),
                                            Text(
                                              'MedNu',
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (hospital.isEmergency) ...[
                                      if (hospital.isMednu)
                                        const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFEBEE),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          '🚨 24/7',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFFD32F2F),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),

                            // Address
                            if (hospital.address.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.location_on_rounded,
                                      size: 13, color: AppColors.textHint),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      hospital.address,
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                        height: 1.4,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            // Distance + Rating + Phone row
                            const SizedBox(height: 7),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (_distanceLabel.isNotEmpty)
                                  _InfoChip(
                                    icon: Icons.near_me_rounded,
                                    label: _distanceLabel,
                                    bg: const Color(0xFFE3F2FD),
                                    fg: const Color(0xFF1565C0),
                                  ),
                                if (hospital.rating != null)
                                  _InfoChip(
                                    icon: Icons.star_rounded,
                                    label: hospital.userRatingsTotal != null
                                        ? '${hospital.rating!.toStringAsFixed(1)} (${_formatCount(hospital.userRatingsTotal!)})'
                                        : hospital.rating!
                                            .toStringAsFixed(1),
                                    bg: const Color(0xFFFFF8E1),
                                    fg: const Color(0xFFF57F17),
                                  ),
                                if (hospital.phone.isNotEmpty)
                                  _InfoChip(
                                    icon: Icons.phone_rounded,
                                    label: hospital.phone,
                                    bg: const Color(0xFFF3F4F6),
                                    fg: AppColors.textSecondary,
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
                        child: _ActionButton(
                          icon: Icons.call_rounded,
                          label: 'Call',
                          enabled: hospital.phone.isNotEmpty,
                          filled: false,
                          color: _blue,
                          onTap: hospital.phone.isNotEmpty ? onCall : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.directions_rounded,
                          label: 'Directions',
                          enabled: true,
                          filled: true,
                          color: _blue,
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

// ── Info chip ───────────────────────────────────────────────────────────────

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
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action button ───────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final bool filled;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.filled,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : AppColors.textHint;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          gradient: filled && enabled
              ? LinearGradient(
                  colors: [color, color.withValues(alpha: 0.8)],
                )
              : null,
          color: filled && !enabled ? AppColors.border : null,
          border: !filled
              ? Border.all(
                  color: effectiveColor.withValues(alpha: 0.5))
              : null,
          borderRadius: BorderRadius.circular(11),
          boxShadow: filled && enabled
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: filled ? Colors.white : effectiveColor,
            ),
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
