import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/distance.dart';
import '../../../core/utils/r.dart';
import '../../home/providers/location_provider.dart';

/// Provider-first equipment browsing — pick a nearby vendor, then see that
/// vendor's own equipment (same shape as Pharmacy's provider list →
/// `MedicineScreen(pharmacyId: ...)`). `equipment_vendors` is admin-managed
/// (see mednu-admin), so unlike pharmacies/labs there is no self-serve
/// partner registration behind this list yet — it starts empty until an
/// admin adds real vendors.
class EquipmentVendorsScreen extends ConsumerStatefulWidget {
  const EquipmentVendorsScreen({super.key});

  @override
  ConsumerState<EquipmentVendorsScreen> createState() => _EquipmentVendorsScreenState();
}

class _EquipmentVendorsScreenState extends ConsumerState<EquipmentVendorsScreen> {
  String _search = '';

  Map<String, Object?> _toCard(QueryDocumentSnapshot<Map<String, dynamic>> doc, double? myLat, double? myLng) {
    final d = doc.data();
    final lat = (d['lat'] as num?)?.toDouble();
    final lng = (d['lng'] as num?)?.toDouble();
    double? distance;
    if (myLat != null && myLng != null && lat != null && lng != null) {
      distance = distanceKm(myLat, myLng, lat, lng);
    }
    return {
      'id': doc.id,
      'name': (d['name'] as String?) ?? 'Equipment Vendor',
      'city': (d['city'] as String?) ?? '',
      'phone': (d['phone'] as String?) ?? '',
      'distanceKm': distance,
    };
  }

  @override
  Widget build(BuildContext context) {
    final myLocation = ref.watch(locationProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: AppSpacing.headerHeight(context),
            backgroundColor: AppColors.primaryDark,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
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
                                Icon(Icons.medical_services_rounded, color: Colors.white, size: AppSpacing.headerIconSize(context)),
                                SizedBox(height: AppSpacing.headerIconGap(context)),
                                const Text('Equipment Vendors', style: AppTextStyles.onPrimaryH2),
                                const Text('Rent or buy from a vendor near you', style: AppTextStyles.onPrimaryBody),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.all(R.p(context, 16)),
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Search vendors or city...',
                      prefixIcon: Icon(Icons.search_rounded, color: context.appTextHint),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close_rounded, color: context.appTextHint, size: 18),
                              onPressed: () => setState(() => _search = ''),
                            )
                          : null,
                      filled: true,
                      fillColor: context.appSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(R.r(context, 14)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('equipment_vendors')
                      .where('isEnabled', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snap) {
                    final q = _search.trim().toLowerCase();
                    final all = (snap.data?.docs ?? const [])
                        .map((d) => _toCard(d, myLocation.lat, myLocation.lng))
                        .toList();

                    final nearby = myLocation.lat != null && myLocation.lng != null
                        ? all.where((v) {
                            final d = v['distanceKm'] as double?;
                            return d == null || d <= nearbyRadiusKm;
                          }).toList()
                        : all;
                    nearby.sort((a, b) {
                      final da = a['distanceKm'] as double?;
                      final db = b['distanceKm'] as double?;
                      if (da == null && db == null) return 0;
                      if (da == null) return 1;
                      if (db == null) return -1;
                      return da.compareTo(db);
                    });
                    final filtered = q.isEmpty
                        ? nearby
                        : nearby.where((v) =>
                            (v['name'] as String).toLowerCase().contains(q) ||
                            (v['city'] as String).toLowerCase().contains(q)).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 8), R.p(context, 16), R.p(context, 12)),
                          child: Text(
                            q.isNotEmpty ? '${filtered.length} result${filtered.length == 1 ? '' : 's'} for "$_search"' : 'Nearby Vendors',
                            style: AppTextStyles.h4,
                          ),
                        ),
                        if (!snap.hasData)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(children: [
                              Icon(Icons.medical_services_outlined, size: 48, color: context.appTextHint),
                              const SizedBox(height: 12),
                              Text(
                                _search.isNotEmpty ? 'No vendor found for "$_search"' : 'No equipment vendors nearby yet',
                                style: AppTextStyles.bodyMedium.copyWith(color: context.appTextHint),
                                textAlign: TextAlign.center,
                              ),
                            ]),
                          )
                        else
                          ...filtered.map((v) => _VendorCard(vendor: v)),
                        SizedBox(height: R.h(context, 40)),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VendorCard extends StatelessWidget {
  final Map<String, Object?> vendor;
  const _VendorCard({required this.vendor});

  @override
  Widget build(BuildContext context) {
    final v = vendor;
    final distanceKm = v['distanceKm'] as double?;

    return Container(
      margin: EdgeInsets.fromLTRB(R.p(context, 16), 0, R.p(context, 16), R.p(context, 12)),
      padding: EdgeInsets.all(R.p(context, 16)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 18)),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: R.w(context, 52),
                height: R.w(context, 52),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(R.r(context, 14)),
                ),
                child: Icon(Icons.medical_services_rounded, color: AppColors.primary, size: R.w(context, 28)),
              ),
              SizedBox(width: R.p(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v['name'] as String, style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    SizedBox(height: R.h(context, 4)),
                    Row(children: [
                      Icon(Icons.location_on_outlined, size: R.w(context, 13), color: context.appTextHint),
                      SizedBox(width: R.p(context, 3)),
                      Flexible(
                        child: Text(
                          distanceKm != null
                              ? '${distanceKm.toStringAsFixed(1)} km away'
                              : (v['city'] as String).isNotEmpty
                                  ? v['city'] as String
                                  : 'Location not set',
                          style: AppTextStyles.labelSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: R.h(context, 12)),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: Icon(Icons.medical_services_rounded, size: R.w(context, 16)),
              label: const Text('View Equipment'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => context.push(
                AppRoutes.equipmentMenu.replaceFirst(':id', v['id'] as String),
                extra: {'vendorName': v['name']},
              ),
            ),
          ),
          SizedBox(height: R.h(context, 8)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(Icons.call_rounded, size: R.w(context, 16)),
                  label: const Text('Call'),
                  onPressed: (v['phone'] as String).isEmpty
                      ? null
                      : () => launchUrl(Uri.parse('tel:${v['phone']}'), mode: LaunchMode.externalApplication),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
