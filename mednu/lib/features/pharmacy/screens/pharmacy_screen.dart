import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';

class PharmacyScreen extends StatefulWidget {
  const PharmacyScreen({super.key});

  @override
  State<PharmacyScreen> createState() => _PharmacyScreenState();
}

class _PharmacyScreenState extends State<PharmacyScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final pharmacies = [
      {'name': 'Apollo Pharmacy', 'location': 'Jubilee Hills', 'distance': '0.8 km', 'open': true, 'rating': 4.8, 'timing': 'Open 24/7', 'phone': '18004255', 'query': 'Apollo Pharmacy Jubilee Hills Hyderabad'},
      {'name': 'MedPlus', 'location': 'Banjara Hills', 'distance': '1.2 km', 'open': true, 'rating': 4.6, 'timing': 'Open till 10 PM', 'phone': '18001022097', 'query': 'MedPlus Banjara Hills Hyderabad'},
      {'name': 'Wellness Forever', 'location': 'Madhapur', 'distance': '2.1 km', 'open': false, 'rating': 4.5, 'timing': 'Opens at 8 AM', 'phone': '18002667736', 'query': 'Wellness Forever Madhapur Hyderabad'},
      {'name': 'Netmeds Store', 'location': 'HITEC City', 'distance': '3.0 km', 'open': true, 'rating': 4.7, 'timing': 'Open till 11 PM', 'phone': '18001232345', 'query': 'Netmeds HITEC City Hyderabad'},
    ];

    final filtered = _search.isEmpty
        ? pharmacies
        : pharmacies.where((p) =>
            (p['name'] as String).toLowerCase().contains(_search.toLowerCase()) ||
            (p['location'] as String).toLowerCase().contains(_search.toLowerCase()),
          ).toList();

    final categories = [
      {'name': 'Tablets', 'icon': Icons.medication_rounded, 'color': const Color(0xFF1565C0)},
      {'name': 'Syrups', 'icon': Icons.local_drink_rounded, 'color': const Color(0xFF2E7D32)},
      {'name': 'Injections', 'icon': Icons.vaccines_rounded, 'color': const Color(0xFFB71C1C)},
      {'name': 'Vitamins', 'icon': Icons.star_rounded, 'color': const Color(0xFFE65100)},
      {'name': 'Skincare', 'icon': Icons.face_rounded, 'color': const Color(0xFF522546)},
      {'name': 'Baby Care', 'icon': Icons.child_care_rounded, 'color': const Color(0xFF633058)},
    ];

    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: AppSpacing.headerHeight(context),
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

                // ── Categories ───────────────────────────────────────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(R.p(context, 16), 0, R.p(context, 16), R.p(context, 12)),
                  child: const Text('Categories', style: AppTextStyles.h4),
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
                                color: catColor.withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(R.r(context, 16)),
                                border: Border.all(color: catColor.withValues(alpha:0.2)),
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
                  child: Text(
                    _search.isEmpty ? 'Nearby Pharmacies' : '${filtered.length} result${filtered.length == 1 ? '' : 's'} for "$_search"',
                    style: AppTextStyles.h4,
                  ),
                ),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(children: [
                      Icon(Icons.search_off_rounded, size: 48, color: context.appTextHint),
                      const SizedBox(height: 12),
                      Text('No pharmacy found for "$_search"',
                          style: AppTextStyles.bodyMedium.copyWith(color: context.appTextHint)),
                    ]),
                  )
                else
                  ...filtered.map((p) => _PharmacyCard(pharmacy: p)),
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
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 18)),
        border: Border.all(color: context.appBorder),
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
                  color: const Color(0xFF1565C0).withValues(alpha:0.1),
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
                        Icon(Icons.location_on_outlined, size: R.w(context, 13), color: context.appTextHint),
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
                  color: statusColor.withValues(alpha:0.1),
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
