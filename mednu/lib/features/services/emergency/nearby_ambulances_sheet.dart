import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../ambulance/ambulance_data_service.dart';

const _kTeal = Color(0xFF00838F);
const _kTealLight = Color(0xFF00ACC1);

const List<double> _radiusOptions = [5, 10, 25, 50];

/// Bottom sheet that finds admin-managed ambulance services within a
/// user-selected radius of the device's current GPS location.
class NearbyAmbulancesSheet extends StatefulWidget {
  const NearbyAmbulancesSheet({super.key});

  @override
  State<NearbyAmbulancesSheet> createState() => _NearbyAmbulancesSheetState();
}

class _NearbyAmbulancesSheetState extends State<NearbyAmbulancesSheet> {
  double _radiusKm = 10;
  Position? _position;
  bool _locating = true;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
  }

  Future<void> _fetchLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locating = false;
          _locationError = 'Location services are disabled.';
        });
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() {
          _locating = false;
          _locationError = 'Location permission denied.';
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(() {
        _position = pos;
        _locating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationError = 'Could not detect your location.';
      });
    }
  }

  double _distanceKm(AmbulanceEntry a) {
    if (_position == null || !a.hasLocation) return double.infinity;
    return Geolocator.distanceBetween(
          _position!.latitude,
          _position!.longitude,
          a.latitude,
          a.longitude,
        ) /
        1000;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _kTeal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.emergency_share_rounded,
                      color: _kTeal, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Nearby Ambulances', style: AppTextStyles.h4),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text('Radius: ', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.black54)),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _radiusOptions.map((r) {
                        final selected = r == _radiusKm;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('${r.toInt()} km'),
                            selected: selected,
                            onSelected: (_) => setState(() => _radiusKm = r),
                            selectedColor: _kTeal.withValues(alpha: 0.15),
                            labelStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected ? _kTeal : Colors.black54,
                            ),
                            side: BorderSide(
                              color: selected ? _kTeal : Colors.grey.shade300,
                            ),
                            backgroundColor: Colors.white,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Flexible(child: _buildBody()),
          SizedBox(height: bottom + 8),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_locating) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(color: _kTeal, strokeWidth: 3),
        ),
      );
    }

    return StreamBuilder<List<AmbulanceEntry>>(
      stream: AmbulanceDataService.availableStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(color: _kTeal, strokeWidth: 3),
            ),
          );
        }
        if (snapshot.hasError) {
          return _message(Icons.wifi_off_rounded,
              'Could not load ambulance services. Check your connection.');
        }

        final all = snapshot.data ?? [];

        if (_locationError != null) {
          return _message(Icons.location_off_rounded, _locationError!,
              retryLabel: 'Retry', onRetry: _fetchLocation);
        }

        final withinRadius = all.where((a) => a.hasLocation && _distanceKm(a) <= _radiusKm).toList()
          ..sort((a, b) => _distanceKm(a).compareTo(_distanceKm(b)));

        if (withinRadius.isEmpty) {
          return _message(Icons.info_outline_rounded,
              'No available ambulances within ${_radiusKm.toInt()} km. Try a larger radius.');
        }

        return ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          itemCount: withinRadius.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _AmbulanceCard(
            entry: withinRadius[i],
            distanceKm: _distanceKm(withinRadius[i]),
          ),
        );
      },
    );
  }

  Widget _message(IconData icon, String text,
      {String? retryLabel, VoidCallback? onRetry}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        children: [
          Icon(icon, color: context.appTextHint, size: 32),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 13, color: context.appTextHint),
          ),
          if (retryLabel != null && onRetry != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(foregroundColor: _kTeal),
              child: Text(retryLabel, style: const TextStyle(fontFamily: 'Poppins')),
            ),
          ],
        ],
      ),
    );
  }
}

class _AmbulanceCard extends StatelessWidget {
  final AmbulanceEntry entry;
  final double distanceKm;
  const _AmbulanceCard({required this.entry, required this.distanceKm});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_kTeal, _kTealLight]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name.isNotEmpty ? entry.name : 'Ambulance Service',
                    style: AppTextStyles.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kTeal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(entry.type,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: _kTeal)),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.near_me_rounded, size: 12, color: context.appTextHint),
                  const SizedBox(width: 2),
                  Text('${distanceKm.toStringAsFixed(1)} km away',
                      style: AppTextStyles.bodySmall),
                ]),
                if (entry.serviceArea.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(entry.serviceArea,
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.call_rounded, color: _kTeal),
            onPressed: () async {
              final clean = entry.phone.replaceAll(RegExp(r'\s'), '');
              if (clean.isNotEmpty) await launchUrl(Uri.parse('tel:$clean'));
            },
          ),
        ],
      ),
    );
  }
}
