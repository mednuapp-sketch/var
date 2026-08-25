import 'package:flutter/material.dart';
import '../../../core/router/app_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/ux_widgets.dart';

class MaternityPrescriptionScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final int pregnancyWeek;

  const MaternityPrescriptionScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    this.pregnancyWeek = 1,
  });

  @override
  State<MaternityPrescriptionScreen> createState() =>
      _MaternityPrescriptionScreenState();
}

class _MaternityPrescriptionScreenState
    extends State<MaternityPrescriptionScreen> {
  final List<Map<String, dynamic>> _items = [];
  bool _saving = false;

  void _addItem() {
    setState(() {
      _items.add({
        'name': '',
        'dosage': '',
        'frequency': '',
        'type': 'medicine',
        'instructions': '',
        'reminderTime': '',
      });
    });
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  Future<void> _save() async {
    final touchedItems = _items.where((i) =>
        (i['name'] as String).trim().isNotEmpty ||
        (i['dosage'] as String).trim().isNotEmpty ||
        (i['frequency'] as String).trim().isNotEmpty).toList();
    if (touchedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one medicine')),
      );
      return;
    }
    // A medicine name alone isn't enough to prescribe safely — dosage and
    // frequency are required for every item the doctor has started filling
    // in, so a prescription can't go out half-specified.
    final incompleteIndex = _items.indexWhere((i) =>
        (i['name'] as String).trim().isNotEmpty &&
        ((i['dosage'] as String).trim().isEmpty ||
            (i['frequency'] as String).trim().isEmpty));
    if (incompleteIndex != -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            'Item ${incompleteIndex + 1}: dosage and frequency are required')),
      );
      return;
    }
    final validItems = touchedItems
        .where((i) => (i['name'] as String).trim().isNotEmpty)
        .toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one medicine name')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final now = Timestamp.now();
      final batch = FirebaseFirestore.instance.batch();

      for (final item in validItems) {
        final ref = FirebaseFirestore.instance.collection('pregnancy_medicines').doc();
        batch.set(ref, {
          'patientId': widget.patientId,
          'name': (item['name'] as String).trim(),
          'dosage': (item['dosage'] as String).trim(),
          'frequency': (item['frequency'] as String).trim(),
          'type': item['type'],
          'instructions': (item['instructions'] as String).trim().isEmpty
              ? null
              : (item['instructions'] as String).trim(),
          'reminderTime': (item['reminderTime'] as String).trim().isEmpty
              ? null
              : (item['reminderTime'] as String).trim(),
          'prescribedBy': uid,
          'pregnancyWeek': widget.pregnancyWeek,
          'startDate': now,
          'isActive': true,
          'createdAt': now,
        });
      }

      // Also notify the patient
      final notifRef = FirebaseFirestore.instance
          .collection('patient_notifications')
          .doc(widget.patientId)
          .collection('items')
          .doc();
      batch.set(notifRef, {
        'title': 'New Prescription',
        'body': 'Your doctor has added ${validItems.length} medicine(s) to your maternity care plan.',
        'type': 'maternity_prescription',
        'isRead': false,
        'createdAt': now,
      });

      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prescription saved and patient notified'),
          backgroundColor: AppColors.success,
        ),
      );
      context.safeBack();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Validators.friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.heroBannerGradient,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => context.safeBack(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Maternity Prescription',
                style: AppTextStyles.h4.copyWith(color: Colors.white)),
            Text(
              widget.patientName,
              style: AppTextStyles.caption.copyWith(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Save', style: AppTextStyles.labelLarge.copyWith(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Patient info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Week ${widget.pregnancyWeek}',
                    style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.textHint),
              const SizedBox(width: 4),
              const Expanded(
                child: Text('Prescriptions will be visible to the patient immediately.',
                    style: TextStyle(fontSize: 11, color: AppColors.textHint)),
              ),
            ]),
          ),
          const SizedBox(height: 4),

          // Quick templates
          Container(
            height: 44,
            color: AppColors.surfaceVariant,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                'Folic Acid', 'Iron', 'Calcium', 'Vitamin D3', 'Vitamin B12',
                'DHA Omega-3', 'Multivitamin',
              ].map((t) => GestureDetector(
                onTap: () => setState(() {
                  _items.add({
                    'name': t,
                    'dosage': '1 tablet',
                    'frequency': 'Once daily',
                    'type': 'vitamin',
                    'instructions': 'After meals',
                    'reminderTime': '08:00 AM',
                  });
                }),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha:0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withValues(alpha:0.2)),
                  ),
                  child: Text('+ $t', style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w500)),
                ),
              )).toList(),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ..._items.asMap().entries.map((e) => _itemCard(e.key, e.value)),
                const SizedBox(height: 8),
                GradientButton(
                  label: 'Add Medicine',
                  icon: Icons.add_rounded,
                  width: double.infinity,
                  height: 48,
                  onTap: _addItem,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(int index, Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Item ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 13)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                onPressed: () => _removeItem(index),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _field(
            label: 'Medicine / Vitamin Name *',
            value: item['name'],
            onChanged: (v) => setState(() => _items[index]['name'] = v),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _field(
              label: 'Dosage',
              value: item['dosage'],
              onChanged: (v) => setState(() => _items[index]['dosage'] = v),
            )),
            const SizedBox(width: 8),
            Expanded(child: _field(
              label: 'Frequency',
              value: item['frequency'],
              onChanged: (v) => setState(() => _items[index]['frequency'] = v),
            )),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: item['type'],
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                items: ['medicine', 'vitamin', 'supplement', 'injection']
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t[0].toUpperCase() + t.substring(1), style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _items[index]['type'] = v!),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _field(
              label: 'Reminder Time',
              value: item['reminderTime'],
              onChanged: (v) => setState(() => _items[index]['reminderTime'] = v),
            )),
          ]),
          const SizedBox(height: 8),
          _field(
            label: 'Instructions',
            value: item['instructions'],
            onChanged: (v) => setState(() => _items[index]['instructions'] = v),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required String value,
    required void Function(String) onChanged,
  }) =>
      TextFormField(
        initialValue: value,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        style: const TextStyle(fontSize: 13),
      );
}
