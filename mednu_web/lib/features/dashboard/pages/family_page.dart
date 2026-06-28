import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/gradient_button.dart';

final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

class FamilyPage extends StatelessWidget {
  const FamilyPage({super.key});

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _stream {
    if (_uid.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance.collection('users').doc(_uid).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Family Members',
                    style: GoogleFonts.poppins(
                        fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text('Manage health profiles for your loved ones',
                    style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
              ]),
            ),
            GradientButton(
              label: '+ Add Member',
              onTap: () => _showAddMemberSheet(context),
              height: 40,
              fontSize: 13,
              width: 130,
              borderRadius: BorderRadius.circular(12),
            ),
          ]),
          const SizedBox(height: 24),
          _uid.isEmpty
              ? _emptyState(context)
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
                    final rawList = data['familyMembers'];
                    final members = rawList is List
                        ? rawList
                            .whereType<Map>()
                            .map((e) => Map<String, dynamic>.from(e))
                            .toList()
                        : <Map<String, dynamic>>[];

                    if (members.isEmpty) return _emptyState(context);

                    return _MemberGrid(members: members, isMobile: isMobile);
                  },
                ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('👨‍👩‍👧‍👦', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text('No family members added',
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('Add your family members to manage their health',
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          GradientButton(
            label: '+ Add Member',
            onTap: () => _showAddMemberSheet(context),
            height: 44,
            fontSize: 13,
            width: 160,
          ),
        ]),
      ),
    );
  }

  void _showAddMemberSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _AddMemberSheet(),
    );
  }
}

// ─── Member Grid ──────────────────────────────────────────────────────────────

class _MemberGrid extends StatelessWidget {
  final List<Map<String, dynamic>> members;
  final bool isMobile;
  const _MemberGrid({required this.members, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 1 : 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: isMobile ? 2.4 : 1.3,
      ),
      itemCount: members.length,
      itemBuilder: (context, i) =>
          _MemberCard(member: members[i]),
    );
  }
}

class _MemberCard extends StatefulWidget {
  final Map<String, dynamic> member;
  const _MemberCard({required this.member});

  @override
  State<_MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<_MemberCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final name = m['name'] as String? ?? '';
    final relation = m['relation'] as String? ?? '';
    final gender = m['gender'] as String? ?? '';
    final dob = m['dob'] as String? ?? '';
    final age = _calcAge(dob);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _hovered
                ? AppColors.primary.withValues(alpha: 0.2)
                : AppColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: _hovered
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: _hovered ? 20 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(initial,
                      style: GoogleFonts.poppins(
                          fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                      style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis),
                  Text(relation,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.textSecondary)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (age != null) _InfoChip(label: '$age yrs'),
              if (gender.isNotEmpty) _InfoChip(label: gender),
            ]),
          ],
        ),
      ),
    );
  }
}

int? _calcAge(String dob) {
  if (dob.isEmpty) return null;
  try {
    // try DD/MM/YYYY
    final parts = dob.split('/');
    if (parts.length == 3) {
      final d = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      final today = DateTime.now();
      int age = today.year - d.year;
      if (today.month < d.month || (today.month == d.month && today.day < d.day)) age--;
      return age;
    }
  } catch (_) {}
  return null;
}

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
    );
  }
}

// ─── Add Member Bottom Sheet ──────────────────────────────────────────────────

class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet();

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _nameController = TextEditingController();
  String _selectedRelation = 'Spouse';
  String _selectedGender = 'Male';
  bool _saving = false;

  static const _relations = ['Spouse', 'Child', 'Parent', 'Sibling', 'Other'];
  static const _genders = ['Male', 'Female', 'Other'];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (_uid.isEmpty) return;
    setState(() => _saving = true);
    try {
      final member = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': name,
        'relation': _selectedRelation,
        'gender': _selectedGender,
      };
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'familyMembers': FieldValue.arrayUnion([member]),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add member: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Add Family Member',
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: AppColors.background, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textSecondary),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          _SheetField(label: 'Full Name *', controller: _nameController, hint: 'Enter name'),
          const SizedBox(height: 14),
          _SheetDropdown(
            label: 'Relation',
            value: _selectedRelation,
            items: _relations,
            onChanged: (v) => setState(() => _selectedRelation = v!),
          ),
          const SizedBox(height: 14),
          _SheetDropdown(
            label: 'Gender',
            value: _selectedGender,
            items: _genders,
            onChanged: (v) => setState(() => _selectedGender = v!),
          ),
          const SizedBox(height: 22),
          GradientButton(
            label: _saving ? 'Adding…' : 'Add Member',
            onTap: _saving ? null : _save,
            height: 48,
            fontSize: 14,
          ),
        ],
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  const _SheetField({required this.label, required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: GoogleFonts.poppins(
              fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.poppins(fontSize: 14, color: AppColors.textHint),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        ),
      ),
    ]);
  }
}

class _SheetDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _SheetDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: GoogleFonts.poppins(
              fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
            items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    ]);
  }
}
