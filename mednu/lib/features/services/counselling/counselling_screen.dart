import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';

class CounsellingScreen extends StatefulWidget {
  const CounsellingScreen({super.key});

  @override
  State<CounsellingScreen> createState() => _CounsellingScreenState();
}

class _CounsellingScreenState extends State<CounsellingScreen> {
  String? _selectedType;

  final _types = [
    {'title': 'Depression & Anxiety', 'icon': Icons.psychology_rounded, 'color': const Color(0xFF7B1FA2), 'specialty': 'Psychiatry'},
    {'title': 'Stress Management', 'icon': Icons.self_improvement_rounded, 'color': const Color(0xFF1565C0), 'specialty': 'Psychology'},
    {'title': 'Relationship Therapy', 'icon': Icons.favorite_rounded, 'color': const Color(0xFFC2185B), 'specialty': 'Counselling'},
    {'title': 'Child & Teen Therapy', 'icon': Icons.child_care_rounded, 'color': const Color(0xFF2E7D32), 'specialty': 'Pediatric Psychiatry'},
    {'title': 'Addiction Recovery', 'icon': Icons.healing_rounded, 'color': const Color(0xFFE65100), 'specialty': 'Psychiatry'},
    {'title': 'Grief Therapy', 'icon': Icons.spa_rounded, 'color': const Color(0xFF37474F), 'specialty': 'Counselling'},
  ];

  void _bookTherapist() {
    final specialty = Uri.encodeComponent(_selectedType ?? 'Psychiatry');
    context.push('${AppRoutes.doctors}?specialty=$specialty');
  }

  void _selectType(Map<String, dynamic> t) {
    setState(() => _selectedType = t['specialty'] as String);
    _showBookingSheet(t);
  }

  void _showBookingSheet(Map<String, dynamic> t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Container(width: 64, height: 64,
              decoration: BoxDecoration(
                  color: (t['color'] as Color).withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(t['icon'] as IconData, color: t['color'] as Color, size: 32)),
          const SizedBox(height: 16),
          Text(t['title'] as String, style: AppTextStyles.h3, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Find certified therapists specialising in ${t['title']}',
              style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('${AppRoutes.doctors}?specialty=${t['specialty']}');
                },
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: const Text('Schedule Session'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  foregroundColor: t['color'] as Color,
                  side: BorderSide(color: t['color'] as Color),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push(AppRoutes.consultation);
                },
                icon: const Icon(Icons.video_call_rounded, size: 16),
                label: const Text('Video Session'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  backgroundColor: t['color'] as Color,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Text('Sessions from ₹299 • Certified therapists • Fully confidential',
              style: AppTextStyles.caption, textAlign: TextAlign.center),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 8),
        ]),
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
            pinned: true, expandedHeight: 160,
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => context.pop()),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 50, 20, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.psychology_rounded, color: Colors.white, size: 36),
                  const SizedBox(height: 8),
                  Text('Therapy', style: AppTextStyles.onPrimaryH2),
                  Text('Confidential mental health support', style: AppTextStyles.onPrimaryBody),
                ]))),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFF7B1FA2).withOpacity(0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF7B1FA2).withOpacity(0.2))),
                  child: const Row(children: [
                    Icon(Icons.lock_rounded, color: Color(0xFF7B1FA2)),
                    SizedBox(width: 10),
                    Expanded(child: Text('All sessions are 100% confidential and anonymous', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF7B1FA2), fontWeight: FontWeight.w500))),
                  ]),
                ),
                const SizedBox(height: 16),

                // Session info row
                Row(children: [
                  _InfoChip(Icons.timer_rounded, 'From ₹299', const Color(0xFF2E7D32)),
                  const SizedBox(width: 8),
                  _InfoChip(Icons.verified_rounded, 'Certified', const Color(0xFF1565C0)),
                  const SizedBox(width: 8),
                  _InfoChip(Icons.video_call_rounded, 'Video/Chat', const Color(0xFFE65100)),
                ]),
                const SizedBox(height: 20),

                Text('I need help with...', style: AppTextStyles.h4),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 1.45,
                  crossAxisSpacing: 12, mainAxisSpacing: 12,
                  children: _types.map((t) {
                    final isSelected = _selectedType == t['specialty'];
                    return GestureDetector(
                      onTap: () => _selectType(t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected ? (t['color'] as Color).withOpacity(0.08) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? t['color'] as Color : AppColors.divider,
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: isSelected ? [BoxShadow(color: (t['color'] as Color).withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 4))] : null,
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(t['icon'] as IconData, color: t['color'] as Color, size: 30),
                          const SizedBox(height: 8),
                          Text(t['title'] as String, textAlign: TextAlign.center,
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
                                  color: isSelected ? t['color'] as Color : AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (t['color'] as Color).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Tap to book', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textHint)),
                          ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _bookTherapist,
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: const Text('Find a Therapist'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B1FA2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.consultation),
                    icon: const Icon(Icons.video_call_rounded, size: 18),
                    label: const Text('Start Video Consultation'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF7B1FA2),
                      side: const BorderSide(color: Color(0xFF7B1FA2)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    ]),
  );
}