import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../home/providers/location_provider.dart';

class PharmacyScreen extends ConsumerStatefulWidget {
  const PharmacyScreen({super.key});

  @override
  ConsumerState<PharmacyScreen> createState() => _PharmacyScreenState();
}

class _PharmacyScreenState extends ConsumerState<PharmacyScreen> {
  String _search = '';
  String _cityFilter = '';

  /// Maps one `pharmacy_profiles/{uid}` doc into the shape `_PharmacyCard`
  /// renders. Only real, registered data is ever shown here — no fabricated
  /// opening hours or "Open now" status, since pharmacies never submit that
  /// at registration; delivery availability and stocked categories are the
  /// real signals collected instead.
  Map<String, Object?> _toCard(QueryDocumentSnapshot<Map<String, dynamic>> doc, double? myLat, double? myLng) {
    final d = doc.data();
    final lat = (d['latitude'] as num?)?.toDouble();
    final lng = (d['longitude'] as num?)?.toDouble();
    double? distanceKm;
    if (myLat != null && myLng != null && lat != null && lng != null) {
      distanceKm = Geolocator.distanceBetween(myLat, myLng, lat, lng) / 1000;
    }
    return {
      'id': doc.id,
      'name': (d['name'] as String?) ?? 'Pharmacy',
      'address': (d['address'] as String?) ?? '',
      'city': (d['city'] as String?) ?? '',
      'phone': (d['phone'] as String?) ?? '',
      'rating': ((d['rating'] as num?) ?? 0).toDouble(),
      'totalReviews': (d['totalReviews'] as int?) ?? 0,
      'deliveryAvailable': (d['deliveryAvailable'] as bool?) ?? false,
      'categories': ((d['categoriesOffered'] as List?) ?? const []).whereType<String>().toList(),
      'photoUrl': (d['photoUrl'] as String?) ?? '',
      'distanceKm': distanceKm,
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
            backgroundColor: const Color(0xFF2E7D32),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.medicineGrad,
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
                                Icon(Icons.local_pharmacy_rounded, color: Colors.white, size: AppSpacing.headerIconSize(context)),
                                SizedBox(height: AppSpacing.headerIconGap(context)),
                                const Text('Pharmacy & Medical Shops', style: AppTextStyles.onPrimaryH2),
                                const Text('Find nearby pharmacies • Order online', style: AppTextStyles.onPrimaryBody),
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
                // ── Search ──────────────────────────────────────────────────
                Padding(
                  padding: EdgeInsets.all(R.p(context, 16)),
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Search medicines or pharmacies...',
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

                // ── City filter ────────────────────────────────────────────
                // Independent of the device's live/set location — lets a
                // patient browse pharmacies in any city regardless of where
                // they currently are, instead of only the 15km GPS radius.
                Padding(
                  padding: EdgeInsets.fromLTRB(R.p(context, 16), 0, R.p(context, 16), R.p(context, 14)),
                  child: TextField(
                    onChanged: (v) => setState(() => _cityFilter = v),
                    decoration: InputDecoration(
                      hintText: 'Filter by city (e.g. Hyderabad)',
                      prefixIcon: Icon(Icons.location_city_rounded, color: context.appTextHint),
                      suffixIcon: _cityFilter.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close_rounded, color: context.appTextHint, size: 18),
                              onPressed: () => setState(() => _cityFilter = ''),
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

                // ── Home Delivery Banner ─────────────────────────────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(R.p(context, 16), 0, R.p(context, 16), R.p(context, 14)),
                  child: GestureDetector(
                    onTap: () => context.push(AppRoutes.medicine),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE8F5E9), Color(0xFFE3F2FD)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delivery_dining_rounded, color: Color(0xFF2E7D32), size: 26),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Order Medicines at Home', style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700,
                              color: Color(0xFF2E7D32))),
                          Text('Delivary at your doorstep • Genuine medicines',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: context.appTextSecondary)),
                        ])),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF2E7D32)),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Nearby Pharmacies (live, from approved registrations) ────
          // The medicines_catalogue stream lets a medicine-name search
          // (e.g. "paracetamol") also surface the pharmacies that stock
          // it, not just pharmacies whose own name matches — mirroring
          // DiagnosticsScreen's lab_tests_catalogue cross-reference.
          //
          // Kept as direct sliver siblings (rather than nested inside one
          // SliverToBoxAdapter/Column) so the empty state can use
          // SliverFillRemaining to center itself in the leftover viewport
          // space instead of hugging the left edge above a wall of blank
          // background.
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('medicines_catalogue')
                .where('isActive', isEqualTo: true)
                .snapshots(),
            builder: (context, medSnap) {
              final q = _search.trim().toLowerCase();
              final matchingPharmacyIds = q.isEmpty
                  ? const <String>{}
                  : (medSnap.data?.docs ?? const [])
                      .where((d) {
                        final data = d.data();
                        final name = (data['name'] as String? ?? '').toLowerCase();
                        final brand = (data['brand'] as String? ?? '').toLowerCase();
                        return name.contains(q) || brand.contains(q);
                      })
                      .map((d) => d.data()['sourcePharmacyId'] as String?)
                      .whereType<String>()
                      .toSet();

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('pharmacy_profiles')
                    .where('status', isEqualTo: 'active')
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    );
                  }

                  final all = snap.data!.docs
                      .map((d) => _toCard(d, myLocation.lat, myLocation.lng))
                      .toList();
                  all.sort((a, b) {
                    final da = a['distanceKm'] as double?;
                    final db = b['distanceKm'] as double?;
                    if (da == null || db == null) return 0;
                    return da.compareTo(db);
                  });
                  // A city filter browses that city outright, ignoring
                  // the device's live location entirely; otherwise fall
                  // back to the 15km in-person radius used for doctors,
                  // instead of listing every registered pharmacy
                  // nationwide.
                  final cityQuery = _cityFilter.trim().toLowerCase();
                  final nearby = cityQuery.isNotEmpty
                      ? all.where((p) =>
                          (p['city'] as String).toLowerCase().contains(cityQuery)).toList()
                      : myLocation.lat != null && myLocation.lng != null
                          ? all.where((p) {
                              final d = p['distanceKm'] as double?;
                              return d != null && d <= 15.0;
                            }).toList()
                          : all;
                  final filtered = q.isEmpty
                      ? nearby
                      : nearby.where((p) =>
                          (p['name'] as String).toLowerCase().contains(q) ||
                          (p['address'] as String).toLowerCase().contains(q) ||
                          matchingPharmacyIds.contains(p['id'] as String),
                        ).toList();

                  final heading = q.isNotEmpty
                      ? '${filtered.length} result${filtered.length == 1 ? '' : 's'} for "$_search"'
                      : cityQuery.isNotEmpty
                          ? 'Pharmacies in "${_cityFilter.trim()}"'
                          : 'Nearby Pharmacies';

                  final headingSliver = SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(R.p(context, 16), 0, R.p(context, 16), R.p(context, 12)),
                      child: Text(heading, style: AppTextStyles.h4),
                    ),
                  );

                  if (filtered.isEmpty) {
                    return SliverMainAxisGroup(slivers: [
                      headingSliver,
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: AppEmptyState(
                          icon: Icons.local_pharmacy_outlined,
                          title: q.isNotEmpty
                              ? 'No pharmacy found'
                              : cityQuery.isNotEmpty
                                  ? 'No pharmacies in "${_cityFilter.trim()}"'
                                  : 'No pharmacies nearby yet',
                          message: q.isNotEmpty
                              ? 'We couldn\'t find "$_search". Try a different search term.'
                              : cityQuery.isNotEmpty
                                  ? 'Try another city, or clear the filter to see pharmacies near you.'
                                  : 'Registered pharmacies near you will show up here once available.',
                        ),
                      ),
                    ]);
                  }

                  return SliverMainAxisGroup(slivers: [
                    headingSliver,
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _PharmacyCard(pharmacy: filtered[i]),
                        childCount: filtered.length,
                      ),
                    ),
                    SliverToBoxAdapter(child: SizedBox(height: R.h(context, 40))),
                  ]);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PharmacyCard extends StatelessWidget {
  final Map<String, Object?> pharmacy;
  const _PharmacyCard({required this.pharmacy});

  @override
  Widget build(BuildContext context) {
    final p = pharmacy;
    final deliveryAvailable = p['deliveryAvailable'] as bool;
    final totalReviews = p['totalReviews'] as int;
    final distanceKm = p['distanceKm'] as double?;
    final categories = (p['categories'] as List).cast<String>();
    final photoUrl = p['photoUrl'] as String? ?? '';
    final name = p['name'] as String;

    return Container(
      margin: EdgeInsets.fromLTRB(R.p(context, 16), 0, R.p(context, 16), R.p(context, 16)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 18)),
        border: Border.all(color: context.appBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(AppRoutes.pharmacyMenu.replaceFirst(':id', p['id'] as String)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Banner (Zomato-style storefront photo) ──────────────
              AspectRatio(
                aspectRatio: 16 / 8,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    photoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: photoUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _PharmacyBannerPlaceholder(name: name),
                          )
                        : _PharmacyBannerPlaceholder(name: name),
                    // Bottom gradient scrim so the rating chip stays legible
                    // over a bright photo, matching Zomato's card treatment.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black45],
                          stops: [0.55, 1],
                        ),
                      ),
                    ),
                    // Delivery / pickup chip, top-right.
                    Positioned(
                      top: R.p(context, 10),
                      right: R.p(context, 10),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: R.p(context, 10), vertical: R.p(context, 4)),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(R.r(context, 8)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            deliveryAvailable ? Icons.delivery_dining_rounded : Icons.storefront_rounded,
                            size: R.w(context, 13),
                            color: Colors.white,
                          ),
                          SizedBox(width: R.p(context, 4)),
                          Text(
                            deliveryAvailable ? 'Delivers' : 'Pickup only',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: R.sp(context, 11), fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ]),
                      ),
                    ),
                    // Rating chip overlapping the bottom edge, like Zomato's
                    // green rating badge on the restaurant card image.
                    Positioned(
                      left: R.p(context, 10),
                      bottom: R.p(context, 10),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: R.p(context, 8), vertical: R.p(context, 4)),
                        decoration: BoxDecoration(
                          color: totalReviews > 0 ? const Color(0xFF2E7D32) : Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(R.r(context, 8)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (totalReviews > 0) ...[
                            Text('${p['rating']}', style: TextStyle(fontFamily: 'Poppins', fontSize: R.sp(context, 12), fontWeight: FontWeight.w700, color: Colors.white)),
                            SizedBox(width: R.p(context, 3)),
                            Icon(Icons.star_rounded, size: R.w(context, 13), color: Colors.white),
                          ] else
                            Text('New', style: TextStyle(fontFamily: 'Poppins', fontSize: R.sp(context, 12), fontWeight: FontWeight.w700, color: Colors.white)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Details ──────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(R.p(context, 14), R.p(context, 12), R.p(context, 14), R.p(context, 12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTextStyles.h4, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (categories.isNotEmpty) ...[
                      SizedBox(height: R.h(context, 3)),
                      Text(
                        categories.join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
                      ),
                    ],
                    SizedBox(height: R.h(context, 6)),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: R.w(context, 13), color: context.appTextHint),
                        SizedBox(width: R.p(context, 3)),
                        Expanded(
                          child: Text(
                            p['address'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
                          ),
                        ),
                        if (distanceKm != null) ...[
                          SizedBox(width: R.p(context, 8)),
                          Text('${distanceKm.toStringAsFixed(1)} km', style: AppTextStyles.labelSmall),
                        ],
                      ],
                    ),
                    SizedBox(height: R.h(context, 10)),
                    const Divider(height: 1),
                    SizedBox(height: R.h(context, 8)),
                    // ── Quick actions (call / navigate) — the card itself
                    // opens the medicine menu; these stay as compact icon
                    // actions so they don't compete with that primary tap.
                    Row(
                      children: [
                        Expanded(
                          child: Text('View Medicines', style: AppTextStyles.labelLarge.copyWith(color: const Color(0xFF2E7D32))),
                        ),
                        _PharmacyIconAction(
                          icon: Icons.call_rounded,
                          onTap: () => launchUrl(Uri.parse('tel:${p['phone']}'), mode: LaunchMode.externalApplication),
                        ),
                        SizedBox(width: R.p(context, 8)),
                        _PharmacyIconAction(
                          icon: Icons.directions_rounded,
                          onTap: () => launchUrl(
                            Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(p['address'] as String)}'),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        SizedBox(width: R.p(context, 8)),
                        Icon(Icons.chevron_right_rounded, color: context.appTextHint),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gradient fallback banner shown when a pharmacy hasn't uploaded a real
/// storefront photo yet (`photoUrl` empty) — every pharmacy today falls into
/// this case, so it must look intentional rather than like a broken image.
class _PharmacyBannerPlaceholder extends StatelessWidget {
  final String name;
  const _PharmacyBannerPlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'P';
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.medicineGrad),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.local_pharmacy_rounded, size: 56, color: Colors.white.withValues(alpha: 0.18)),
          Text(
            initial,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 40, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _PharmacyIconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _PharmacyIconAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onTap,
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 17, color: const Color(0xFF2E7D32)),
    ),
  );
}
