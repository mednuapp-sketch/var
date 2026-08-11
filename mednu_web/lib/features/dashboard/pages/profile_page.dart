import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/gradient_button.dart';

String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _genderCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyRelationCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  Map<String, dynamic> _user = {};
  String _phone = '';
  bool _loading = true;
  bool _saving = false;
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    if (_uid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    _userSub = FirebaseFirestore.instance.collection('users').doc(_uid).snapshots().listen((snap) {
      if (!mounted) return;
      final d = snap.data() ?? {};
      setState(() {
        _user = d;
        // Mobile writes 'phone' (+91XXXXXXXXXX), web writes 'phoneNumber' (digits only).
        // Normalise to digits only so the display always shows '+91 XXXXXXXXXX'.
        final rawPhone = (d['phone'] ?? d['phoneNumber']) as String? ?? '';
        _phone = rawPhone.startsWith('+91') ? rawPhone.substring(3) : rawPhone;
        _loading = false;
        if (!_hydrated) {
          _nameCtrl.text = d['name'] as String? ?? '';
          _emailCtrl.text = d['email'] as String? ?? '';
          _dobCtrl.text = d['dob'] as String? ?? '';
          _genderCtrl.text = d['gender'] as String? ?? '';
          _cityCtrl.text = d['city'] as String? ?? '';
          _emergencyNameCtrl.text = d['emergencyContactName'] as String? ?? '';
          _emergencyRelationCtrl.text = d['emergencyContactRelation'] as String? ?? '';
          _emergencyPhoneCtrl.text = d['emergencyContactPhone'] as String? ?? '';
          _hydrated = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _dobCtrl.dispose();
    _genderCtrl.dispose();
    _cityCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyRelationCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    super.dispose();
  }

  void _resetForm() {
    setState(() {
      _nameCtrl.text = _user['name'] as String? ?? '';
      _emailCtrl.text = _user['email'] as String? ?? '';
      _dobCtrl.text = _user['dob'] as String? ?? '';
      _genderCtrl.text = _user['gender'] as String? ?? '';
      _cityCtrl.text = _user['city'] as String? ?? '';
      _emergencyNameCtrl.text = _user['emergencyContactName'] as String? ?? '';
      _emergencyRelationCtrl.text = _user['emergencyContactRelation'] as String? ?? '';
      _emergencyPhoneCtrl.text = _user['emergencyContactPhone'] as String? ?? '';
    });
  }

  Future<void> _save() async {
    if (_uid.isEmpty) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'dob': _dobCtrl.text.trim(),
        'gender': _genderCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'emergencyContactName': _emergencyNameCtrl.text.trim(),
        'emergencyContactRelation': _emergencyRelationCtrl.text.trim(),
        'emergencyContactPhone': _emergencyPhoneCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final name = _nameCtrl.text.isNotEmpty ? _nameCtrl.text : (_user['name'] as String? ?? 'Patient');
    final status = _user['status'] as String? ?? 'active';

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('My Profile', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        Text('Manage your personal information', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
        else
          isMobile
              ? Column(children: [
                  _ProfileCard(name: name, status: status),
                  const SizedBox(height: 20),
                  _ProfileForm(
                    nameCtrl: _nameCtrl, emailCtrl: _emailCtrl, dobCtrl: _dobCtrl,
                    genderCtrl: _genderCtrl, cityCtrl: _cityCtrl, phone: _phone,
                    emergencyNameCtrl: _emergencyNameCtrl, emergencyRelationCtrl: _emergencyRelationCtrl,
                    emergencyPhoneCtrl: _emergencyPhoneCtrl, saving: _saving, onSave: _save, onCancel: _resetForm,
                  ),
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 2, child: _ProfileCard(name: name, status: status)),
                  const SizedBox(width: 24),
                  Expanded(flex: 5, child: _ProfileForm(
                    nameCtrl: _nameCtrl, emailCtrl: _emailCtrl, dobCtrl: _dobCtrl,
                    genderCtrl: _genderCtrl, cityCtrl: _cityCtrl, phone: _phone,
                    emergencyNameCtrl: _emergencyNameCtrl, emergencyRelationCtrl: _emergencyRelationCtrl,
                    emergencyPhoneCtrl: _emergencyPhoneCtrl, saving: _saving, onSave: _save, onCancel: _resetForm,
                  )),
                ]),
      ]),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String status;
  const _ProfileCard({required this.name, required this.status});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final isVerified = status == 'active';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(children: [
        Stack(alignment: Alignment.bottomRight, children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
            child: Center(child: Text(initial, style: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white))),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
            child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
          ),
        ]),
        const SizedBox(height: 14),
        Text(name, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        Text('Patient', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 12),
        StreamBuilder<int>(
          stream: _countStream('appointments', 'patientId'),
          builder: (context, snap) => _ProfileStat('Appointments', '${snap.data ?? 0}'),
        ),
        const SizedBox(height: 8),
        StreamBuilder<int>(
          stream: _countStream('prescriptions', 'patientId'),
          builder: (context, snap) => _ProfileStat('Prescriptions', '${snap.data ?? 0}'),
        ),
        const SizedBox(height: 8),
        StreamBuilder<int>(
          stream: _countStream('referrals', 'referrerId'),
          builder: (context, snap) => _ProfileStat('Referrals', '${snap.data ?? 0}'),
        ),
        const SizedBox(height: 16),
        if (isVerified)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('Verified Patient', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success)),
            ]),
          ),
      ]),
    );
  }

  Stream<int> _countStream(String collection, String field) {
    if (_uid.isEmpty) return Stream.value(0);
    return FirebaseFirestore.instance
        .collection(collection)
        .where(field, isEqualTo: _uid)
        .snapshots()
        .map((s) => s.size);
  }
}

class _ProfileStat extends StatelessWidget {
  final String label;
  final String value;
  const _ProfileStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
      const Spacer(),
      Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
    ]);
  }
}

class _ProfileForm extends StatelessWidget {
  final TextEditingController nameCtrl, emailCtrl, dobCtrl, genderCtrl, cityCtrl;
  final TextEditingController emergencyNameCtrl, emergencyRelationCtrl, emergencyPhoneCtrl;
  final String phone;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _ProfileForm({
    required this.nameCtrl, required this.emailCtrl, required this.dobCtrl,
    required this.genderCtrl, required this.cityCtrl, required this.phone,
    required this.emergencyNameCtrl, required this.emergencyRelationCtrl, required this.emergencyPhoneCtrl,
    required this.saving, required this.onSave, required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Personal Information', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 20),
        _FieldGroup(fields: [
          _FormField(label: 'Full Name', controller: nameCtrl, icon: Icons.person_outline_rounded),
          _FormField(label: 'Mobile Number', value: phone.isNotEmpty ? '+91 $phone' : '—', icon: Icons.phone_outlined, readOnly: true),
          _FormField(label: 'Email Address', controller: emailCtrl, icon: Icons.email_outlined),
          _FormField(label: 'Date of Birth', controller: dobCtrl, icon: Icons.cake_outlined),
          _FormField(label: 'Gender', controller: genderCtrl, icon: Icons.wc_rounded),
          _FormField(label: 'City', controller: cityCtrl, icon: Icons.location_city_outlined),
        ]),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 20),
        Text('Emergency Contact', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        _FieldGroup(fields: [
          _FormField(label: 'Contact Name', controller: emergencyNameCtrl, icon: Icons.person_add_alt_rounded),
          _FormField(label: 'Relation', controller: emergencyRelationCtrl, icon: Icons.family_restroom_rounded),
          _FormField(label: 'Contact Number', controller: emergencyPhoneCtrl, icon: Icons.phone_outlined),
        ]),
        const SizedBox(height: 24),
        Row(children: [
          GradientButton(label: saving ? 'Saving…' : 'Save Changes', width: 160, height: 44, fontSize: 13, onTap: saving ? null : onSave),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: saving ? null : onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
            ),
            child: Text('Cancel', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}

class _FieldGroup extends StatelessWidget {
  final List<_FormField> fields;
  const _FieldGroup({required this.fields});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    if (isMobile) {
      return Column(children: fields.map((f) => Padding(padding: const EdgeInsets.only(bottom: 14), child: f)).toList());
    }
    return Column(
      children: [
        for (int i = 0; i < fields.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              Expanded(child: fields[i]),
              if (i + 1 < fields.length) ...[
                const SizedBox(width: 16),
                Expanded(child: fields[i + 1]),
              ],
            ]),
          ),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? value;
  final IconData icon;
  final bool readOnly;

  const _FormField({required this.label, required this.icon, this.controller, this.value, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      TextFormField(
        controller: controller,
        initialValue: controller == null ? value : null,
        readOnly: readOnly,
        style: GoogleFonts.poppins(fontSize: 14, color: readOnly ? AppColors.textSecondary : AppColors.textPrimary),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 18),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          fillColor: readOnly ? AppColors.background : null,
          filled: readOnly,
        ),
      ),
    ]);
  }
}
