import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../services/hospital_service.dart';
import '../../../core/widgets/ux_widgets.dart';

class HospitalsScreen extends StatefulWidget {
  const HospitalsScreen({super.key});

  @override
  State<HospitalsScreen> createState() => _HospitalsScreenState();
}

class _HospitalsScreenState extends State<HospitalsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _call(String phone) async {
    final clean = phone.replaceAll(RegExp(r'\s'), '');
    if (clean.isEmpty) return;
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _directions(String mapsUrl, String name) async {
    final Uri uri;
    if (mapsUrl.isNotEmpty) {
      uri = Uri.parse(mapsUrl);
    } else {
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(name)}');
    }
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Hospitals & Centres'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search hospitals...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Hospital>>(
              stream: HospitalService.stream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ListView(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: List.generate(6, (_) => const SkeletonListTile()),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 52, color: AppColors.textHint),
                          const SizedBox(height: 12),
                          Text('Could not load hospitals', style: AppTextStyles.h4),
                          const SizedBox(height: 6),
                          Text('Check your connection and try again',
                              style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ),
                  );
                }

                var hospitals = snapshot.data ?? [];
                if (_query.isNotEmpty) {
                  hospitals = hospitals
                      .where((h) =>
                          h.name.toLowerCase().contains(_query) ||
                          h.address.toLowerCase().contains(_query))
                      .toList();
                }

                if (hospitals.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1565C0).withValues(alpha:0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.local_hospital_outlined,
                                size: 40, color: Color(0xFF1565C0)),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _query.isNotEmpty
                                ? 'No results for "$_query"'
                                : 'No hospitals listed yet',
                            style: AppTextStyles.h4,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _query.isNotEmpty
                                ? 'Try a different search term'
                                : 'Hospitals will appear here once added by admin',
                            style: AppTextStyles.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  color: const Color(0xFF1565C0),
                  onRefresh: () async {},
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: hospitals.length,
                    itemBuilder: (_, i) {
                      final h = hospitals[i];
                      return _HospitalCard(
                        hospital: h,
                        onCall: () => _call(h.phone),
                        onDirections: () => _directions(h.mapsUrl, h.name),
                      );
                    },
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

class _HospitalCard extends StatelessWidget {
  final Hospital hospital;
  final VoidCallback onCall;
  final VoidCallback onDirections;

  const _HospitalCard({
    required this.hospital,
    required this.onCall,
    required this.onDirections,
  });

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF1565C0);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.local_hospital_rounded, color: color, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            hospital.name,
                            style: AppTextStyles.labelLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hospital.isEmergency) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935).withValues(alpha:0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '🚨 Emergency',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFE53935),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (hospital.address.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 13, color: AppColors.textHint),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              hospital.address,
                              style: AppTextStyles.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (hospital.phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.phone_outlined,
                              size: 13, color: AppColors.textHint),
                          const SizedBox(width: 3),
                          Text(hospital.phone, style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.call_rounded, size: 16),
                  label: const Text('Call'),
                  onPressed: hospital.phone.isNotEmpty ? onCall : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: const BorderSide(color: color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.directions_rounded, size: 16),
                  label: const Text('Directions'),
                  onPressed: onDirections,
                  style: ElevatedButton.styleFrom(backgroundColor: color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
