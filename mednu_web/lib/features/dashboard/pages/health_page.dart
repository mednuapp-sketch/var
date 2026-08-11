import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

class HealthPage extends StatelessWidget {
  const HealthPage({super.key});

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _stream {
    if (_uid.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance.collection('users').doc(_uid).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Health Dashboard',
            style: GoogleFonts.poppins(
                fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        Text('Your personal health overview',
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        _uid.isEmpty
            ? _emptyState()
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator()));
                  }
                  final data = snap.data?.data() ?? {};
                  return _HealthContent(data: data, isMobile: isMobile);
                },
              ),
      ]),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('❤️', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text('Sign in to view health data',
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ]),
      ),
    );
  }
}

class _HealthContent extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMobile;
  const _HealthContent({required this.data, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final dob = data['dob'] as String? ?? '';
    final age = _calcAge(dob);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Medical Info from profile
      _MedicalInfoCard(data: data, age: age),
      const SizedBox(height: 20),

      // Vitals note — vitals are tracked in the mobile app
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('📱', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Text('Vital Signs & Tracking',
                style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ]),
          const SizedBox(height: 12),
          Text(
            'Track your vitals — blood pressure, blood sugar, steps, and more — using the MedNU mobile app. Your data syncs automatically to your profile.',
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary, height: 1.6),
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: isMobile ? 2 : 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.2,
            children: const [
              _VitalPlaceholder(emoji: '❤️', label: 'Blood Pressure'),
              _VitalPlaceholder(emoji: '🩸', label: 'Blood Sugar'),
              _VitalPlaceholder(emoji: '⚖️', label: 'BMI'),
              _VitalPlaceholder(emoji: '🏃', label: 'Steps Today'),
            ],
          ),
        ]),
      ),
    ]);
  }
}

class _MedicalInfoCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final int? age;
  const _MedicalInfoCard({required this.data, required this.age});

  @override
  Widget build(BuildContext context) {
    final height = data['height'] as String? ?? '';
    final weight = data['weight'] as String? ?? '';
    final chronicConditions = data['chronicConditions'] as String? ?? '';
    final allergies = data['allergies'];
    final allergyList = allergies is List
        ? allergies.whereType<String>().toList()
        : (allergies is String && allergies.isNotEmpty)
            ? allergies.split(',').map((e) => e.trim()).toList()
            : <String>[];

    final rows = <(String, String, String)>[];
    if (age != null) rows.add(('🎂', 'Age', '$age years'));
    if (height.isNotEmpty) rows.add(('📏', 'Height', height));
    if (weight.isNotEmpty) rows.add(('⚖️', 'Weight', weight));
    if (chronicConditions.isNotEmpty) {
      rows.add(('💊', 'Chronic Conditions', chronicConditions));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Medical Information',
            style: GoogleFonts.poppins(
                fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        const Divider(height: 1),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Complete your profile to see medical information here.',
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
            ),
          )
        else
          ...rows.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  Text(item.$1, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(item.$2,
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: AppColors.textSecondary))),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(item.$3,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ),
                ]),
              )),
        if (allergyList.isNotEmpty) ...[
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(children: [
            const Text('⚠️', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text('Known Allergies',
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.error)),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allergyList
                .map((a) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                      ),
                      child: Text(a,
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.error)),
                    ))
                .toList(),
          ),
        ],
      ]),
    );
  }
}

class _VitalPlaceholder extends StatelessWidget {
  final String emoji;
  final String label;
  const _VitalPlaceholder({required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppColors.textSecondary, height: 1.3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('—',
                style: GoogleFonts.poppins(
                    fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textHint)),
          ]),
        ],
      ),
    );
  }
}

int? _calcAge(String dob) {
  if (dob.isEmpty) return null;
  try {
    final parts = dob.split('/');
    if (parts.length == 3) {
      final d = DateTime(
          int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      final today = DateTime.now();
      int age = today.year - d.year;
      if (today.month < d.month ||
          (today.month == d.month && today.day < d.day)) { age--; }
      return age;
    }
  } catch (_) {}
  return null;
}
