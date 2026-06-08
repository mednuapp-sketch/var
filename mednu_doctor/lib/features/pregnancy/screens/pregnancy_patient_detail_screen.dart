import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';

class PregnancyPatientDetailScreen extends StatefulWidget {
  final String profileId;
  final String patientId;
  final String patientName;

  const PregnancyPatientDetailScreen({
    super.key,
    required this.profileId,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<PregnancyPatientDetailScreen> createState() =>
      _PregnancyPatientDetailScreenState();
}

class _PregnancyPatientDetailScreenState
    extends State<PregnancyPatientDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('pregnancy_profiles')
          .doc(widget.profileId)
          .snapshots(),
      builder: (context, snap) {
        final profile = snap.data?.data() as Map<String, dynamic>? ?? {};
        final lmpDate = (profile['lmpDate'] as Timestamp?)?.toDate() ?? DateTime.now();
        final days = DateTime.now().difference(lmpDate).inDays;
        final week = (days / 7).floor().clamp(1, 42);
        final isHighRisk = profile['isHighRisk'] as bool? ?? false;
        final dueDate = (profile['dueDate'] as Timestamp?)?.toDate();

        return Scaffold(
          backgroundColor: const Color(0xFFF7F4F8),
          body: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit_note_rounded, color: Colors.white),
                    onPressed: () => _showAddNoteDialog(context, week),
                    tooltip: 'Add Note',
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                    onSelected: (v) {
                      if (v == 'prescribe') {
                        context.push(AppRoutes.maternityPrescription, extra: {
                          'patientId': widget.patientId,
                          'patientName': widget.patientName,
                          'pregnancyWeek': week,
                        });
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'prescribe', child: Text('Add Prescription')),
                    ],
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                        child: Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  widget.patientName.isNotEmpty ? widget.patientName[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(widget.patientName,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    _headerChip('Week $week'),
                                    const SizedBox(width: 6),
                                    if (dueDate != null)
                                      _headerChip('Due ${DateFormat('dd MMM yy').format(dueDate)}'),
                                    const SizedBox(width: 6),
                                    if (isHighRisk)
                                      _headerChip('HIGH RISK', color: const Color(0xFFFFEBEE), textColor: const Color(0xFFB71C1C)),
                                  ]),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                bottom: TabBar(
                  controller: _tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  indicatorColor: Colors.white,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Journal'),
                    Tab(text: 'Checkups'),
                    Tab(text: 'Medicines'),
                  ],
                ),
              ),
            ],
            body: TabBarView(
              controller: _tab,
              children: [
                _buildOverview(profile, week),
                _buildJournalTab(),
                _buildCheckupsTab(),
                _buildMedicinesTab(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _headerChip(String text, {Color? color, Color? textColor}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color ?? Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text, style: TextStyle(
        color: textColor ?? Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  Widget _buildOverview(Map<String, dynamic> profile, int week) {
    final bloodGroup = profile['bloodGroup'] as String? ?? '';
    final weight = profile['weightKg'] as num? ?? 0;
    final age = profile['ageYears'] as int? ?? 0;
    final conditions = List<String>.from(profile['medicalConditions'] as List? ?? []);
    final prevPregnancies = profile['previousPregnancies'] as int? ?? 0;
    final emergencyName = profile['emergencyContactName'] as String? ?? '';
    final emergencyPhone = profile['emergencyContactPhone'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Key stats
          Row(children: [
            _statCard('Week', '$week/40', const Color(0xFFC2185B), Icons.pregnant_woman_rounded),
            const SizedBox(width: 8),
            _statCard('Blood', bloodGroup, const Color(0xFFEF5350), Icons.bloodtype_rounded),
            const SizedBox(width: 8),
            _statCard('Weight', '${weight}kg', const Color(0xFF7B1FA2), Icons.monitor_weight_rounded),
            const SizedBox(width: 8),
            _statCard('Age', '$age yrs', const Color(0xFF42A5F5), Icons.person_rounded),
          ]),
          const SizedBox(height: 16),

          // Doctor notes stream
          _sectionCard(
            title: 'Doctor\'s Notes',
            icon: Icons.notes_rounded,
            color: const Color(0xFF7B1FA2),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('pregnancy_doctor_notes')
                  .where('patientId', isEqualTo: widget.patientId)
                  .orderBy('createdAt', descending: true)
                  .limit(5)
                  .snapshots(),
              builder: (context, snap) {
                final notes = snap.data?.docs ?? [];
                if (notes.isEmpty) {
                  return const Text('No notes yet. Add a note using the edit button.',
                      style: TextStyle(color: AppColors.textHint, fontSize: 12));
                }
                return Column(
                  children: notes.map((n) {
                    final d = n.data() as Map<String, dynamic>;
                    return _noteTile(d);
                  }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          if (conditions.isNotEmpty)
            _sectionCard(
              title: 'Medical Conditions',
              icon: Icons.medical_information_rounded,
              color: const Color(0xFFEF5350),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: conditions.map((c) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(c, style: const TextStyle(fontSize: 11, color: Color(0xFFB71C1C))),
                )).toList(),
              ),
            ),
          const SizedBox(height: 12),

          _sectionCard(
            title: 'Emergency Contact',
            icon: Icons.emergency_rounded,
            color: const Color(0xFFEF5350),
            child: Row(children: [
              const Icon(Icons.person_rounded, size: 16, color: AppColors.textHint),
              const SizedBox(width: 6),
              Text('$emergencyName • $emergencyPhone',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildJournalTab() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('pregnancy_weekly_data')
        .where('patientId', isEqualTo: widget.patientId)
        .orderBy('loggedAt', descending: true)
        .limit(20)
        .snapshots(),
    builder: (context, snap) {
      final docs = snap.data?.docs ?? [];
      if (docs.isEmpty) {
        return const Center(child: Text('No journal entries yet', style: TextStyle(color: AppColors.textHint)));
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: docs.length,
        itemBuilder: (context, i) {
          final d = docs[i].data() as Map<String, dynamic>;
          return _journalCard(d);
        },
      );
    },
  );

  Widget _journalCard(Map<String, dynamic> d) {
    final loggedAt = (d['loggedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final symptoms = List<String>.from(d['symptoms'] as List? ?? []);
    final mood = d['mood'] as String? ?? '';
    final week = d['pregnancyWeek'] as int? ?? 0;
    final bp = d['bpSystolic'] != null ? '${d['bpSystolic']}/${d['bpDiastolic']}' : null;
    final weight = d['weightKg'];
    final movements = d['babyMovements'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Week $week',
                  style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Text(mood, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(DateFormat('dd MMM, hh:mm a').format(loggedAt),
                style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
          ]),
          if (symptoms.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Symptoms: ${symptoms.join(', ')}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (bp != null) _metricChip('BP: $bp'),
            if (weight != null) _metricChip('Wt: ${weight}kg'),
            if (movements != null) _metricChip('Movements: $movements'),
          ]),
        ],
      ),
    );
  }

  Widget _metricChip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F4F8),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
  );

  Widget _buildCheckupsTab() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('pregnancy_checkups')
        .where('patientId', isEqualTo: widget.patientId)
        .orderBy('scheduledDate')
        .snapshots(),
    builder: (context, snap) {
      final docs = snap.data?.docs ?? [];
      if (docs.isEmpty) {
        return const Center(
            child: Text('No checkups scheduled', style: TextStyle(color: AppColors.textHint)));
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: docs.length,
        itemBuilder: (context, i) {
          final d = docs[i].data() as Map<String, dynamic>;
          return _checkupTile(d, docs[i].id);
        },
      );
    },
  );

  Widget _checkupTile(Map<String, dynamic> d, String id) {
    final status = d['status'] as String? ?? 'upcoming';
    final date = (d['scheduledDate'] as Timestamp?)?.toDate() ?? DateTime.now();
    final color = status == 'completed'
        ? const Color(0xFF66BB6A)
        : status == 'missed' ? const Color(0xFFEF5350) : const Color(0xFF42A5F5);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Icon(Icons.event_rounded, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d['title'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(DateFormat('dd MMM yyyy').format(date),
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(status.toUpperCase(),
              style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _buildMedicinesTab() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          onPressed: () => context.push(AppRoutes.maternityPrescription, extra: {
            'patientId': widget.patientId,
            'patientName': widget.patientName,
          }),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Prescription'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('pregnancy_medicines')
              .where('patientId', isEqualTo: widget.patientId)
              .where('isActive', isEqualTo: true)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Center(child: Text('No medicines prescribed', style: TextStyle(color: AppColors.textHint)));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                return _medTile(d);
              },
            );
          },
        ),
      ),
    ],
  );

  Widget _medTile(Map<String, dynamic> d) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
    ),
    child: Row(children: [
      const Icon(Icons.medication_rounded, color: Color(0xFF66BB6A), size: 22),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text('${d['dosage']} • ${d['frequency']}',
                style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
          ],
        ),
      ),
    ]),
  );

  Widget _noteTile(Map<String, dynamic> d) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFF3E5F5),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(d['content'] as String? ?? '', style: const TextStyle(fontSize: 12, height: 1.5)),
        if (d['recommendation'] != null) ...[
          const SizedBox(height: 4),
          Text('💡 ${d['recommendation']}',
              style: const TextStyle(fontSize: 11, color: Color(0xFFE65100), fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 4),
        Text(
          DateFormat('dd MMM').format((d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now()),
          style: const TextStyle(fontSize: 10, color: AppColors.textHint),
        ),
      ],
    ),
  );

  Widget _statCard(String label, String value, Color color, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textHint)),
      ]),
    ),
  );

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13)),
            ]),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );

  Future<void> _showAddNoteDialog(BuildContext context, int week) async {
    final contentCtrl = TextEditingController();
    final recCtrl = TextEditingController();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(child: Text('Add Doctor Note',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: contentCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Clinical Notes *',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: recCtrl,
              decoration: const InputDecoration(
                labelText: 'Recommendation (optional)',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (contentCtrl.text.isEmpty) return;
                  await FirebaseFirestore.instance.collection('pregnancy_doctor_notes').add({
                    'patientId': widget.patientId,
                    'doctorId': uid,
                    'doctorName': 'Doctor',
                    'content': contentCtrl.text.trim(),
                    'recommendation': recCtrl.text.trim().isEmpty ? null : recCtrl.text.trim(),
                    'pregnancyWeek': week,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Save Note', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
    contentCtrl.dispose();
    recCtrl.dispose();
  }
}
