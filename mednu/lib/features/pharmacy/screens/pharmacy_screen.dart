import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/r.dart';

class PharmacyScreen extends StatelessWidget {
  const PharmacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pharmacies = [
      {'name': 'Apollo Pharmacy', 'location': 'Jubilee Hills', 'distance': '0.8 km', 'open': true, 'rating': 4.8, 'timing': 'Open 24/7', 'phone': '18004255', 'query': 'Apollo Pharmacy Jubilee Hills Hyderabad'},
      {'name': 'MedPlus', 'location': 'Banjara Hills', 'distance': '1.2 km', 'open': true, 'rating': 4.6, 'timing': 'Open till 10 PM', 'phone': '18001022097', 'query': 'MedPlus Banjara Hills Hyderabad'},
      {'name': 'Wellness Forever', 'location': 'Madhapur', 'distance': '2.1 km', 'open': false, 'rating': 4.5, 'timing': 'Opens at 8 AM', 'phone': '18002667736', 'query': 'Wellness Forever Madhapur Hyderabad'},
      {'name': 'Netmeds Store', 'location': 'HITEC City', 'distance': '3.0 km', 'open': true, 'rating': 4.7, 'timing': 'Open till 11 PM', 'phone': '18001232345', 'query': 'Netmeds HITEC City Hyderabad'},
    ];

    final categories = [
      {'name': 'Tablets', 'icon': Icons.medication_rounded, 'color': const Color(0xFF1565C0)},
      {'name': 'Syrups', 'icon': Icons.local_drink_rounded, 'color': const Color(0xFF2E7D32)},
      {'name': 'Injections', 'icon': Icons.vaccines_rounded, 'color': const Color(0xFFB71C1C)},
      {'name': 'Vitamins', 'icon': Icons.star_rounded, 'color': const Color(0xFFE65100)},
      {'name': 'Skincare', 'icon': Icons.face_rounded, 'color': const Color(0xFFC2185B)},
      {'name': 'Baby Care', 'icon': Icons.child_care_rounded, 'color': const Color(0xFF7B1FA2)},
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: R.h(context, 160),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      R.p(context, 20), R.p(context, 48),
                      R.p(context, 20), R.p(context, 16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_pharmacy_rounded, color: Colors.white, size: R.w(context, 36)),
                        SizedBox(height: R.h(context, 6)),
                        Text('Pharmacy & Medical Shops', style: AppTextStyles.onPrimaryH2),
                        Text('Find nearby pharmacies • Order online', style: AppTextStyles.onPrimaryBody),
                      ],
                    ),
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
                    decoration: InputDecoration(
                      hintText: 'Search medicines or pharmacies...',
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(R.r(context, 14)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                // ── Categories ───────────────────────────────────────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(R.p(context, 16), 0, R.p(context, 16), R.p(context, 12)),
                  child: Text('Categories', style: AppTextStyles.h4),
                ),
                SizedBox(
                  height: R.h(context, 90),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: R.p(context, 16)),
                    itemCount: categories.length,
                    itemBuilder: (_, i) {
                      final cat = categories[i];
                      final catColor = cat['color'] as Color;
                      return Container(
                        width: R.w(context, 70),
                        margin: EdgeInsets.only(right: R.p(context, 12)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: R.w(context, 56),
                              height: R.w(context, 56),
                              decoration: BoxDecoration(
                                color: catColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(R.r(context, 16)),
                                border: Border.all(color: catColor.withOpacity(0.2)),
                              ),
                              child: Icon(cat['icon'] as IconData, color: catColor, size: R.w(context, 28)),
                            ),
                            SizedBox(height: R.h(context, 6)),
                            Text(
                              cat['name'] as String,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: R.h(context, 16)),

                // ── Nearby Pharmacies ────────────────────────────────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(R.p(context, 16), 0, R.p(context, 16), R.p(context, 12)),
                  child: Text('Nearby Pharmacies', style: AppTextStyles.h4),
                ),
                ...pharmacies.map((p) => _PharmacyCard(pharmacy: p)),
                SizedBox(height: R.h(context, 40)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PharmacyCard extends StatelessWidget {
  final Map<String, Object> pharmacy;
  const _PharmacyCard({required this.pharmacy});

  @override
  Widget build(BuildContext context) {
    final p = pharmacy;
    final isOpen = p['open'] as bool;
    final statusColor = isOpen ? AppColors.accent : Colors.grey;

    return Container(
      margin: EdgeInsets.fromLTRB(R.p(context, 16), 0, R.p(context, 16), R.p(context, 12)),
      padding: EdgeInsets.all(R.p(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(R.r(context, 18)),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ─────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: R.w(context, 52),
                height: R.w(context, 52),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(R.r(context, 14)),
                ),
                child: Icon(Icons.local_pharmacy_rounded, color: const Color(0xFF1565C0), size: R.w(context, 28)),
              ),
              SizedBox(width: R.p(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['name'] as String, style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    SizedBox(height: R.h(context, 2)),
                    Text(p['location'] as String, style: AppTextStyles.bodySmall),
                    SizedBox(height: R.h(context, 4)),
                    Row(
                      children: [
                        Icon(Icons.star_rounded, size: R.w(context, 13), color: Colors.amber),
                        SizedBox(width: R.p(context, 3)),
                        Text('${p['rating']}', style: AppTextStyles.labelSmall),
                        SizedBox(width: R.p(context, 8)),
                        Icon(Icons.location_on_outlined, size: R.w(context, 13), color: AppColors.textHint),
                        SizedBox(width: R.p(context, 3)),
                        Flexible(
                          child: Text(p['distance'] as String, style: AppTextStyles.labelSmall, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: R.p(context, 8)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: R.p(context, 10), vertical: R.p(context, 4)),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(R.r(context, 8)),
                ),
                child: Text(
                  isOpen ? 'Open' : 'Closed',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: R.sp(context, 11),
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: R.h(context, 8)),
          Text(
            p['timing'] as String,
            style: AppTextStyles.bodySmall.copyWith(color: statusColor),
          ),
          SizedBox(height: R.h(context, 10)),

          // ── Action buttons ──────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(Icons.call_rounded, size: R.w(context, 16)),
                  label: const Text('Call'),
                  onPressed: () => launchUrl(
                    Uri.parse('tel:${p['phone']}'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
              SizedBox(width: R.p(context, 10)),
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.directions_rounded, size: R.w(context, 16)),
                  label: const Text('Navigate'),
                  onPressed: () => launchUrl(
                    Uri.parse(
                      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(p['query'] as String)}',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
