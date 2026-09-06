import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../orders/providers/order_providers.dart';

/// Read-only history of medicines the patient has taken — merges doctor
/// prescriptions (`prescriptions` collection) with pharmacy purchases
/// (`orders` collection, via [myOrdersProvider]) into one timeline. This is
/// distinct from the pharmacy/ordering flow at [AppRoutes.medicine].
class MyMedicinesScreen extends ConsumerStatefulWidget {
  const MyMedicinesScreen({super.key});

  @override
  ConsumerState<MyMedicinesScreen> createState() => _MyMedicinesScreenState();
}

enum _MedSource { prescribed, ordered }

class _MedicineEntry {
  final _MedSource source;
  final String name;
  final String subtitle;
  final DateTime? date;

  // Prescription-only fields
  final bool morning;
  final bool afternoon;
  final bool night;
  final String foodTiming;
  final String duration;
  final String instruction;
  final String frequency;
  final String dosage;
  final String doctorName;
  final Map<String, dynamic>? rx;

  // Order-only fields
  final int quantity;
  final String status;
  final String? orderId;

  _MedicineEntry.prescribed({
    required this.name,
    required this.subtitle,
    required this.date,
    required this.morning,
    required this.afternoon,
    required this.night,
    required this.foodTiming,
    required this.duration,
    required this.instruction,
    required this.frequency,
    required this.dosage,
    required this.doctorName,
    required this.rx,
  })  : source = _MedSource.prescribed,
        quantity = 0,
        status = '',
        orderId = null;

  _MedicineEntry.ordered({
    required this.name,
    required this.subtitle,
    required this.date,
    required this.quantity,
    required this.status,
    required this.orderId,
  })  : source = _MedSource.ordered,
        morning = false,
        afternoon = false,
        night = false,
        foodTiming = '',
        duration = '',
        instruction = '',
        frequency = '',
        dosage = '',
        doctorName = '',
        rx = null;

  bool get hasDose => morning || afternoon || night;
}

class _MyMedicinesScreenState extends ConsumerState<MyMedicinesScreen> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<_MedicineEntry> _prescribedEntries = [];
  bool _rxLoading = true;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _subscribePrescriptions();
  }

  void _subscribePrescriptions() {
    if (_uid.isEmpty) {
      setState(() => _rxLoading = false);
      return;
    }
    _sub = FirebaseFirestore.instance
        .collection('prescriptions')
        .where('patientId', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final entries = <_MedicineEntry>[];
      for (final doc in snap.docs) {
        final rx = Map<String, dynamic>.from(doc.data());
        rx['id'] = doc.id;
        final doctorName = rx['doctorName'] as String? ?? 'Doctor';
        final createdAt = rx['createdAt'];
        final date = createdAt is Timestamp ? createdAt.toDate() : null;
        final meds = rx['medicines'] as List<dynamic>? ?? [];
        for (final raw in meds) {
          final m = Map<String, dynamic>.from(raw as Map);
          final strength = m['strength'] as String? ?? m['dosage'] as String? ?? '';
          entries.add(_MedicineEntry.prescribed(
            name: (m['medicineName'] as String? ?? m['name'] as String? ?? '').trim(),
            subtitle: strength,
            date: date,
            morning: m['morning'] as bool? ?? false,
            afternoon: m['afternoon'] as bool? ?? false,
            night: m['night'] as bool? ?? false,
            foodTiming: m['foodTiming'] as String? ?? m['timing'] as String? ?? '',
            duration: m['duration'] as String? ?? '',
            instruction: m['instruction'] as String? ?? '',
            frequency: m['frequency'] as String? ?? '',
            dosage: m['dosage'] as String? ?? '',
            doctorName: doctorName,
            rx: rx,
          ));
        }
      }
      setState(() {
        _prescribedEntries = entries;
        _rxLoading = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _rxLoading = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _formatDate(DateTime? d) => d == null ? '' : DateFormat('d MMM yyyy').format(d);

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
      case 'rejected':
        return AppColors.error;
      case 'out_for_delivery':
      case 'shipped':
      case 'confirmed':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  String _statusLabel(String status) {
    if (status.isEmpty) return '';
    return status
        .split('_')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(myOrdersProvider);
    final orderedEntries = ordersAsync.maybeWhen(
      data: (orders) => orders
          .expand((order) => order.items.map((item) => _MedicineEntry.ordered(
                name: item.name,
                subtitle: item.brand,
                date: order.createdAt,
                quantity: item.count,
                status: order.status,
                orderId: order.orderId,
              )))
          .toList(),
      orElse: () => <_MedicineEntry>[],
    );

    final loading = _rxLoading || ordersAsync.isLoading;

    final combined = [..._prescribedEntries, ...orderedEntries]
      ..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.appTextPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'My Medicines',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: context.appTextPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      body: loading ? _buildSkeleton() : _buildBody(combined),
    );
  }

  Widget _buildSkeleton() => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppShimmer(
              child: Container(
                height: 96,
                decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _buildBody(List<_MedicineEntry> entries) {
    if (entries.isEmpty) {
      return const AppEmptyState(
        icon: Icons.medication_rounded,
        title: 'No medicines booked yet',
        message: 'Medicines you order or get prescribed will appear here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: entries.length,
      itemBuilder: (context, i) => entries[i].source == _MedSource.prescribed
          ? _buildPrescribedCard(entries[i])
          : _buildOrderedCard(entries[i]),
    );
  }

  Widget _cardShell({required Widget child, required VoidCallback onTap, required Color color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(14), child: child),
        ),
      ),
    );
  }

  Widget _sourceTag(String label, IconData icon, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _buildPrescribedCard(_MedicineEntry e) {
    const color = AppColors.primary;
    return _cardShell(
      color: color,
      onTap: () => context.push(AppRoutes.prescriptionViewer, extra: e.rx),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.medication_rounded, color: color, size: 20),
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
                            e.name.isEmpty ? 'Medicine' : e.name,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: context.appTextPrimary,
                            ),
                          ),
                        ),
                        _sourceTag('Prescribed', Icons.receipt_long_rounded, color),
                      ],
                    ),
                    if (e.subtitle.isNotEmpty)
                      Text(
                        e.subtitle,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: context.appTextSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (e.morning) _chip(Icons.wb_sunny_outlined, 'Morning', const Color(0xFFFF9800)),
              if (e.afternoon) _chip(Icons.wb_twilight_rounded, 'Afternoon', const Color(0xFFF44336)),
              if (e.night) _chip(Icons.nights_stay_outlined, 'Night', const Color(0xFF5C6BC0)),
              if (!e.hasDose && e.frequency.isNotEmpty) _chip(Icons.repeat_rounded, e.frequency, color),
              if (!e.hasDose && e.dosage.isNotEmpty && e.dosage != e.subtitle)
                _chip(Icons.scale_rounded, e.dosage, color),
              if (e.foodTiming.isNotEmpty) _chip(Icons.restaurant_rounded, e.foodTiming, AppColors.accent),
              if (e.duration.isNotEmpty)
                _chip(Icons.calendar_today_rounded, e.duration, const Color(0xFF633058)),
            ],
          ),
          if (e.instruction.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              e.instruction,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: context.appTextSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.person_rounded, size: 12, color: context.appTextHint),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Dr. ${e.doctorName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: context.appTextHint),
                ),
              ),
              if (e.date != null) ...[
                const SizedBox(width: 6),
                Text(
                  _formatDate(e.date),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: context.appTextHint),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderedCard(_MedicineEntry e) {
    const color = AppColors.accent;
    return _cardShell(
      color: color,
      onTap: () => context.push(AppRoutes.orderDetail, extra: {'orderId': e.orderId}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.shopping_bag_rounded, color: color, size: 20),
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
                            e.name.isEmpty ? 'Medicine' : e.name,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: context.appTextPrimary,
                            ),
                          ),
                        ),
                        _sourceTag('Ordered', Icons.shopping_bag_rounded, color),
                      ],
                    ),
                    if (e.subtitle.isNotEmpty)
                      Text(
                        e.subtitle,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: context.appTextSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(Icons.numbers_rounded, 'Qty ${e.quantity}', color),
              if (e.status.isNotEmpty)
                StatusBadge(label: _statusLabel(e.status), color: _statusColor(e.status)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.local_pharmacy_rounded, size: 12, color: context.appTextHint),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Pharmacy order',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: context.appTextHint),
                ),
              ),
              if (e.date != null) ...[
                const SizedBox(width: 6),
                Text(
                  _formatDate(e.date),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: context.appTextHint),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}
