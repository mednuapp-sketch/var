import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/add_to_cart_button.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../cart/models/cart_item.dart';
import '../../cart/providers/cart_provider.dart';

class MedicineScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>>? prescriptionMedicines;
  const MedicineScreen({super.key, this.prescriptionMedicines});

  @override
  ConsumerState<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends ConsumerState<MedicineScreen> {
  // Firestore-loaded catalogue
  List<Map<String, dynamic>> _catalogue = [];
  bool _catalogueLoading = true;
  StreamSubscription<QuerySnapshot>? _catalogueSub;

  // Search & prescription state
  String _search = '';
  final String _selectedCategory = 'All';
  List<Map<String, dynamic>> _prescriptionMeds = [];
  bool _showPrescriptionMeds = false;

  // Computed
  List<Map<String, dynamic>> get _filteredMeds {
    var list = _catalogue;
    if (_selectedCategory != 'All') {
      list = list.where((m) {
        final unit = (m['unit'] as String).toLowerCase();
        final name = (m['name'] as String).toLowerCase();
        final cat = (m['category'] as String).toLowerCase();
        return switch (_selectedCategory) {
          'Tablets'     => unit.contains('tablet') || cat.contains('tablet'),
          'Syrups'      => unit.contains('syrup') || unit.contains('liquid') || cat.contains('syrup'),
          'Injections'  => unit.contains('injection') || unit.contains('vial') || cat.contains('inject'),
          'Vitamins'    => name.contains('vitamin') || name.contains('zinc') || cat.contains('vitamin'),
          'Pain Relief' => name.contains('paracetamol') || name.contains('ibuprofen') || name.contains('pain') || cat.contains('pain'),
          'Antibiotics' => name.contains('amoxicillin') || name.contains('azithromycin') || name.contains('antibiotic') || cat.contains('antibiotic'),
          _             => true,
        };
      }).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((m) =>
        (m['name'] as String).toLowerCase().contains(q) ||
        (m['brand'] as String).toLowerCase().contains(q),
      ).toList();
    }
    return list;
  }

  List<CartItem> get _medicineCartItems =>
      ref.watch(cartProvider).where((i) => i.type == 'medicine').toList();
  int get _cartCount => _medicineCartItems.length;
  int get _cartTotal => _medicineCartItems.fold<int>(0, (s, i) => s + i.totalAmount);
  CartItem? _cartItemForMed(String medId) =>
      _medicineCartItems.where((i) => i.serviceDetails['id'] == medId).firstOrNull;

  @override
  void initState() {
    super.initState();
    if (widget.prescriptionMedicines != null && widget.prescriptionMedicines!.isNotEmpty) {
      _prescriptionMeds = List.from(widget.prescriptionMedicines!);
      _showPrescriptionMeds = true;
    }
    _catalogueSub = FirebaseFirestore.instance
        .collection('medicines_catalogue')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _catalogueLoading = false;
        _catalogue = snap.docs.map((d) {
          final data = d.data();
          return {
            'id':                   d.id,
            'name':                 (data['name'] as String? ?? '').trim(),
            'brand':                (data['brand'] as String? ?? '').trim(),
            'price':                (data['price'] as num?)?.toInt() ?? 0,
            'mrp':                  (data['mrp'] as num?)?.toInt() ?? 0,
            'qty':                  (data['qty'] as num?)?.toInt() ?? 1,
            'unit':                 data['unit'] as String? ?? 'Tablets',
            'requiresPrescription': data['requiresPrescription'] as bool? ?? false,
            'category':             (data['category'] as String? ?? '').trim(),
          };
        }).toList();
      });
    }, onError: (_) {
      if (mounted) setState(() => _catalogueLoading = false);
    });
  }

  @override
  void dispose() {
    _catalogueSub?.cancel();
    super.dispose();
  }

  void _addMedToCart(Map<String, dynamic> med) {
    ref.read(cartProvider.notifier).addItem(
          type: 'medicine',
          serviceName: med['name'] as String,
          themeColor: const Color(0xFF2E7D32),
          unitAmount: med['price'] as int,
          serviceDetails: {
            'id': med['id'],
            'name': med['name'],
            'brand': med['brand'],
          },
        );
  }

  void _addToCatalogueFromPrescription(Map<String, dynamic> rxMed) {
    final keyword = (rxMed['name'] as String? ?? '').toLowerCase().split(' ').first;
    final med = _catalogue.where((c) => (c['name'] as String).toLowerCase().contains(keyword)).firstOrNull;
    if (med != null && _cartItemForMed(med['id'] as String) == null) {
      _addMedToCart(med);
    }
  }

  void _addAllPrescriptionMeds() {
    int added = 0;
    for (final m in _prescriptionMeds) {
      final keyword = (m['name'] as String? ?? '').toLowerCase().split(' ').first;
      final med = _catalogue.where((c) => (c['name'] as String).toLowerCase().contains(keyword)).firstOrNull;
      if (med != null && _cartItemForMed(med['id'] as String) == null) {
        _addMedToCart(med);
        added++;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(added > 0 ? '$added medicine${added > 1 ? 's' : ''} added to cart' : 'Medicines already in cart'),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: R.h(context, 80),
            centerTitle: false,
            title: const Text('Pharmacy', style: AppTextStyles.onPrimaryH2),
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => context.pop()),
            actions: const [CartBadgeAction()],
            flexibleSpace: const FlexibleSpaceBar(
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(children: [
              // Prescription medicines section
              if (_showPrescriptionMeds && _prescriptionMeds.isNotEmpty) ...[
                SizedBox(height: R.h(context, 14)),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: R.p(context, 16)),
                  padding: EdgeInsets.all(R.p(context, 16)),
                  decoration: BoxDecoration(
                    color: context.appSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha:0.35)),
                    boxShadow: [BoxShadow(color: const Color(0xFF2E7D32).withValues(alpha:0.06), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.receipt_long_rounded, color: Color(0xFF2E7D32), size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Medicines from Prescription', style: AppTextStyles.labelLarge.copyWith(color: const Color(0xFF2E7D32)))),
                      TextButton(
                        onPressed: _addAllPrescriptionMeds,
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        child: const Text('Add All', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    ..._prescriptionMeds.map((m) {
                      final name = m['name'] as String? ?? '';
                      final keyword = name.toLowerCase().split(' ').first;
                      final isAdded = _catalogue.any((c) {
                        final cId = c['id'] as String;
                        return (c['name'] as String).toLowerCase().contains(keyword) && _cartItemForMed(cId) != null;
                      });
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isAdded ? const Color(0xFFE8F5E9) : const Color(0xFFF9FBE7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          Icon(isAdded ? Icons.check_circle_rounded : Icons.medication_rounded, color: const Color(0xFF2E7D32), size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name, style: AppTextStyles.labelLarge),
                            Text('${m['dosage'] ?? ''} • ${m['frequency'] ?? ''} • ${m['duration'] ?? ''}', style: AppTextStyles.caption),
                          ])),
                          if (!isAdded)
                            GestureDetector(
                              onTap: () => _addToCatalogueFromPrescription(m),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(8)),
                                child: const Text('Add', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                              ),
                            )
                          else
                            const Text('Added', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
                        ]),
                      );
                    }),
                  ]),
                ),
              ],

              // Search bar
              Padding(
                padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 16), R.p(context, 16), 0),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search medicines, brands…',
                    prefixIcon: Icon(Icons.search_rounded, color: context.appTextHint),
                    filled: true,
                    fillColor: context.appSurface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),

              SizedBox(height: R.h(context, 14)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: R.p(context, 16)),
                child: Align(alignment: Alignment.centerLeft, child: Text('Available Medicines', style: AppTextStyles.h4)),
              ),
              SizedBox(height: R.h(context, 12)),

              // Loading state
              if (_catalogueLoading)
                _buildSkeletonCards()
              else if (_catalogue.isEmpty)
                _buildEmptyState()
              else if (_filteredMeds.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(children: [
                    Icon(Icons.search_off_rounded, size: 48, color: context.appTextHint),
                    const SizedBox(height: 12),
                    Text('No medicines found for "$_search"', style: AppTextStyles.bodyMedium.copyWith(color: context.appTextHint)),
                  ]),
                )
              else
                ..._filteredMeds.map((med) {
                  final id = med['id'] as String;
                  final cartItem = _cartItemForMed(id);
                  final cartCount = cartItem?.quantity ?? 0;
                  return _MedicineCard(
                    medicine: med,
                    cartCount: cartCount,
                    onAdd: () => _addMedToCart(med),
                    onIncrement: () {
                      if (cartItem != null) {
                        ref.read(cartProvider.notifier).incrementQty(cartItem.id);
                      }
                    },
                    onDecrement: () {
                      if (cartItem != null) {
                        if (cartItem.quantity <= 1) {
                          ref.read(cartProvider.notifier).removeItem(cartItem.id);
                        } else {
                          ref.read(cartProvider.notifier).decrementQty(cartItem.id);
                        }
                      }
                    },
                  );
                }),

              const SizedBox(height: 110),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: _cartCount > 0
          ? Container(
              padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 12), R.p(context, 20), R.p(context, 30)),
              decoration: BoxDecoration(
                color: context.appSurface,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.08), blurRadius: 16, offset: const Offset(0, -4))],
              ),
              child: ElevatedButton(
                onPressed: () => context.push(AppRoutes.cart),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.2), borderRadius: BorderRadius.circular(8)),
                    child: Text('$_cartCount item${_cartCount > 1 ? 's' : ''}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white)),
                  ),
                  Row(children: [
                    Text('₹$_cartTotal', style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(width: 8),
                    const Text('View Cart →', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white70)),
                  ]),
                ]),
              ),
            )
          : null,
    );
  }

  Widget _buildSkeletonCards() => AppShimmer(
    child: Column(children: List.generate(5, (_) => Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      height: 90,
      decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(16)),
    ))),
  );

  Widget _buildEmptyState() => const AppEmptyState(
    icon: Icons.medication_outlined,
    title: 'No Medicines Available',
    message: 'The medicine catalogue will appear here once added by the pharmacy team.',
  );
}

// ── Reusable widgets ────────────────────────────────────────────────────────

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 26, height: 26,
      decoration: BoxDecoration(color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(7)),
      child: Icon(icon, color: Colors.white, size: 14),
    ),
  );
}


class _MedicineCard extends StatelessWidget {
  final Map<String, dynamic> medicine;
  final int cartCount;
  final VoidCallback onAdd, onIncrement, onDecrement;
  const _MedicineCard({
    required this.medicine,
    required this.cartCount,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final mrp      = medicine['mrp']   as int;
    final price    = medicine['price'] as int;
    final discount = mrp > 0 ? (((mrp - price) / mrp) * 100).round() : 0;
    final needsRx  = medicine['requiresPrescription'] as bool;
    final inCart   = cartCount > 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: inCart ? const Color(0xFF2E7D32).withValues(alpha:0.4) : context.appBorder),
        boxShadow: inCart ? [BoxShadow(color: const Color(0xFF2E7D32).withValues(alpha:0.08), blurRadius: 8, offset: const Offset(0, 2))] : null,
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha:0.1), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.medication_rounded, color: Color(0xFF2E7D32), size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(medicine['name'] as String, style: AppTextStyles.labelLarge)),
            if (needsRx)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha:0.1), borderRadius: BorderRadius.circular(6)),
                child: const Text('Rx', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w800, color: Colors.orange)),
              ),
          ]),
          Text('${medicine['brand']} • ${medicine['qty']} ${medicine['unit']}', style: AppTextStyles.bodySmall),
          const SizedBox(height: 4),
          Row(children: [
            Text('₹$price', style: AppTextStyles.labelLarge.copyWith(color: const Color(0xFF2E7D32))),
            const SizedBox(width: 6),
            if (mrp > price) ...[
              Text('₹$mrp', style: AppTextStyles.caption.copyWith(decoration: TextDecoration.lineThrough, color: context.appTextHint)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha:0.1), borderRadius: BorderRadius.circular(6)),
                child: Text('$discount% OFF', style: const TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
              ),
            ],
          ]),
        ])),
        const SizedBox(width: 8),
        inCart
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                _QtyBtn(icon: Icons.remove_rounded, onTap: onDecrement),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('$cartCount', style: AppTextStyles.labelLarge)),
                _QtyBtn(icon: Icons.add_rounded, onTap: onIncrement),
              ])
            : GestureDetector(
                onTap: onAdd,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('Add', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
      ]),
    );
  }
}
