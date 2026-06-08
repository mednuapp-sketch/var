import 'dart:async';
import 'dart:math' show asin, cos, pi, sin, sqrt;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/places_service.dart';
import '../providers/location_provider.dart';
import '../../location/providers/saved_addresses_provider.dart';
import '../../location/models/saved_address.dart';
import '../../location/screens/map_location_picker_screen.dart';

class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen>
    with TickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();

  List<PlacesSuggestion> _results = [];
  bool _searching = false;
  bool _loadingDetails = false;
  Timer? _debounce;
  Position? _myPos;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  static const _popularCities = [
    ('Hyderabad', 17.3850, 78.4867),
    ('Visakhapatnam', 17.6868, 83.2185),
    ('Mumbai', 19.0760, 72.8777),
    ('Delhi', 28.6139, 77.2090),
    ('Bangalore', 12.9716, 77.5946),
    ('Chennai', 13.0827, 80.2707),
    ('Pune', 18.5204, 73.8567),
    ('Kolkata', 22.5726, 88.3639),
    ('Ahmedabad', 23.0225, 72.5714),
    ('Jaipur', 26.9124, 75.7873),
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _searchCtrl.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _fetchMyPosition();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _debounce?.cancel();
    _searchCtrl.removeListener(_onChanged);
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchMyPosition() async {
    try {
      final ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) return;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 5),
      );
      if (mounted) setState(() => _myPos = pos);
    } catch (_) {}
  }

  void _onChanged() {
    final q = _searchCtrl.text.trim();
    _debounce?.cancel();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce =
        Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (!mounted) return;
    final suggestions = await placesService.autocomplete(
      q,
      lat: _myPos?.latitude,
      lng: _myPos?.longitude,
    );
    if (!mounted) return;
    setState(() {
      _results = suggestions;
      _searching = false;
    });
  }

  String _distLabel(double lat, double lng) {
    if (_myPos == null) return '';
    const r = 6371.0;
    final dLat = (lat - _myPos!.latitude) * pi / 180;
    final dLng = (lng - _myPos!.longitude) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_myPos!.latitude * pi / 180) *
            cos(lat * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final km = r * 2 * asin(sqrt(a));
    if (km < 1) return '${(km * 1000).toInt()} m';
    if (km < 10) return '${km.toStringAsFixed(1)} km';
    return '${km.toInt()} km';
  }

  Future<void> _pickSuggestion(PlacesSuggestion s) async {
    _focusNode.unfocus();
    setState(() => _loadingDetails = true);
    try {
      final details = await placesService.details(s.placeId);
      if (!mounted) return;
      if (details != null) {
        final suggestion = LocationSuggestion(
          shortName: s.mainText.isNotEmpty ? s.mainText : s.fullText.split(',').first.trim(),
          displayName: s.fullText,
          lat: details.lat,
          lng: details.lng,
        );
        await ref.read(locationProvider.notifier).setFromSuggestion(suggestion);
        // Update precise address with Places details
        ref.read(locationProvider.notifier).applyPlacesDetails(details);
      } else {
        // Fallback: use the text only
        ref.read(locationProvider.notifier).setCity(s.mainText);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingDetails = false);
        Navigator.pop(context);
      }
    }
  }

  void _pickCity(String city, double lat, double lng) {
    ref.read(locationProvider.notifier).setFromSuggestion(LocationSuggestion(
      shortName: city,
      displayName: city,
      lat: lat,
      lng: lng,
    ));
    Navigator.pop(context);
  }

  void _pickSavedAddress(SavedAddress addr) {
    ref.read(locationProvider.notifier).setFromSuggestion(
          LocationSuggestion(
            shortName: addr.displayLabel,
            displayName: addr.formattedAddress,
            lat: addr.lat,
            lng: addr.lng,
          ),
        );
    Navigator.pop(context);
  }

  void _useCurrentLocation() async {
    _focusNode.unfocus();
    await ref.read(locationProvider.notifier).fetchCurrent();
    if (mounted) Navigator.pop(context);
  }

  void _openMapPicker() async {
    _focusNode.unfocus();
    final locState = ref.read(locationProvider);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(
          initialLat: locState.lat,
          initialLng: locState.lng,
        ),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  bool get _showResults => _searchCtrl.text.trim().length >= 2;

  @override
  Widget build(BuildContext context) {
    final locState = ref.watch(locationProvider);
    final savedAsync = ref.watch(savedAddressesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF8F9FE);
    final divColor =
        isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade100;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top bar ──────────────────────────────────
                Container(
                  color: isDark ? const Color(0xFF0F1923) : Colors.white,
                  padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          'Set Your Location',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Search bar ───────────────────────────────
                Container(
                  color: isDark ? const Color(0xFF0F1923) : Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1A2535)
                          : const Color(0xFFF2F3F7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _focusNode.hasFocus
                            ? AppColors.primary.withOpacity(0.6)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 14),
                        Icon(
                          Icons.search_rounded,
                          color: _focusNode.hasFocus
                              ? AppColors.primary
                              : Colors.grey.shade400,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            focusNode: _focusNode,
                            textInputAction: TextInputAction.search,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search area, street, landmark…',
                              hintStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                color: Colors.grey.shade400,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_searchCtrl.text.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchCtrl.clear();
                              _debounce?.cancel();
                              setState(() {
                                _results = [];
                                _searching = false;
                              });
                              _focusNode.requestFocus();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Icon(Icons.cancel_rounded,
                                  color: Colors.grey.shade400, size: 18),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                Divider(height: 1, color: divColor),

                // ── Body ─────────────────────────────────────
                Expanded(
                  child: _showResults
                      ? _buildSearchResults(isDark, divColor)
                      : _buildDefaultContent(
                          locState, savedAsync, isDark, divColor),
                ),
              ],
            ),
          ),
        ),

        // Global loading overlay while fetching place details
        if (_loadingDetails)
          Container(
            color: Colors.black.withOpacity(0.3),
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
      ],
    );
  }

  // ── Search results ─────────────────────────────────────
  Widget _buildSearchResults(bool isDark, Color divColor) {
    if (_searching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            Text('Searching…',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No results found',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('Try a different area or landmark',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: divColor, indent: 72),
      itemBuilder: (_, i) {
        final s = _results[i];
        return _PlacesTile(
          suggestion: s,
          onTap: () => _pickSuggestion(s),
          isDark: isDark,
        );
      },
    );
  }

  // ── Default content ────────────────────────────────────
  Widget _buildDefaultContent(
    LocationState locState,
    AsyncValue<List<SavedAddress>> savedAsync,
    bool isDark,
    Color divColor,
  ) {
    final recent = locState.recentLocations;
    final saved = savedAsync.valueOrNull ?? [];

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── Use current location ───────────────────────
        _CurrentLocationTile(
          locState: locState,
          pulseAnim: _pulseAnim,
          isDark: isDark,
          onTap: _useCurrentLocation,
        ),

        // ── Pick on Map ───────────────────────────────
        _PickOnMapTile(isDark: isDark, onTap: _openMapPicker),

        Divider(height: 1, color: divColor),

        // ── Saved addresses ───────────────────────────
        if (saved.isNotEmpty) ...[
          _SectionHeader(
            title: 'SAVED ADDRESSES',
            isDark: isDark,
            trailing: TextButton(
              onPressed: () => context.push('/address-book'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Manage',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          ...saved.map((addr) => _SavedAddressTile(
                address: addr,
                isDark: isDark,
                onTap: () => _pickSavedAddress(addr),
              )),
          Divider(height: 1, color: divColor),
        ],

        // ── Recent searches ───────────────────────────
        if (recent.isNotEmpty) ...[
          _SectionHeader(
            title: 'RECENT SEARCHES',
            isDark: isDark,
            trailing: GestureDetector(
              onTap: () => ref.read(locationProvider.notifier).clearRecent(),
              child: Text(
                'Clear all',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.grey.shade500),
              ),
            ),
          ),
          ...recent.map((s) => _RecentTile(
                suggestion: s,
                distLabel: _distLabel(s.lat, s.lng),
                onTap: () {
                  ref.read(locationProvider.notifier).setFromSuggestion(s);
                  Navigator.pop(context);
                },
                isDark: isDark,
              )),
          Divider(height: 1, color: divColor),
        ],

        // ── Popular cities ────────────────────────────
        const _SectionHeader(title: 'POPULAR CITIES'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _popularCities.map((c) {
              final (city, lat, lng) = c;
              final isActive = locState.displayName == city;
              return GestureDetector(
                onTap: () => _pickCity(city, lat, lng),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primary
                        : isDark
                            ? const Color(0xFF1A2535)
                            : const Color(0xFFF2F3F7),
                    borderRadius: BorderRadius.circular(24),
                    border: isActive
                        ? null
                        : Border.all(
                            color: isDark
                                ? Colors.white.withOpacity(0.08)
                                : Colors.grey.shade200,
                          ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_city_rounded,
                        size: 13,
                        color: isActive ? Colors.white : Colors.grey.shade500,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        city,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? Colors.white
                              : isDark
                                  ? const Color(0xFFB0BEC5)
                                  : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ── Section header ────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    this.isDark = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: 1.0,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ── Pick on Map tile ──────────────────────────────────────
class _PickOnMapTile extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;

  const _PickOnMapTile({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.map_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pick on Map',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Drag pin to set exact location',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Saved address tile ────────────────────────────────────
class _SavedAddressTile extends StatelessWidget {
  final SavedAddress address;
  final bool isDark;
  final VoidCallback onTap;

  const _SavedAddressTile({
    required this.address,
    required this.isDark,
    required this.onTap,
  });

  IconData get _icon {
    switch (address.label) {
      case 'home':
        return Icons.home_rounded;
      case 'work':
        return Icons.work_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  Color get _iconBg {
    switch (address.label) {
      case 'home':
        return const Color(0xFF43A047);
      case 'work':
        return const Color(0xFF1E88E5);
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _iconBg.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon, color: _iconBg, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        address.displayLabel,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (address.isDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'DEFAULT',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address.formattedAddress,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Current location tile ─────────────────────────────────
class _CurrentLocationTile extends StatelessWidget {
  final LocationState locState;
  final Animation<double> pulseAnim;
  final bool isDark;
  final VoidCallback onTap;

  const _CurrentLocationTile({
    required this.locState,
    required this.pulseAnim,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDetecting = locState.isDetecting;

    return InkWell(
      onTap: isDetecting ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isDetecting)
                    AnimatedBuilder(
                      animation: pulseAnim,
                      builder: (_, __) => Transform.scale(
                        scale: pulseAnim.value,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: isDetecting
                          ? null
                          : const LinearGradient(
                              colors: [AppColors.primary, AppColors.secondary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: isDetecting
                          ? AppColors.primary.withOpacity(0.2)
                          : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isDetecting
                          ? Icons.gps_fixed_rounded
                          : Icons.my_location_rounded,
                      color: isDetecting ? AppColors.primary : Colors.white,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isDetecting
                        ? 'Detecting your location…'
                        : 'Use current location',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isDetecting
                        ? 'Getting your GPS location'
                        : locState.status == LocationStatus.set &&
                                locState.hasCoordinates
                            ? locState.preciseAddress?.formatted ??
                                locState.fullAddress
                            : 'Using your device GPS',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isDetecting)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              )
            else
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Google Places result tile ─────────────────────────────
class _PlacesTile extends StatelessWidget {
  final PlacesSuggestion suggestion;
  final VoidCallback onTap;
  final bool isDark;

  const _PlacesTile({
    required this.suggestion,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = isDark ? const Color(0xFF4A6080) : Colors.grey.shade500;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.location_on_outlined,
                  color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.mainText.isNotEmpty
                        ? suggestion.mainText
                        : suggestion.fullText.split(',').first.trim(),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (suggestion.secondaryText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      suggestion.secondaryText,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.north_west_rounded,
                size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// ── Recent search tile ────────────────────────────────────
class _RecentTile extends StatelessWidget {
  final LocationSuggestion suggestion;
  final String distLabel;
  final VoidCallback onTap;
  final bool isDark;

  const _RecentTile({
    required this.suggestion,
    required this.distLabel,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              child: distLabel.isNotEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          distLabel.split(' ').first,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        if (distLabel.contains(' '))
                          Text(
                            distLabel.split(' ').last,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              color: Colors.grey.shade400,
                            ),
                          ),
                      ],
                    )
                  : const SizedBox(),
            ),
            Icon(Icons.history_rounded,
                color: Colors.grey.shade400, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.shortName,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (suggestion.displayName != suggestion.shortName) ...[
                    const SizedBox(height: 2),
                    Text(
                      suggestion.displayName,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.north_west_rounded,
                size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
