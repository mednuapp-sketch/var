import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../home/providers/location_provider.dart';
import '../../location/screens/map_location_picker_screen.dart';

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

  // Cart: medicine id → quantity
  final Map<String, int> _cart = {};

  // Search & prescription state
  String _search = '';
  File? _prescriptionImage;
  List<Map<String, dynamic>> _prescriptionMeds = [];
  bool _showPrescriptionMeds = false;
  final _imagePicker = ImagePicker();

  // Computed
  List<Map<String, dynamic>> get _filteredMeds {
    if (_search.isEmpty) return _catalogue;
    final q = _search.toLowerCase();
    return _catalogue.where((m) =>
      (m['name'] as String).toLowerCase().contains(q) ||
      (m['brand'] as String).toLowerCase().contains(q),
    ).toList();
  }

  int get _cartCount => _cart.values.where((v) => v > 0).length;
  int get _cartTotal => _catalogue
      .where((m) => (_cart[m['id'] as String] ?? 0) > 0)
      .fold(0, (s, m) => s + (m['price'] as int) * (_cart[m['id'] as String] ?? 0));
  List<Map<String, dynamic>> get _cartItems =>
      _catalogue.where((m) => (_cart[m['id'] as String] ?? 0) > 0).toList();

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

  void _addToCatalogueFromPrescription(Map<String, dynamic> rxMed) {
    final keyword = (rxMed['name'] as String? ?? '').toLowerCase().split(' ').first;
    final med = _catalogue.where((c) => (c['name'] as String).toLowerCase().contains(keyword)).firstOrNull;
    if (med != null && (_cart[med['id'] as String] ?? 0) == 0) {
      setState(() => _cart[med['id'] as String] = 1);
    }
  }

  void _addAllPrescriptionMeds() {
    int added = 0;
    for (final m in _prescriptionMeds) {
      final keyword = (m['name'] as String? ?? '').toLowerCase().split(' ').first;
      final med = _catalogue.where((c) => (c['name'] as String).toLowerCase().contains(keyword)).firstOrNull;
      if (med != null && (_cart[med['id'] as String] ?? 0) == 0) {
        _cart[med['id'] as String] = 1;
        added++;
      }
    }
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(added > 0 ? '$added medicine${added > 1 ? 's' : ''} added to cart' : 'Medicines already in cart'),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _pickPrescription(ImageSource source) async {
    Navigator.pop(context);
    try {
      final picked = await _imagePicker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      final file = File(picked.path);
      setState(() {
        _prescriptionImage = file;
        _prescriptionMeds = [];
        _showPrescriptionMeds = true;
      });
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance
          .ref()
          .child('prescriptions/$uid/${timestamp}_rx.jpg');
      final task = await ref.putFile(file);
      final url = await task.ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('prescription_uploads').add({
        'patientId':   uid,
        'imageUrl':    url,
        'storagePath': ref.fullPath,
        'status':      'pending_review',
        'uploadedAt':  FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Prescription uploaded! Our pharmacist will verify and add medicines shortly.'),
          backgroundColor: Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload failed: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ));
      }
    }
  }

  void _showUploadSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('Upload Prescription', style: AppTextStyles.h4),
          const SizedBox(height: 6),
          Text('Take a photo or upload from gallery', style: AppTextStyles.bodySmall),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _UploadOption(icon: Icons.camera_alt_rounded, label: 'Camera', color: const Color(0xFF2E7D32), onTap: () => _pickPrescription(ImageSource.camera))),
            const SizedBox(width: 14),
            Expanded(child: _UploadOption(icon: Icons.photo_library_rounded, label: 'Gallery', color: const Color(0xFF1565C0), onTap: () => _pickPrescription(ImageSource.gallery))),
          ]),
        ]),
      ),
    );
  }

  void _showCart() {
    if (_cartItems.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final items = _catalogue.where((m) => (_cart[m['id'] as String] ?? 0) > 0).toList();
          final subtotal = items.fold(0, (s, m) => s + (m['price'] as int) * (_cart[m['id'] as String] ?? 0));
          final deliveryFee = subtotal > 499 ? 0 : 30;
          final total = subtotal + deliveryFee;

          void doIncrement(String id) {
            setState(() => _cart[id] = (_cart[id] ?? 0) + 1);
            setSheetState(() {});
          }

          void doDecrement(String id) {
            setState(() {
              if ((_cart[id] ?? 0) <= 1) { _cart.remove(id); }
              else { _cart[id] = (_cart[id] ?? 0) - 1; }
            });
            setSheetState(() {});
            if (_cart.isEmpty) Navigator.pop(ctx);
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.78,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
            child: Column(children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              Row(children: [
                Text('Your Cart', style: AppTextStyles.h3),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text('${items.length} item${items.length > 1 ? 's' : ''}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
                ),
              ]),
              const SizedBox(height: 16),
              Expanded(child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final m = items[i];
                  final id = m['id'] as String;
                  final count = _cart[id] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(children: [
                      Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha:0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.medication_rounded, color: Color(0xFF2E7D32), size: 24)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m['name'] as String, style: AppTextStyles.labelLarge),
                        Text('${m['brand']} • ₹${m['price']}/strip', style: AppTextStyles.caption),
                      ])),
                      Row(children: [
                        _QtyBtn(icon: Icons.remove_rounded, onTap: () => doDecrement(id)),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('$count', style: AppTextStyles.labelLarge)),
                        _QtyBtn(icon: Icons.add_rounded, onTap: () => doIncrement(id)),
                      ]),
                      const SizedBox(width: 12),
                      Text('₹${(m['price'] as int) * count}', style: AppTextStyles.labelLarge.copyWith(color: const Color(0xFF2E7D32))),
                    ]),
                  );
                },
              )),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
                child: Column(children: [
                  _BillRow('Subtotal', '₹$subtotal'),
                  const SizedBox(height: 6),
                  _BillRow('Delivery Fee', deliveryFee == 0 ? 'FREE' : '₹$deliveryFee', valueColor: deliveryFee == 0 ? const Color(0xFF2E7D32) : null),
                  if (deliveryFee == 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Free delivery on orders above ₹499', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: Color(0xFF2E7D32))),
                    ),
                  const Divider(height: 20),
                  _BillRow('Total', '₹$total', bold: true),
                  const SizedBox(height: 14),
                  SafeArea(
                    child: SizedBox(width: double.infinity, child: ElevatedButton(
                      onPressed: () async {
                        final address = await _collectDeliveryAddress(context);
                        if (address == null) return;
                        Navigator.pop(context);
                        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                        final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
                        final cartItems = _cartItems.map((m) {
                          final id = m['id'] as String;
                          return {
                            'id':    id,
                            'name':  m['name'],
                            'brand': m['brand'],
                            'price': m['price'],
                            'count': _cart[id] ?? 0,
                          };
                        }).toList();
                        final orderData = {
                          'orderId':         orderId,
                          'patientId':       uid,
                          'items':           cartItems,
                          'total':           total,
                          'status':          'confirmed',
                          'deliveryAddress': address['address'],
                          'deliveryName':    address['name'],
                          'deliveryPhone':   address['phone'],
                          if (address['lat'] != null) 'lat': address['lat'],
                          if (address['lng'] != null) 'lng': address['lng'],
                          'createdAt':       FieldValue.serverTimestamp(),
                        };
                        if (uid.isNotEmpty) {
                          await FirebaseFirestore.instance
                              .collection('orders')
                              .doc(orderId)
                              .set(orderData);
                        }
                        if (context.mounted) {
                          context.push(AppRoutes.orderTracking, extra: {
                            ...orderData,
                            'createdAt': null,
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text('Place Order  •  ₹$total', style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700)),
                    )),
                  ),
                  const SizedBox(height: 8),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _collectDeliveryAddress(BuildContext ctx) async {
    final nameCtrl    = TextEditingController();
    final phoneCtrl   = TextEditingController();
    final addressCtrl = TextEditingController();
    double? deliveryLat;
    double? deliveryLng;

    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Pre-fill from locationProvider (shared service)
    final locState = ref.read(locationProvider);
    if (locState.hasCoordinates) {
      final precise = locState.preciseAddress;
      addressCtrl.text = precise?.formatted ?? locState.fullAddress;
      deliveryLat = locState.lat;
      deliveryLng = locState.lng;
    }

    // Also load name/phone from Firestore
    if (uid != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final data = snap.data();
        if (data != null) {
          nameCtrl.text  = data['name']  as String? ?? '';
          phoneCtrl.text = data['phone'] as String? ?? '';
          // Only override address if locationProvider had nothing
          if (addressCtrl.text.isEmpty) {
            addressCtrl.text =
                data['deliveryAddress'] as String? ?? '';
          }
        }
      } catch (_) {}
    }

    if (!ctx.mounted) return null;

    return showDialog<Map<String, dynamic>>(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Delivery Details',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon:
                        const Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon:
                        const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Delivery Address',
                    prefixIcon:
                        const Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 13),
                ),
                const SizedBox(height: 10),
                // Map picker shortcut
                OutlinedButton.icon(
                  onPressed: () async {
                    final locS = ref.read(locationProvider);
                    final picked =
                        await Navigator.push<PreciseAddress>(
                      dCtx,
                      MaterialPageRoute(
                        builder: (_) => MapLocationPickerScreen(
                          initialLat: locS.lat,
                          initialLng: locS.lng,
                        ),
                      ),
                    );
                    if (picked != null) {
                      setDState(() {
                        addressCtrl.text = picked.formatted;
                        deliveryLat = picked.lat;
                        deliveryLng = picked.lng;
                      });
                    }
                  },
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text(
                    'Pick on Map',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.4)),
                    minimumSize: const Size(double.infinity, 40),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name  = nameCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                final addr  = addressCtrl.text.trim();
                if (name.isEmpty || phone.isEmpty || addr.isEmpty) {
                  return;
                }
                if (uid != null) {
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .update({'deliveryAddress': addr})
                      .catchError((_) {});
                }
                Navigator.pop(dCtx, {
                  'name': name,
                  'phone': phone,
                  'address': addr,
                  if (deliveryLat != null) 'lat': deliveryLat,
                  if (deliveryLng != null) 'lng': deliveryLng,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 160,
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => context.pop()),
            actions: [
              Stack(alignment: Alignment.center, children: [
                IconButton(icon: const Icon(Icons.shopping_cart_rounded, color: Colors.white), onPressed: _showCart),
                if (_cartCount > 0)
                  Positioned(top: 8, right: 8, child: Container(
                    width: 16, height: 16,
                    decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                    child: Center(child: Text('$_cartCount', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black))),
                  )),
              ]),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: SafeArea(child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.medication_liquid_rounded, color: Colors.white, size: 36),
                    const SizedBox(height: 8),
                    Text('Medicine Delivery', style: AppTextStyles.onPrimaryH2),
                    Text('Delivered in 2–4 hours  •  Genuine medicines', style: AppTextStyles.onPrimaryBody),
                  ]),
                )),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(children: [
              // Upload Prescription card
              GestureDetector(
                onTap: _showUploadSheet,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFE3F2FD), Color(0xFFE8F5E9)]),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha:0.3)),
                  ),
                  child: Row(children: [
                    _prescriptionImage != null
                        ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(_prescriptionImage!, width: 56, height: 56, fit: BoxFit.cover))
                        : Container(width: 56, height: 56, decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha:0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.upload_file_rounded, color: Color(0xFF2E7D32), size: 30)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        _prescriptionImage != null ? 'Prescription Uploaded ✓' : 'Upload Prescription',
                        style: AppTextStyles.labelLarge.copyWith(color: const Color(0xFF2E7D32)),
                      ),
                      Text(
                        _prescriptionImage != null
                            ? (_prescriptionMeds.isNotEmpty ? 'Tap to change  •  ${_prescriptionMeds.length} medicines found' : 'Pending pharmacist review  •  Search medicines below')
                            : 'Get medicines as prescribed by your doctor',
                        style: AppTextStyles.bodySmall,
                      ),
                    ])),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        _prescriptionImage != null ? 'Change' : 'Upload',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
              ),

              // Prescription medicines section
              if (_showPrescriptionMeds && _prescriptionMeds.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
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
                        return (c['name'] as String).toLowerCase().contains(keyword) && (_cart[cId] ?? 0) > 0;
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search medicines, brands…',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(alignment: Alignment.centerLeft, child: Text('Available Medicines', style: AppTextStyles.h4)),
              ),
              const SizedBox(height: 12),

              // Loading state
              if (_catalogueLoading)
                ..._buildSkeletonCards()
              else if (_catalogue.isEmpty)
                _buildEmptyState()
              else if (_filteredMeds.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(children: [
                    const Icon(Icons.search_off_rounded, size: 48, color: AppColors.textHint),
                    const SizedBox(height: 12),
                    Text('No medicines found for "$_search"', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
                  ]),
                )
              else
                ..._filteredMeds.map((med) {
                  final id = med['id'] as String;
                  final cartCount = _cart[id] ?? 0;
                  return _MedicineCard(
                    medicine: med,
                    cartCount: cartCount,
                    onAdd:       () => setState(() => _cart[id] = 1),
                    onIncrement: () => setState(() => _cart[id] = (_cart[id] ?? 0) + 1),
                    onDecrement: () => setState(() {
                      if ((_cart[id] ?? 0) <= 1) { _cart.remove(id); }
                      else { _cart[id] = (_cart[id] ?? 0) - 1; }
                    }),
                  );
                }),

              const SizedBox(height: 110),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: _cartCount > 0
          ? Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.08), blurRadius: 16, offset: const Offset(0, -4))],
              ),
              child: ElevatedButton(
                onPressed: _showCart,
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

  List<Widget> _buildSkeletonCards() => List.generate(5, (_) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    height: 90,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.divider),
    ),
  ));

  Widget _buildEmptyState() => Padding(
    padding: const EdgeInsets.all(40),
    child: Column(children: [
      Icon(Icons.medication_outlined, size: 64, color: Colors.grey[300]),
      const SizedBox(height: 16),
      Text('No medicines available yet', style: AppTextStyles.bodyMedium, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text('Medicine catalogue will appear here once added by the pharmacy team', style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
    ]),
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

class _BillRow extends StatelessWidget {
  final String label, value;
  final bool bold;
  final Color? valueColor;
  const _BillRow(this.label, this.value, {this.bold = false, this.valueColor});
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: bold ? AppTextStyles.labelLarge : AppTextStyles.bodyMedium),
    Text(value, style: (bold ? AppTextStyles.labelLarge : AppTextStyles.bodyMedium).copyWith(color: valueColor)),
  ]);
}

class _UploadOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _UploadOption({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha:0.3)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ]),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: inCart ? const Color(0xFF2E7D32).withValues(alpha:0.4) : AppColors.divider),
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
              Text('₹$mrp', style: AppTextStyles.caption.copyWith(decoration: TextDecoration.lineThrough, color: AppColors.textHint)),
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
