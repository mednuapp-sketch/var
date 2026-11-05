import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/distance.dart';
import '../../../core/widgets/add_to_cart_button.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../cart/providers/cart_provider.dart';
import '../../home/providers/location_provider.dart';

class EquipmentScreen extends ConsumerStatefulWidget {
  // When set, scopes the catalog to one admin-managed vendor (see
  // EquipmentVendorsScreen) instead of the flat, unscoped national catalog —
  // same optional-scoping shape as MedicineScreen's pharmacyId.
  final String? vendorId;
  final String? vendorName;

  const EquipmentScreen({super.key, this.vendorId, this.vendorName});

  @override
  ConsumerState<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends ConsumerState<EquipmentScreen> with SingleTickerProviderStateMixin {
  int _retryKey = 0;
  String _mode = 'rent'; // 'rent' | 'buy'
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() => _mode = _tabController.index == 0 ? 'rent' : 'buy');
        }
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  static const _palette = [
    Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF0097A7),
    Color(0xFF633058), Color(0xFFE65100), Color(0xFF522546),
    Color(0xFF37474F), Color(0xFF4527A0), Color(0xFF00838F),
  ];

  static const _icons = [
    Icons.accessible_rounded, Icons.bed_rounded, Icons.air_rounded,
    Icons.masks_rounded, Icons.accessibility_new_rounded, Icons.monitor_heart_rounded,
    Icons.medical_services_rounded, Icons.local_hospital_rounded, Icons.healing_rounded,
  ];

  static Color _colorAt(int i) => _palette[i % _palette.length];
  static IconData _iconAt(int i) => _icons[i % _icons.length];

  // The pinned TabBar is additional height on top of the hero content, not
  // space carved out of it — otherwise the header shrinks below what the
  // icon/title/subtitle need and they sink into the tab bar (see equipment
  // header collision fix).
  static const _tabBarHeight = 46.0;

  /// Which partner vendor's menu item this is — present only for items a
  /// vendor published from its own menu (admin-listed legacy items carry no
  /// `sourceItemId`). Checkout uses it to route the order to that vendor.
  Map<String, dynamic> _vendorDetails(Map<String, dynamic> eq) => {
        if (eq['sourceVendorId'] != null) 'sourceVendorId': eq['sourceVendorId'],
        if (eq['sourceItemId'] != null) 'sourceItemId': eq['sourceItemId'],
        if (eq['vendorName'] != null) 'vendorName': eq['vendorName'],
      };

  void _addRentToCart(Map<String, dynamic> eq, int days) {
    final pricePerDay = eq['price'] as int;
    final deposit = eq['deposit'] as int;
    ref.read(cartProvider.notifier).addItem(
          type: 'equipment',
          serviceName: eq['name'] as String,
          themeColor: eq['color'] as Color,
          unitAmount: pricePerDay * days,
          serviceDetails: {
            'equipmentName': eq['name'],
            'mode':          'rent',
            'pricePerDay':   pricePerDay,
            'rentalDays':    days,
            'deposit':       deposit,
            'deliveryFree':  true,
            ..._vendorDetails(eq),
          },
        );
    if (mounted) FeedbackService.showSuccess(context, '${eq['name']} added to cart');
  }

  void _addBuyToCart(Map<String, dynamic> eq) {
    final purchasePrice = eq['purchasePrice'] as int;
    final deposit = eq['deposit'] as int;
    ref.read(cartProvider.notifier).addItem(
          type: 'equipment',
          serviceName: eq['name'] as String,
          themeColor: eq['color'] as Color,
          unitAmount: purchasePrice,
          serviceDetails: {
            'equipmentName':  eq['name'],
            'mode':           'buy',
            'purchasePrice':  purchasePrice,
            'deposit':        deposit,
            'deliveryFree':   true,
            ..._vendorDetails(eq),
          },
        );
    if (mounted) FeedbackService.showSuccess(context, '${eq['name']} added to cart');
  }

  Future<void> _showRentSheet(Map<String, dynamic> eq) async {
    final pricePerDay = eq['price'] as int;
    final color = eq['color'] as Color;
    int days = 1;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(eq['name'] as String, style: AppTextStyles.h4),
                const SizedBox(height: 4),
                Text('₹$pricePerDay/day', style: AppTextStyles.labelMedium.copyWith(color: color)),
                const SizedBox(height: 20),
                const Text('Number of days', style: AppTextStyles.labelLarge),
                const SizedBox(height: 10),
                Row(children: [
                  IconButton.filledTonal(
                    onPressed: days > 1 ? () => setSheetState(() => days--) : null,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  Expanded(
                    child: Text('$days ${days == 1 ? 'day' : 'days'}',
                        textAlign: TextAlign.center, style: AppTextStyles.h4),
                  ),
                  IconButton.filledTonal(
                    onPressed: days < 30 ? () => setSheetState(() => days++) : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ]),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total', style: AppTextStyles.labelLarge),
                  Text('₹${pricePerDay * days}', style: AppTextStyles.h4.copyWith(color: color)),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Add to Cart', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) _addRentToCart(eq, days);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        key: ValueKey(_retryKey),
        slivers: [
          AppSliverHeader(
            icon: Icons.medical_services_rounded,
            title: widget.vendorName ?? 'Medical Equipment',
            subtitle: widget.vendorId != null
                ? 'Rent or buy from this vendor'
                : 'Rent or buy medical equipment online',
            color: AppColors.primaryDark,
            gradient: AppColors.primaryGradient,
            actions: const [CartBadgeAction()],
            bottom: PreferredSize(
                        preferredSize: const Size.fromHeight(_tabBarHeight),
                        child: Container(
                          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
                          child: TabBar(
                            controller: _tabController,
                            indicatorColor: Colors.white,
                            indicatorWeight: 3,
                            labelColor: Colors.white,
                            unselectedLabelColor: Colors.white60,
                            labelStyle: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700),
                            unselectedLabelStyle: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500),
                            tabs: const [
                              Tab(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.event_available_rounded, size: 16),
                                    SizedBox(width: 5),
                                    Flexible(
                                      child: Text('Rent', maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ),
                              ),
                              Tab(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.shopping_cart_rounded, size: 16),
                                    SizedBox(width: 5),
                                    Flexible(
                                      child: Text('Buy', maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
          ),
          // Service providers — live from `equipment_vendors`, independent of
          // whether any equipment is listed yet. Hidden inside a vendor's own
          // scoped catalog.
          if (widget.vendorId == null)
            const SliverToBoxAdapter(child: _EquipmentProvidersSection()),
          SliverToBoxAdapter(
            child: StreamBuilder<QuerySnapshot>(
              stream: (() {
                Query query = FirebaseFirestore.instance
                    .collection('services')
                    .where('type', isEqualTo: 'equipment')
                    .where('isEnabled', isEqualTo: true);
                if (widget.vendorId != null) {
                  query = query.where('sourceVendorId', isEqualTo: widget.vendorId);
                }
                return query.snapshots();
              })(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _buildSkeleton();
                }
                if (snap.hasError) {
                  return _buildError(context);
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _buildEmpty();
                }
                final items = docs.asMap().entries.map((e) {
                  final d = e.value.data() as Map<String, dynamic>;
                  return {
                    'id':            e.value.id,
                    'name':          (d['name'] as String? ?? '').trim(),
                    'price':         (d['price'] as num?)?.toInt() ?? 0,
                    'purchasePrice': (d['purchasePrice'] as num?)?.toInt() ?? 0,
                    'deposit':       (d['deposit'] as num?)?.toInt() ?? 0,
                    'description':   (d['description'] as String? ?? '').trim(),
                    'imageUrl':      (d['imageUrl'] as String? ?? '').trim(),
                    // Live from the vendor's menu. Legacy admin-listed items
                    // have neither field, which reads as "always available".
                    'isAvailable':   (d['isAvailable'] as bool?) ?? true,
                    'stock':         (d['stock'] as num?)?.toInt(),
                    'sourceVendorId': d['sourceVendorId'],
                    'sourceItemId':  d['sourceItemId'],
                    'vendorName':    d['vendorName'],
                    'color':         _colorAt(e.key),
                    'icon':          _iconAt(e.key),
                  };
                }).toList();

                final visible = items.where((eq) {
                  return _mode == 'rent' ? (eq['price'] as int) > 0 : (eq['purchasePrice'] as int) > 0;
                }).toList();

                return Padding(
                  padding: AppSpacing.page(context),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Available Equipment', style: AppTextStyles.h4),
                    SizedBox(height: AppSpacing.cardGap(context)),
                    if (visible.isEmpty)
                      _buildModeEmpty()
                    else
                      staticGrid(
                        crossAxisCount: 2,
                        aspectRatio: 0.82,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        children: visible.map(_buildCard).toList(),
                      ),
                    const SizedBox(height: 40),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> eq) {
    final color = eq['color'] as Color;
    final deposit = eq['deposit'] as int;
    final desc = eq['description'] as String;
    final imageUrl = eq['imageUrl'] as String;
    final isRent = _mode == 'rent';
    final stock = eq['stock'] as int?;
    final available = eq['isAvailable'] as bool;
    final soldOut = !available || (stock != null && stock <= 0);
    final lowStock = !soldOut && stock != null && stock <= 2;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: imageUrl.isNotEmpty
              ? Image.network(
                  imageUrl, width: 46, height: 46, fit: BoxFit.cover,
                  cacheWidth: 138, cacheHeight: 138,
                  errorBuilder: (_, __, ___) => Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(12)),
                    child: Icon(eq['icon'] as IconData, color: color, size: 26),
                  ),
                )
              : Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(eq['icon'] as IconData, color: color, size: 26),
                ),
        ),
        const SizedBox(height: 10),
        Text(eq['name'] as String, style: AppTextStyles.labelLarge),
        const SizedBox(height: 4),
        Text(
          isRent ? '₹${eq['price']}/day' : '₹${eq['purchasePrice']}',
          style: AppTextStyles.labelMedium.copyWith(color: color),
        ),
        if (deposit > 0)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFFFD54F)),
            ),
            child: Text('₹$deposit refundable deposit',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 9,
                    fontWeight: FontWeight.w600, color: Color(0xFFE65100))),
          )
        else if (desc.isNotEmpty)
          Text(desc, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (soldOut || lowStock)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              soldOut ? 'Sold out' : 'Only $stock left',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: soldOut ? AppColors.error : const Color(0xFFE65100),
              ),
            ),
          ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: soldOut ? null : () => isRent ? _showRentSheet(eq) : _addBuyToCart(eq),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              minimumSize: const Size(double.infinity, 32),
              padding: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(soldOut ? 'Sold out' : (isRent ? 'Rent Now' : 'Buy Now'),
                style: const TextStyle(fontSize: 12, fontFamily: 'Poppins')),
          ),
        ),
      ]),
    );
  }

  Widget _buildModeEmpty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: AppEmptyState(
      icon: Icons.medical_services_outlined,
      title: _mode == 'rent' ? 'No Equipment Available for Rent' : 'No Equipment Available for Purchase',
      message: _mode == 'rent'
          ? 'Try switching to Buy to see purchasable equipment.'
          : 'Try switching to Rent to see rentable equipment.',
    ),
  );

  Widget _buildSkeleton() {
    return AppShimmer(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 160, height: 16, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(8))),
          staticGrid(
            crossAxisCount: 2,
            aspectRatio: 0.82,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: List.generate(4, (_) => Container(
              decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(16)),
            )),
          ),
        ]),
      ),
    );
  }

  Widget _buildError(BuildContext context) => AppErrorState(
    message: 'Could not load equipment. Please try again.',
    onRetry: () => setState(() => _retryKey++),
  );

  Widget _buildEmpty() => const AppEmptyState(
    icon: Icons.medical_services_outlined,
    title: 'No Equipment Listed',
    message: 'Medical equipment will appear here once added.',
  );
}

/// Live "Service Providers" strip: enabled vendors from `equipment_vendors`
/// (admin-listed + auto-fed from approved partner vendors), nearest first.
/// Tapping a vendor opens that vendor's own catalog; "View all" opens the
/// full searchable list.
class _EquipmentProvidersSection extends ConsumerWidget {
  const _EquipmentProvidersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(locationProvider);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('equipment_vendors')
          .where('isEnabled', isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        final pad = AppSpacing.page(context);
        final vendors = (snap.data?.docs ?? const []).map((doc) {
          final d = doc.data();
          final lat = (d['lat'] as num?)?.toDouble();
          final lng = (d['lng'] as num?)?.toDouble();
          double? km;
          if (loc.lat != null && loc.lng != null && lat != null && lng != null) {
            km = distanceKm(loc.lat!, loc.lng!, lat, lng);
          }
          return {
            'id': doc.id,
            'name': ((d['name'] as String?) ?? 'Equipment Vendor').trim(),
            'city': ((d['city'] as String?) ?? '').trim(),
            'open': (d['acceptingOrders'] as bool?) ?? true,
            'km': km,
          };
        }).toList()
          ..sort((a, b) {
            final ka = a['km'] as double?, kb = b['km'] as double?;
            if (ka == null && kb == null) return 0;
            if (ka == null) return 1;
            if (kb == null) return -1;
            return ka.compareTo(kb);
          });

        return Padding(
          padding: EdgeInsets.only(top: pad.top, bottom: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad.horizontal / 2),
              child: Row(children: [
                const Expanded(child: Text('Service Providers', style: AppTextStyles.h4)),
                if (vendors.isNotEmpty)
                  TextButton(
                    onPressed: () => context.push(AppRoutes.equipmentVendors),
                    child: const Text('View all'),
                  ),
              ]),
            ),
            if (snap.hasError)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: pad.horizontal / 2),
                child: Text('Could not load providers.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
              )
            else if (!snap.hasData)
              SizedBox(
                height: 112,
                child: AppShimmer(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: pad.horizontal / 2),
                    itemCount: 3,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, __) => Container(
                      width: 200,
                      decoration: BoxDecoration(
                          color: context.appSurface, borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              )
            else if (vendors.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: pad.horizontal / 2),
                child: Text('No service providers listed yet. They appear here as soon as they join.',
                    style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
              )
            else
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: pad.horizontal / 2),
                  itemCount: vendors.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _ProviderChipCard(vendor: vendors[i]),
                ),
              ),
            const SizedBox(height: 4),
          ]),
        );
      },
    );
  }
}

class _ProviderChipCard extends StatelessWidget {
  final Map<String, Object?> vendor;
  const _ProviderChipCard({required this.vendor});

  @override
  Widget build(BuildContext context) {
    final open = vendor['open'] == true;
    final km = vendor['km'] as double?;
    final city = vendor['city'] as String;
    final place = km != null
        ? '${km.toStringAsFixed(1)} km away'
        : (city.isNotEmpty ? city : 'Location not set');

    return GestureDetector(
      onTap: () => context.push(
        AppRoutes.equipmentMenu.replaceFirst(':id', vendor['id'] as String),
        extra: {'vendorName': vendor['name']},
      ),
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.appBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.medical_services_rounded, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(vendor['name'] as String,
                  style: AppTextStyles.labelLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ]),
          const Spacer(),
          Row(children: [
            Icon(Icons.location_on_outlined, size: 13, color: context.appTextHint),
            const SizedBox(width: 3),
            Flexible(
              child: Text(place,
                  style: AppTextStyles.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 4),
          Text(open ? 'Open · View equipment' : 'Closed right now',
              style: AppTextStyles.labelSmall.copyWith(
                  color: open ? const Color(0xFF2E7D32) : AppColors.error,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
