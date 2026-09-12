import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/add_to_cart_button.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../cart/models/cart_item.dart';
import '../../cart/providers/cart_provider.dart';
import '../../cart/providers/pending_prescription_provider.dart';
import '../../orders/screens/prescription_preview_screen.dart';
import '../../orders/services/prescription_upload_service.dart';
import '../../orders/widgets/prescription_source_sheet.dart';

class MedicineScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>>? prescriptionMedicines;
  /// When set, scopes the catalogue to one pharmacy's own stock — the "menu"
  /// screen reached by tapping a pharmacy card on [PharmacyScreen]. Fetched
  /// by id (not passed via nav `extra`) so deep links still work.
  final String? pharmacyId;
  const MedicineScreen({super.key, this.prescriptionMedicines, this.pharmacyId});

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

  // Pharmacy scoping (set when reached via a pharmacy card, see widget.pharmacyId)
  Map<String, dynamic>? _pharmacy;

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

  // ── Upload prescription before checkout ──────────────────────────────────
  // The upload feature itself was already well-built (source picker, review,
  // compression, size guard) — it just wasn't reachable from here, only from
  // an order's own detail screen after purchase. No `orders/{orderId}` exists
  // yet at this point, so this uploads to a uid-scoped pending path instead
  // (see PrescriptionUploadService.uploadPending) and carries the result via
  // pendingPrescriptionProvider — cart_screen.dart's checkout reads it and
  // writes it onto the new order's initial fields.
  /// Returns whether a prescription is attached to [pendingPrescriptionProvider]
  /// once this call resolves (true after a successful upload, false if the
  /// patient backed out at any step).
  Future<bool> _uploadPrescription() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final file = await showPrescriptionSourceSheet(context);
    if (file == null || !mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrescriptionPreviewScreen(
          file: file,
          onUpload: (f, onProgress) async {
            final result = await PrescriptionUploadService.uploadPending(
              uid: uid,
              file: f,
              onProgress: onProgress,
            );
            ref.read(pendingPrescriptionProvider.notifier).state =
                PendingPrescription(
              url: result.url,
              fileType: result.fileType,
              fileName: result.fileName,
            );
          },
        ),
      ),
    );
    return ref.read(pendingPrescriptionProvider) != null;
  }

  /// Shown once per screen visit (skippable) so patients can attach a
  /// prescription before browsing, instead of only via the app-bar icon.
  /// Skipped entirely when arriving from a doctor's own e-prescription
  /// (`widget.prescriptionMedicines`) — that's already a verified
  /// prescription on file, nothing more to collect.
  Future<void> _showInitialPrescriptionPrompt() async {
    if (!mounted || ref.read(pendingPrescriptionProvider) != null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PrescriptionPromptSheet(),
    );
    if (action == 'upload') await _uploadPrescription();
  }

  /// Gate for Rx-required medicines: if skipped earlier (or never prompted)
  /// and no prescription is attached yet, ask for one now before adding —
  /// added to cart immediately once the upload succeeds.
  Future<bool> _ensurePrescriptionFor(String medName) async {
    if (ref.read(pendingPrescriptionProvider) != null) return true;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Prescription Required'),
        content: Text('$medName needs a valid prescription. Upload one now to add it to your cart.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            child: const Text('Upload Prescription', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return false;
    return _uploadPrescription();
  }

  void _clearPendingPrescription() {
    ref.read(pendingPrescriptionProvider.notifier).state = null;
    FeedbackService.showInfo(context, 'Prescription removed');
  }
  CartItem? _cartItemForMed(String medId) =>
      _medicineCartItems.where((i) => i.serviceDetails['id'] == medId).firstOrNull;

  @override
  void initState() {
    super.initState();
    if (widget.prescriptionMedicines != null && widget.prescriptionMedicines!.isNotEmpty) {
      _prescriptionMeds = List.from(widget.prescriptionMedicines!);
      _showPrescriptionMeds = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showInitialPrescriptionPrompt());
    }
    if (widget.pharmacyId != null) {
      FirebaseFirestore.instance.collection('pharmacy_profiles').doc(widget.pharmacyId).get().then((snap) {
        if (mounted) setState(() => _pharmacy = snap.data());
      });
    }
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('medicines_catalogue')
        .where('isActive', isEqualTo: true);
    if (widget.pharmacyId != null) {
      query = query.where('sourcePharmacyId', isEqualTo: widget.pharmacyId);
    }
    _catalogueSub = query.snapshots().listen((snap) {
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
            'sourcePharmacyId':     data['sourcePharmacyId'] as String?,
            'pharmacyName':         data['pharmacyName'] as String?,
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

  /// Shows the "your cart has items from another pharmacy" confirm dialog;
  /// returns true if the cart's medicine items should be cleared and the add
  /// should proceed, false/null if the user cancelled.
  Future<bool> _confirmPharmacySwitch(String existingVendorName, String newPharmacyName) async {
    final replace = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace items in cart?'),
        content: Text(
          'Your cart has medicines from $existingVendorName. '
          'Add medicines from $newPharmacyName instead?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
        ],
      ),
    );
    return replace == true;
  }

  /// Entry point for manual "Add" taps on the general catalogue: gates
  /// Rx-required medicines behind a prescription before adding.
  Future<void> _addMedToCart(Map<String, dynamic> med) async {
    if (med['requiresPrescription'] == true) {
      final ok = await _ensurePrescriptionFor(med['name'] as String);
      if (!ok || !mounted) return;
    }
    await _performAddToCart(med);
  }

  /// Actually adds [med] to the cart — no prescription gate. Used both by
  /// [_addMedToCart] after the gate passes, and directly by the
  /// doctor-e-prescription flow ([_addToCatalogueFromPrescription],
  /// [_addAllPrescriptionMeds]), which is already a verified prescription.
  Future<void> _performAddToCart(Map<String, dynamic> med) async {
    final sourcePharmacyId = med['sourcePharmacyId'] as String?;
    if (sourcePharmacyId != null) {
      final conflict = ref.read(cartProvider.notifier)
          .conflictFor(type: 'medicine', vendorKey: 'pharmacy:$sourcePharmacyId');
      if (conflict != null) {
        final proceed = await _confirmPharmacySwitch(
          conflict.existingVendorName,
          (med['pharmacyName'] as String?) ?? 'this pharmacy',
        );
        if (!proceed || !mounted) return;
        ref.read(cartProvider.notifier).clearType('medicine');
      }
    }
    ref.read(cartProvider.notifier).addItem(
          type: 'medicine',
          serviceName: med['name'] as String,
          themeColor: const Color(0xFF2E7D32),
          unitAmount: med['price'] as int,
          serviceDetails: {
            'id': med['id'],
            'name': med['name'],
            'brand': med['brand'],
            'sourcePharmacyId': med['sourcePharmacyId'],
            'pharmacyName': med['pharmacyName'],
          },
        );
  }

  void _addToCatalogueFromPrescription(Map<String, dynamic> rxMed) {
    final keyword = (rxMed['name'] as String? ?? '').toLowerCase().split(' ').first;
    final med = _catalogue.where((c) => (c['name'] as String).toLowerCase().contains(keyword)).firstOrNull;
    if (med != null && _cartItemForMed(med['id'] as String) == null) {
      _performAddToCart(med);
    }
  }

  Future<void> _addAllPrescriptionMeds() async {
    // Resolve the batch's target pharmacy from the first catalogue match, so
    // a flat multi-pharmacy catalogue doesn't prompt a replace-cart dialog
    // once per item. Items from a different pharmacy than this are skipped,
    // not individually confirmed.
    String? targetPharmacyId;
    String? targetPharmacyName;
    for (final m in _prescriptionMeds) {
      final keyword = (m['name'] as String? ?? '').toLowerCase().split(' ').first;
      final med = _catalogue.where((c) => (c['name'] as String).toLowerCase().contains(keyword)).firstOrNull;
      if (med != null) {
        targetPharmacyId = med['sourcePharmacyId'] as String?;
        targetPharmacyName = med['pharmacyName'] as String?;
        break;
      }
    }

    if (targetPharmacyId != null) {
      final conflict = ref.read(cartProvider.notifier)
          .conflictFor(type: 'medicine', vendorKey: 'pharmacy:$targetPharmacyId');
      if (conflict != null) {
        final proceed = await _confirmPharmacySwitch(
          conflict.existingVendorName,
          targetPharmacyName ?? 'this pharmacy',
        );
        if (!proceed || !mounted) return;
        ref.read(cartProvider.notifier).clearType('medicine');
      }
    }

    int added = 0;
    int skipped = 0;
    for (final m in _prescriptionMeds) {
      final keyword = (m['name'] as String? ?? '').toLowerCase().split(' ').first;
      final med = _catalogue.where((c) => (c['name'] as String).toLowerCase().contains(keyword)).firstOrNull;
      if (med == null || _cartItemForMed(med['id'] as String) != null) continue;
      final medPharmacyId = med['sourcePharmacyId'] as String?;
      if (targetPharmacyId != null && medPharmacyId != null && medPharmacyId != targetPharmacyId) {
        skipped++;
        continue;
      }
      ref.read(cartProvider.notifier).addItem(
            type: 'medicine',
            serviceName: med['name'] as String,
            themeColor: const Color(0xFF2E7D32),
            unitAmount: med['price'] as int,
            serviceDetails: {
              'id': med['id'],
              'name': med['name'],
              'brand': med['brand'],
              'sourcePharmacyId': med['sourcePharmacyId'],
              'pharmacyName': med['pharmacyName'],
            },
          );
      added++;
    }
    if (mounted) {
      final parts = <String>[
        if (added > 0) '$added medicine${added > 1 ? 's' : ''} added to cart',
        if (skipped > 0) '$skipped skipped (different pharmacy)',
      ];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(parts.isEmpty ? 'Medicines already in cart' : parts.join(', ')),
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
            backgroundColor: const Color(0xFF2E7D32),
            expandedHeight: AppSpacing.headerHeight(context),
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => context.pop()),
            actions: [
              IconButton(
                icon: const Icon(Icons.upload_file_rounded, color: Colors.white),
                tooltip: 'Upload Prescription',
                onPressed: _uploadPrescription,
              ),
              const CartBadgeAction(),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppColors.medicineGrad),
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
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
                              Text(
                                widget.pharmacyId != null ? ((_pharmacy?['name'] as String?) ?? 'Pharmacy') : 'Pharmacy',
                                style: AppTextStyles.onPrimaryH2,
                              ),
                              const Text('Order genuine medicines, delivered fast', style: AppTextStyles.onPrimaryBody),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(children: [
              if (ref.watch(pendingPrescriptionProvider) != null) ...[
                SizedBox(height: R.h(context, 14)),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: R.p(context, 16)),
                  padding: EdgeInsets.symmetric(horizontal: R.p(context, 14), vertical: R.p(context, 12)),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(R.r(context, 14)),
                    border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 20),
                    SizedBox(width: R.w(context, 10)),
                    Expanded(
                      child: Text(
                        'Prescription attached — it will be added to your order.',
                        style: AppTextStyles.bodySmall.copyWith(color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                      ),
                    ),
                    GestureDetector(
                      onTap: _clearPendingPrescription,
                      child: const Icon(Icons.close_rounded, color: Color(0xFF2E7D32), size: 18),
                    ),
                  ]),
                ),
              ],
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
                child: const Align(alignment: Alignment.centerLeft, child: Text('Available Medicines', style: AppTextStyles.h4)),
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

  Widget _buildEmptyState() => AppEmptyState(
    icon: Icons.medication_outlined,
    iconColor: const Color(0xFF2E7D32),
    title: 'No Medicines Available',
    message: widget.pharmacyId != null
        ? 'This pharmacy hasn\'t listed its catalogue yet. Check back soon or try another pharmacy nearby.'
        : 'The medicine catalogue will appear here once added by the pharmacy team.',
    actionLabel: widget.pharmacyId != null ? 'Browse Other Pharmacies' : null,
    onAction: widget.pharmacyId != null ? () => context.pop() : null,
  );
}

// ── Reusable widgets ────────────────────────────────────────────────────────

/// Skippable first-touch sheet: attach a prescription before browsing, or
/// skip and get prompted again only when an Rx-required medicine is added
/// (see [_MedicineScreenState._ensurePrescriptionFor]).
class _PrescriptionPromptSheet extends StatelessWidget {
  const _PrescriptionPromptSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF2E7D32), size: 28),
            ),
            const SizedBox(height: 14),
            const Text('Have a prescription?', style: AppTextStyles.h4, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'Upload it now to order prescription medicines directly, or skip and add it later when needed.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, 'upload'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Upload Prescription', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, 'skip'),
                child: Text('Skip for now', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: inCart ? const Color(0xFF2E7D32).withValues(alpha:0.4) : context.appBorder),
        boxShadow: inCart ? [BoxShadow(color: const Color(0xFF2E7D32).withValues(alpha:0.08), blurRadius: 8, offset: const Offset(0, 2))] : null,
      ),
      // Zomato-style dish row: name/description/price on the left, a photo
      // tile with a floating Add button overlapping its bottom edge on the
      // right. Medicines have no photo field yet, so the tile is a fixed
      // icon rather than a fabricated image.
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(medicine['name'] as String, style: AppTextStyles.labelLarge)),
            if (needsRx) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha:0.1), borderRadius: BorderRadius.circular(6)),
                child: const Text('Rx', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w800, color: Colors.orange)),
              ),
            ],
          ]),
          const SizedBox(height: 3),
          Text('${medicine['brand']} • ${medicine['qty']} ${medicine['unit']}', style: AppTextStyles.bodySmall),
          const SizedBox(height: 8),
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
        const SizedBox(width: 10),
        SizedBox(
          width: 88,
          child: Column(children: [
            Container(
              width: 76, height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha:0.15)),
              ),
              child: const Icon(Icons.medication_rounded, color: Color(0xFF2E7D32), size: 34),
            ),
            Transform.translate(
              offset: const Offset(0, -14),
              child: inCart
                  ? Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: context.appSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2E7D32)),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.08), blurRadius: 4, offset: const Offset(0, 1))],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _QtyBtn(icon: Icons.remove_rounded, onTap: onDecrement),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text('$cartCount', style: AppTextStyles.labelLarge)),
                        _QtyBtn(icon: Icons.add_rounded, onTap: onIncrement),
                      ]),
                    )
                  : GestureDetector(
                      onTap: onAdd,
                      child: Container(
                        height: 28,
                        width: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF2E7D32)),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.08), blurRadius: 4, offset: const Offset(0, 1))],
                        ),
                        child: const Text('ADD', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF2E7D32))),
                      ),
                    ),
            ),
          ]),
        ),
      ]),
    );
  }
}
