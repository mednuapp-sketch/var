import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/gradient_button.dart';

class FamilyPage extends StatefulWidget {
  const FamilyPage({super.key});

  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  static final List<Map<String, String>> _members = [
    {
      'name': 'You',
      'relation': 'Primary Account',
      'dob': '1990-06-15',
      'blood': 'B+',
      'age': '36',
      'emoji': '👤',
      'gender': 'Male',
    },
    {
      'name': 'Ananya',
      'relation': 'Wife',
      'dob': '1993-03-22',
      'blood': 'O+',
      'age': '33',
      'emoji': '👩',
      'gender': 'Female',
    },
    {
      'name': 'Arjun',
      'relation': 'Son',
      'dob': '2018-11-05',
      'blood': 'B+',
      'age': '7',
      'emoji': '👦',
      'gender': 'Male',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Family Members',
                        style: GoogleFonts.poppins(
                            fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text('Manage health profiles for your loved ones',
                        style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              GradientButton(
                label: '+ Add Member',
                onTap: () => _showAddMemberSheet(context),
                height: 40,
                fontSize: 13,
                width: 130,
                borderRadius: BorderRadius.circular(12),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _MemberGrid(members: _members, isMobile: isMobile),
          const SizedBox(height: 28),
          _HealthSummarySection(isMobile: isMobile),
        ],
      ),
    );
  }

  void _showAddMemberSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _AddMemberSheet(),
    );
  }
}

// ─── Member Grid ─────────────────────────────────────────────────────────────

class _MemberGrid extends StatelessWidget {
  final List<Map<String, String>> members;
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
      itemBuilder: (context, i) => _MemberCard(member: members[i], isPrimary: i == 0),
    );
  }
}

class _MemberCard extends StatefulWidget {
  final Map<String, String> member;
  final bool isPrimary;
  const _MemberCard({required this.member, required this.isPrimary});

  @override
  State<_MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<_MemberCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
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
            color: widget.isPrimary
                ? AppColors.primary.withValues(alpha: 0.3)
                : (_hovered ? AppColors.primary.withValues(alpha: 0.2) : AppColors.border),
            width: widget.isPrimary ? 1.5 : 1,
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
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: widget.isPrimary
                        ? AppColors.primaryGradient
                        : const LinearGradient(
                            colors: [Color(0xFFE8F4FD), Color(0xFFD0E8FA)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(m['emoji']!,
                        style: const TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m['name']!,
                          style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      Text(m['relation']!,
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (widget.isPrimary)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('You',
                        style: GoogleFonts.poppins(
                            fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _InfoChip(label: '${m['age']!} yrs'),
                const SizedBox(width: 8),
                _InfoChip(label: m['blood']!),
                const SizedBox(width: 8),
                _InfoChip(label: m['gender']!),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CardAction(
                    icon: Icons.calendar_today_rounded,
                    label: 'Book',
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CardAction(
                    icon: Icons.folder_outlined,
                    label: 'Records',
                    color: AppColors.info,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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

class _CardAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _CardAction({required this.icon, required this.label, required this.color});

  @override
  State<_CardAction> createState() => _CardActionState();
}

class _CardActionState extends State<_CardAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: _hovered ? widget.color.withValues(alpha: 0.1) : AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _hovered ? widget.color.withValues(alpha: 0.3) : AppColors.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(widget.icon, size: 13, color: widget.color),
          const SizedBox(width: 5),
          Text(widget.label,
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w600, color: widget.color)),
        ]),
      ),
    );
  }
}

// ─── Health Summary Section ───────────────────────────────────────────────────

class _HealthSummarySection extends StatelessWidget {
  final bool isMobile;
  const _HealthSummarySection({required this.isMobile});

  static const _summary = [
    {'name': 'You', 'emoji': '👤', 'appointments': '2', 'prescriptions': '3', 'status': 'Good'},
    {'name': 'Ananya', 'emoji': '👩', 'appointments': '1', 'prescriptions': '1', 'status': 'Good'},
    {'name': 'Arjun', 'emoji': '👦', 'appointments': '0', 'prescriptions': '0', 'status': 'Healthy'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Family Health Summary',
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Quick overview of all members',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          const Divider(height: 1),
          ..._summary.map((m) => _SummaryRow(data: m)),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final Map<String, String> data;
  const _SummaryRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text(data['emoji']!, style: const TextStyle(fontSize: 18))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(data['name']!,
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ),
        _MiniStat(icon: Icons.calendar_today_rounded, value: data['appointments']!, color: AppColors.info),
        const SizedBox(width: 16),
        _MiniStat(icon: Icons.medication_rounded, value: data['prescriptions']!, color: AppColors.primary),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(data['status']!,
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success)),
        ),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  const _MiniStat({required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 4),
      Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
    ]);
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
  String _selectedBlood = 'B+';

  static const _relations = ['Spouse', 'Child', 'Parent', 'Sibling', 'Other'];
  static const _genders = ['Male', 'Female', 'Other'];
  static const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
                width: 32, height: 32,
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textSecondary),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          _SheetField(label: 'Full Name', controller: _nameController, hint: 'Enter name'),
          const SizedBox(height: 14),
          _SheetDropdown(
            label: 'Relation',
            value: _selectedRelation,
            items: _relations,
            onChanged: (v) => setState(() => _selectedRelation = v!),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _SheetDropdown(
                label: 'Gender',
                value: _selectedGender,
                items: _genders,
                onChanged: (v) => setState(() => _selectedGender = v!),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _SheetDropdown(
                label: 'Blood Group',
                value: _selectedBlood,
                items: _bloodGroups,
                onChanged: (v) => setState(() => _selectedBlood = v!),
              ),
            ),
          ]),
          const SizedBox(height: 22),
          GradientButton(
            label: 'Add Member',
            onTap: () => Navigator.pop(context),
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
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
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
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
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
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
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
            items: items
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    ]);
  }
}
